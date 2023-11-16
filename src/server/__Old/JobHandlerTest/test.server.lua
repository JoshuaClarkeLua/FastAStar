local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ParallelJobHandler = require(ReplicatedStorage.Packages.ParallelJobHandler)

local actor = ParallelJobHandler.getActor()

actor:BindToMessageParallel("testA", function(self, i)
	-- print('testA')
	-- task.wait(3)
	self:Return('testA')
end)

actor:BindToMessageParallel("testB", function(self, i)
	-- print('testB')
	-- task.wait(3)
	self:Return('testB')
end)