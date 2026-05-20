local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local XPScaleUtil = require(ReplicatedStorage.Shared.XPScaleUtil)

local xpCollectedRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("XPCollected") :: RemoteEvent

local XPPickup = {}

type OrbState = "falling" | "idle" | "attracting" | "collected"

type OrbEntry = {
	model: Model,
	state: OrbState,
	groundPosition: Vector3,
	originCFrame: CFrame,
	pickupReadyAt: number,
	bobPhase: number,
	fallStartPosition: Vector3?,
	fallControlPoint: Vector3?,
	fallStartTime: number?,
}

local activeFolder: Folder? = nil
local orbsByModel: { [Model]: OrbEntry } = {}

local function randomInRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function prepareModel(model: Model)
	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			model.PrimaryPart = firstPart
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function quadraticBezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local oneMinusT = 1 - t
	return oneMinusT * oneMinusT * p0 + 2 * oneMinusT * t * p1 + t * t * p2
end

local function buildFallControlPoint(startPosition: Vector3, groundPosition: Vector3): Vector3
	local mid = startPosition:Lerp(groundPosition, 0.38)
	local drop = startPosition.Y - groundPosition.Y
	local lateral = (math.random() - 0.5) * 2 * GameConfig.XPFallHorizontalDrift * GameConfig.XPFallArcStrength

	return Vector3.new(
		mid.X + lateral,
		startPosition.Y - drop * 0.22,
		mid.Z + (math.random() - 0.5) * GameConfig.XPFallHorizontalDrift * GameConfig.XPFallArcStrength
	)
end

local function computeFallPosition(startPosition: Vector3, groundPosition: Vector3, controlPoint: Vector3, t: number): Vector3
	local dropPhaseEnd = 0.84

	if t <= dropPhaseEnd then
		local u = t / dropPhaseEnd
		local pathT = u * u * u
		return quadraticBezier(startPosition, controlPoint, groundPosition, pathT)
	end

	local bounceT = (t - dropPhaseEnd) / (1 - dropPhaseEnd)
	local hop = math.sin(bounceT * math.pi) * GameConfig.XPFallBounceHeight * (1 - bounceT * 0.5)
	return groundPosition + Vector3.new(0, hop, 0)
end

