local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PriorityQueue = require(ReplicatedStorage.Shared.PriorityQueue)
local PriorityQueue2 = require(ReplicatedStorage.Shared.PriorityQueue2)



local q1 = PriorityQueue.new()
local q2 = PriorityQueue2.new()
local s: number
local _n = 1000
local _p = 10

-- q1
--1
s = os.clock()
for p = 1, _p do
	for i = 1, _n do
		q1:Put(i, p)
	end
end
print('q1', os.clock() - s)
--2
s = os.clock()
for i = 1, _n do
	for p = 1, _p do
		q1:Put(i, p)
	end
end
print('q1', os.clock() - s)
--3
s = os.clock()
for i = 1, _n*_p do
	q1:Pop()
end
print('q1', os.clock() - s)

-- q2
--1
s = os.clock()
for p = 1, _p do
	for i = 1, _n do
		q2:Add(i, p)
	end
end
print('q2', os.clock() - s)
--2
s = os.clock()
for i = 1, _n do
	for p = 1, _p do
		q2:Add(i, p)
	end
end
print('q2', os.clock() - s)
--3
s = os.clock()
for i = 1, _n*_p do
	q2:Pop()
end
print('q2', os.clock() - s)