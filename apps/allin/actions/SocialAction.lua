local string_split       = string.split
local gbc = cc.import("#gbc")
local json      = cc.import("#json")
local Constants  = cc.import(".Constants", "..")
local SocialAction = cc.class("SocialAction", gbc.ActionBase)

SocialAction.ACCEPTED_REQUEST_TYPE = "websocket"

local json_encode = json.encode
local json_decode = json.decode

-- public methods
function SocialAction:ctor(config)
    SocialAction.super.ctor(self, config)
end

function SocialAction:gametablechatAction(args)
    local data = args.data
    local game_id  = data.game_id
    local table_id = data.table_id
    local content  = data.content
    local message = {state_type = "chat_state", data = {
        action = args.action}
    }

    if not game_id then
        cc.printinfo("argument not provided: \"game_id\"")
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not table_id then
        cc.printinfo("argument not provided: \"table_id\"")
        result.data.msg = "table_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not content then
        cc.printinfo("argument not provided: \"content\"")
        result.data.msg = "content not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local content_type = data.content_type or "text" -- can be "text" or "voice", voice messages should be base64 encrypted
    message.data.content_type = content_type
    message.data.content = content

    local instance = self:getInstance()
    message.data.sender_id  = instance:getCid()
    local redis = instance:getRedis()

    local table_channel = Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id)
    cc.printdebug("sending message to game: %s, table: %s, message: %s", game_id, table_id, json_encode(message))
    local ok, err = redis:publish(table_channel, _formatmsg(message))
    if not ok then
        cc.printerror("failed to publish message to redis: %s", err)
        result.data.msg = "failed to publish message to redis: " .. err
        result.data.state = Constants.Error.RedisError 
        return result
    end

    return result
end

function SocialAction:updateinstallationAction(args)
    local data = args.data
    local result = {state_type = "action_state", data = {
        action = data.action, state = 0, msg = "installation updated"}
    }

    local user_id = data.user_id
    local installation = data.installation

    --parameter validity check
    if not user_id then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "user id not provided"
        return
    end
    if not installation then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "installation not provided"
        return
    end

    --check if phone is signed up
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "select * from user where id = ".. user_id .. ";"
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误" .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "user id " .. user_id .. " not found"
        return result
    end

    local sql = "update user set installation = " .. instance:sqlQuote(installation) .. " where id = ".. user_id .. ";"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    return result
end

-- private 
_formatmsg = function(message, format)
    format = format or Constants.MESSAGE_FORMAT_JSON
    if type(message) == "table" then
        if format == Constants.MESSAGE_FORMAT_JSON then
            message = json_encode(message)
        else
            -- TODO: support more message formats
        end
    end
    return tostring(message)
end

return SocialAction
