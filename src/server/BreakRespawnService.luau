local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local BreakCollision = require(ReplicatedStorage.Shared.BreakCollision)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local partRespawnRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PartRespawn") :: RemoteEvent

local BreakRespawnService = {}

type DescendantSnapshot = {
	transparency: number,
	size: Vector3?,
	localCFrame: CFrame?,
}

type PartSnapshot = {
	partName: string,
	workspaceFullName: string?,
	cframe: CFrame,
	parent: Instance,
	parentPath: string?,
	anchored: boolean,
	canCollide: boolean,
	collisionGroup: string,
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

type TreeWeldSnapshot = {
	className: string,
	name: string,
	part0: BasePart,
	part1: BasePart,
	parent: Instance,
}

local treeWeldSnapshots: { [Instance]: { TreeWeldSnapshot } } = {}
-- Pose original del arbol: se captura una sola vez al cargar y nunca se sobrescribe.
local treeOriginSnapshots: { [Instance]: { [BasePart]: PartSnapshot } } = {}
local treeAnchorRestore: { [BasePart]: boolean } = {}
local treeRootByPart: { [BasePart]: Instance } = {}
local treeScaleInPending: { [Instance]: { [BasePart]: boolean } } = {}
local treeFormationForced: { [Instance]: { [BasePart]: boolean } } = {}

local function getTreeRoot(part: BasePart): Instance?
	return BreakableUtil.getTreeRoot(part)
end

local function setTreeFormingState(treeRoot: Instance, forming: boolean)
	if forming then
		treeRoot:SetAttribute("TreeForming", true)
	else
		treeRoot:SetAttribute("TreeForming", nil)
	end

	for _, descendant in treeRoot:GetDescendants() do
		if descendant:IsA("BasePart") then
			if forming then
				descendant:SetAttribute("TreeForming", true)
			else
				descendant:SetAttribute("TreeForming", nil)
			end
		end
	end
end

local function partBelongsToTree(part: BasePart, treeRoot: Instance, snapshot: PartSnapshot?): boolean
	if treeRootByPart[part] == treeRoot or getTreeRoot(part) == treeRoot then
		return true
	end

	if snapshot and (snapshot.parent == treeRoot or snapshot.parent:IsDescendantOf(treeRoot)) then
		return true
	end

	return false
end

local function captureTreeWelds(treeRoot: Instance)
	if treeWeldSnapshots[treeRoot] then
		return
	end

	local welds: { TreeWeldSnapshot } = {}
	for _, inst in treeRoot:GetDescendants() do
		if inst:IsA("WeldConstraint") or inst:IsA("Weld") then
			local part0 = inst.Part0
			local part1 = inst.Part1
			if part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") then
				table.insert(welds, {
					className = inst.ClassName,
					name = inst.Name,
					part0 = part0,
					part1 = part1,
					parent = inst.Parent :: Instance,
				})
			end
		end
	end

	treeWeldSnapshots[treeRoot] = welds
end

local function weldAlreadyExists(part0: BasePart, part1: BasePart, treeRoot: Instance): boolean
	for _, inst in treeRoot:GetDescendants() do
		if inst:IsA("WeldConstraint") or inst:IsA("Weld") then
			if (inst.Part0 == part0 and inst.Part1 == part1) or (inst.Part0 == part1 and inst.Part1 == part0) then
				return true
			end
		end
	end

	return false
end

local function restoreTreeWelds(treeRoot: Instance)
	local welds = treeWeldSnapshots[treeRoot]
	if not welds then
		return
	end

	for _, data in welds do
		if data.part0.Parent and data.part1.Parent and not weldAlreadyExists(data.part0, data.part1, treeRoot) then
			local weld = Instance.new(data.className)
			weld.Name = data.name
			weld.Part0 = data.part0
			weld.Part1 = data.part1
			weld.Parent = if data.parent.Parent then data.parent else treeRoot
		end
	end

end

local function anchorTreeForFormation(treeRoot: Instance)
	local forced = treeFormationForced[treeRoot]
	if not forced then
		forced = {}
		treeFormationForced[treeRoot] = forced
	end

	for _, descendant in treeRoot:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			forced[descendant] = true
			descendant.Anchored = true
		end
	end

	if treeRoot:IsA("BasePart") and not treeRoot.Anchored then
		forced[treeRoot] = true
		treeRoot.Anchored = true
	end
end

local function anchorTreePartForFormation(part: BasePart)
	if part.Anchored then
		return
	end

	part.Anchored = true
	local treeRoot = getTreeRoot(part)
	if treeRoot then
		local forced = treeFormationForced[treeRoot]
		if not forced then
			forced = {}
			treeFormationForced[treeRoot] = forced
		end
		forced[part] = true
	end

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			descendant.Anchored = true
			if treeRoot then
				local forced = treeFormationForced[treeRoot]
				if forced then
					forced[descendant] = true
				end
			end
		end
	end
end

local function treeHasScaleInPending(treeRoot: Instance): boolean
	local pending = treeScaleInPending[treeRoot]
	if not pending then
		return false
	end

	for _ in pending do
		return true
	end

	return false
end

local function beginTreePartScaleIn(treeRoot: Instance, part: BasePart)
	local pending = treeScaleInPending[treeRoot]
	if not pending then
		pending = {}
		treeScaleInPending[treeRoot] = pending
	end
	pending[part] = true
end

local function endTreePartScaleIn(treeRoot: Instance, part: BasePart)
	local pending = treeScaleInPending[treeRoot]
	if pending then
		pending[part] = nil
	end
end

local function isPartHiddenForRespawn(part: BasePart): boolean
	if part:GetAttribute("HiddenForRespawn") == true then
		return true
	end

	local folder = hiddenFolder
	if folder and part.Parent == folder then
		return true
	end

	return false
end

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

local function findInstanceByFullName(fullName: string): Instance?
	local current: Instance = game

	for _, segment in string.split(fullName, ".") do
		if segment == "Game" then
			continue
		end

		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end

		current = child
	end

	return current
end

local function treeHasHiddenPartsPending(treeRoot: Instance): boolean
	local folder = hiddenFolder
	if not folder then
		return false
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("HiddenForRespawn") then
			if treeRootByPart[child] == treeRoot or snapshotsByPart[child] then
				return true
			end
		end
	end

	return false
end

local function treeHasOutstandingParts(treeRoot: Instance): boolean
	if treeHasScaleInPending(treeRoot) or treeHasHiddenPartsPending(treeRoot) then
		return true
	end

	for part, snapshot in snapshotsByPart do
		if partBelongsToTree(part, treeRoot, snapshot) then
			return true
		end
	end

	for _, entry in pendingRespawns do
		if partBelongsToTree(entry.part, treeRoot, entry.snapshot) then
			return true
		end
	end

	for part, root in treeRootByPart do
		if root == treeRoot and (snapshotsByPart[part] or isPartHiddenForRespawn(part)) then
			return true
		end
	end

	return false
end

local function findPartForRespawn(entry: PendingRespawn): BasePart?
	local part = entry.part
	if part.Parent then
		return part
	end

	local folder = getHiddenFolder()
	if folder then
		for _, child in folder:GetChildren() do
			if not child:IsA("BasePart") or not child:GetAttribute("HiddenForRespawn") then
				continue
			end

			if child == part then
				return child
			end

			if child.Name == entry.snapshot.partName and snapshotsByPart[child] then
				return child
			end
		end
	end

	if entry.snapshot.workspaceFullName then
		local found = findInstanceByFullName(entry.snapshot.workspaceFullName)
		if found and found:IsA("BasePart") then
			return found
		end
	end

	return nil
end

local function resolveRestoreParent(snapshot: PartSnapshot, part: BasePart, treeRoot: Instance?): Instance?
	if snapshot.parent.Parent then
		return snapshot.parent
	end

	if snapshot.parentPath then
		local fromPath = findInstanceByFullName(snapshot.parentPath)
		if fromPath then
			return fromPath
		end
	end

	if treeRoot then
		local named = treeRoot:FindFirstChild(snapshot.parent.Name, true)
		if named then
			return named
		end

		return treeRoot
	end

	local workspaceParent = workspace:FindFirstChild(snapshot.parent.Name, true)
	if workspaceParent then
		return workspaceParent
	end

	return nil
end

local function clearTreeStateForPart(part: BasePart, treeRoot: Instance?)
	local root = treeRoot or treeRootByPart[part]
	treeAnchorRestore[part] = nil
	treeRootByPart[part] = nil

	if root then
		local pending = treeScaleInPending[root]
		if pending then
			pending[part] = nil
		end
	end
end

local function clearTreeSessionState(treeRoot: Instance)
	treeScaleInPending[treeRoot] = nil
	treeFormationForced[treeRoot] = nil

	for part, root in treeRootByPart do
		if root == treeRoot then
			treeAnchorRestore[part] = nil
			treeRootByPart[part] = nil
		end
	end
end

local function restoreDescendantPartTransforms(part: BasePart, snapshot: PartSnapshot)
	for instance, data in snapshot.descendants do
		if instance.Parent and instance:IsA("BasePart") and data.localCFrame then
			instance.CFrame = part.CFrame * data.localCFrame
			if data.size then
				instance.Size = data.size
			end
		end
	end
end

local function applyPartTransform(part: BasePart, snapshot: PartSnapshot, anchored: boolean?, treeRoot: Instance?)
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	local restoreParent = resolveRestoreParent(snapshot, part, treeRoot)
	if restoreParent then
		part.Parent = restoreParent
	end

	part:PivotTo(snapshot.cframe)
	part.CanCollide = snapshot.canCollide
	BreakCollision.restorePart(part, snapshot.collisionGroup)
	part.CanTouch = snapshot.canTouch
	part.CanQuery = snapshot.canQuery
	part.Anchored = if anchored ~= nil then anchored else snapshot.anchored
	restoreDescendantPartTransforms(part, snapshot)
end

local function cloneSnapshot(snapshot: PartSnapshot): PartSnapshot
	local descendants: { [Instance]: DescendantSnapshot } = {}
	for instance, data in snapshot.descendants do
		descendants[instance] = {
			transparency = data.transparency,
			size = data.size,
			localCFrame = data.localCFrame,
		}
	end

	return {
		partName = snapshot.partName,
		workspaceFullName = snapshot.workspaceFullName,
		cframe = snapshot.cframe,
		parent = snapshot.parent,
		parentPath = snapshot.parentPath,
		anchored = snapshot.anchored,
		canCollide = snapshot.canCollide,
		collisionGroup = snapshot.collisionGroup,
		canTouch = snapshot.canTouch,
		canQuery = snapshot.canQuery,
		transparency = snapshot.transparency,
		color = snapshot.color,
		material = snapshot.material,
		size = snapshot.size,
		descendants = descendants,
	}
end

local function captureTreeOriginSnapshots(treeRoot: Instance)
	local origins = treeOriginSnapshots[treeRoot]
	if not origins then
		origins = {}
		treeOriginSnapshots[treeRoot] = origins
	end

	for _, descendant in treeRoot:GetDescendants() do
		if descendant:IsA("BasePart") and not origins[descendant] then
			origins[descendant] = cloneSnapshot(BreakRespawnService.captureSnapshot(descendant))
		end
	end

	if treeRoot:IsA("BasePart") and not origins[treeRoot] then
		origins[treeRoot] = cloneSnapshot(BreakRespawnService.captureSnapshot(treeRoot))
	end

	captureTreeWelds(treeRoot)
end

local function ensurePartInTreeOrigins(treeRoot: Instance, part: BasePart): PartSnapshot?
	captureTreeOriginSnapshots(treeRoot)

	local origins = treeOriginSnapshots[treeRoot]
	if not origins then
		return nil
	end

	if not origins[part] then
		origins[part] = cloneSnapshot(BreakRespawnService.captureSnapshot(part))
	end

	return origins[part]
end

local function getTreeOriginSnapshot(part: BasePart, treeRoot: Instance): PartSnapshot?
	local origins = treeOriginSnapshots[treeRoot]
	if origins then
		return origins[part]
	end

	return nil
end

local function getTreeRespawnSnapshot(part: BasePart, fallback: PartSnapshot): PartSnapshot
	local treeRoot = treeRootByPart[part] or getTreeRoot(part)
	if treeRoot then
		local originSnapshot = getTreeOriginSnapshot(part, treeRoot)
		if originSnapshot then
			return originSnapshot
		end

		warn(`[BreakRespawn] Missing origin snapshot for {part:GetFullName()} under {treeRoot:GetFullName()}`)
	end

	return fallback
end

local function restoreTreeOriginTransforms(treeRoot: Instance)
	local origins = treeOriginSnapshots[treeRoot]
	if not origins then
		return
	end

	for part, snapshot in origins do
		if treeAnchorRestore[part] == nil then
			continue
		end

		if not part.Parent or isPartHiddenForRespawn(part) then
			continue
		end

		if not resolveRestoreParent(snapshot, part, treeRoot) then
			continue
		end

		applyPartTransform(part, snapshot, true, treeRoot)
	end
end

local function releaseTreeFormation(treeRoot: Instance)
	restoreTreeOriginTransforms(treeRoot)
	restoreTreeWelds(treeRoot)

	local partsToRestore: { BasePart } = {}
	for part, _ in treeAnchorRestore do
		if treeRootByPart[part] == treeRoot or getTreeRoot(part) == treeRoot then
			table.insert(partsToRestore, part)
		end
	end

	for _, part in partsToRestore do
		if part.Parent then
			part.Anchored = treeAnchorRestore[part]
		end
		treeAnchorRestore[part] = nil
		treeRootByPart[part] = nil
	end

	local forced = treeFormationForced[treeRoot]
	if forced then
		for part, wasForced in forced do
			if wasForced and part.Parent and treeAnchorRestore[part] == nil then
				part.Anchored = false
			end
		end
		treeFormationForced[treeRoot] = nil
	end

	clearTreeSessionState(treeRoot)
	setTreeFormingState(treeRoot, false)
end

local function collectActiveTreeFormationRoots(): { Instance }
	local roots: { [Instance]: boolean } = {}

	for _, treeRoot in treeRootByPart do
		roots[treeRoot] = true
	end

	for _, tagged in CollectionService:GetTagged(GameConfig.TreeTag) do
		if tagged:GetAttribute("TreeForming") == true then
			roots[tagged] = true
		end
	end

	local unique: { Instance } = {}
	for treeRoot in roots do
		table.insert(unique, treeRoot)
	end

	return unique
end

local function tryCompleteTreeFormation(treeRoot: Instance)
	if treeHasOutstandingParts(treeRoot) then
		return
	end

	releaseTreeFormation(treeRoot)
end

local function forceCompleteStuckTreeFormations()
	for _, treeRoot in collectActiveTreeFormationRoots() do
		tryCompleteTreeFormation(treeRoot)
	end
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
		if part.Parent or isPartHiddenForRespawn(part) then
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
				localCFrame = part.CFrame:ToObjectSpace(descendant.CFrame),
			}
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendants[descendant] = {
				transparency = descendant.Transparency,
			}
		end
	end

	local parent = part.Parent :: Instance
	local workspaceFullName = if part:IsDescendantOf(workspace) then part:GetFullName() else nil

	return {
		partName = part.Name,
		workspaceFullName = workspaceFullName,
		cframe = part.CFrame,
		parent = parent,
		parentPath = parent:GetFullName(),
		anchored = part.Anchored,
		canCollide = part.CanCollide,
		collisionGroup = part.CollisionGroup,
		canTouch = part.CanTouch,
		canQuery = part.CanQuery,
		transparency = part.Transparency,
		color = part.Color,
		material = part.Material,
		size = part.Size,
		descendants = descendants,
	}
