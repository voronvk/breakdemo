local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local BreakCollision = require(ReplicatedStorage.Shared.BreakCollision)
local FallTracker = require(script.Parent.FallTracker)

local partRespawnRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartRespawn") :: RemoteEvent
local CloneMapService = {}

local MANAGED_ATTR = "CloneMapManaged"
local ORIG_TRANSPARENCY_ATTR = "CloneMapOrigTransparency"
local ORIG_CAN_COLLIDE_ATTR = "CloneMapOrigCanCollide"
local ORIG_ANCHORED_ATTR = "CloneMapOrigAnchored"
local STAGING_FOLDER_NAME = "CloneMapStaging"
local HIDDEN_FOLDER_NAME = "BrokenPartsHidden"
local DEBRIS_FOLDER_NAME = "BreakDebris"

local scaleInTweenInfo = TweenInfo.new(
	GameConfig.BreakRespawnScaleInDuration,
	Enum.EasingStyle.Back,
	Enum.EasingDirection.Out
)

local liveRoots: { Instance } = {}
local cachedRevealParts: { BasePart } = {}
local mapBuilt = false
local isRestoring = false

local function setWaveAttributes(active: boolean)
	ReplicatedStorage:SetAttribute("RespawnWaveInProgress", active)
	if active then
		ReplicatedStorage:SetAttribute("MapRestoring", true)
	else
		ReplicatedStorage:SetAttribute("MapRestoring", nil)
	end
end

local function markManaged(root: Instance)
	root:SetAttribute(MANAGED_ATTR, true)
end

local function isManagedPart(part: Instance): boolean
	local current: Instance? = part
	while current do
		if current:GetAttribute(MANAGED_ATTR) == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function collectAllBaseParts(roots: { Instance }): { BasePart }
	local parts: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}

	for _, root in roots do
		if not root.Parent then
			continue
		end

		if root:IsA("BasePart") and not seen[root] then
			seen[root] = true
			table.insert(parts, root)
		end

		for _, descendant in root:GetDescendants() do
			if descendant:IsA("BasePart") and not seen[descendant] then
				seen[descendant] = true
				table.insert(parts, descendant)
			end
		end
	end

	table.sort(parts, function(a: BasePart, b: BasePart)
		return a:GetFullName() < b:GetFullName()
	end)

	return parts
end

local function rebuildRevealCache()
	cachedRevealParts = collectAllBaseParts(liveRoots)
end

local function collectManagedBaseParts(): { BasePart }
	local roots: { Instance } = table.clone(liveRoots)

	local hiddenFolder = ServerStorage:FindFirstChild(HIDDEN_FOLDER_NAME)
	if hiddenFolder then
		for _, child in hiddenFolder:GetChildren() do
			if isManagedPart(child) then
				table.insert(roots, child)
			end
		end
	end

	return collectAllBaseParts(roots)
end

local function clearHiddenFolder()
	local hiddenFolder = ServerStorage:FindFirstChild(HIDDEN_FOLDER_NAME)
	if hiddenFolder then
		hiddenFolder:ClearAllChildren()
	end
end

local function clearDebrisFolder()
	local debrisFolder = Workspace:FindFirstChild(DEBRIS_FOLDER_NAME)
	if debrisFolder then
		debrisFolder:ClearAllChildren()
	end
end

local function clearTreeFormingState()
	for _, tagged in CollectionService:GetTagged(GameConfig.TreeTag) do
		tagged:SetAttribute("TreeForming", nil)
		for _, descendant in tagged:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant:SetAttribute("TreeForming", nil)
			end
		end
	end
end

local function getOrCreateStagingFolder(): Folder
	local folder = ServerStorage:FindFirstChild(STAGING_FOLDER_NAME) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = STAGING_FOLDER_NAME
		folder.Parent = ServerStorage
	end
	return folder
end

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

local function storeOriginalTransparency(instance: Instance)
	if
		not (
			instance:IsA("BasePart")
			or instance:IsA("Decal")
			or instance:IsA("Texture")
		)
	then
		return
	end

	if instance:GetAttribute(ORIG_TRANSPARENCY_ATTR) == nil then
		instance:SetAttribute(ORIG_TRANSPARENCY_ATTR, instance.Transparency)
	end
end

local function hideVisual(instance: Instance)
	if
		instance:IsA("BasePart")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
	then
		storeOriginalTransparency(instance)
		instance.Transparency = 1
	end
end

local function showVisual(instance: Instance)
	if
		not (
			instance:IsA("BasePart")
			or instance:IsA("Decal")
			or instance:IsA("Texture")
		)
	then
		return
	end

	instance.Transparency = getTargetTransparency(instance)
