local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local partRespawnRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartRespawn") :: RemoteEvent
local mapRevealBatchRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapRevealBatch") :: RemoteEvent

local ORIG_TRANSPARENCY_ATTR = "CloneMapOrigTransparency"

local activeTweens: { [BasePart]: { Tween } } = {}

local function getTargetTransparency(instance: Instance): number
	local original = instance:GetAttribute(ORIG_TRANSPARENCY_ATTR)
	if typeof(original) == "number" then
		return original
	end

	if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") then
		return instance.Transparency
	end

	return 0
end

local function addPartRevealTweens(part: BasePart, tweens: { Tween }, tweenInfo: TweenInfo)
	part.Transparency = 1

	local goals: { [string]: any } = {
		Transparency = getTargetTransparency(part),
	}

	local targetSize = part:GetAttribute("RespawnTargetSize")
	if typeof(targetSize) == "Vector3" then
		goals.Size = targetSize
	end

	table.insert(tweens, TweenService:Create(part, tweenInfo, goals))
end

local function playScaleIn(part: BasePart)
	if activeTweens[part] then
		for _, tween in activeTweens[part] do
			tween:Cancel()
		end
	end

	local tweens: { Tween } = {}
	local tweenInfo = TweenInfo.new(
		GameConfig.BreakRespawnScaleInDuration,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)

	addPartRevealTweens(part, tweens, tweenInfo)

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			local baseSize = descendant:GetAttribute("RespawnBaseSize")
			if typeof(baseSize) == "Vector3" then
				descendant.Transparency = 1
				table.insert(
					tweens,
					TweenService:Create(descendant, tweenInfo, {
						Transparency = getTargetTransparency(descendant),
						Size = baseSize,
					})
				)
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
			table.insert(
				tweens,
				TweenService:Create(descendant, tweenInfo, {
					Transparency = getTargetTransparency(descendant),
				})
			)
		end
	end

	if #tweens == 0 then
		return
	end

	activeTweens[part] = tweens
	for _, tween in tweens do
		tween:Play()
	end

	task.delay(GameConfig.BreakRespawnScaleInDuration, function()
		if activeTweens[part] then
			for _, tween in activeTweens[part] do
				tween:Cancel()
			end
			activeTweens[part] = nil
		end

		local finalSize = part:GetAttribute("RespawnTargetSize")
		if typeof(finalSize) == "Vector3" then
			part.Size = finalSize
		end
		part.Transparency = getTargetTransparency(part)

		for _, descendant in part:GetDescendants() do
			if descendant:IsA("BasePart") then
				local baseSize = descendant:GetAttribute("RespawnBaseSize")
				if typeof(baseSize) == "Vector3" then
					descendant.Size = baseSize
				end
				descendant.Transparency = getTargetTransparency(descendant)
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				descendant.Transparency = getTargetTransparency(descendant)
			end
		end
	end)
end

local function playScaleInBatch(parts: { BasePart })
	for _, part in parts do
		if part.Parent then
			playScaleIn(part)
		end
	end
end

local function parseBatchPayload(payload: unknown): { BasePart }
	local batch: { BasePart } = {}

	if typeof(payload) == "Instance" and payload:IsA("BasePart") then
		table.insert(batch, payload)
		return batch
	end

	if typeof(payload) ~= "table" then
		return batch
	end

	for _, entry in payload do
		if typeof(entry) == "Instance" and entry:IsA("BasePart") then
			table.insert(batch, entry)
		end
	end

	return batch
end

partRespawnRemote.OnClientEvent:Connect(function(part: unknown)
	local batch = parseBatchPayload(part)
	if #batch > 0 then
		playScaleInBatch(batch)
	end
end)

mapRevealBatchRemote.OnClientEvent:Connect(playScaleInBatch)

return nil
