local string_split       = string.split
local gbc = cc.import("#gbc")
local GameAction = cc.class("GameAction", gbc.ActionBase)
local WebSocketInstance = cc.import(".WebSocketInstance", "..")
local Constants = cc.import(".Constants", "..")
GameAction.ACCEPTED_REQUEST_TYPE = "websocket"

-- private
local snap = cc.import(".snap")

local _updateUserGameHistory = function (mysql, args)
    local user_id = args.user_id
    local game_id = args.game_id

    local sql = "INSERT INTO user_game_history (user_id, game_id, is_player, is_owner, is_spectator) "
                .. " VALUES (" .. user_id .. ", " .. game_id .. ", " .. args.is_player .. ", " .. args.is_owner .. ", " .. args.is_spectator .. ")"
              .. " ON DUPLICATE KEY UPDATE is_player = " .. args.is_player 
                                           .. ",  is_owner = " .. args.is_owner
                                           .. ",  is_spectator = " .. args.is_spectator
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("db err: %s", err)
    end
end

local _handlePSERVER, _handleSNAP, _handleGAMEINFO, _handleGAMELIST, _handlePLAYERLIST, _handleCLIENTINFO, _handleERR

_handlePSERVER = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }

    -- // server command PSERVER <version> <client-id> <time>
    -- example: PSERVER 999 1 145148909, 999=server version, 1 = assigned client_id, 145148909=timestamp

    if #parts ~= 4 then
        result.data.state = Constants.Error.AllinError
        result.data.msg = "Invalid PSERVER response: " .. table.concat(parts, " ")
        return result
    end

    result.data.msg = "client version is valid"
    result.data.server_version = parts[2]
    return result
end


