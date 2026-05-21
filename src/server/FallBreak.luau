local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakService = require(script.Parent.BreakService)
local CollisionBreak = require(script.Parent.CollisionBreak)
local FallTracker = require(script.Parent.FallTracker)
local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local FallBreak = {}

local function resolveAssemblyRoot(part: BasePart): BasePart
	return part.AssemblyRootPart or part
end

local function unwatchPartAssemblies(part: BasePart)
	FallTracker.unwatch(part)
	local assemblyRoot = part.AssemblyRootPart
	if assemblyRoot and assemblyRoot ~= part then
		FallTracker.unwatch(assemblyRoot)
	end
end

local hookedParts: { [BasePart]: boolean } = {}
local breakableRoots: { [Instance]: boolean } = {}
local lastFreefallScan = 0
local freefallScanInterval = 0.15

local function collectParts(instance: Instance): { BasePart }
	local parts: { BasePart } = {}

	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	elseif instance:IsA("Model") then
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	return parts
end

local function shouldTrackFreefall(part: BasePart): boolean
	if part:GetAttribute("Broken") or part:GetAttribute("Shattered") then
		return false
	end

	if part.Anchored or BreakableUtil.isTreeForming(part) then
		return false
	end

	return part.AssemblyLinearVelocity.Y <= GameConfig.FallBreakFreefallVelocity
end

local function getFallThresholds(part: BasePart): (number, number)
	if BreakableUtil.isHard(part) then
		return GameConfig.HardFallBreakMinHeight, GameConfig.HardFallBreakMinSpeed
	end
	return GameConfig.FallBreakMinHeight, GameConfig.FallBreakMinSpeed
end

local function groupTouchPartsByAssembly(instanceParts: { BasePart }): { [BasePart]: { BasePart } }
	local byAssembly: { [BasePart]: { BasePart } } = {}

	for _, instancePart in instanceParts do
		if instancePart.Parent and not instancePart.Anchored and not BreakableUtil.isPartBrokenState(instancePart) then
			local assemblyRoot = resolveAssemblyRoot(instancePart)
			local touchParts = byAssembly[assemblyRoot]
			if not touchParts then
				touchParts = {}
				byAssembly[assemblyRoot] = touchParts
			end
			table.insert(touchParts, instancePart)
		end
	end

	return byAssembly
end

local function getRelativeImpactSpeed(part: BasePart, hit: BasePart): number
	return (part.AssemblyLinearVelocity - hit.AssemblyLinearVelocity).Magnitude
end

local function onFallImpact(fallingPart: BasePart, contactPoint: Vector3, hitPart: BasePart)
	local fallingIsHard = BreakableUtil.isHard(fallingPart)
	local impactSpeed = getRelativeImpactSpeed(fallingPart, hitPart)

	if fallingIsHard then
		if
			BreakableUtil.isBreakable(hitPart)
			and not BreakableUtil.isPartBrokenState(hitPart)
			and not BreakableUtil.isHard(hitPart)
			and impactSpeed >= GameConfig.HardBreakOthersMinRelativeSpeed
		then
			BreakService.breakFromFall(hitPart, contactPoint)
		end
		return
	end

	BreakService.breakFromFall(fallingPart, contactPoint)
end

local function startAssemblyFallWatch(assemblyRoot: BasePart, touchParts: { BasePart })
	if FallTracker.isWatching(assemblyRoot) then
		return
	end

	if not shouldTrackFreefall(assemblyRoot) then
		return
	end

	local minHeight, minSpeed = getFallThresholds(assemblyRoot)

	FallTracker.watch(
		assemblyRoot,
		onFallImpact,
		{
			minHeight = minHeight,
			minSpeed = minSpeed,
			touchParts = touchParts,
		}
	)
end

local function tryStartInstanceFallWatch(triggerPart: BasePart)
	if not BreakableUtil.isBreakable(triggerPart) or BreakableUtil.isPartBrokenState(triggerPart) then
		return
	end

	local instanceParts = BreakableUtil.getBreakableInstanceParts(triggerPart)
	local assemblies = groupTouchPartsByAssembly(instanceParts)

	for assemblyRoot, touchParts in assemblies do
		startAssemblyFallWatch(assemblyRoot, touchParts)
	end
end

function FallBreak.scheduleFallWatch(part: BasePart)
	if ReplicatedStorage:GetAttribute("MapRestoring") == true then
		return
	end

	if not BreakableUtil.isBreakable(part) or part:GetAttribute("Broken") then
		return
	end

	task.spawn(function()
		for _ = 1, 80 do
			if not part.Parent or part:GetAttribute("Broken") then
				break
			end
			tryStartInstanceFallWatch(part)
			if FallTracker.isWatching(resolveAssemblyRoot(part)) then
				break
			end
			task.wait(0.05)
		end
	end)
end

local function scanBreakableRootsForFreefall()
	if ReplicatedStorage:GetAttribute("MapRestoring") == true then
		return
	end

	local now = os.clock()
	if now - lastFreefallScan < freefallScanInterval then
		return
	end
	lastFreefallScan = now

	for root in breakableRoots do
		if not root.Parent then
			breakableRoots[root] = nil
			continue
		end

		for _, instancePart in collectParts(root) do
			if shouldTrackFreefall(instancePart) then
				tryStartInstanceFallWatch(instancePart)
			end
		end
	end
end

local function hookPart(part: BasePart)
	if hookedParts[part] then
		return
	end
	hookedParts[part] = true

	CollisionBreak.hookPart(part)

	part:GetPropertyChangedSignal("Anchored"):Connect(function()
		if part.Anchored then
			return
		end

		FallBreak.scheduleFallWatch(part)
	end)

	part:GetAttributeChangedSignal("Broken"):Connect(function()
		if part:GetAttribute("Broken") then
			unwatchPartAssemblies(part)
		end
	end)

	part.Destroying:Connect(function()
		hookedParts[part] = nil
		unwatchPartAssemblies(part)
	end)

	if shouldTrackFreefall(part) then
		tryStartInstanceFallWatch(part)
	end
end

local function hookBreakableRoot(instance: Instance)
	breakableRoots[instance] = true

	for _, instancePart in collectParts(instance) do
		hookPart(instancePart)
	end

	instance.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and BreakableUtil.isBreakable(descendant) then
			hookPart(descendant)
			if not descendant.Anchored then
				FallBreak.scheduleFallWatch(descendant)
			end
		end
	end)

	instance.Destroying:Connect(function()
		breakableRoots[instance] = nil
	end)
end

local function registerBreakRoot(instance: Instance)
	hookBreakableRoot(instance)
end

for _, instance in CollectionService:GetTagged(GameConfig.BreakableTag) do
	registerBreakRoot(instance)
end

for _, instance in CollectionService:GetTagged(GameConfig.HardTag) do
	registerBreakRoot(instance)
end

CollectionService:GetInstanceAddedSignal(GameConfig.BreakableTag):Connect(registerBreakRoot)
CollectionService:GetInstanceAddedSignal(GameConfig.HardTag):Connect(registerBreakRoot)

RunService.Heartbeat:Connect(scanBreakableRootsForFreefall)

return FallBreak
