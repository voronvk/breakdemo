local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakService = require(script.Parent.BreakService)
local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CollisionBreak = {}

local hookedParts: { [BasePart]: boolean } = {}
local recentPairs: { [string]: number } = {}
local debrisFolderName = "BreakDebris"

local function pairKey(rootA: BasePart, rootB: BasePart): string
	if rootA:GetFullName() < rootB:GetFullName() then
		return rootA:GetFullName() .. "|" .. rootB:GetFullName()
	end
	return rootB:GetFullName() .. "|" .. rootA:GetFullName()
end

local function isOnCooldown(rootA: BasePart, rootB: BasePart): boolean
	local key = pairKey(rootA, rootB)
	local lastTime = recentPairs[key]
	if lastTime and os.clock() - lastTime < GameConfig.CollisionBreakCooldown then
		return true
	end
	recentPairs[key] = os.clock()
	return false
end

local function isDebrisPart(hit: BasePart): boolean
	if hit.Name == "BreakDebris" then
		return true
	end

	local parent = hit.Parent
	return parent ~= nil and parent.Name == debrisFolderName
end

local function isValidCollisionTarget(part: BasePart, hit: BasePart): boolean
	if hit == part or hit.AssemblyRootPart == part.AssemblyRootPart then
		return false
	end

	if not hit.CanCollide or isDebrisPart(hit) then
		return false
	end

	if not BreakableUtil.isBreakable(hit) then
		return false
	end

	if BreakableUtil.isPartBrokenState(part) or BreakableUtil.isPartBrokenState(hit) then
		return false
	end

	if BreakableUtil.isTreeForming(part) or BreakableUtil.isTreeForming(hit) then
		return false
	end

	return true
end

local function getRelativeImpactSpeed(part: BasePart, hit: BasePart): number
	local velocityA = part.AssemblyLinearVelocity
	local velocityB = hit.AssemblyLinearVelocity
	local relative = (velocityA - velocityB).Magnitude

	if part.Anchored and not hit.Anchored then
		return math.max(relative, velocityB.Magnitude)
	end

	if hit.Anchored and not part.Anchored then
		return math.max(relative, velocityA.Magnitude)
	end

	return relative
end

local function breakVictim(victim: BasePart, contactPoint: Vector3, useStrongBreak: boolean)
	if BreakableUtil.isHard(victim) then
		return
	end

	BreakService.breakFromFall(victim, contactPoint, {
		useStrongBreak = useStrongBreak,
	})
end

local function getContactPoint(part: BasePart, hit: BasePart): Vector3
	return (part.Position + hit.Position) * 0.5
end

local function tryBreakFromCollision(part: BasePart, hit: BasePart)
	if ReplicatedStorage:GetAttribute("MapRestoring") == true then
		return
	end

	if not BreakableUtil.isBreakable(part) or BreakableUtil.isPartBrokenState(part) then
		return
	end

	if not isValidCollisionTarget(part, hit) then
		return
	end

	local partRoot = part.AssemblyRootPart
	local hitRoot = hit.AssemblyRootPart
	if isOnCooldown(partRoot, hitRoot) then
		return
	end

	local contactPoint = getContactPoint(part, hit)
	local impactSpeed = getRelativeImpactSpeed(part, hit)
	local partIsHard = BreakableUtil.isHard(part)
	local hitIsHard = BreakableUtil.isHard(hit)

	if partIsHard then
		if not hitIsHard and impactSpeed >= GameConfig.HardBreakOthersMinRelativeSpeed then
			breakVictim(hit, contactPoint, false)
		end
		return
	end

	if hitIsHard then
		if impactSpeed >= GameConfig.CollisionBreakMinRelativeSpeed then
			breakVictim(part, contactPoint, false)
		end
		return
	end

	if impactSpeed >= GameConfig.CollisionBreakMinRelativeSpeed then
		breakVictim(part, contactPoint, false)
		breakVictim(hit, contactPoint, false)
	end
end

function CollisionBreak.hookPart(part: BasePart)
	if hookedParts[part] then
		return
	end
	hookedParts[part] = true

	part.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end

		tryBreakFromCollision(part, hit)
	end)

	part.Destroying:Connect(function()
		hookedParts[part] = nil
	end)
end

return CollisionBreak