local function getPickupTarget(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
		or character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("Torso") :: BasePart?
end

local function getTargetPosition(targetPart: BasePart): Vector3
	return targetPart.Position + Vector3.new(0, 0.6, 0)
end

local function unregisterOrb(model: Model)
	orbsByModel[model] = nil
end

local function collectOrb(entry: OrbEntry, player: Player)
	if entry.state == "collected" then
		return
	end

	entry.state = "collected"
	local model = entry.model

	if model.Parent and model:GetAttribute("XPActive") == true then
		model:SetAttribute("XPActive", false)
		xpCollectedRemote:FireClient(player)
	end

	unregisterOrb(model)
end

local function updateFalling(entry: OrbEntry, now: number): boolean
	if entry.state ~= "falling" or not entry.fallStartTime or not entry.fallStartPosition then
		return false
	end

	local elapsed = now - entry.fallStartTime
	local t = math.clamp(elapsed / GameConfig.XPFallDuration, 0, 1)
	local position = computeFallPosition(
		entry.fallStartPosition,
		entry.groundPosition,
		entry.fallControlPoint :: Vector3,
		t
	)
	entry.model:PivotTo(CFrame.new(position))

	if t < 1 then
		return true
	end

	entry.model:PivotTo(CFrame.new(entry.groundPosition))
	entry.originCFrame = CFrame.new(entry.groundPosition)
	entry.state = "idle"
	entry.pickupReadyAt = os.clock() + GameConfig.XPPickupDelay
	entry.fallStartTime = nil
	entry.fallStartPosition = nil
	entry.fallControlPoint = nil
	entry.model:SetAttribute("XPActive", true)

	return true
end

local function updateIdleBob(entry: OrbEntry, now: number)
	if entry.state ~= "idle" then
		return
	end

	local bobOffset = math.sin(now * math.pi * 2 / GameConfig.XPIdleBobDuration + entry.bobPhase)
		* GameConfig.XPIdleBobHeight
	entry.model:PivotTo(entry.originCFrame * CFrame.new(0, bobOffset, 0))
end

function XPPickup.launchOrb(model: Model, fallStart: Vector3, groundPosition: Vector3)
	if not activeFolder or not model.Parent then
		return
	end

	prepareModel(model)
	XPScaleUtil.stampBaseSizes(model)
	XPScaleUtil.resetPartScale(model)

	local existing = orbsByModel[model]
	if existing then
		existing.state = "falling"
		existing.groundPosition = groundPosition
		existing.fallStartPosition = fallStart
		existing.fallControlPoint = buildFallControlPoint(fallStart, groundPosition)
		existing.fallStartTime = os.clock()
		existing.pickupReadyAt = math.huge
		model:SetAttribute("XPGroundPosition", groundPosition)
		model:SetAttribute("XPActive", false)
		model:PivotTo(CFrame.new(fallStart))
		return
	end

	local entry: OrbEntry = {
		model = model,
		state = "falling",
		groundPosition = groundPosition,
		originCFrame = CFrame.new(groundPosition),
		pickupReadyAt = math.huge,
		bobPhase = randomInRange(0, math.pi * 2),
		fallStartPosition = fallStart,
		fallControlPoint = buildFallControlPoint(fallStart, groundPosition),
		fallStartTime = os.clock(),
	}

	orbsByModel[model] = entry
	model:SetAttribute("XPGroundPosition", groundPosition)
	model:SetAttribute("XPActive", false)
	model:PivotTo(CFrame.new(fallStart))

	model.Destroying:Connect(function()
		unregisterOrb(model)
	end)
end

local function updateOrb(entry: OrbEntry, deltaTime: number, now: number)
	local model = entry.model
	if not model.Parent or model:GetAttribute("XPActive") == false and entry.state ~= "falling" then
		unregisterOrb(model)
		return
	end

	if updateFalling(entry, now) then
		return
	end

	if entry.state == "collected" or os.clock() < entry.pickupReadyAt then
		if entry.state == "idle" then
			updateIdleBob(entry, now)
		end
		return
	end

	local orbPosition = model:GetPivot().Position
	local closestPlayer: Player? = nil
	local closestTarget: Vector3? = nil
	local closestDistance = math.huge

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local targetPart = getPickupTarget(character)
		if not targetPart then
			continue
		end

		local targetPosition = getTargetPosition(targetPart)
		local distance = (targetPosition - orbPosition).Magnitude
		if distance < closestDistance then
			closestDistance = distance
			closestPlayer = player
			closestTarget = targetPosition
		end
	end

	if not closestPlayer or not closestTarget then
		if entry.state == "attracting" then
			entry.state = "idle"
			entry.originCFrame = CFrame.new(entry.groundPosition)
			XPScaleUtil.resetPartScale(model)
		end
		updateIdleBob(entry, now)
		return
	end

	if entry.state == "idle" and closestDistance > GameConfig.XPAttractRadius then
		updateIdleBob(entry, now)
		return
	end

	if entry.state == "attracting" and closestDistance > GameConfig.XPAttractRadius then
		entry.state = "idle"
		entry.originCFrame = CFrame.new(entry.groundPosition)
		XPScaleUtil.resetPartScale(model)
		updateIdleBob(entry, now)
		return
	end

	if entry.state == "idle" then
		entry.state = "attracting"
	end

	if closestDistance <= GameConfig.XPPickupRadius then
		collectOrb(entry, closestPlayer)
		return
	end

	local offset = closestTarget - orbPosition
	local closeness = 1 - math.clamp(closestDistance / GameConfig.XPAttractRadius, 0, 1)
	local speed = GameConfig.XPAttractSpeedMin
		+ (GameConfig.XPAttractSpeedMax - GameConfig.XPAttractSpeedMin) * closeness
		+ GameConfig.XPAttractAccel / math.max(closestDistance, 0.35)

	local step = offset.Unit * speed * deltaTime
	if step.Magnitude > closestDistance then
		step = offset
	end

	local newPosition = orbPosition + step
	local shrink = math.clamp(1 - closeness * 0.85, GameConfig.XPMinScale, 1)
	model:PivotTo(CFrame.new(newPosition))
	XPScaleUtil.applyPartScale(model, shrink)
end

function XPPickup.init(folder: Folder)
	activeFolder = folder

	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("XPOrb") == true and child:GetAttribute("XPActive") == true then
			local groundHint = child:GetAttribute("XPGroundPosition")
			local groundPosition = if typeof(groundHint) == "Vector3"
				then groundHint
				else child:GetPivot().Position

			local entry: OrbEntry = {
				model = child,
				state = "idle",
				groundPosition = groundPosition,
				originCFrame = CFrame.new(groundPosition),
				pickupReadyAt = 0,
				bobPhase = randomInRange(0, math.pi * 2),
			}
			orbsByModel[child] = entry
			child:PivotTo(entry.originCFrame)
		end
	end

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child:GetAttribute("XPOrb") == true then
			child.Destroying:Connect(function()
				unregisterOrb(child)
			end)
		end
	end)
end

RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()
	for model, entry in orbsByModel do
		if model.Parent then
			updateOrb(entry, deltaTime, now)
		else
			orbsByModel[model] = nil
		end
	end
end)

return XPPickup
