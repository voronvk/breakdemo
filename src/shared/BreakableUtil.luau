local CollectionService = game:GetService("CollectionService")

local GameConfig = require(script.Parent.GameConfig)

local BreakableUtil = {}

function BreakableUtil.isBreakable(part: Instance): boolean
	if not part:IsA("BasePart") then
		return false
	end

	local current: Instance? = part
	while current do
		if CollectionService:HasTag(current, GameConfig.BreakableTag) then
			return true
		end
		current = current.Parent
	end

	return false
end

function BreakableUtil.getDistanceToPart(player: Player, part: BasePart): number?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	return (part.Position - root.Position).Magnitude
end

function BreakableUtil.isInBreakRange(player: Player, part: BasePart): boolean
	local distance = BreakableUtil.getDistanceToPart(player, part)
	if not distance then
		return false
	end

	return distance <= GameConfig.BreakRange
end

function BreakableUtil.getClusterSearchRoot(part: BasePart): Instance
	return part:FindFirstAncestorWhichIsA("Model") or part.Parent or part
end

function BreakableUtil.getBreakCluster(part: BasePart, includeNearbySiblings: boolean?): { BasePart }
	local searchRoot = BreakableUtil.getClusterSearchRoot(part)
	local connected: { [BasePart]: boolean } = { [part] = true }
	local changed = true

	while changed do
		changed = false
		for _, inst in searchRoot:GetDescendants() do
			if inst:IsA("WeldConstraint") or inst:IsA("Weld") then
				local p0 = inst.Part0
				local p1 = inst.Part1
				if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
					if connected[p0] and not connected[p1] and p1:IsDescendantOf(searchRoot) then
						connected[p1] = true
						changed = true
					elseif connected[p1] and not connected[p0] and p0:IsDescendantOf(searchRoot) then
						connected[p0] = true
						changed = true
					end
				end
			end
		end
	end

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			connected[descendant] = true
		end
	end

	if includeNearbySiblings == true and GameConfig.BreakClusterIncludeSiblings == true then
		local parent = part.Parent
		if parent then
			for _, sibling in parent:GetChildren() do
				if sibling:IsA("BasePart") and BreakableUtil.isBreakable(sibling) then
					if (sibling.Position - part.Position).Magnitude <= GameConfig.BreakClusterSiblingRadius then
						connected[sibling] = true
					end
				end
			end
		end
	end

	local cluster: { BasePart } = {}
	for clusterPart in connected do
		table.insert(cluster, clusterPart)
	end

	return cluster
end

function BreakableUtil.removeClusterWelds(cluster: { BasePart }, part: BasePart)
	local searchRoot = BreakableUtil.getClusterSearchRoot(part)
	local inCluster: { [BasePart]: boolean } = {}
	for _, clusterPart in cluster do
		inCluster[clusterPart] = true
	end

	for _, inst in searchRoot:GetDescendants() do
		if inst:IsA("WeldConstraint") or inst:IsA("Weld") then
			local p0 = inst.Part0
			local p1 = inst.Part1
			if p0 and p1 and (inCluster[p0] or inCluster[p1]) then
				inst:Destroy()
			end
		end
	end
end

function BreakableUtil.getTreeRoot(part: BasePart): Instance?
	local current: Instance? = part
	while current do
		if CollectionService:HasTag(current, GameConfig.TreeTag) then
			return current
		end
		current = current.Parent
	end

	return nil
end

function BreakableUtil.isTreeForming(part: BasePart): boolean
	if part:GetAttribute("TreeForming") == true then
		return true
	end

	local treeRoot = BreakableUtil.getTreeRoot(part)
	if treeRoot and treeRoot:GetAttribute("TreeForming") == true then
		return true
	end

	return false
end

function BreakableUtil.isPartBrokenState(part: BasePart): boolean
	return part:GetAttribute("Broken") == true or part:GetAttribute("HiddenForRespawn") == true
end

function BreakableUtil.filterBreakableCluster(cluster: { BasePart }): { BasePart }
	local active: { BasePart } = {}

	for _, clusterPart in cluster do
		if clusterPart.Parent and not BreakableUtil.isPartBrokenState(clusterPart) then
			table.insert(active, clusterPart)
		end
	end

	return active
end

return BreakableUtil