end

function BreakRespawnService.hasSnapshot(part: BasePart): boolean
	return snapshotsByPart[part] ~= nil
end

local function registerBrokenPartInternal(part: BasePart, snapshot: PartSnapshot)
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

function BreakRespawnService.registerTreeClusterBroken(treeRoot: Instance, clusterParts: { BasePart })
	captureTreeOriginSnapshots(treeRoot)

	for _, clusterPart in clusterParts do
		if not clusterPart.Parent then
			continue
		end

		local originSnapshot = ensurePartInTreeOrigins(treeRoot, clusterPart)
		if not originSnapshot then
			warn(`[BreakRespawn] Skipping tree cluster part without origin: {clusterPart:GetFullName()}`)
			continue
		end

		treeRootByPart[clusterPart] = treeRoot
		treeAnchorRestore[clusterPart] = originSnapshot.anchored
		registerBrokenPartInternal(clusterPart, originSnapshot)
	end
end

function BreakRespawnService.registerBrokenPart(part: BasePart, snapshot: PartSnapshot)
	if not part.Parent then
		return
	end

	local treeRoot = getTreeRoot(part)
	if treeRoot then
		treeRootByPart[part] = treeRoot
		local originSnapshot = ensurePartInTreeOrigins(treeRoot, part)
		if originSnapshot then
			snapshot = originSnapshot
		else
			snapshot = cloneSnapshot(snapshot)
			warn(`[BreakRespawn] Using break-time snapshot for tree part: {part:GetFullName()}`)
		end
		treeAnchorRestore[part] = snapshot.anchored
	end

	registerBrokenPartInternal(part, snapshot)
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
			if data.localCFrame then
				instance.CFrame = part.CFrame * data.localCFrame
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

