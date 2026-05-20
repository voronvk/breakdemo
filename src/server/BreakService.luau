local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local BreakBudget = require(script.Parent.BreakBudget)
local BreakVFX = require(script.Parent.BreakVFX)
local XPService = if GameConfig.XPEnabled then require(script.Parent.XPService) else nil
local BreakRespawnService = require(script.Parent.BreakRespawnService)
local FallShatter = require(script.Parent.FallShatter)
local FallTracker = require(script.Parent.FallTracker)

local breakPartRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BreakPart") :: RemoteFunction

local BreakService = {}

local breakingParts: { [BasePart]: boolean } = {}
local frozenClusters: { [BasePart]: { BasePart } } = {}

local function randomInRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function shuffle<T>(list: { T })
	for index = #list, 2, -1 do
		local swapIndex = math.random(1, index)
		list[index], list[swapIndex] = list[swapIndex], list[index]
	end
end

local function releaseClusterState(primaryPart: BasePart, cluster: { BasePart })
	for _, clusterPart in cluster do
		breakingParts[clusterPart] = nil
	end
	frozenClusters[primaryPart] = nil
	BreakBudget.releaseBroken()
end

local function fadeAndHideClusterForRespawn(primaryPart: BasePart, cluster: { BasePart }, fadeDuration: number)
	BreakRespawnService.fadeAndHideCluster(cluster, fadeDuration, function()
		releaseClusterState(primaryPart, cluster)
	end)
end

local function getPartsNeedingHide(cluster: { BasePart }): { BasePart }
	local parts: { BasePart } = {}

	for _, clusterPart in cluster do
		if clusterPart.Parent and not clusterPart:GetAttribute("HiddenForRespawn") then
			table.insert(parts, clusterPart)
		end
	end

	return parts
end

local function applyHitTint(part: BasePart, strong: boolean?)
	local tintAmount = if strong
		then GameConfig.DirectHitTintAmount + randomInRange(-GameConfig.HitTintAmountVariance * 0.5, GameConfig.HitTintAmountVariance * 0.5)
		else GameConfig.HitTintAmount + randomInRange(-GameConfig.HitTintAmountVariance, GameConfig.HitTintAmountVariance)
	tintAmount = math.clamp(tintAmount, 0.1, 0.65)
	part.Color = part.Color:Lerp(GameConfig.HitTintColor, tintAmount)
end

local function applyHitTintToCluster(cluster: { BasePart }, useStrongBreak: boolean)
	for _, clusterPart in cluster do
		applyHitTint(clusterPart, useStrongBreak)
	end
end

local function resolveBreakCluster(part: BasePart, expandSiblings: boolean): { BasePart }
	return BreakableUtil.filterBreakableCluster(BreakableUtil.getBreakCluster(part, expandSiblings))
end

local function registerClusterForRespawn(cluster: { BasePart })
	for _, clusterPart in cluster do
		local respawnSnapshot = BreakRespawnService.captureSnapshot(clusterPart)
		BreakRespawnService.registerBrokenPart(clusterPart, respawnSnapshot)
	end
end

local function markClusterBroken(cluster: { BasePart })
	for _, clusterPart in cluster do
		breakingParts[clusterPart] = true
		clusterPart:SetAttribute("Broken", true)
	end
end

local function tryRecoverStuckBreak(part: BasePart): boolean
	if not part:GetAttribute("Broken") or part:GetAttribute("HiddenForRespawn") then
		return false
	end

	if not part.Parent or not part:IsDescendantOf(workspace) then
		part:SetAttribute("Broken", nil)
		return false
	end

	local cluster = BreakableUtil.getBreakCluster(part, true)
	registerClusterForRespawn(cluster)
	frozenClusters[part] = cluster

	BreakRespawnService.fadeAndHideCluster(cluster, 0.25, function()
		for _, clusterPart in cluster do
			breakingParts[clusterPart] = nil
		end
		frozenClusters[part] = nil
	end)

	return true
end

