local Online = cc.import("#online")
local Leancloud = cc.import("#leancloud")
local Session = cc.import("#session")
local Constants = cc.import(".Constants", "..")

local gbc = cc.import("#gbc")
local AuthAction = cc.class("AuthAction", gbc.ActionBase)

local json      = cc.import("#json")
local json_encode = json.encode
local json_decode = json.decode

local _opensession

function AuthAction:requestsmscodeAction(args)
    local data = args.data
    if not data.phone then
        cc.throw("phone number not provided")
    end
    local phone = data.phone
    cc.printdebug("requestsmscode: phone: %s", phone)

    local result = {state_type = "action_state", data = {
        action = data.action, state = 0, msg = "发送成功"}
    }

    local res, err = Leancloud:sendsms(phone)
    if not res then
        result.data.state = Constants.Error.LeanCloudError
        result.data.msg = "发送失败: " .. err
        return result
    end

    local body = json_decode(res.body)
    if body.error then
        --LeanCloud returns like: {"code":601,"error":"发送验证类短信已经超过一天五条的限制。"}
        result.data.state = Constants.Error.LeanCloudError
        result.data.msg = body.error
        return result
    end
    cc.printdebug("requestsmscode: body: %s", res.body)

    return result
end

function AuthAction:signupAction(args)
    local inspect = require("inspect")
    local data = args.data
    local result = {state_type = "action_state", data = {
        action = data.action, state = 0, msg = "注册成功"}
    }

    local phone = data.phone
    local password = data.password
    local smscode = data.sms_code
    local nickname = phone
    if data.nickname then
        nickname = data.nickname
    end

    --parameter validity check
    if not phone then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "手机号码为空"
        return
    end
    --check if phone is already signed up
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local dbres, err, errno, sqlstate = mysql:query("select * from user where phone = \'".. phone .. "\'")
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误" .. err
        return result
    end
    if next(dbres) ~= nil then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "手机号" .. phone .. "已注册"
        return result
    end

    if not password then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "密码未设置"
        return result
    end
    if not smscode then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "短信验证码未填写"
        return result
    end

    cc.printdebug("signing up new user : %s", phone)

    local res, err = Leancloud:verifysms(phone, smscode)

    if not res then
        result.data.state = Constants.Error.LeanCloudError
        result.data.msg = "发送失败: " .. err
        return result
    end

    local body = json_decode(res.body)
    if body.error then
        result.data.state = Constants.Error.LeanCloudError
        result.data.msg = body.error
        return result
    end

    local sql = "insert into user (phone, password, nickname) "
                                                 .. " values (\'" .. phone .. "\', "
                                                             .. "\'" .. password .. "\', "
                                                             .. "\'" .. nickname .. "\');"

    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- put it into the connection pool of size 100,
    -- with 10 seconds max idle timeout
    local ok, err = mysql:set_keepalive(10000, 100)
    if not ok then
        cc.printwarn("AuthAction:signup() failed to set keepalive: %s", err)
    end

    return result
end

function AuthAction:signinAction(args)
    local inspect = require("inspect")
    local data = args.data
    local result = {state_type = "action_state", data = {
        action = data.action, state = 0, msg = "登录成功"}
    }

    local phone = data.phone
    local password = data.password

    --parameter validity check
    if not phone then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "手机号码为空"
        return
    end
    --check if phone is signed up
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "select * from user where phone = \'".. phone .. "\';"
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误" .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "手机号" .. phone .. "未注册"
        return result
    end

    --check if phone and password matches
    if not password then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "密码未设置"
        return result
    end
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "select * from user where phone = \'".. phone .. "\' and password=\'"  .. password .. "\';"
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误" .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "密码错误"
        return result
    end
    result.data.user_id = dbres[1].id

    -- generate a new session id on every login. we dont care about expiry, only use the sid string
    local instance = self:getInstance()
    local redis = instance:getRedis()
    local session = Session:new(redis)
    session:start()
    local session = session:getSid()

    local sql = "update user set session = \'" .. session .. "\', last_login=now() where phone = \'".. phone .. "\' and password=\'"  .. password .. "\';"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- put it into the connection pool of size 100,
    -- with 10 seconds max idle timeout
    local ok, err = mysql:set_keepalive(10000, 100)
    if not ok then
        cc.printwarn("AuthAction:signin failed to set keepalive: %s", err)
    end

    result.data.session = session
    return result
end


function AuthAction:signoutAction(args)
    --TODO
    --1. remove user from online user list
    return {err = "not implemented"}
end

return AuthAction
