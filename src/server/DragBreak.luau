local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BreakVFX = require(script.Parent.BreakVFX)
local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)

local dragBreakRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DragBreak") :: RemoteEvent

local hookedDetectors: { [DragDetector]: boolean } = {}
local processingClusters: { [BasePart]: boolean } = {}

local function resolveDragPart(dragDetector: DragDetector, clickedPart: Instance?): BasePart?
	if clickedPart and clickedPart:IsA("BasePart") then
		return clickedPart
	end

	local parent = dragDetector.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end

	if parent and parent:IsA("Model") then
		if parent.PrimaryPart then
			return parent.PrimaryPart
		end

		for _, child in parent:GetChildren() do
			if child:IsA("BasePart") then
				return child
			end
		end
	end

	return nil
end

local function getActiveDragCluster(part: BasePart): { BasePart }
	local cluster = BreakableUtil.getBreakCluster(part, true)
	local active: { BasePart } = {}

	for _, clusterPart in cluster do
		if clusterPart.Parent and not BreakableUtil.isPartBrokenState(clusterPart) and not BreakableUtil.isTreeForming(clusterPart) then
			table.insert(active, clusterPart)
		end
	end

	return active
end

local function clusterAlreadyDetached(cluster: { BasePart }): boolean
	for _, clusterPart in cluster do
		if clusterPart:GetAttribute("DragWeldsBroken") then
			return true
		end
	end

	return false
end

local function processDragBreak(player: Player, part: BasePart)
	if not part:IsA("BasePart") or not part:IsDescendantOf(Workspace) then
		return
	end

	local cluster = getActiveDragCluster(part)
	if #cluster == 0 then
		return
	end

	if clusterAlreadyDetached(cluster) then
		return
	end

	local clusterKey = cluster[1]
	if processingClusters[clusterKey] then
		return
	end
	processingClusters[clusterKey] = true

	for _, clusterPart in cluster do
		clusterPart:SetAttribute("DragWeldsBroken", true)
	end

	BreakableUtil.removeClusterWelds(cluster, part)

	for _, clusterPart in cluster do
		if clusterPart.Anchored then
			clusterPart.Anchored = false
		end
	end

	local impactPoint = part.Position
	BreakVFX.playDirect(part, impactPoint, player, true)

	for _, clusterPart in cluster do
		if clusterPart ~= part then
			task.defer(function()
				if clusterPart.Parent then
					BreakVFX.playChain(clusterPart, impactPoint, player)
				end
			end)
		end
	end

	dragBreakRemote:FireClient(player)
	processingClusters[clusterKey] = nil
end

local function hookDragDetector(dragDetector: DragDetector)
	if hookedDetectors[dragDetector] then
		return
	end
	hookedDetectors[dragDetector] = true

	local function onDragStart(playerWhoDragged: Player, _, _, _, clickedPart: Instance?)
		local targetPart = resolveDragPart(dragDetector, clickedPart)
		if targetPart then
			processDragBreak(playerWhoDragged, targetPart)
		end
	end

	dragDetector.DragStart:Connect(onDragStart)

	dragDetector.Destroying:Connect(function()
		hookedDetectors[dragDetector] = nil
	end)
end

local function registerDragDetector(dragDetector: DragDetector)
	hookDragDetector(dragDetector)
end

local function scanForDragDetectors(root: Instance)
	if root:IsA("DragDetector") then
		registerDragDetector(root)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("DragDetector") then
			registerDragDetector(descendant)
		end
	end
end

dragBreakRemote.OnServerEvent:Connect(function(player: Player, part: Instance?)
	if not part or not part:IsA("BasePart") then
		return
	end

	processDragBreak(player, part)
end)

scanForDragDetectors(Workspace)

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("DragDetector") then
		registerDragDetector(descendant)
	end
end)

return nil