local function quickCleanupCluster(cluster: { BasePart }, primaryPart: BasePart)
	for _, clusterPart in cluster do
		FallTracker.unwatch(clusterPart)
	end

	BreakableUtil.removeExternalWelds(cluster, primaryPart)

	for _, clusterPart in cluster do
		if clusterPart.Parent then
			clusterPart.CanCollide = false
			if clusterPart.Anchored then
				clusterPart.Anchored = false
			end
		end
	end

	local partsToHide = getPartsNeedingHide(cluster)
	if #partsToHide > 0 then
		fadeAndHideClusterForRespawn(primaryPart, cluster, 0.35)
	else
		releaseClusterState(primaryPart, cluster)
	end
end

local function applyBreakImpulse(
	part: BasePart,
	explosionCenter: Vector3?,
	useStrongBreak: boolean,
	isPrimaryPart: boolean
)
	local mass = part.AssemblyMass
	local impulseScale = randomInRange(GameConfig.BreakImpulseMinScale, GameConfig.BreakImpulseMaxScale)

	local strengthScale = 1
	local massImpulseScale = 0.35
	local angularScale = 1

	if useStrongBreak then
		if isPrimaryPart then
			strengthScale = GameConfig.DirectBreakImpulseScale
			massImpulseScale = GameConfig.DirectBreakImpulseMassScale
			angularScale = GameConfig.DirectBreakAngularScale
		else
			strengthScale = GameConfig.ChainBreakImpulseScale
			massImpulseScale = GameConfig.ChainBreakImpulseMassScale
			angularScale = GameConfig.ChainBreakAngularScale
		end
	end

	local direction = Vector3.new(
		randomInRange(-0.9, 0.9),
		randomInRange(0.35, 0.95),
		randomInRange(-0.9, 0.9)
	)

	if explosionCenter then
		local pushAway = part.Position - explosionCenter
		if pushAway.Magnitude > 0.05 then
			local pushStrength = if isPrimaryPart
				then randomInRange(2, 3.2)
				elseif useStrongBreak
				then randomInRange(1.25, 2.35)
				else randomInRange(0.5, 1.8)
			direction += pushAway.Unit * pushStrength

			local upBoost = if isPrimaryPart then 1.15 elseif useStrongBreak then GameConfig.ChainExplosionUpBoost else 0.5
			direction += Vector3.yAxis * randomInRange(0.35, 1) * upBoost
		end
	end

	direction = direction.Unit
	local speed = GameConfig.BreakUpImpulse * impulseScale * strengthScale * randomInRange(0.9, 1.35)

	part.AssemblyLinearVelocity = direction * speed
	part:ApplyImpulse(direction * GameConfig.BreakUpImpulse * impulseScale * strengthScale * mass * massImpulseScale)

	local spinAxis = Vector3.new(
		randomInRange(-1, 1),
		randomInRange(-1, 1),
		randomInRange(-1, 1)
	)
	if spinAxis.Magnitude > 0.05 then
		local angularSpeed = randomInRange(5, 16) * randomInRange(0.85, 1.45) * angularScale
		part.AssemblyAngularVelocity = spinAxis.Unit * angularSpeed
		part:ApplyAngularImpulse(
			spinAxis.Unit * GameConfig.BreakAngularImpulse * randomInRange(0.65, 1.4) * angularScale * mass
		)
	end
end

local function playBreakVfxForPart(
	clusterPart: BasePart,
	explosionCenter: Vector3?,
	hitter: Player?,
	useStrongBreak: boolean,
	isPrimaryPart: boolean,
	isPrimaryHit: boolean,
	useBudgetLightVfx: boolean
)
	if useBudgetLightVfx then
		if useStrongBreak then
			if isPrimaryPart then
				BreakVFX.playDirect(clusterPart, explosionCenter, hitter, isPrimaryHit)
			else
				BreakVFX.playChainBurst(clusterPart, explosionCenter, hitter)
			end
		else
			BreakVFX.playLight(clusterPart, explosionCenter)
		end
		return
	end

	if useStrongBreak then
		if isPrimaryPart then
			BreakVFX.playDirect(clusterPart, explosionCenter, hitter, isPrimaryHit)
		else
			BreakVFX.playChainBurst(clusterPart, explosionCenter, hitter)
		end
	else
		BreakVFX.playChain(clusterPart, explosionCenter, hitter)
	end
