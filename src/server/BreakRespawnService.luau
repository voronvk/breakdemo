local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local partRespawnRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartRespawn") :: RemoteEvent

local BreakRespawnService = {}

type DescendantSnapshot = {
	transparency: number,
	size: Vector3?,
}

type PartSnapshot = {
	cframe: CFrame,
	parent: Instance,
	anchored: boolean,
	canCollide: boolean,
	canTouch: boolean,
	canQuery: boolean,
	transparency: number,
	color: Color3,
	material: Enum.Material,
	size: Vector3,
	descendants: { [Instance]: DescendantSnapshot },
}

type PendingRespawn = {
	part: BasePart,
	snapshot: PartSnapshot,
	order: number,
}

local hiddenFolder: Folder
local pendingRespawns: { PendingRespawn } = {}
local snapshotsByPart: { [BasePart]: PartSnapshot } = {}
local nextWaveTime: number? = nil
local waveScheduled = false
local respawnOrderCounter = 0

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

local function hasPendingRespawns(): boolean
	if #pendingRespawns > 0 then
		return true
	end

	for part, _ in snapshotsByPart do
		if part.Parent then
			return true
		end
	end

	return false
end

local function scheduleRespawnWave()
	if waveScheduled or not nextWaveTime then
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
	if not hasPendingRespawns() then
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

function BreakRespawnService.captureSnapshot(part: BasePart): PartSnapshot
	local descendants: { [Instance]: DescendantSnapshot } = {}
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendants[descendant] = {
				transparency = descendant.Transparency,
				size = descendant.Size,
			}
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendants[descendant] = {
				transparency = descendant.Transparency,
			}
		end
	end

	return {
		cframe = part.CFrame,
		parent = part.Parent :: Instance,
		anchored = part.Anchored,
		canCollide = part.CanCollide,
		canTouch = part.CanTouch,
		canQuery = part.CanQuery,
		transparency = part.Transparency,
		color = part.Color,
		material = part.Material,
		size = part.Size,
		descendants = descendants,
	}
end

function BreakRespawnService.registerBrokenPart(part: BasePart, snapshot: PartSnapshot)
	snapshotsByPart[part] = snapshot

	for _, entry in pendingRespawns do
		if entry.part == part then
			entry.snapshot = snapshot
			ensureRespawnWaveScheduled()
			return
		end
	end

	respawnOrderCounter += 1
	table.insert(pendingRespawns, {
		part = part,
		snapshot = snapshot,
		order = respawnOrderCounter,
	})

	ensureRespawnWaveScheduled()
end

local function restoreVisuals(part: BasePart, snapshot: PartSnapshot)
	part.Transparency = snapshot.transparency
	part.Color = snapshot.color
	part.Material = snapshot.material

	for instance, data in snapshot.descendants do
		if not instance.Parent then
			continue
		end

		if instance:IsA("BasePart") then
			instance.Transparency = data.transparency
			if data.size then
				instance.Size = data.size
			end
			instance:SetAttribute("RespawnBaseSize", nil)
		elseif instance:IsA("Decal") or instance:IsA("Texture") then
			instance.Transparency = data.transparency
		end
	end
end

local function clearRespawnScaleAttributes(part: BasePart)
	part:SetAttribute("RespawnTargetSize", nil)

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("RespawnBaseSize", nil)
		end
	end
end

local function applyScaleInStart(part: BasePart, snapshot: PartSnapshot)
	part.Size = snapshot.size * GameConfig.BreakRespawnScaleInStart

	for instance, data in snapshot.descendants do
		if instance.Parent and instance:IsA("BasePart") and data.size then
			instance:SetAttribute("RespawnBaseSize", data.size)
			instance.Size = data.size * GameConfig.BreakRespawnScaleInStart
		end
	end
end

local function applySnapshotTransform(part: BasePart, snapshot: PartSnapshot)
	part.CFrame = snapshot.cframe
	part.Anchored = snapshot.anchored
	part.CanCollide = snapshot.canCollide
	part.CanTouch = snapshot.canTouch
	part.CanQuery = snapshot.canQuery
end

local function finishRespawnRestore(part: BasePart, snapshot: PartSnapshot)
	if not part.Parent then
		return
	end

	part.Size = snapshot.size
	restoreVisuals(part, snapshot)
	clearRespawnScaleAttributes(part)
end

