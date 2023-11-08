export type NodeGrid = SharedTable -- {[number]: {[number]: number}}

local DIR = {
	Vector2.new(-1,0), Vector2.new(1,0), Vector2.new(0,-1), Vector2.new(0,1), -- Cardinal
	Vector2.new(-1,-1), Vector2.new(1,-1), Vector2.new(-1,1), Vector2.new(1,1), -- Diagonal
}
local CARDINAL_DIR = {
	DIR[1], DIR[2], DIR[3], DIR[4], -- Cardinal
}
local DIR_COST = {
	[DIR[1]] = 1,
	[DIR[2]] = 1,
	[DIR[3]] = 1,
	[DIR[4]] = 1,
	[DIR[5]] = 1.4,
	[DIR[6]] = 1.4,
	[DIR[7]] = 1.4,
	[DIR[8]] = 1.4,
}

local TARGET_COL = Color3.new(1,0,0)

local Util = {
	DIR = DIR,
	CARDINAL_DIR = CARDINAL_DIR,
	DIR_COST = DIR_COST,
	TARGET_COL = TARGET_COL,
}

function Util.isInGrid(gridSizeX: number, gridSizeY: number, x: number, y: number): boolean
	return x >= 0 and x <= gridSizeX and y >= 0 and y <= gridSizeY
end

return Util