end

local function applyClusterPartPhysics(
	clusterPart: BasePart,
	explosionCenter: Vector3?,
	hitter: Player?,
	useStrongBreak: boolean,
	isPrimaryPart: boolean,
	isPrimaryHit: boolean,
	useBudgetLightVfx: boolean
)
	if not clusterPart.Parent then
		return
	end

	playBreakVfxForPart(
		clusterPart,
		explosionCenter,
		hitter,
		useStrongBreak,
		isPrimaryPart,
		isPrimaryHit,
		useBudgetLightVfx
	)

	if clusterPart.Anchored then
		clusterPart.Anchored = false
	end
	clusterPart.CanCollide = true
	applyBreakImpulse(clusterPart, explosionCenter, useStrongBreak, isPrimaryPart)
	FallShatter.watch(clusterPart)
end

local function releaseClusterPhysics(
	primaryPart: BasePart,
	cluster: { BasePart },
	explosionCenter: Vector3?,
	hitter: Player?,
	useStrongBreak: boolean,
	isPrimaryHit: boolean,
	useBudgetLightVfx: boolean
)
	BreakableUtil.removeExternalWelds(cluster, primaryPart)

	applyClusterPartPhysics(
		primaryPart,
		explosionCenter,
		hitter,
		useStrongBreak,
		true,
		isPrimaryHit,
		useBudgetLightVfx
	)

	for _, clusterPart in cluster do
		if clusterPart ~= primaryPart then
			task.defer(function()
				applyClusterPartPhysics(
					clusterPart,
					explosionCenter,
					hitter,
					useStrongBreak,
					false,
					false,
					useBudgetLightVfx
				)
			end)
		end
	end
end

local function isWithinChainBreakRange(originPosition: Vector3, partPosition: Vector3, breakRadius: number): boolean
	local offset = partPosition - originPosition
	local euclidean = offset.Magnitude
	if euclidean <= 0.02 then
		return false
	end

	if GameConfig.ChainBreakUsePlanarDistance == true then
		local planar = math.max(math.abs(offset.X), math.abs(offset.Z))
		local verticalLimit = math.max(2, breakRadius * 0.85)
		return planar <= breakRadius and math.abs(offset.Y) <= verticalLimit and euclidean <= breakRadius * 1.45
	end

	return euclidean <= breakRadius
end

local function getChainBreakCount(): number
	local minCount = math.max(0, math.floor(GameConfig.ChainBreakCountMin))
	local maxCount = math.max(minCount, math.floor(GameConfig.ChainBreakCountMax))
	return math.random(minCount, maxCount)
end

local function getChainBreakRadius(): number
	local variance = GameConfig.ChainBreakRadiusVariance
	return GameConfig.ChainBreakRadius + randomInRange(-variance, variance)
end

