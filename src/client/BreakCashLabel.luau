local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local partRespawnRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartRespawn") :: RemoteEvent

local boundParts: { [BasePart]: boolean } = {}
local activeTweens: { [BasePart]: { Tween } } = {}
local tweenGeneration: { [BasePart]: number } = {}
local fadeWatchers: { [BasePart]: RBXScriptConnection } = {}
local hideThreads: { [BasePart]: thread } = {}

local function findCashLabel(part: BasePart): TextLabel?
	for _, child in part:GetChildren() do
		if child:IsA("BillboardGui") then
			local label = child:FindFirstChild("CashLabel")
			if label and label:IsA("TextLabel") then
				return label
			end
		end
	end

	return nil
end

local function ensureUIScale(label: GuiObject): UIScale
	local uiScale = label:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "CashLabelScale"
		uiScale.Parent = label
	end

	return uiScale
end

local function cancelTweens(part: BasePart)
	local tweens = activeTweens[part]
	if tweens then
		for _, tween in tweens do
			tween:Cancel()
		end
		activeTweens[part] = nil
	end

	tweenGeneration[part] = (tweenGeneration[part] or 0) + 1
end

local function cancelHideSchedule(part: BasePart)
	local thread = hideThreads[part]
	if thread then
		task.cancel(thread)
		hideThreads[part] = nil
	end
end

local function stopFadeWatch(part: BasePart)
	local connection = fadeWatchers[part]
	if connection then
		connection:Disconnect()
		fadeWatchers[part] = nil
	end
end

local function trackTweens(part: BasePart, tweens: { Tween })
	activeTweens[part] = tweens
	for _, tween in tweens do
		tween:Play()
	end
end

local function hideCashLabel(part: BasePart, instant: boolean?)
	local label = findCashLabel(part)
	if not label then
		return
	end

	cancelHideSchedule(part)
	stopFadeWatch(part)
	cancelTweens(part)

	local uiScale = label:FindFirstChildOfClass("UIScale")

	if instant or not uiScale then
		label.Visible = false
		label.TextTransparency = 1
		if uiScale then
			uiScale.Scale = 0
		end
		return
	end

	label.Visible = true

	local hideDuration = GameConfig.CashLabelHideDuration
	local hideInfo = TweenInfo.new(hideDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tweens: { Tween } = {
		TweenService:Create(uiScale, hideInfo, { Scale = 0 }),
		TweenService:Create(label, hideInfo, { TextTransparency = 1 }),
	}

	trackTweens(part, tweens)
	tweens[1].Completed:Connect(function()
		if activeTweens[part] == tweens then
			activeTweens[part] = nil
		end
		label.Visible = false
		label.TextTransparency = 0
		uiScale.Scale = 0
	end)
end

local function scheduleAutoHide(part: BasePart, generation: number)
	cancelHideSchedule(part)

	local hold = GameConfig.CashLabelHoldAfterPop
	local hideDelay = GameConfig.CashLabelPopSlamDuration + 0.12 + hold

	hideThreads[part] = task.delay(hideDelay, function()
		hideThreads[part] = nil
		if tweenGeneration[part] ~= generation then
			return
		end
		if not part.Parent or not part:GetAttribute("Broken") or part:GetAttribute("HiddenForRespawn") then
			return
		end
		hideCashLabel(part, false)
	end)
end

local function startFadeWatch(part: BasePart)
	stopFadeWatch(part)

	fadeWatchers[part] = part:GetPropertyChangedSignal("Transparency"):Connect(function()
		if part.Transparency >= 0.92 then
			stopFadeWatch(part)
			hideCashLabel(part, false)
		end
	end)
end

local function showCashLabelPop(part: BasePart)
	local label = findCashLabel(part)
	if not label then
		return
	end

	cancelHideSchedule(part)
	stopFadeWatch(part)
	cancelTweens(part)

	local uiScale = ensureUIScale(label)

	label.Visible = true
	label.TextTransparency = 1
	uiScale.Scale = 0

	local slamDuration = GameConfig.CashLabelPopSlamDuration
	local peakScale = GameConfig.CashLabelPopPeakScale
	local bounceScale = GameConfig.CashLabelPopBounceScale

	local slamInfo = TweenInfo.new(slamDuration, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	local bounceInfo = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local slamTweens: { Tween } = {
		TweenService:Create(uiScale, slamInfo, { Scale = peakScale }),
		TweenService:Create(label, TweenInfo.new(slamDuration * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }),
	}

	local generation = (tweenGeneration[part] or 0) + 1
	tweenGeneration[part] = generation
	trackTweens(part, slamTweens)

	slamTweens[1].Completed:Connect(function()
		if tweenGeneration[part] ~= generation then
			return
		end

		if not part.Parent or not part:GetAttribute("Broken") or part:GetAttribute("HiddenForRespawn") then
			return
		end

		local bounceTweens: { Tween } = {
			TweenService:Create(uiScale, bounceInfo, { Scale = bounceScale }),
		}
		trackTweens(part, bounceTweens)

		bounceTweens[1].Completed:Connect(function()
			if tweenGeneration[part] ~= generation then
				return
			end

			local settleTweens: { Tween } = {
				TweenService:Create(uiScale, settleInfo, { Scale = 1 }),
			}
			trackTweens(part, settleTweens)

			settleTweens[1].Completed:Connect(function()
				if tweenGeneration[part] == generation then
					activeTweens[part] = nil
				end
			end)
		end)
	end)

	scheduleAutoHide(part, generation)
end

local function onBrokenChanged(part: BasePart)
	if part:GetAttribute("Broken") == true then
		showCashLabelPop(part)
		startFadeWatch(part)
	elseif not part:GetAttribute("HiddenForRespawn") then
		stopFadeWatch(part)
		hideCashLabel(part, true)
	end
end

local function onHiddenChanged(part: BasePart)
	if part:GetAttribute("HiddenForRespawn") == true then
		stopFadeWatch(part)
		hideCashLabel(part, true)
	end
end

local function bindPart(part: BasePart)
	if boundParts[part] then
		return
	end

	if not BreakableUtil.isBreakable(part) then
		return
	end

	boundParts[part] = true
	hideCashLabel(part, true)

	part:GetAttributeChangedSignal("Broken"):Connect(function()
		onBrokenChanged(part)
	end)

	part:GetAttributeChangedSignal("HiddenForRespawn"):Connect(function()
		onHiddenChanged(part)
	end)

	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			stopFadeWatch(part)
			hideCashLabel(part, true)
			boundParts[part] = nil
		end
	end)

	if part:GetAttribute("Broken") == true and not part:GetAttribute("HiddenForRespawn") then
		showCashLabelPop(part)
		startFadeWatch(part)
	end
end

local function scanBreakableRoot(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			bindPart(descendant)
		end
	end

	if root:IsA("BasePart") then
		bindPart(root)
	end
end

for _, tagged in CollectionService:GetTagged(GameConfig.BreakableTag) do
	scanBreakableRoot(tagged)
	tagged.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			bindPart(descendant)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(GameConfig.BreakableTag):Connect(function(tagged)
	scanBreakableRoot(tagged)
	tagged.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			bindPart(descendant)
		end
	end)
end)

partRespawnRemote.OnClientEvent:Connect(function(part: unknown)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end

	hideCashLabel(part, true)
end)

return nil
