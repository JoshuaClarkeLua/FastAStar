local Util = {}

function Util.abs(v: Vector2): Vector2
	return Vector2.new(math.abs(v.X), math.abs(v.Y))
end

--[=[
	@within Vector2Util
	@function floor

	Floors each component of a vector
	@param v - Vector to floor
	@return Floored vector
]=]
function Util.floor(v: Vector2): Vector2
	return Vector2.new(math.floor(v.X),math.floor(v.Y))
end

--[=[
	@within Vector2Util
	@function ceil

	Ceil each component of a vector
	@param v - Vector to ceil
	@return Ceiled vector
]=]
function Util.ceil(v: Vector2): Vector2
	return Vector2.new(math.ceil(v.X), math.ceil(v.Y))
end

function Util.sign(v: Vector2): Vector2
	return Vector2.new(math.sign(v.X), math.sign(v.Y))
end

return Util