end

local function prepOneBasePart(part: BasePart)
	if part:GetAttribute(ORIG_CAN_COLLIDE_ATTR) == nil then
		part:SetAttribute(ORIG_CAN_COLLIDE_ATTR, part.CanCollide)
	end
	if part:GetAttribute(ORIG_ANCHORED_ATTR) == nil then
		part:SetAttribute(ORIG_ANCHORED_ATTR, part.Anchored)
	end

	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	local targetSize = part.Size
	part:SetAttribute("RespawnTargetSize", targetSize)
	part.Size = targetSize * GameConfig.BreakRespawnScaleInStart
	hideVisual(part)
end

local function hideEntireCloneTree(root: Instance)
	if root:IsA("BasePart") then
		prepOneBasePart(root)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			prepOneBasePart(descendant)
		else
			hideVisual(descendant)
		end
	end
end

local function prepLiveRootsForReveal()
	for _, root in liveRoots do
		hideEntireCloneTree(root)
	end
end

local function restorePartInteraction(part: BasePart)
	local originalCollide = part:GetAttribute(ORIG_CAN_COLLIDE_ATTR)
	if typeof(originalCollide) == "boolean" then
		part.CanCollide = originalCollide
	else
		part.CanCollide = true
	end

	local originalAnchored = part:GetAttribute(ORIG_ANCHORED_ATTR)
	if typeof(originalAnchored) == "boolean" then
		part.Anchored = originalAnchored
	else
		part.Anchored = false
	end

	part.CanTouch = true
	part.CanQuery = true
	part:SetAttribute(ORIG_CAN_COLLIDE_ATTR, nil)
	part:SetAttribute(ORIG_ANCHORED_ATTR, nil)
end

local function clearRevealAttributes(part: BasePart)
	part:SetAttribute("RespawnTargetSize", nil)
	part:SetAttribute(ORIG_TRANSPARENCY_ATTR, nil)
end

local function playServerScaleIn(part: BasePart)
	local targetSize = part:GetAttribute("RespawnTargetSize")
	if typeof(targetSize) ~= "Vector3" then
		targetSize = part.Size
	end

	local targetTransparency = getTargetTransparency(part)
	part.Transparency = 1

	local tween = TweenService:Create(part, scaleInTweenInfo, {
		Size = targetSize,
		Transparency = targetTransparency,
	})

	tween:Play()
	return tween, targetSize
end

local function finishRevealPart(part: BasePart, targetSize: Vector3)
	part.Size = targetSize
	part.Transparency = getTargetTransparency(part)
	restorePartInteraction(part)
	clearRevealAttributes(part)
	BreakCollision.restorePart(part, part.CollisionGroup)
end

local function revealOnePart(part: BasePart)
	if not part.Parent then
		return
	end

	part:SetAttribute("Broken", nil)
	part:SetAttribute("HiddenForRespawn", nil)
	part:SetAttribute("TreeForming", nil)
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	partRespawnRemote:FireAllClients(part)

	local _, targetSize = playServerScaleIn(part)
	task.delay(GameConfig.BreakRespawnScaleInDuration, function()
		if part.Parent then
			finishRevealPart(part, targetSize)
		end
	end)
end

local function waitForRevealAudience()
	if #Players:GetPlayers() > 0 then
		task.wait(0.35)
		return
	end

	Players.PlayerAdded:Wait()
	task.wait(0.35)
end

local function isPartAwaitingReveal(part: BasePart): boolean
	if part:GetAttribute("RespawnTargetSize") == nil then
		return false
	end

	return part.Transparency >= 0.95
end

local function flushHiddenManagedParts()
	for _, root in liveRoots do
		local toCheck: { BasePart } = {}
		if root:IsA("BasePart") then
			table.insert(toCheck, root)
		end

		for _, descendant in root:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(toCheck, descendant)
			end
		end

		for _, part in toCheck do
			if not part.Parent or not isPartAwaitingReveal(part) then
				continue
			end

			local targetSize = part:GetAttribute("RespawnTargetSize")
			if typeof(targetSize) == "Vector3" then
				finishRevealPart(part, targetSize)
			else
				showVisual(part)
				restorePartInteraction(part)
				BreakCollision.restorePart(part, part.CollisionGroup)
			end
		end
	end
end

local function collectRevealGroups(): { { label: string, parts: { BasePart } } }
	local groups: { { label: string, parts: { BasePart } } } = {}

	for _, root in liveRoots do
		if not root.Parent then
			continue
		end

		local parts = collectAllBaseParts({ root })
		table.insert(groups, {
			label = root:GetFullName(),
			parts = parts,
		})
	end

	table.sort(groups, function(a, b)
		return a.label < b.label
	end)

	return groups
