local Session = cc.import("#session")
local Online = cc.import("#online")

local gbc = cc.import("#gbc")
local WebSocketInstance = cc.class("WebSocketInstance", gbc.WebSocketInstanceBase)

local _EVENT = table.readonly({
    ALLIN_MESSAGE       = "ALLIN_MESSAGE",
    DISCONNECT          = "DISCONNECT"
})
WebSocketInstance.EVENT = _EVENT

function WebSocketInstance:ctor(config)
    WebSocketInstance.super.ctor(self, config)
    self:addEventListener(WebSocketInstance.super.EVENT.CONNECTED, cc.handler(self, self.onConnected))
    self:addEventListener(WebSocketInstance.super.EVENT.DISCONNECTED, cc.handler(self, self.onDisconnected))
end

function WebSocketInstance:onConnected()
    -- do nothing
    self:sendMessage({message = "Welcome back, " .. self._nickname})
    -- load session
    local redis = self:getRedis();
    local session = Session:new(redis)

    session:start()
    local username = self:getCid()
    session:set("username", username)
    session:save()

    -- add user to online users list
    local online = Online:new(self)
    online:add(username, self:getConnectId())

    -- add user to each of his/her club's online user list
    local clubIds = self:getClubIds()
    local inspect = require("inspect")
    if type(clubIds) == "table" then
        for key, value in pairs(clubIds) do
            online:addToClub(self:getCid(), value)
        end
    end

    self._session = session
    self._online = online
end

function WebSocketInstance:onDisconnected(event)
    if event.reason ~= gbc.Constants.CLOSE_CONNECT then
        -- connection interrupted unexpectedly, remove user from online list
        cc.printwarn("[websocket:%s] connection interrupted unexpectedly", self:getConnectId())
        local username = self.getCid()

        -- remove user to each of his/her club's online user list
        local clubs = self:getClubIds()
        if type(clubs) == "table" then
            for key, value in pairs(clubs) do
                local online = self:getOnline()
                online:removeFromClub(self:getCid(), value)
            end
        end
        self._online:remove(username)
    end

    self:dispatchEvent({
        name    = _EVENT.DISCONNECT,
        websocket = self,
        mysql     = mysql
    })
end

function WebSocketInstance:validateSession(session)
    local mysql = self:getMysql()

    local sql = "select * from user where session = \'".. session .. "\';"
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return nil
    end
    if next(dbres) == nil then
        return nil
    end

    self._nickname = dbres[1].nickname
    self._cid = dbres[1].id
    self._phone = dbres[1].phone
    self._allinSession = session
    self._installation = dbres[1].installation 
    return true
end

function WebSocketInstance:getAllinSession()
    return self._allinSession
end

function WebSocketInstance:getNickname()
    return self._nickname
end

function WebSocketInstance:getCid()
    return self._cid
end

function WebSocketInstance:getPhone()
    return self._phone
end

function WebSocketInstance:getInstallation()
    return self._installation
end

function WebSocketInstance:getOnline()
    return self._online
end

function WebSocketInstance:getClubIds()
    local mysql = self:getMysql()
    local sql = "SELECT club_id from user_club WHERE deleted = 0 AND user_id = ".. self:getCid() .. ";"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return nil
    end
    if next(dbres) == nil then
        return nil
    end
    
    local clubs = {}
    while next(dbres) ~= nil do
        table.insert(clubs, dbres[1].club_id)
        table.remove(dbres, 1)
    end

    return clubs;
end

function WebSocketInstance:addCustomLoop()
    -- in the thread handling message from allin server, mysql connection cannot be reused, otherwise a "context 2" error occurs
    -- we need to create another mysql connection. TODO: find out why
    local mysql = self:createMysql()
    if not mysql then
        cc.throw("cannot create mysql connection")
    end

    -- create connection to allin server
    local allin, err = self:getAllin():makeAllinLoop(connectId, mysql)
    if not allin then
        cc.throw("Error creating connnection to allin server: %s", err)
    end

    allin:start(function(message, mysql)
        cc.printdebug("dispatching response %s", message)
        self:dispatchEvent({
            name    = _EVENT.ALLIN_MESSAGE .. "_" .. self:getConnectId(),
            message = message,
            websocket = self,
            mysql     = mysql
        })
    end)
    self._allinloop = allin
end

function WebSocketInstance:stopCustomLoop()
    if not self._allinloop then
        self._allinloop.stop()
        self._allinloop = nil
    end
end

return WebSocketInstance