local function gatherNearbyBreakables(origin: BasePart): { BasePart }
	local candidates: { BasePart } = {}
	local searchRoot = origin:FindFirstAncestorWhichIsA("Model") or origin.Parent
	if not searchRoot then
		return {}
	end

	local breakRadius = math.max(0.75, getChainBreakRadius())
	local originPosition = origin.Position

	for _, descendant in searchRoot:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= origin then
			if BreakableUtil.isBreakable(descendant) and not BreakableUtil.isPartBrokenState(descendant) then
				if isWithinChainBreakRange(originPosition, descendant.Position, breakRadius) then
					table.insert(candidates, descendant)
				end
			end
		end
	end

	if #candidates == 0 then
		return {}
	end

	shuffle(candidates)

	local chainCount = math.min(getChainBreakCount(), #candidates)
	local selected: { BasePart } = {}
	for index = 1, chainCount do
		selected[index] = candidates[index]
	end

	return selected
end

local function scheduleFadeAndCleanup(primaryPart: BasePart, useLightBreak: boolean)
	local cluster = frozenClusters[primaryPart]
	if not cluster then
		return
	end

	local fadeDelay = if useLightBreak
		then GameConfig.LightBreakFadeDelay
		else GameConfig.BreakFadeDelay + randomInRange(0, GameConfig.BreakFadeDelayVariance)

	local fadeDuration = if useLightBreak
		then 0.4
		else GameConfig.BreakFadeDuration + randomInRange(-GameConfig.BreakFadeDurationVariance, GameConfig.BreakFadeDurationVariance)
	fadeDuration = math.max(0.2, fadeDuration)

	task.delay(fadeDelay, function()
		local sessionCluster = frozenClusters[primaryPart] or cluster
		local partsToHide = getPartsNeedingHide(sessionCluster)

		if #partsToHide == 0 then
			releaseClusterState(primaryPart, sessionCluster)
			return
		end

		fadeAndHideClusterForRespawn(primaryPart, sessionCluster, fadeDuration)
	end)
end

local function breakPartInternal(
	part: BasePart,
	impactPoint: Vector3?,
	physicsDelay: number,
	hitter: Player?,
	useStrongBreak: boolean,
	isPrimaryHit: boolean
): boolean
	if not part:IsDescendantOf(workspace) or not BreakableUtil.isBreakable(part) then
		return false
	end

	if tryRecoverStuckBreak(part) then
		return true
	end

	if breakingParts[part] or BreakableUtil.isPartBrokenState(part) then
		return false
	end

	local cluster = resolveBreakCluster(part, isPrimaryHit)
	if #cluster == 0 then
		return false
	end

	frozenClusters[part] = cluster
	registerClusterForRespawn(cluster)

	local hasBudget = BreakBudget.tryRegisterBroken()
	local useLightBreak = not hasBudget

	if useLightBreak then
		markClusterBroken(cluster)
		applyHitTintToCluster(cluster, useStrongBreak)
		if XPService then
			XPService.trySpawnFromBreak(part, impactPoint)
		end
		quickCleanupCluster(cluster, part)
		return true
	end

	markClusterBroken(cluster)
	if XPService then
		XPService.trySpawnFromBreak(part, impactPoint)
	end
	applyHitTintToCluster(cluster, useStrongBreak)

	local useBudgetLightVfx = not BreakBudget.useFullVfx()

	local function runPhysics()
		local sessionCluster = frozenClusters[part] or cluster
		if not part.Parent then
			releaseClusterState(part, sessionCluster)
			return
		end
		releaseClusterPhysics(part, sessionCluster, impactPoint, hitter, useStrongBreak, isPrimaryHit, useBudgetLightVfx)
		scheduleFadeAndCleanup(part, useLightBreak)
	end

	if physicsDelay > 0 then
		task.delay(physicsDelay, runPhysics)
	else
		runPhysics()
	end

	return true
end

function BreakService.breakFromFall(part: BasePart, contactPoint: Vector3?)
	breakPartInternal(part, contactPoint, 0, nil, false, false)
end

local function breakPart(player: Player, part: BasePart): boolean
	if not BreakableUtil.isInBreakRange(player, part) then
		return false
	end

	if not BreakableUtil.isBreakable(part) or BreakableUtil.isPartBrokenState(part) then
		return false
	end

	local impactPoint = part.Position
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			impactPoint = root.Position
		end
	end

	if not breakPartInternal(part, impactPoint, 0, player, true, true) then
		return false
	end

	task.spawn(function()
		local directCluster = resolveBreakCluster(part, true)
		local directClusterSet: { [BasePart]: boolean } = {}
		for _, clusterPart in directCluster do
			directClusterSet[clusterPart] = true
		end

		local nearbyParts = gatherNearbyBreakables(part)
		for index, nearbyPart in nearbyParts do
			if directClusterSet[nearbyPart] then
				continue
			end

			local stagger = randomInRange(0, GameConfig.ChainBreakStaggerMax) * index
			breakPartInternal(nearbyPart, part.Position, stagger, player, true, false)
		end
	end)

	return true
end

breakPartRemote.OnServerInvoke = function(player: Player, part: unknown): boolean
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	return breakPart(player, part)
end

return BreakService
