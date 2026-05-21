local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CloneMapService = require(script.Parent.CloneMapService)

local BreakRespawnService = {}

local hiddenFolder: Folder
local nextWaveTime: number? = nil
local waveScheduled = false
local damagePending = false

local function getHiddenFolder(): Folder
	if hiddenFolder and hiddenFolder.Parent then
		return hiddenFolder
	end

	hiddenFolder = ServerStorage:FindFirstChild("BrokenPartsHidden") :: Folder?
	if not hiddenFolder then
		hiddenFolder = Instance.new("Folder")
		hiddenFolder.Name = "BrokenPartsHidden"
		hiddenFolder.Parent = ServerStorage
	end

	return hiddenFolder
end

local function updateNextRespawnTime()
	ReplicatedStorage:SetAttribute("NextRespawnTime", nextWaveTime)
end

local function setRespawnWaveInProgress(active: boolean)
	ReplicatedStorage:SetAttribute("RespawnWaveInProgress", active)
end

local function scheduleRespawnWave()
	if waveScheduled or not nextWaveTime or CloneMapService.isRestoring() then
		return
	end

	waveScheduled = true
	local delay = math.max(0, nextWaveTime - workspace:GetServerTimeNow())

	task.delay(delay, function()
		waveScheduled = false
		BreakRespawnService.runRespawnWave()
	end)
end

local function ensureRespawnWaveScheduled()
	if CloneMapService.isRestoring() then
		return
	end

	if not damagePending then
		nextWaveTime = nil
		updateNextRespawnTime()
		return
	end

	if not nextWaveTime then
		nextWaveTime = workspace:GetServerTimeNow() + GameConfig.BreakRespawnDelay
		updateNextRespawnTime()
	end

	scheduleRespawnWave()
end

function BreakRespawnService.notifyMapDamaged()
	if CloneMapService.isRestoring() then
		return
	end

	damagePending = true
	ensureRespawnWaveScheduled()
end

function BreakRespawnService.registerBrokenPart(_part: BasePart, _snapshot: any?)
	BreakRespawnService.notifyMapDamaged()
end

function BreakRespawnService.registerTreeClusterBroken(_treeRoot: Instance, _clusterParts: { BasePart })
	BreakRespawnService.notifyMapDamaged()
end

function BreakRespawnService.captureSnapshot(_part: BasePart)
	return nil
end

function BreakRespawnService.hasSnapshot(_part: BasePart): boolean
	return false
end

function BreakRespawnService.runRespawnWave()
	if CloneMapService.isRestoring() then
		return
	end

	damagePending = false
	nextWaveTime = nil
	updateNextRespawnTime()
	CloneMapService.performFullRestore(function()
		setRespawnWaveInProgress(false)
		ensureRespawnWaveScheduled()
	end)
end

function BreakRespawnService.fadeAndHideCluster(
	clusterParts: { BasePart },
	fadeDuration: number,
	onHidden: (() -> ())?
)
	local partsToHide: { BasePart } = {}
	for _, clusterPart in clusterParts do
		if clusterPart.Parent and not clusterPart:GetAttribute("HiddenForRespawn") then
			table.insert(partsToHide, clusterPart)
		end
	end

	if #partsToHide == 0 then
		if onHidden then
			onHidden()
		end
		return
	end

	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tweens: { Tween } = {}

	for _, clusterPart in partsToHide do
		table.insert(tweens, TweenService:Create(clusterPart, tweenInfo, { Transparency = 1 }))

		for _, descendant in clusterPart:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(tweens, TweenService:Create(descendant, tweenInfo, { Transparency = 1 }))
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				table.insert(tweens, TweenService:Create(descendant, tweenInfo, { Transparency = 1 }))
			end
		end
	end

	for _, tween in tweens do
		tween:Play()
	end

	task.delay(fadeDuration, function()
		local folder = getHiddenFolder()

		for _, clusterPart in partsToHide do
			if not clusterPart.Parent then
				continue
			end

			clusterPart.AssemblyLinearVelocity = Vector3.zero
			clusterPart.AssemblyAngularVelocity = Vector3.zero
			clusterPart.Anchored = true
			clusterPart.Parent = folder
			clusterPart:SetAttribute("HiddenForRespawn", true)
		end

		if onHidden then
			onHidden()
		end
	end)
end

function BreakRespawnService.fadeAndHide(part: BasePart, fadeDuration: number, onHidden: (() -> ())?)
	BreakRespawnService.fadeAndHideCluster({ part }, fadeDuration, onHidden)
end

return BreakRespawnService