function BreakRespawnService.respawnPart(part: BasePart): boolean
	local snapshot = snapshotsByPart[part]
	if not snapshot then
		return false
	end

	if not part.Parent then
		snapshotsByPart[part] = nil
		return false
	end

	local restoreParent = snapshot.parent
	if not restoreParent.Parent then
		snapshotsByPart[part] = nil
		return false
	end

	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Parent = restoreParent
	applySnapshotTransform(part, snapshot)
	restoreVisuals(part, snapshot)
	applyScaleInStart(part, snapshot)

	part:SetAttribute("Broken", nil)
	part:SetAttribute("Shattered", nil)
	part:SetAttribute("HiddenForRespawn", nil)
	part:SetAttribute("RespawnTargetSize", snapshot.size)

	snapshotsByPart[part] = nil

	for index = #pendingRespawns, 1, -1 do
		if pendingRespawns[index].part == part then
			table.remove(pendingRespawns, index)
		end
	end

	partRespawnRemote:FireAllClients(part)

	task.delay(GameConfig.BreakRespawnScaleInDuration, function()
		finishRespawnRestore(part, snapshot)
	end)

	return true
end

local function collectWaveBatch(): { PendingRespawn }
	local waveBatch: { PendingRespawn } = {}
	local seen: { [BasePart]: boolean } = {}

	local function addEntry(part: BasePart, snapshot: PartSnapshot?, order: number)
		if seen[part] or not snapshotsByPart[part] then
			return
		end

		seen[part] = true
		table.insert(waveBatch, {
			part = part,
			snapshot = snapshot or snapshotsByPart[part],
			order = order,
		})
	end

	for _, entry in pendingRespawns do
		addEntry(entry.part, entry.snapshot, entry.order)
	end
	pendingRespawns = {}

	for part, snapshot in snapshotsByPart do
		if not seen[part] then
			addEntry(part, snapshot, respawnOrderCounter + 1)
		end
	end

	table.sort(waveBatch, function(a, b)
		return a.order < b.order
	end)

	return waveBatch
end

local function flushOrphanedSnapshots()
	for part, snapshot in snapshotsByPart do
		if not part.Parent then
			snapshotsByPart[part] = nil
			continue
		end

		if not snapshot.parent.Parent then
			snapshotsByPart[part] = nil
			continue
		end

		BreakRespawnService.respawnPart(part)
	end
end

function BreakRespawnService.runRespawnWave()
	local waveBatch = collectWaveBatch()

	if #waveBatch == 0 then
		setRespawnWaveInProgress(false)
		flushOrphanedSnapshots()
		ensureRespawnWaveScheduled()
		return
	end

	nextWaveTime = nil
	updateNextRespawnTime()
	setRespawnWaveInProgress(true)

	for index, entry in waveBatch do
		task.delay((index - 1) * GameConfig.BreakRespawnDominoStagger, function()
			if not entry.part.Parent or not entry.snapshot.parent.Parent then
				return
			end

			snapshotsByPart[entry.part] = entry.snapshot
			BreakRespawnService.respawnPart(entry.part)
		end)
	end

	local waveFinishDelay = #waveBatch * GameConfig.BreakRespawnDominoStagger
		+ GameConfig.BreakRespawnScaleInDuration
		+ 0.05

	task.delay(waveFinishDelay, function()
		flushOrphanedSnapshots()
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
		clusterPart.CanCollide = false
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
		local hiddenFolder = getHiddenFolder()

		for _, clusterPart in partsToHide do
			if not clusterPart.Parent then
				continue
			end

			clusterPart.AssemblyLinearVelocity = Vector3.zero
			clusterPart.AssemblyAngularVelocity = Vector3.zero
			clusterPart.Anchored = true
			clusterPart.Parent = hiddenFolder
			clusterPart:SetAttribute("HiddenForRespawn", true)
		end

		if onHidden then
			onHidden()
		end
	end)
end

function BreakRespawnService.fadeAndHide(part: BasePart, fadeDuration: number, onHidden: (() -> ())?)
	if not part.Parent then
		if onHidden then
			onHidden()
		end
		return
	end

	part.CanCollide = false

	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tweens: { Tween } = { TweenService:Create(part, tweenInfo, { Transparency = 1 }) }

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(tweens, TweenService:Create(descendant, tweenInfo, { Transparency = 1 }))
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			table.insert(tweens, TweenService:Create(descendant, tweenInfo, { Transparency = 1 }))
		end
	end

	for _, tween in tweens do
		tween:Play()
	end

	task.delay(fadeDuration, function()
		if not part.Parent then
			if onHidden then
				onHidden()
			end
			return
		end

		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Anchored = true
		part.Parent = getHiddenFolder()
		part:SetAttribute("HiddenForRespawn", true)

		if onHidden then
			onHidden()
		end
	end)
end

return BreakRespawnService
