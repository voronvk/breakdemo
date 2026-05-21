local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local BreakBudget = {}

local activeBrokenCount = 0
local debrisFolderName = "BreakDebris"

function BreakBudget.getActiveBrokenCount(): number
	return activeBrokenCount
end

function BreakBudget.isOverCapacity(): boolean
	return activeBrokenCount >= GameConfig.MaxActiveBrokenParts
end

function BreakBudget.tryRegisterBroken(): boolean
	if activeBrokenCount >= GameConfig.MaxActiveBrokenParts then
		return false
	end
	activeBrokenCount += 1
	return true
end

function BreakBudget.releaseBroken()
	activeBrokenCount = math.max(0, activeBrokenCount - 1)
end

function BreakBudget.resetAll()
	activeBrokenCount = 0
end

function BreakBudget.getDebrisCount(): number
	local folder = Workspace:FindFirstChild(debrisFolderName)
	if not folder then
		return 0
	end
	return #folder:GetChildren()
end

function BreakBudget.shouldSpawnDebris(requestedCount: number): number
	local remaining = GameConfig.MaxDebrisInWorld - BreakBudget.getDebrisCount()
	if remaining <= 0 then
		return 0
	end
	return math.min(requestedCount, remaining)
end

function BreakBudget.useFullVfx(): boolean
	return not BreakBudget.isOverCapacity() and BreakBudget.getDebrisCount() < GameConfig.MaxDebrisInWorld * 0.85
end

return BreakBudget
