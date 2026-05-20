local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakVFX = require(script.Parent.BreakVFX)
local FallTracker = require(script.Parent.FallTracker)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local FallShatter = {}

local function shatterOnGround(part: BasePart, contactPoint: Vector3)
	if part:GetAttribute("Shattered") then
		return
	end

	part:SetAttribute("Shattered", true)

	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CanCollide = false

	BreakVFX.playGroundShatter(part, contactPoint)
	task.spawn(BreakVFX.quickFadePart, part)
end

function FallShatter.watch(part: BasePart)
	if part:GetAttribute("Shattered") then
		return
	end

	FallTracker.watch(part, shatterOnGround, {
		minHeight = GameConfig.FallShatterMinHeight,
		minSpeed = GameConfig.FallShatterMinSpeed,
	})
end

return FallShatter
