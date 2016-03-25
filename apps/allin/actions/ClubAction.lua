local string_split       = string.split
local Constants = cc.import(".Constants", "..")
local gbc = cc.import("#gbc")
local json = cc.import("#json")
local ClubAction = cc.class("ClubAction", gbc.ActionBase)
ClubAction.ACCEPTED_REQUEST_TYPE = "websocket"

-- public methods
function ClubAction:ctor(config)
    ClubAction.super.ctor(self, config)
end

function ClubAction:createclubAction(args)
    local data = args.data
    local name = data.name
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not name then
        cc.printinfo("argument not provided: \"name\"")
        result.data.msg = "name not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    local area = data.area
    if not area then
        cc.printinfo("argument not provided: \"area\"")
        result.data.msg = "area not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    local description = data.description
    if not description then
        local nickname = self:getInstance():getNickname()
        description = nickname .. "'s club"
        cc.printinfo("club description set to default: %s", description)
    end


    local instance = self:getInstance()
    local mysql = instance:getMysql()

    -- get next auto increment id
    local club_id, err = instance:getNextId("club")
    if not club_id then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "failed to get next_id for table club, err: %s" .. err
        return result
    end

    -- insert into db
    local sql = "INSERT INTO club (name, area, description, owner_id) "
                      .. " VALUES (" .. instance:sqlQuote(name) .. ", "
                               .. instance:sqlQuote(area) .. ", "
                               ..  instance:sqlQuote(description) .. ", "
                               .. "(SELECT id FROM user WHERE session = " .. instance:sqlQuote(self:getInstance():getAllinSession()) .. "));"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- join the club automatically
    sql = "INSERT INTO user_club (user_id, club_id) "
                      .. " VALUES (" .. instance:getCid() .. ", " .. club_id .. ") "
                      .. " ON DUPLICATE KEY UPDATE deleted = 0"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.club_id = club_id
    result.data.state = 0
    result.data.msg = "club created"
    return result
end

function ClubAction:clubinfoAction(args)
    local data = args.data
    local club_id = data.club_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT id , name, owner_id, area, description" 
                .. " FROM club WHERE id " .. club_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end

    table.merge(result.data, dbres)
    result.data.state = 0
    result.data.msg = "club found"
    return result
end

function ClubAction:listjoinedclubAction(args)
    local data = args.data
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT a.id, a.name, a.owner_id, a.area, a.description FROM club a, user_club b "
                .. " WHERE b.deleted = 0 AND "
                .. " a.id = b.club_id AND "
                .. " b.user_id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.club_joined = dbres
    result.data.state = 0
    result.data.msg = #dbres .. " club(s) joined"
    return result
end

function ClubAction:leaveclubAction(args)
    local data = args.data
    local club_id = data.club_id

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    local instance = self:getInstance()
    local joined_clubs = instance:getClubIds()
    if not table.contains(joined_clubs, club_id) then
        result.data.msg = "you must be a member of the club before you can leave the club: " .. club_id
        result.data.state = Constants.Error.LogicError
        return result
    end

    local mysql = instance:getMysql()
    local sql = "UPDATE user_club SET deleted = 1 "
                .. " WHERE deleted = 0 "
                .. " AND club_id = " .. club_id
                .. " AND user_id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.club_id = club_id
    result.data.msg = "club left"
    return result
end

function ClubAction:listclubAction(args)
    local data = args.data
    local keyword = data.keyword
    local limit = data.limit or Constants.Limit.ListClubLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListClubLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListClubLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    if not keyword then
        result.data.msg = "keyword not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"keyword\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local word = '%' .. keyword .. '%'
    local sql = "SELECT id, name, owner_id, area, description" 
                .. " FROM club WHERE name like " .. instance:sqlQuote(word) 
                .. " or area like " .. instance:sqlQuote(word) 
                .. " or description like " .. instance:sqlQuote(word) 
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.clubs = dbres
    result.data.state = 0
    result.data.msg = #dbres .. " club(s) found"
    return result
