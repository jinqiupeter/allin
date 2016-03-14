local string_format = string.format

local json = cc.import("#json")
local json_encode = json.encode
local json_decode = json.decode
local http = require("resty/http")
local httpc = http.new()

local gbc = cc.import("#gbc")

local lc_app_id = "wm47B8HP9v2TpHq6PCMHj2YB-gzGzoHsz"
local lc_app_key = "TQuoN8SPi7sveRutaWJyYscL"
local default_headers = {
    ["Content-Type"] = "application/json",
    ["X-LC-Id"] = lc_app_id,
    ["X-LC-Key"] = lc_app_key
}

local Leancloud = cc.class("Leancloud")

function Leancloud:ctor(instance)
    self._instance  = instance
end

function Leancloud:requestsms(phone)
    if not phone then 
        return nil, "phone number not provided"
    end

    local body = "{\"mobilePhoneNumber\":\"" .. phone .. "\"}"
    --curl command: curl -X POST -H "X-LC-Id: UkJQrQpjsjQAWX6Rx9eMt6Bh-gzGzoHsz" -H "X-LC-Key: CqE2nYdhaTDxsYgcBOECLxK9" -H "Content-Type: application/json" -d '{"mobilePhoneNumber": "18662527616"}' https://api.leancloud.cn/1.1/requestSmsCode
    return httpc:request_uri("https://api.leancloud.cn/1.1/requestSmsCode", {
        method = "POST",
        ssl_verify = false,
        body = body,
        headers = default_headers
    })
end

function Leancloud:verifysms(phone, smscode)
    if not phone then 
        return nil, "phone number not provided"
    end
    if not smscode then
        return nil, "smd code not provided"
    end

    --"https://api.leancloud.cn/1.1/verifySmsCode/6位数字验证码?mobilePhoneNumber=186xxxxxxxx"
    local url = "https://api.leancloud.cn/1.1/verifySmsCode/" .. smscode .. "?mobilePhoneNumber=" .. phone
    return  httpc:request_uri(url, {
        method = "POST",
        ssl_verify = false,
        headers = default_headers
    })

end

function Leancloud:subscribeChannel(args)
    local channel = args.channel or ""
    local installation = args.installation
    if not installation then
        cc.printdebug("installation not registered, nothing to do")
        return
    end

    cc.printdebug("installation: %s subscribing to channel: %s" , installation, channel)

    local url = "https://leancloud.cn/1.1/installations/" .. installation
    local body = {channels={channel}}
    local json_body = json_encode(body)
    return  httpc:request_uri(url, {
        method = "PUT",
        ssl_verify = false,
        body = json_body,
        headers = default_headers
    })

end

function Leancloud:push(args, message)
    local channel = args.channel or ""
    local push_time = args.push_time
    if not message then
        return nil, "message not provided"
    end

    local url = "https://leancloud.cn/1.1/push"
    local body = {prod = "dev",
        data = {
            alert = message,
            badge = "Increment",
            sound = "default"
        },
        channels = {channel} 
    }
    if push_time then
        -- YYYY-MM-DDTHH:MM:SS.MMMZ
        body.push_time = os.date('!%Y-%m-%dT%H:%M:%S.000Z', push_time) -- ! means to convert to utc time
        cc.printdebug("push time: %s", body.push_time)
    end
    local json_body = json_encode(body)

    cc.printdebug("pushing message: %s to channel: %s", message, channel)
    return  httpc:request_uri(url, {
        method = "POST",
        ssl_verify = false,
        body = json_body,
        headers = default_headers
    })
end

return Leancloud
