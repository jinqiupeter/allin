local _tcp, _null, _unix_socket, _TIME_MULTIPLY
if ngx and ngx.socket then
    _tcp = ngx.socket.tcp
    _null = ngx.null
    _TIME_MULTIPLY = 1000
else
    local socket = require("socket")
    _tcp = socket.tcp
    _null = function() return nil end
    _unix_socket = require("socket.unix")
    _TIME_MULTIPLY = 1
end

local pairs         = pairs
local string_byte   = string.byte
local string_format = string.format
local string_lower  = string.lower
local string_sub    = string.sub
local string_upper  = string.upper
local table_concat  = table.concat
local table_new     = table.new
local tonumber      = tonumber
local tostring      = tostring
local type          = type

local Loop
if ngx then
    Loop = cc.import(".NginxAllinLoop")
end

local Allin = cc.class("Allin")

Allin.VERSION = "0.1"
Allin.null    = _null

local DEFAULT_HOST = "localhost"
local DEFAULT_PORT = 40888

local _genreq, _readreply, _checksub

function Allin:ctor()
    self._config = {}
end

function Allin:connect(host, port)
    local socket_file, socket, ok, err
    host = host or DEFAULT_HOST
    if string_sub(host, 1, 5) == "unix:" then
        socket_file = host
        if _unix_socket then
            socket_file = string_sub(host, 6)
            socket = _unix_socket()
        else
            socket = _tcp()
        end
        ok, err = socket:connect(socket_file)
    else
        socket = _tcp()
        ok, err = socket:connect(host, port or DEFAULT_PORT)
    end

    if not ok then
        return nil, err
    end

    self._config = {host = host, port = port}
    self._socket = socket
    return 1
end

function Allin:setTimeout(timeout)
    local socket = self._socket
    if not socket then
        return nil, "not initialized"
    end
    return socket:settimeout(timeout * _TIME_MULTIPLY)
end

function Allin:setKeepAlive(...)
    local socket = self._socket
    if not socket then
        return nil, "not initialized"
    end

    self._socket = nil
    if not ngx then
        return socket:close()
    else
        return socket:setkeepalive(...)
    end
end

function Allin:getReusedTimes()
    local socket = self._socket
    if not socket then
        return nil, "not initialized"
    end
    if socket.getreusedtimes then
        return socket:getreusedtimes()
    else
        return 0
    end
end

function Allin:close()
    local socket = self._socket
    if not socket then
        return nil, "not initialized"
    end
    self._socket = nil
    return socket:close()
end

function Allin:sendMessage(msg)
    local socket = self._socket
    if not socket then
        return nil, "not initialized"
    end
    socket:settimeout(5 * 1000)  -- 5 seconds timeout. TODO: use timeout from config.luq
    return socket:send(msg)
end

function Allin:receive()
    local socket = self._socket
    if not socket then
        return nil, "not initialized"
    end
    return socket:receive()
end

function Allin:makeAllinLoop(id, mysql)
    if not Loop then
        return nil, "not support subscribe loop in current platform"
    end

    --[[
    local allin = Allin:new()
    local ok, err = allin:connect(self._config.host, self._config.port)
    if not ok then
        return nil, err
    end
    --]]
    return Loop:new(self, id, mysql)
end

-- private
return Allin