end

function ClubAction:joinclubAction(args)
    local data = args.data
    local club_id = data.club_id
    local notes = data.notes or ""
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end
    
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT id, owner_id, name FROM club WHERE id =" .. club_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club with club_id ".. club_id .. " not found"
        return result
    end
    local owner_id = dbres[1].owner_id
    local club_name = dbres[1].name

    local joined_clubs = instance:getClubIds()
    if table.contains(joined_clubs, club_id) then
        result.data.msg = "you have already joined this club: " .. club_id
        result.data.state = Constants.Error.LogicError
        return result
    end

    sql = "INSERT INTO club_application (user_id, club_id, notes ) "
                      .. " VALUES (" .. instance:getCid() .. ", " .. club_id .. ", " .. instance:sqlQuote(notes) .. ") "
                      .. " ON DUPLICATE KEY UPDATE status = 0, notes = " .. instance:sqlQuote(notes)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.club_id = club_id
    result.data.msg = "applied"

    -- send to club owner for approval
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "club.application"}}
    message.data.user_id = instance:getCid()
    message.data.phone = instance:getPhone()
    message.data.nickname = instance:getNickname()
    message.data.club_id = club_id
    message.data.club_name = club_name
    message.data.notes = notes
    online:sendMessage(owner_id, json.encode(message))

    return result
end

-- a club owner needs to handle club applications
function ClubAction:listapplicationAction(args)
    local data = args.data
    local limit = data.limit or Constants.Limit.ListClubApplicationListLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListClubApplicationListLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListClubApplicationListLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT a.id as user_id, a.phone, a.nickname, b.id as club_id, b.name as club_name, c.notes, c.applied_at from user a, club b, club_application c "
                .. " WHERE c.status = 0 "
                .. " AND b.id = c.club_id "
                .. " AND a.id = c.user_id "
                .. " AND b.owner_id = " .. instance:getCid()
                .. " ORDER BY b.id"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    result.data.applications = dbres
    result.data.state = 0
    result.data.msg = #dbres .. " applications found"
    return result
end

-- approve or reject the application
function ClubAction:handleapplicationAction(args)
    local data = args.data
    local club_id = data.club_id
    local user_id = data.user_id
    local status = data.status
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not user_id then
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not status then
        result.data.msg = "status not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if status < 0 or status > 2 then
        result.data.msg = "status must be 0, 1 or 2"
        result.data.state = Constants.Error.LogicError
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " UPDATE club_application set status = " .. status 
                .. " WHERE user_id = " .. user_id
                .. " AND club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    if status == 1 then
        sql = "INSERT INTO user_club (user_id, club_id) "
                          .. " VALUES (" .. user_id .. ", " .. club_id .. ") "
                          .. " ON DUPLICATE KEY UPDATE deleted = 0"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end
    end
     
    result.data.state = 0
    result.data.msg = "application handled"
    return result
end

-- remove a club member
function ClubAction:removememberAction(args)
    local data = args.data
    local club_id = data.club_id
    local user_id = data.user_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not user_id then
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " UPDATE user_club set deleted = 1 "
                .. " WHERE user_id = " .. user_id
                .. " AND club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.club_id = club_id
    result.data.user_id = user_id
    result.data.msg = "user " .. user_id .. " removed from club " .. club
    return result
end

function ClubAction:disbandclubAction(args)
    local data = args.data
    local club_id = data.club_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " SELECT owner_id FROM club where deleted = 0 and id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end
    local owner_id = dbres[1].owner_id
    if owner_id ~= instance:getCid() then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not owner of club " .. club_id .. ". Only the club owner can disband the club"
        return result
    end

    -- delete the club
    sql = " UPDATE club set deleted = 1 where id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    -- remove all users
    sql = " UPDATE user_club set deleted = 1 where club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.msg = "club " .. club_id .. " disbanded"
    return result
end

return ClubAction