end

local function runDominoReveal(parts: { BasePart }, onComplete: (() -> ())?)
	local total = #parts
	if total == 0 then
		if onComplete then
			onComplete()
		end
		return
	end

	local stagger = GameConfig.CloneMapRevealStagger
	local scaleDuration = GameConfig.BreakRespawnScaleInDuration

	for index, part in parts do
		task.delay((index - 1) * stagger, function()
			if part.Parent then
				revealOnePart(part)
			end
		end)
	end

	task.delay((total - 1) * stagger + scaleDuration + 0.1, function()
		flushHiddenManagedParts()
		if onComplete then
			onComplete()
		end
	end)
end

local function runRootGroupReveal(onComplete: (() -> ())?)
	local groups = collectRevealGroups()
	local totalGroups = #groups

	if totalGroups == 0 then
		if onComplete then
			onComplete()
		end
		return
	end

	local stagger = GameConfig.CloneMapRevealStagger
	local scaleDuration = GameConfig.BreakRespawnScaleInDuration

	for index, group in groups do
		task.delay((index - 1) * stagger, function()
			for _, part in group.parts do
				if part.Parent then
					revealOnePart(part)
				end
			end
		end)
	end

	task.delay((totalGroups - 1) * stagger + scaleDuration + 0.2, function()
		flushHiddenManagedParts()

		if onComplete then
			onComplete()
		end
	end)
end

local function runRevealWave(onComplete: (() -> ())?)
	if GameConfig.CloneMapRevealByRoot == true then
		runRootGroupReveal(onComplete)
	else
		runDominoReveal(cachedRevealParts, onComplete)
	end
end

local function destroyLiveRoots()
	FallTracker.clearAll()

	for _, root in liveRoots do
		if root.Parent then
			root:Destroy()
		end
	end
	liveRoots = {}
	cachedRevealParts = {}
	clearHiddenFolder()
end

local function fadeBatchOut(batch: { BasePart }, fadeDuration: number)
	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	for _, part in batch do
		if not part.Parent then
			continue
		end

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
	end
end

local function runBatchedTeardown(parts: { BasePart }, onComplete: (() -> ())?)
	local total = #parts
	if total == 0 then
		destroyLiveRoots()
		clearTreeFormingState()
		if onComplete then
			onComplete()
		end
		return
	end

	if total >= GameConfig.CloneMapFastTeardownPartCount then
		destroyLiveRoots()
		clearTreeFormingState()
		if onComplete then
			onComplete()
		end
		return
	end

	local batchSize = math.max(1, GameConfig.CloneMapTeardownBatchSize)
	local stagger = GameConfig.CloneMapTeardownStagger
	local fadeDuration = GameConfig.BreakFadeDuration * 0.65
	local batchIndex = 0
	local batchCount = math.ceil(total / batchSize)

	for offset = 1, total, batchSize do
		batchIndex += 1
		local batch: { BasePart } = {}
		local limit = math.min(offset + batchSize - 1, total)

		for index = offset, limit do
			local part = parts[index]
			if part.Parent then
				table.insert(batch, part)
			end
		end

		if #batch > 0 then
			task.delay((batchIndex - 1) * stagger, function()
				fadeBatchOut(batch, fadeDuration)
			end)
		end
	end

	local totalDelay = (batchCount - 1) * stagger + fadeDuration + 0.05
	task.delay(totalDelay, function()
		destroyLiveRoots()
		clearTreeFormingState()
		if onComplete then
			onComplete()
		end
	end)
end

local function folderHasNonModelSpawnContent(folder: Folder): boolean
	for _, nested in folder:GetChildren() do
		if nested:IsA("Model") then
			continue
		end

		if nested:IsA("Folder") then
			return true
		end

		if nested:IsA("BasePart") or nested:IsA("PVInstance") then
			return true
		end
	end

	return false
end

local function collectSpawnInstances(template: Folder): { Instance }
	local spawnList: { Instance } = {}
	local seen: { [Instance]: boolean } = {}

	local function add(inst: Instance)
		if seen[inst] then
			return
		end
		seen[inst] = true
		table.insert(spawnList, inst)
	end

	for _, templateChild in template:GetChildren() do
		if templateChild:IsA("Folder") then
			local modelsInFolder: { Model } = {}
			for _, nested in templateChild:GetChildren() do
				if nested:IsA("Model") then
					table.insert(modelsInFolder, nested)
				end
			end

			if #modelsInFolder > 0 and not folderHasNonModelSpawnContent(templateChild) then
				for _, model in modelsInFolder do
					add(model)
				end
			else
				add(templateChild)
			end
		else
			add(templateChild)
		end
	end

	return spawnList
