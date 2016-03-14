
local Online = cc.import("#online")
local Leancloud = cc.import("#leancloud")

local gbc = cc.import("#gbc")
local JobsAction = cc.class("JobsAction", gbc.ActionBase)

JobsAction.ACCEPTED_REQUEST_TYPE = "worker"

function JobsAction:echoAction(job)
    local username = job.data.username
    local message = job.data.message

    local online = Online:new(self:getInstance())
    online:sendMessage(username, {
        name   = "MESSAGE",
        sender = username,
        body   = string.format("'%s' do a job, message is '%s', delay is %d", username, message, job.delay),
    })
end

function JobsAction:mttstartingAction(job)
    local channel = job.data.channel or ""
    local start_at = job.data.start_at

    local message = "您报名的MTT大型赛事即将在10分钟后（%s）开始，请做好准备！"
    string.format(message, os.date('%Y-%m-%d %H:%M:%S', start_at))

    local res, err = Leancloud:push({channel=channel}, message)
    if not res then
        result.data.state = Constants.Error.LeanCloudError
        result.data.msg = "failed to push message to channel: " .. err
        cc.printdebug("failed to push message: %s", err)
        return result
    end
end

return JobsAction
