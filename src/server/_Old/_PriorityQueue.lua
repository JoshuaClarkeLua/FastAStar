local floor = math.floor

local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new(): PriorityQueue
	return setmetatable({
		heap = {},
		size = 0,
	}, PriorityQueue)
end

function PriorityQueue:Empty(): boolean
    return self.size == 0
end

function PriorityQueue:Size(): number
    return self.size
end

function PriorityQueue:Swim()
    -- Swim up on the tree and fix the order heap property.
    local heap = self.heap
    local floor = floor
    local i = self.size

    while floor(i / 2) > 0 do
        local half = floor(i / 2)
        if heap[i][2] < heap[half][2] then
            heap[i], heap[half] = heap[half], heap[i]
        end
        i = half
    end
end

function PriorityQueue:Put(v: any, p: number)
    self.heap[self.size + 1] = {v, p}
    self.size = self.size + 1
    self:Swim()
end

function PriorityQueue:Sink()
    -- Sink down on the tree and fix the order heap property.
    local size = self.size
    local heap = self.heap
    local i = 1

    while (i * 2) <= size do
        local mc = self:GetMin(i)
        if heap[i][2] > heap[mc][2] then
            heap[i], heap[mc] = heap[mc], heap[i]
        end
        i = mc
    end
end

function PriorityQueue:GetMin(i: number): number
    if (i * 2) + 1 > self.size then
        return i * 2
    else
        if self.heap[i * 2][2] < self.heap[i * 2 + 1][2] then
            return i * 2
        else
            return i * 2 + 1
        end
    end
end

function PriorityQueue:Pop(): (any, number)
    -- Remove and return the top priority item
    local heap = self.heap
    local val = heap[1][1]
	local priority = heap[1][2]
    heap[1] = heap[self.size]
    heap[self.size] = nil
    self.size = self.size - 1
    self:Sink()
    return val, priority
end

export type PriorityQueue = typeof(PriorityQueue.new(...))
return PriorityQueue