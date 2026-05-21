local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local BreakBudget = require(script.Parent.BreakBudget)
local BreakRespawnService = require(script.Parent.BreakRespawnService)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local breakFeedbackRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BreakFeedback") :: RemoteEvent

local debrisFolder: Folder
local random = Random.new()

local BreakVFX = {}

local function randomInRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function getDebrisFolder(): Folder
	if debrisFolder and debrisFolder.Parent then
		return debrisFolder
	end

	debrisFolder = Workspace:FindFirstChild("BreakDebris") :: Folder?
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "BreakDebris"
		debrisFolder.Parent = Workspace
	end

	return debrisFolder
end

local function playBreakPop(part: BasePart, popScale: number?)
	local originalSize = part.Size
	local popSize = originalSize * (popScale or GameConfig.BreakPopScale)

	local grow = TweenService:Create(part, TweenInfo.new(GameConfig.BreakPopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = popSize,
	})
	local shrink = TweenService:Create(part, TweenInfo.new(GameConfig.BreakPopDuration * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = originalSize,
	})

	grow:Play()
	grow.Completed:Once(function()
		if part.Parent then
			shrink:Play()
		end
	end)
end

type DebrisOptions = {
	minCount: number?,
	maxCount: number?,
	horizontalSpread: boolean?,
	speedScale: number?,
}

local function spawnDebris(part: BasePart, impactPoint: Vector3?, options: DebrisOptions?)
	local minCount = options and options.minCount or GameConfig.DebrisMinCount
	local maxCount = options and options.maxCount or GameConfig.DebrisMaxCount
	local debrisCount = math.random(minCount, maxCount)
	debrisCount = BreakBudget.shouldSpawnDebris(debrisCount)

	if debrisCount <= 0 then
		return
	end

	local folder = getDebrisFolder()
	local chunkScale = math.min(part.Size.X, part.Size.Y, part.Size.Z)
	local horizontalSpread = options and options.horizontalSpread == true
	local speedScale = if options and options.speedScale then options.speedScale else 1

	for _ = 1, debrisCount do
		local debris = Instance.new("Part")
		debris.Name = "BreakDebris"
		debris.Material = part.Material
		debris.Color = part.Color:Lerp(Color3.fromRGB(90, 90, 90), random:NextNumber(0, 0.35))
		debris.Size = Vector3.new(
			randomInRange(0.12, 0.35),
			randomInRange(0.12, 0.35),
			randomInRange(0.12, 0.35)
		) * math.max(chunkScale * 0.45, 0.35)
		debris.Size = Vector3.new(
			math.clamp(debris.Size.X, 0.12, 1.4),
			math.clamp(debris.Size.Y, 0.12, 1.4),
			math.clamp(debris.Size.Z, 0.12, 1.4)
		)
		debris.CFrame = part.CFrame * CFrame.new(
			randomInRange(-0.5, 0.5),
			randomInRange(-0.5, 0.5),
			randomInRange(-0.5, 0.5)
		)
		debris.Anchored = false
		debris.CanCollide = true
		debris.CanTouch = false
		debris.CanQuery = false
		debris.Parent = folder

		local direction: Vector3
		if horizontalSpread then
			direction = Vector3.new(randomInRange(-1.4, 1.4), randomInRange(0.05, 0.45), randomInRange(-1.4, 1.4))
		else
			direction = Vector3.new(randomInRange(-1, 1), randomInRange(0.35, 1.2), randomInRange(-1, 1))
		end

		if impactPoint then
			local away = debris.Position - impactPoint
			if away.Magnitude > 0.05 then
				local push = if horizontalSpread then away.Unit * randomInRange(1, 2.5) else away.Unit * randomInRange(0.8, 2)
				direction += push
			end
		end

		local speed = randomInRange(GameConfig.DebrisSpeedMin, GameConfig.DebrisSpeedMax) * speedScale
		debris.AssemblyLinearVelocity = direction.Unit * speed
		debris.AssemblyAngularVelocity = Vector3.new(
			randomInRange(-12, 12),
			randomInRange(-12, 12),
			randomInRange(-12, 12)
		)

		Debris:AddItem(debris, GameConfig.DebrisLifetime + random:NextNumber(0, 0.6))
	end
end

local function spawnParticleBurst(part: BasePart, scale: number)
	if scale <= 0 then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "BreakParticleAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.05
	anchor.CFrame = part.CFrame
	anchor.Parent = getDebrisFolder()

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "BreakDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.25, 0.55)
	dust.Speed = NumberRange.new(6, 14)
	dust.SpreadAngle = Vector2.new(55, 55)
	dust.Drag = 2
	dust.RotSpeed = NumberRange.new(-120, 120)
	dust.Color = ColorSequence.new(part.Color, part.Color:Lerp(Color3.fromRGB(180, 180, 180), 0.5))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.clamp(part.Size.Magnitude * 0.12, 0.25, 1.2)),
		NumberSequenceKeypoint.new(1, 0),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment

	local chips = Instance.new("ParticleEmitter")
	chips.Name = "BreakChips"
	chips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chips.Rate = 0
	chips.Lifetime = NumberRange.new(0.15, 0.35)
	chips.Speed = NumberRange.new(8, 18)
	chips.SpreadAngle = Vector2.new(70, 70)
	chips.Color = ColorSequence.new(part.Color:Lerp(Color3.new(1, 1, 1), 0.25))
	chips.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	chips.Parent = attachment

	local dustEmit = math.floor(math.random(GameConfig.ParticleBurstMin, GameConfig.ParticleBurstMax) * scale)
	local chipEmit = math.floor(math.random(6, 12) * scale)
	dust:Emit(math.max(dustEmit, 1))
	chips:Emit(math.max(chipEmit, 1))

	Debris:AddItem(anchor, 1.2)
