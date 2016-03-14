local ipairs             = ipairs
local ngx_thread_kill    = ngx.thread.kill
local ngx_thread_spawn   = ngx.thread.spawn
local string_byte        = string.byte
local string_split       = string.split
local string_sub         = string.sub
local table_concat       = table.concat
local table_remove       = table.remove
local tostring           = tostring
local unpack             = unpack

local NginxAllinLoop = cc.class("NginxAllinLoop")

local _loop, _cleanup, _onmessage, _onerror

function NginxAllinLoop:ctor(allin, id, mysql)
    self._allin = allin
    self._mysql = mysql
    id = id or ""
    cc.printdebug("id : %s", id)
    self._id = id .. "_" .. string_sub(tostring(self), 10)
end

function NginxAllinLoop:start(onmessage, cmdchannel, ...)
    if not self._allin then
        return nil, " NginxAllinLoop:start: allin not initialized"
    end
    local onmessage = onmessage or _onmessage
    local onerror = _onerror
    self._cmdchannel = cmdchannel

    self._thread = ngx_thread_spawn(_loop, self, onmessage, onerror)
    return 1
end

function NginxAllinLoop:stop()
    _cleanup(self)
end

-- add methods

-- private
_loop = function(self, onmessage, onerror)
    local id         = self._id
    local allin      = self._allin
    local mysql      = self._mysql
    local running    = true
    local DEBUG = cc.DEBUG > cc.DEBUG_WARN

    while running do
        allin:setTimeout(10) -- 10 seconds
        local res, err = allin:receive()
        if not res then
            if err ~= "timeout" then
                cc.printdebug("error receiving data from server: %s", err)
                onerror(err, id)
                running = false -- stop loop
                break
            end
        else
            cc.printdebug("received server response: %s", res)
            onmessage(res, mysql)
        end
    end -- loop

    cc.printinfo("[Allin:%s] STOPPED", id)

    allin:setKeepAlive()
    _cleanup(self)
end

_cleanup = function(self)
    ngx_thread_kill(self._thread)
    self._thread = nil
    self._allin = nil
    self._id = nil
end

_onmessage = function(msg, pchannel, id)
    if pchannel then
        cc.printinfo("[AllinSub:%s] <%s> <%s> %s", id, pchannel, msg)
    else
        cc.printinfo("[AllinSub:%s] received: %s", id, msg)
    end
end

_onerror = function(err, id)
    cc.printwarn("[AllinSub:%s] onerror: %s", id, err)
end

return NginxAllinLoop