end

local function removeConflictingWorkspaceChildren(spawnList: { Instance })
	for _, templateInst in spawnList do
		local existing = Workspace:FindFirstChild(templateInst.Name)
		if existing and existing ~= templateInst then
			existing:Destroy()
		end
	end
end

local function safeCloneTemplateInstance(templateInst: Instance): Instance?
	if not templateInst.Archivable then
		warn(`[CloneMapService] No se puede clonar (Archivable=false): {templateInst:GetFullName()}`)
		return nil
	end

	local ok, live = pcall(function()
		return templateInst:Clone()
	end)

	if not ok or not live then
		warn(`[CloneMapService] Error al clonar: {templateInst:GetFullName()} -> {tostring(live)}`)
		return nil
	end

	return live
end

local function getTemplateFolder(): Folder?
	local template = ServerStorage:FindFirstChild(GameConfig.CloneMapFolderName)
	if template and template:IsA("Folder") then
		return template
	end

	warn(`[CloneMapService] Falta ServerStorage.{GameConfig.CloneMapFolderName} (Folder)`)
	return nil
end

local function moveLiveRootsToWorkspace()
	for _, root in liveRoots do
		root.Parent = Workspace
	end
end

local function spawnLiveFromTemplate(): { BasePart }
	local template = getTemplateFolder()
	if not template then
		return {}
	end

	local spawnList = collectSpawnInstances(template)
	if #spawnList == 0 then
		warn(`[CloneMapService] {GameConfig.CloneMapFolderName} no tiene contenido para clonar`)
		return {}
	end

	removeConflictingWorkspaceChildren(spawnList)
	destroyLiveRoots()

	local staging = getOrCreateStagingFolder()
	liveRoots = {}

	for _, templateInst in spawnList do
		local live = safeCloneTemplateInstance(templateInst)
		if not live then
			continue
		end

		markManaged(live)
		live.Parent = staging
		table.insert(liveRoots, live)
	end

	if #liveRoots == 0 then
		warn("[CloneMapService] Ninguna instancia se clonó correctamente")
		return {}
	end

	rebuildRevealCache()
	prepLiveRootsForReveal()
	moveLiveRootsToWorkspace()

	return cachedRevealParts
end

local function startRevealWave(onComplete: (() -> ())?)
	task.spawn(function()
		waitForRevealAudience()
		runRevealWave(onComplete)
	end)
end

function CloneMapService.isRestoring(): boolean
	return isRestoring
end

function CloneMapService.isMapBuilt(): boolean
	return mapBuilt
end

function CloneMapService.buildMapAnimated()
	if mapBuilt or isRestoring then
		return
	end

	if not getTemplateFolder() then
		return
	end

	isRestoring = true
	setWaveAttributes(true)

	spawnLiveFromTemplate()

	startRevealWave(function()
		mapBuilt = true
		isRestoring = false
		setWaveAttributes(false)
		ReplicatedStorage:SetAttribute("MapReady", true)
	end)
end

function CloneMapService.performFullRestore(onComplete: (() -> ())?)
	if isRestoring then
		return
	end

	if not getTemplateFolder() then
		return
	end

	isRestoring = true
	setWaveAttributes(true)

	local partsToRemove = collectManagedBaseParts()
	runBatchedTeardown(partsToRemove, function()
		clearDebrisFolder()

		local BreakService = require(script.Parent.BreakService)
		local BreakBudget = require(script.Parent.BreakBudget)
		BreakService.resetMapState()
		BreakBudget.resetAll()

		spawnLiveFromTemplate()

		startRevealWave(function()
			mapBuilt = true
			isRestoring = false
			setWaveAttributes(false)
			ReplicatedStorage:SetAttribute("MapReady", true)

			if onComplete then
				onComplete()
			end
		end)
	end)
end

function CloneMapService.init()
	local template = ServerStorage:WaitForChild(GameConfig.CloneMapFolderName, 30)
	if not template or not template:IsA("Folder") then
		warn(`[CloneMapService] Crea ServerStorage/{GameConfig.CloneMapFolderName} con el mapa plantilla`)
		return
	end

	if #template:GetChildren() == 0 then
		warn(`[CloneMapService] {GameConfig.CloneMapFolderName} está vacío`)
		return
	end

	CloneMapService.buildMapAnimated()

	Players.PlayerAdded:Connect(function()
		if not mapBuilt and not isRestoring then
			CloneMapService.buildMapAnimated()
		end
	end)
end

return CloneMapService