end

local function fireClientFeedback(part: BasePart, impactPoint: Vector3?, hitter: Player?, isDirectHit: boolean)
	if not BreakBudget.useFullVfx() then
		return
	end

	breakFeedbackRemote:FireAllClients({
		position = if impactPoint then impactPoint else part.Position,
		color = part.Color,
		size = part.Size,
		hitterId = if hitter then hitter.UserId else nil,
		isDirectHit = isDirectHit,
	})
end

function BreakVFX.play(part: BasePart, impactPoint: Vector3?, hitter: Player?, isDirectHit: boolean)
	playBreakPop(part)
	spawnDebris(part, impactPoint, nil)

	local particleScale = if BreakBudget.useFullVfx() then 1 else 0.5
	spawnParticleBurst(part, particleScale)

	fireClientFeedback(part, impactPoint, hitter, isDirectHit)
end

function BreakVFX.playDirect(part: BasePart, impactPoint: Vector3?, hitter: Player?, isPrimaryHit: boolean?)
	playBreakPop(part, GameConfig.DirectBreakPopScale)
	spawnDebris(part, impactPoint, {
		minCount = GameConfig.DebrisMinCount,
		maxCount = GameConfig.DebrisMaxCount,
		speedScale = GameConfig.DirectDebrisSpeedScale,
	})

	local particleScale = (if BreakBudget.useFullVfx() then 1 else 0.55) * GameConfig.DirectParticleScale
	spawnParticleBurst(part, particleScale)

	fireClientFeedback(part, impactPoint, hitter, isPrimaryHit == true)
end

function BreakVFX.playLight(part: BasePart, impactPoint: Vector3?)
	spawnDebris(part, impactPoint, {
		minCount = 1,
		maxCount = 2,
		speedScale = 0.65,
	})
end

function BreakVFX.playChain(part: BasePart, impactPoint: Vector3?, hitter: Player?)
	playBreakPop(part)
	spawnDebris(part, impactPoint, {
		minCount = GameConfig.DebrisMinCount,
		maxCount = math.max(4, math.floor(GameConfig.DebrisMaxCount * 0.6)),
		speedScale = 0.9,
	})

	local particleScale = if BreakBudget.useFullVfx() then 0.9 else 0.55
	spawnParticleBurst(part, particleScale)
	fireClientFeedback(part, impactPoint, hitter, false)
end

function BreakVFX.playChainBurst(part: BasePart, explosionCenter: Vector3?, hitter: Player?)
	playBreakPop(part, GameConfig.ChainBreakPopScale)
	spawnDebris(part, explosionCenter, {
		minCount = math.max(3, math.floor(GameConfig.DebrisMinCount * 0.85)),
		maxCount = math.max(5, math.floor(GameConfig.DebrisMaxCount * 0.75)),
		speedScale = GameConfig.ChainDebrisSpeedScale,
	})

	local particleScale = (if BreakBudget.useFullVfx() then 0.95 else 0.6) * GameConfig.ChainParticleScale
	spawnParticleBurst(part, particleScale)
	fireClientFeedback(part, explosionCenter, hitter, false)
end

function BreakVFX.playGroundShatter(part: BasePart, contactPoint: Vector3)
	local useFull = BreakBudget.useFullVfx()
	spawnDebris(part, contactPoint, {
		minCount = if useFull then GameConfig.GroundShatterDebrisMin else 3,
		maxCount = if useFull then GameConfig.GroundShatterDebrisMax else 5,
		horizontalSpread = true,
		speedScale = 0.75,
	})
	spawnParticleBurst(part, if useFull then 0.7 else 0.35)

	fireClientFeedback(part, contactPoint, nil, false)
end

function BreakVFX.quickFadePart(part: BasePart)
	if BreakableUtil.getTreeRoot(part) then
		return
	end

	local cluster = BreakableUtil.getBreakCluster(part)
	local visibleCluster: { BasePart } = {}

	for _, clusterPart in cluster do
		if clusterPart.Parent and not clusterPart:GetAttribute("HiddenForRespawn") then
			table.insert(visibleCluster, clusterPart)
		end
	end

	if #visibleCluster == 0 then
		return
	end

	for _, clusterPart in visibleCluster do
		if not BreakRespawnService.hasSnapshot(clusterPart) then
			BreakRespawnService.registerBrokenPart(clusterPart, BreakRespawnService.captureSnapshot(clusterPart))
		end
	end

	BreakRespawnService.fadeAndHideCluster(visibleCluster, GameConfig.GroundShatterFadeDuration)
end

return BreakVFX
