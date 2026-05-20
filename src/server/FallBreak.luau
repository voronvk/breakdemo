local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreakService = require(script.Parent.BreakService)
local FallTracker = require(script.Parent.FallTracker)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local FallBreak = {}

local hookedParts: { [BasePart]: boolean } = {}

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

	if part.Anchored then
		return false
	end

	return part.AssemblyLinearVelocity.Y <= GameConfig.FallBreakFreefallVelocity
end

local function startFallWatch(part: BasePart)
	if FallTracker.isWatching(part) then
		return
	end

	if not shouldTrackFreefall(part) then
		return
	end

	FallTracker.watch(
		part,
		function(fallingPart, contactPoint)
			BreakService.breakFromFall(fallingPart, contactPoint)
		end,
		{
			minHeight = GameConfig.FallBreakMinHeight,
			minSpeed = GameConfig.FallBreakMinSpeed,
		}
	)
end

local function hookPart(part: BasePart)
	if hookedParts[part] then
		return
	end
	hookedParts[part] = true

	part:GetPropertyChangedSignal("Anchored"):Connect(function()
		if part.Anchored then
			return
		end

		task.spawn(function()
			for _ = 1, 80 do
				if not part.Parent or part:GetAttribute("Broken") then
					break
				end
				if shouldTrackFreefall(part) then
					startFallWatch(part)
					break
				end
				task.wait(0.05)
			end
		end)
	end)

	part:GetAttributeChangedSignal("Broken"):Connect(function()
		if part:GetAttribute("Broken") then
			FallTracker.unwatch(part)
		end
	end)

	part.Destroying:Connect(function()
		hookedParts[part] = nil
		FallTracker.unwatch(part)
	end)

	if shouldTrackFreefall(part) then
		startFallWatch(part)
	end
end

local function registerBreakable(instance: Instance)
	for _, part in collectParts(instance) do
		hookPart(part)
	end
end

for _, instance in CollectionService:GetTagged(GameConfig.BreakableTag) do
	registerBreakable(instance)
end

CollectionService:GetInstanceAddedSignal(GameConfig.BreakableTag):Connect(registerBreakable)

return FallBreak