local function finishRespawnRestore(part: BasePart, snapshot: PartSnapshot)
	local treeRoot = treeRootByPart[part] or getTreeRoot(part)
	if treeRoot then
		endTreePartScaleIn(treeRoot, part)
	end

	if not part.Parent then
		if treeRoot then
			tryCompleteTreeFormation(treeRoot)
		end
		return
	end

	snapshot = getTreeRespawnSnapshot(part, snapshot)

	part.Size = snapshot.size
	restoreVisuals(part, snapshot)
	clearRespawnScaleAttributes(part)
	part:PivotTo(snapshot.cframe)
	restoreDescendantPartTransforms(part, snapshot)

	if treeRoot then
		tryCompleteTreeFormation(treeRoot)
	end
end

function BreakRespawnService.respawnPart(part: BasePart): boolean
	local snapshot = snapshotsByPart[part]
	if not snapshot then
		return false
	end

	snapshot = getTreeRespawnSnapshot(part, snapshot)

	if not part.Parent then
		return false
	end

	local treeRoot = treeRootByPart[part] or getTreeRoot(part)
	if not resolveRestoreParent(snapshot, part, treeRoot) then
		if treeRoot then
			tryCompleteTreeFormation(treeRoot)
		end
		return false
	end

	local respawnAnchored = if treeRoot then true else snapshot.anchored

	if treeRoot then
		setTreeFormingState(treeRoot, true)
		anchorTreeForFormation(treeRoot)
	end

	applyPartTransform(part, snapshot, respawnAnchored, treeRoot)

	if treeRoot then
		anchorTreePartForFormation(part)
		beginTreePartScaleIn(treeRoot, part)
	end

	restoreVisuals(part, snapshot)
	applyScaleInStart(part, snapshot)

	part:SetAttribute("Broken", nil)
	part:SetAttribute("Shattered", nil)
	part:SetAttribute("HiddenForRespawn", nil)
	part:SetAttribute("DragWeldsBroken", nil)
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
	local needsSoonRetry = false
	local processed: { [BasePart]: boolean } = {}

	for part, snapshot in snapshotsByPart do
		local target = part
		if not target.Parent and not isPartHiddenForRespawn(target) then
			local entry: PendingRespawn = {
				part = part,
				snapshot = snapshot,
				order = 0,
			}
			target = findPartForRespawn(entry) or part
		end

		if not target.Parent and not isPartHiddenForRespawn(target) then
			snapshotsByPart[part] = nil
			clearTreeStateForPart(part, nil)
			continue
		end

		if processed[target] then
			continue
		end
		processed[target] = true

		if target ~= part then
			snapshotsByPart[target] = snapshot
			snapshotsByPart[part] = nil
		end

		if not BreakRespawnService.respawnPart(target) then
			needsSoonRetry = true
		end
	end

	if needsSoonRetry and hasPendingRespawns() then
		task.delay(2, flushOrphanedSnapshots)
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
			local part = findPartForRespawn(entry)
			if not part then
				snapshotsByPart[entry.part] = nil
				clearTreeStateForPart(entry.part, treeRootByPart[entry.part])
				warn(`[BreakRespawn] Lost part for respawn: {entry.snapshot.partName}`)
				return
			end

			local snapshot = getTreeRespawnSnapshot(part, entry.snapshot)
			entry.snapshot = snapshot
			entry.part = part
			snapshotsByPart[part] = snapshot
			if entry.part ~= part then
				snapshotsByPart[entry.part] = nil
			end

			if not BreakRespawnService.respawnPart(part) then
				local treeRoot = treeRootByPart[part] or getTreeRoot(part)
				if treeRoot then
					tryCompleteTreeFormation(treeRoot)
				end
			end
		end)
	end

	local waveFinishDelay = #waveBatch * GameConfig.BreakRespawnDominoStagger
		+ GameConfig.BreakRespawnScaleInDuration
		+ 0.05

	task.delay(waveFinishDelay, function()
		forceCompleteStuckTreeFormations()

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

local function hookTreeOriginCapture(treeRoot: Instance)
	if treeRoot:GetAttribute("TreeOriginsHooked") == true then
		return
	end
	treeRoot:SetAttribute("TreeOriginsHooked", true)

	treeRoot.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			task.defer(captureTreeOriginSnapshots, treeRoot)
		end
	end)
end

local function bootstrapTreeOrigins(treeInstance: Instance)
	if treeInstance:IsA("BasePart") then
		local treeRoot = getTreeRoot(treeInstance)
		if treeRoot then
			captureTreeOriginSnapshots(treeRoot)
			hookTreeOriginCapture(treeRoot)
		end
		return
	end

	if CollectionService:HasTag(treeInstance, GameConfig.TreeTag) then
		captureTreeOriginSnapshots(treeInstance)
		hookTreeOriginCapture(treeInstance)
	end
end

for _, treeInstance in CollectionService:GetTagged(GameConfig.TreeTag) do
	task.defer(bootstrapTreeOrigins, treeInstance)
end

CollectionService:GetInstanceAddedSignal(GameConfig.TreeTag):Connect(function(treeInstance: Instance)
	task.defer(bootstrapTreeOrigins, treeInstance)
end)

return BreakRespawnService
