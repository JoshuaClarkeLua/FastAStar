local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)


local handler = ParallelJobHandler.new(script.test, 128, true)

if not handler.IsReady then
	print('waiting')
	handler.OnReady:Wait()
	print('ready')
end

local a = 0
local b = 0
local ai = 0
handler:Run(function(actor)
	ai += 1
	actor:SendMessage("testA")
	actor:SendMessage("testA")
	-- actor:SendMessage("testB")
	-- print('A', ai)
	return ai == 64
end, {
	testA = function(actor, i)
		if i == "testA" then
			a += 1
		else
			b += 1
		end
	end,
	testB = function(actor, i)
		if i == "testA" then
			a += 1
		else
			b += 1
		end
	end,
}, 'A'):andThen(function()
	print(a, b)
end)

local bi = 0
handler:Run(function(actor)
	bi += 1
	actor:SendMessage("testB")
	actor:SendMessage("testB")
	-- actor:SendMessage("testB")
	-- print('B', bi)
	return bi == 64
end, {
	testA = function(actor, i)
		if i == "testA" then
			a += 1
		else
			b += 1
		end
	end,
	testB = function(actor, i)
		if i == "testA" then
			a += 1
		else
			b += 1
		end
	end,
}, 'B'):andThen(function()
	print(a, b)
end)