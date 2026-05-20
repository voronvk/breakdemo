local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local partRespawnRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartRespawn") :: RemoteEvent

local activeTweens: { [BasePart]: { Tween } } = {}

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

	local targetSize = part:GetAttribute("RespawnTargetSize")
	if typeof(targetSize) == "Vector3" then
		table.insert(tweens, TweenService:Create(part, tweenInfo, { Size = targetSize }))
	end

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			local baseSize = descendant:GetAttribute("RespawnBaseSize")
			if typeof(baseSize) == "Vector3" then
				table.insert(tweens, TweenService:Create(descendant, tweenInfo, { Size = baseSize }))
			end
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

		local targetSize = part:GetAttribute("RespawnTargetSize")
		if typeof(targetSize) == "Vector3" then
			part.Size = targetSize
		end
		part:SetAttribute("RespawnTargetSize", nil)

		for _, descendant in part:GetDescendants() do
			if descendant:IsA("BasePart") then
				local baseSize = descendant:GetAttribute("RespawnBaseSize")
				if typeof(baseSize) == "Vector3" then
					descendant.Size = baseSize
				end
				descendant:SetAttribute("RespawnBaseSize", nil)
			end
		end
	end)
end

partRespawnRemote.OnClientEvent:Connect(function(part: unknown)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end

	playScaleIn(part)
end)

return nil