_handleGAMELIST = function (parts, args)
    local msgid = args.msgid
    local club_id = args.club_id
    local mysql = args.mysql
    local limit = args.limit
    local offset = args.offset

    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }

    -- tcp format: GAMELIST 1 2 3
    local game_ids = table.subrange(parts, 2, #parts)
    if #game_ids == 0 then
        game_ids[1] = -1
    end

    local game_id_condition = "(" .. table.concat(game_ids, ", ") .. ") "
    local sql = "SELECT g.id, club_id, g.name, g.owner_id, g.max_players, c.name as club_name, blinds_start, blinds_factor, game_mode, u.nickname , COUNT(ug.user_id) AS player_count "
                .. " FROM game g, club c, user u, user_game_history ug"
                .. " WHERE g.deleted != 1 "
                .. " AND g.id IN " .. game_id_condition 
                .. " AND g.id = ug.game_id "
                .. " AND g.club_id = c.id " 
                .. " AND g.owner_id = u.id"
                .. " AND g.club_id = " .. club_id -- only return games belong to club_id
                .. " GROUP BY g.id"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("db err: %s", err)
    end

    result.data.msg = #dbres .. " games(s) found"
    result.data.games = dbres
    return result
end

_handleGAMEINFO = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }

    -- server response looks like: GAMEINFO 1 1:3:1:9:5:1:30:1500 20:20:300 "peter's game 1"
    result.data.game_id = parts[2]
    local info = string_split(parts[3], ":")
    result.data.game_type = info[1] -- 1: GameTypeHoldem 
    result.data.game_mode = info[2] -- 1: Cash game, 2: Tournament, 3: SNG
    result.data.game_state = info[3] -- 1: GameStateWaiting, 2: GameStateStarted, 3: GameStateEnded 
    --info[4] is combination of : GameInfoRegistered = 0x01, GameInfoPassword = 0x02, GameInfoRestart = 0x04, GameInfoOwner = 0x08, GameInfoSubscribed  = 0x10,
    result.data.is_player = 0
    if bit.band(0x01 ,tonumber(info[4])) > 0 then 
        result.data.is_player = 1
    end
    result.data.password_protected = 0
    if bit.band(0x02 ,tonumber(info[4])) > 0 then 
        result.data.password_protected = 1
    end
    result.data.auto_restart = 0
    if bit.band(0x04 ,tonumber(info[4])) > 0 then 
        result.data.auto_restart = 1
    end
    result.data.is_owner = 0
    if bit.band(0x08 ,tonumber(info[4])) > 0 then 
        result.data.is_owner = 1
    end
    result.data.is_spectator = 0
    if bit.band(0x10 ,tonumber(info[4])) > 0 then 
        result.data.is_spectator = 1
    end

    result.data.max_players         = info[5]
    result.data.player_count        = info[6]
    result.data.timeout             = info[7]
    result.data.stake               = info[7]
    _updateUserGameHistory(args.mysql, {game_id = result.data.game_id, 
                                        user_id = args.user_id, 
                                        is_player = result.data.is_player,
                                        is_owner = result.data.is_owner, 
                                        is_spectator = result.data.is_spectator
                                        }
                          )

    info = string_split(parts[4], ":")
    result.data.blinds_start        = info[1]
    result.data.blinds_factor       = info[2]
    result.data.blinds_time         = info[3]

    result.data.name                = table.concat(table.subrange(parts, 5, #parts), " ")

    --[[
    -- send new game to all online users of the club
    cc.printdebug("sending new game info to all users in club %s", args.club_id)
    local message = {state_type = "server_push", data = {push_type = "game.newgame"}}
    message.data.name = result.data.name
    message.data.stake = result.data.stake
    message.data.blinds_time = result.data.blinds_time
    message.data.blinds_start = result.data.blinds_start
    message.data.blinds_factor = result.data.blinds_factor
    message.data.timeout = result.data.timeout
    message.data.max_players = result.data.max_players
    message.data.player_count = result.data.player_count
    message.data.password_protected = result.data.password_protected
    message.data.game_type = result.data.game_type
    message.data.game_id = result.data.game_id
    message.data.game_type = result.data.game_type
    message.data.auto_restart = result.data.auto_restart
    message.data.game_mode = result.data.game_mode
    message.data.created_by = args.user_id
    local online = args.instance:getOnline()
    online:sendClubMessage(args.club_id or 0, message)
    --]]

    return result
end

_handlePLAYERLIST = function (parts, args)
    local msgid = args.msgid
    local mysql = args.mysql
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {state_type = "server_push", data = {push_type = "game.playerlist"}}

    --server response looks like: PLAYERLIST 1 0   
    result.data.game_id = parts[2]
    local player_ids = table.subrange(parts, 3, #parts) 
    local player_id_condition = "(" .. table.concat(player_ids, ", ") .. ") "
    local sql = "SELECT id, nickname, phone FROM user where id in " .. player_id_condition
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.msg = #dbres .. " players(s) found"
    result.data.players = dbres
    local inspect = require("inspect")
    cc.printdebug("return result: %s", inspect(result))
    return result
end

_handleSNAP = function (parts, args)
    return snap:handleSNAP(parts, args)
end

_handleOK = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }
    if parts[3] then
        result.data.game_id = parts[3]
    end

    return result
end

_handleERR = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.Error.AllinError, msg = "ERR: " .. table.concat(table.subrange(parts, 3, #parts), " ")}
    }

    return result
end

local _serverCmdHandler = {
    PSERVER         = _handlePSERVER,
    SNAP            = _handleSNAP,
    GAMEINFO        = _handleGAMEINFO,
    GAMELIST        = _handleGAMELIST,
    PLAYERLIST      = _handlePLAYERLIST,
    CLIENTINFO      = _handleCLIENTINFO,
    OK              = _handleOK,
    ERR             = _handleERR
}
GameAction.ServerCmdHandler = _serverCmdHandler

-- public methods
function GameAction:ctor(config)
    GameAction.super.ctor(self, config)
    local allinMsgChannel = WebSocketInstance.EVENT.ALLIN_MESSAGE .. "_" .. self:getInstance():getConnectId()
    self:getInstance():addEventListener(allinMsgChannel, cc.handler(self, self.onAllinMessage))
    self:getInstance():addEventListener(WebSocketInstance.EVENT.DISCONNECT, cc.handler(self, self.onDisconnect))
end

function GameAction:versioncheckAction(args)
    local data = args.data
    local client_version = data.client_version
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }
    if not client_version then
        result.data.msg = "client_version not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --tcp msg format: PCLIENT 5 934a69ec-034a-4ced-81d7-4ba097157096
    local message = msgid .. " PCLIENT " .. client_version .. " " .. self:getInstance():getAllinSession() .. " " ..self:getInstance():getCid() .. "\n" -- '\n' is mandatory
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 
    
    return 
end

function GameAction:creategameAction(args)
    local data = args.data
    local msgid = args.__id

    -- user input validity check
    local game_mode = data.game_mode
    local start_at = 0
    local allow_rebuy = 0
    local allow_rebuy_after = 0
    local deny_register_after = 0
    if not game_mode or game_mode ~= Constants.GameMode.GameModeFreezeOut then
        game_mode = Constants.GameMode.GameModeSNG -- default to SNG
        cc.printinfo("game_mode set to default: %d", game_mode)
    else
        game_mode = data.game_mode
        start_at =  data.start_at
        allow_rebuy = data.allow_rebuy
        allow_rebuy_after = data.allow_rebuy_after
        deny_register_after = data.deny_register_after
    end

    local max_players = data.max_players
    if not max_players then
        max_players = 5
        cc.printinfo("max_players set to default: %d", max_players)
    end
    local stake = data.stake -- player's initial stake
    if not stake then
        stake = 1500
        cc.printinfo("stake set to default: %d", stake)
    end
    local timeout = data.timeout -- user action timeout, in seconds
    if not timeout then
        timeout = 30
        cc.printinfo("timeout set to default: %d", timeout)
    end
    local blinds_start = data.blinds_start
    if not blinds_start then
        blinds_start = 20
        cc.printinfo("blinds_start set to default: %d", blinds_start)
    end
    local blinds_factor = data.blinds_factor -- blind.amount = (blind.blinds_factor * blind.amount) / 10
    if not blinds_factor then
        blinds_factor = 20
        cc.printinfo("blinds_factor set to default: %d", blinds_factor)
    end
    local blinds_time = data.blinds_time -- time interval to raise blinds, in seconds
    if not blinds_time then
        blinds_time = 300
        cc.printinfo("blinds_time set to default: %d", blinds_time)
    end
    local password = data.password
    if not timeout then
        password = ""
        cc.printinfo("password not set")
    end
    local name = data.name
    if not name then
        local nickname = self:getInstance():getNickname()
        name = nickname .. "'s game"
        cc.printinfo("name set to default: %s", name)
    end
    local expire_in = data.expire_in
    if not expire_in then
        expire_in = 30 * 60
        cc.printinfo("expire_in set to default: %d", expire_in)
    end
    local club_id = data.club_id
    if not club_id then
        club_id = 0
        cc.printinfo("club_id set to default: %d", club_id)
    end

    self._currentAction = args.action
    self._msgid = msgid
    local result = {state_type = "action_state", data = {
        action = args.action}
    }


    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local game_id, err = instance:getNextId("game")
    if not game_id then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "failed to get next_id for table game, err: %s" .. err
        return result
    end

    --tcp msg format: CREATE game_id: 23 players:5 stake:1500 timeout:30 blinds_start:20 blinds_factor:20 blinds_time:300 password: "name:peter's game 1"
    local message = msgid .. " CREATE game_id:"         .. game_id
                                .. " players:"          .. max_players 
                                .. " stake:"            .. stake 
                                .. " timeout:"          .. timeout
                                .. " blinds_start:"     .. blinds_start
                                .. " blinds_factor:"    .. blinds_factor
                                .. " blinds_time:"      .. blinds_time
                                .. " password:"         .. password
                                .. " \"name:"           .. name .. "\""
                                .. "\n" -- '\n' is mandatory
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    local sql = "INSERT INTO game (max_players, stake, timeout, blinds_start, blinds_factor, blinds_time, password, name, state, owner_id, expire_in, club_id, game_mode, start_at, allow_rebuy, allow_rebuy_after, deny_register_after) "
                      .. " VALUES (" .. max_players .. ", "
                               ..  stake .. ", "
                               ..  timeout .. ", "
                               ..  blinds_start .. ", "
                               ..  blinds_factor .. ", "
                               ..  blinds_time .. ", "
                               .. instance:sqlQuote(password) .. ", "
                               .. instance:sqlQuote(name) .. ", "
                               ..  1 .. ", "
                               .. "(SELECT id FROM user WHERE session = " .. instance:sqlQuote(self:getInstance():getAllinSession()) .. "), "
                               .. expire_in .. ", "
                               .. club_id .. ", "
                               .. game_mode .. ", "
                               .. start_at .. ", "
                               .. allow_rebuy .. ", "
                               .. allow_rebuy_after .. ", "
                               .. deny_register_after .. ");"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    return 
end

function GameAction:listgameAction(args)
    local data = args.data
    local club_id = data.club_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid
    self._club_id = club_id

    --send command to allin server, tcp format: REGISTER 1
    local message = msgid .. " REQUEST gamelist\n"
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local name = data.name
    if not name then
        local nickname = self:getInstance():getNickname()
        name = nickname .. "'s game"
        cc.printinfo("name set to default: %s", name)
    end
    local expire_in = data.expire_in
    if not expire_in then
        expire_in = 30 * 60
        cc.printinfo("expire_in set to default: %d", expire_in)
    end
    local club_id = data.club_id
    if not club_id then
        club_id = 0
        cc.printinfo("club_id set to default: %d", club_id)
    end

    self._currentAction = args.action
    self._msgid = msgid
    self._club_id = club_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }


    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local game_id, err = instance:getNextId("game")
    if not game_id then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "failed to get next_id for table game, err: " .. err
        return result
    end

    --tcp msg format: CREATE game_id: 23 players:5 stake:1500 timeout:30 blinds_start:20 blinds_factor:20 blinds_time:300 password: "name:peter's game 1"
    local message = msgid .. " CREATE game_id:"         .. game_id
                                .. " type:"             .. game_mode 
                                .. " players:"          .. max_players 
                                .. " stake:"            .. stake 
                                .. " timeout:"          .. timeout
                                .. " blinds_start:"     .. blinds_start
                                .. " blinds_factor:"    .. blinds_factor
                                .. " blinds_time:"      .. blinds_time
                                .. " password:"         .. password
                                .. " expire_in:"        .. expire_in
                                .. " \"name:"           .. name .. "\""
                                .. "\n" -- '\n' is mandatory
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    local sql = "INSERT INTO game (max_players, stake, timeout, blinds_start, blinds_factor, blinds_time, password, name, state, owner_id, expire_in, club_id, game_mode, start_at, allow_rebuy, allow_rebuy_after, deny_register_after) "
                      .. " VALUES (" .. max_players .. ", "
                               ..  stake .. ", "
                               ..  timeout .. ", "
                               ..  blinds_start .. ", "
                               ..  blinds_factor .. ", "
                               ..  blinds_time .. ", "
                               .. instance:sqlQuote(password) .. ", "
                               .. instance:sqlQuote(name) .. ", "
                               ..  1 .. ", "
                               .. "(SELECT id FROM user WHERE session = " .. instance:sqlQuote(self:getInstance():getAllinSession()) .. "), "
                               .. expire_in .. ", "
                               .. club_id .. ", "
                               .. game_mode .. ", "
                               .. start_at .. ", "
                               .. allow_rebuy .. ", "
                               .. allow_rebuy_after .. ", "
                               .. deny_register_after .. "); "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    if game_mode == Constants.GameMode.GameModeFreezeOut then
        -- add game owner to the channel
        local channel = "mtt_" .. tostring(game_id)
        local res, err = Leancloud:subscribeChannel({channel = channel, 
                                    installation = instance:getInstallation()
                                    })
        if not res then
            result.data.state = Constants.Error.LeanCloudError
            result.data.msg = "failed to subscribe to channel: " .. err
            return result
        end
    
        -- push reminder to all registered players 10 minutes before mtt game starts
        local message = "您报名的MTT大型赛事《" 
                        .. name 
                        .. "》即将在10分钟后（" 
                        .. os.date('%Y-%m-%d %H:%M', start_at) 
                        .. "）开始，请做好准备！"

        local args = {channel=channel, push_time = start_at - 10 * 60} 
        -- for test: local args = {channel=channel, push_time = os.time() + 60} 
        local res, err = Leancloud:push(args, message)
        if not res then
            result.data.state = Constants.Error.LeanCloudError
            result.data.msg = "failed to push message to channel: " .. err
            cc.printdebug("failed to push message: %s", err)
            return result
        end

        --[[ calling Leancloud:push from worker processes won't work because resty.http uses ngx context
        local action = "/jobs/jobs.mttstarting"
        local delay = start_at - 10 * 60     -- 10 minutes before start time
        local data = {channel = channel, start_at = start_at}
        _addJob(instance:getJobs(), action, delay, data)
        --]]
    end

    return 
end

function GameAction:listgameAction(args)
    local data = args.data
    local club_id = data.club_id
    local limit = data.limit or Constants.Limit.ListGameLimit
    local offset = data.offset or 0
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    if limit > 50 then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListGameLimit .. " allowed in one query"
        result.data.state = PermissionDenied
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid
    self._club_id = club_id
    self._limit = limit
    self._offset = offset

    --send command to allin server, tcp format: REGISTER 1
    local message = msgid .. " REQUEST gamelist\n"
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:joingameAction(args)
    local data = args.data
    local game_id = data.game_id
    local password = data.password or ""
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    local user_clubs = instance:getClubIds()
    if not table.contains(user_clubs, game.club_id) then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not member of club with club_id: " .. game.club_id
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: REGISTER 1
    local message = msgid .. " REGISTER " .. game_id .. " " .. password .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:leavegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: UNREGISTER 1
    local message = msgid .. " UNREGISTER " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:requestgameinfoAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: REQUEST gameinfo 1
    local message = msgid .. " REQUEST gameinfo " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:onAllinMessage(event)
    -- This function is called in a seperate thread from /opt/gbc-core/src/packages/allin/NginxAllinLoop.lua
    local message = event.message
    local mysql   = event.mysql
    if not message then
        cc.printdebug("message not found in event")
    end
    if not mysql then
        cc.printdebug("mysql not found in event")
    end

    local websocket = event.websocket
    if not websocket then
        cc.printdebug("websocket not found in event")
    end

    websocket:sendMessage(self:processMessage(message, mysql))
end

function GameAction:requestplayerlistAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action

    --send command to allin server, tcp format: REQUEST gameinfo 1
    local message = msgid .. " REQUEST playerlist " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:requestplayerinfoAction(args)
    local data = args.data
    local user_id = data.user_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not user_id then
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"user_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT id, phone, nickname, club_id FROM user WHERE id = " .. user_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "player with user_id: " .. user_id .. " not found"
        return result
    end

    local player = dbres[1]
    result.data.id          = player.id
    result.data.phone       = player.phone
    result.data.nickname    = player.nickname
    result.data.club_id     = player.club_id
    result.data.state = Constants.OK
    return result
end

function GameAction:startgameAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end


    self._currentAction = args.action
    self._msgid = msgid

    -- check if current user is the game owner
    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    if game.owner_id ~= user_id then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not game owner, only the game owner can start a game"
        return result
    end
    if game.state ~= 1 then
        result.data.state = Constants.Error.LogicError
        result.data.msg = "game already started or ended"
        return result
    end
    if game.game_mode == Constants.GameMode.GameModeFreezeOut then
        result.data.state = Constants.Error.LogicError
        result.data.msg = "cannot start MTT games. MTT games will start automatically at scheduled time"
        return result
    end

    -- at least 2 players are required. user_game_history records are added in handleGameInfo
    local sql = "SELECT * FROM user_game_history WHERE game_id = " .. game_id .. " AND user_state  = 1 or user_state = 5" -- 5=0x01(is_player) | 0x04(is_owner)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres < 2 then
        result.data.state = Constants.Error.LogicError
        result.data.msg = "there must be at least 2 players joined the game before the game can be started"
        return result
    end

    --send command to allin server, tcp format: REQUEST start 1
    local message = msgid .. " REQUEST start " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:pausegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local delay = data.delay   -- in seconds
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    -- check if current user is the game owner
    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    if game.owner_id ~= user_id then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not game owner, only the game owner can pause a game"
        return result
    end

    --send command to allin server, tcp format: REQUEST start 1
    local message = msgid .. " REQUEST pause " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:resumegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local delay = data.delay   -- in seconds
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    -- check if current user is the game owner
    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    if game.owner_id ~= user_id then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not game owner, only the game owner can resume a game"
        return result
    end

    --send command to allin server, tcp format: REQUEST start 1
    local message = msgid .. " REQUEST resume " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:useractionAction(args)
    local data = args.data 
    local game_id = data.game_id 
    local msgid = args.__id 
    local user_action = data.user_action 
    local amount = data.amount or 0 
    local result = {state_type = "action_state", data = { action = args.action} }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end
    if not user_action then
        result.data.msg = "user_action not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"user_action\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: ACTION <game_id> <action_name> <amount>
    local message = msgid .. " ACTION " .. game_id .. " " .. user_action .. " " .. amount .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:processMessage(message, mysql)
    cc.printdebug("GameAction:processMessage processing message: %s", message)
    local parts = string_split(message, " ")
    local cmd = parts[1]

    if tonumber(cmd) ~= nil then
       cmd = parts[2] 
    end

    if not self.ServerCmdHandler[cmd] then
       return { err = "Unknown server response: " .. cmd }
    end
    
    return self.ServerCmdHandler[cmd](parts, {action = self._currentAction
                                            , msgid = self._msgid
                                            , club_id = self._club_id
                                            , limit = self._limit
                                            , offset = self._offset
                                            , mysql = mysql
                                            , user_id = self:getInstance():getCid()
                                            , instance = self:getInstance()
                                            })
end


function GameAction:onDisconnect(event)
    -- unregister all games user has registered
    local message = " UNREGISTER -1 " .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        local err = Constants.Error.AllinError
        cc.printwarn("failed to send message: %s", err)
    end 
end

return GameAction
