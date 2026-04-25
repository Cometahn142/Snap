--!strict
--!optimize 2
--!native

local freeThreads: { thread } = {}

local function yielder()
	while true do
		local fn: any, a: any, b: any = coroutine.yield()
		fn(a, b)
		table.insert(freeThreads, coroutine.running())
	end
end

local function acquire(): thread
	local n = #freeThreads
	if n > 0 then
		local t = freeThreads[n]
		freeThreads[n] = nil
		return t
	end
	local t = coroutine.create(yielder)
	coroutine.resume(t)
	return t
end

local function spawn1(fn: (any) -> (), a: any)
	task.spawn(acquire(), fn, a, nil)
end

local function spawn2(fn: (any, any) -> (), a: any, b: any)
	task.spawn(acquire(), fn, a, b)
end

return table.freeze({
	spawn1 = spawn1,
	spawn2 = spawn2,
})
