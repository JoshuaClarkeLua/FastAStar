--[=[
	@class Vector3Util

	Provides utility functions for Vector3s
]=]

local Vec3 = {}

--[[
	@within Vector3Util
	@function scalarProjection

	Returns scalar projection of va onto vb
	@param va - Vector to be projected
	@param vb - Vector to project onto
]]
function Vec3.scalarProjection(va: Vector2 | Vector3, vb: Vector2 | Vector3)
	return (va :: Vector3):Dot((vb :: Vector3).Unit)
end

--[[
	@within Vector3Util
	@function project

	Projects va onto vb
	@param va - Vector to be projected
	@param vb - Vector to project onto
]]
function Vec3.project(va: Vector2 | Vector3, vb: Vector2 | Vector3)
	return Vec3.scalarProjection(va, vb) * vb.Unit
end

--[[
	@within Vector3Util
	@function projectOnPlane

	Projects v onto plane defined by normal n
	@param v - Vector to be projected
	@param n - Plane normal
]]
function Vec3.projectOnPlane(v: Vector3, n: Vector3)
	return v - Vec3.project(v, n)
end

--[=[
	@within Vector3Util
	@function maxMagnitude

	Returns the vector with the largest magnitude
	@param va - Vector to compare
	@param vb - Vector to compare
	@return Vector with the largest magnitude
]=]
function Vec3.maxMagnitude(va: Vector3, vb: Vector3)
	return va.Magnitude >= vb.Magnitude and va or vb
end

--[=[
	@within Vector3Util
	@function floor

	Floors each component of a vector
	@param v - Vector to floor
	@return Floored vector
]=]
function Vec3.floor(v: Vector3): Vector3
	return Vector3.new(math.floor(v.X),math.floor(v.Y),math.floor(v.Z))
end

--[=[
	@within Vector3Util
	@function mod

	Modulo each component of a vector
	@param v - Vector to modulo
	@param n - Number to modulo by
	@return Moduloed vector
]=]
function Vec3.mod(v: Vector3, n: number): Vector3
	return Vector3.new(v.X % n, v.Y % n, v.Z % n)
end

--[=[
	@within Vector3Util
	@function abs

	Absolute value of each component of a vector
	@param v - Vector to absolute
	@return Absolute vector
]=]
function Vec3.abs(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

--[=[
	@within Vector3Util
	@function round

	Round each component of a vector
	@param v - Vector to round
	@return Rounded vector
]=]
function Vec3.round(v: Vector3): Vector3
	return Vector3.new(math.round(v.X), math.round(v.Y), math.round(v.Z))
end

--[=[
	@within Vector3Util
	@function sign

	Sign of each component of a vector
	@param v - Vector to sign
	@return Signed vector
]=]
function Vec3.sign(v: Vector3): Vector3
	return Vector3.new(math.sign(v.X), math.sign(v.Y), math.sign(v.Z))
end

--[=[
	@within Vector3Util
	@function ceil

	Ceil each component of a vector
	@param v - Vector to ceil
	@return Ceiled vector
]=]
function Vec3.ceil(v: Vector3): Vector3
	return Vector3.new(math.ceil(v.X), math.ceil(v.Y), math.ceil(v.Z))
end

function Vec3.clamp(v: Vector3, min: Vector3, max: Vector3): Vector3
	return Vector3.new(math.clamp(v.X, min.X, max.X), math.clamp(v.Y, min.Y, max.Y), math.clamp(v.Z, min.Z, max.Z))
end

function Vec3.max(v: Vector3, n: number): Vector3
	return Vector3.new(math.max(v.X, n), math.max(v.Y, n), math.max(v.Z, n))
end

return Vec3