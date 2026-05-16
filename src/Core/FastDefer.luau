--!strict
--!native
--!optimize 2

local pendingByKey: { [string]: boolean } = {}
local callbackByKey: { [string]: () -> () } = {}

local FastDefer = {}

local function executeTask(key: string)
	pendingByKey[key] = nil
	local fn = callbackByKey[key]
	callbackByKey[key] = nil
	if fn then
		fn()
	end
end

function FastDefer.defer(key: string, callback: () -> ())
	if pendingByKey[key] then
		return
	end
	pendingByKey[key] = true
	callbackByKey[key] = callback

	task.defer(executeTask, key)
end

return FastDefer





