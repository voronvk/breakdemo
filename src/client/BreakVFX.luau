local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local breakFeedbackRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BreakFeedback") :: RemoteEvent

local shakeOffset = Vector3.zero
local shakeTimeLeft = 0
local shakeIntensity = 0

local function randomInRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function startCameraShake(intensity: number, duration: number)
	shakeIntensity = math.max(shakeIntensity, intensity)
	shakeTimeLeft = math.max(shakeTimeLeft, duration)
end

local function spawnClientBurst(payload: { position: Vector3, color: Color3, size: Vector3 })
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.05
	anchor.CFrame = CFrame.new(payload.position)
	anchor.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local flash = Instance.new("ParticleEmitter")
	flash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flash.Rate = 0
	flash.Lifetime = NumberRange.new(0.08, 0.16)
	flash.Speed = NumberRange.new(4, 10)
	flash.SpreadAngle = Vector2.new(180, 180)
	flash.Color = ColorSequence.new(payload.color:Lerp(Color3.new(1, 1, 1), 0.4))
	flash.Size = NumberSequence.new(0.2, 0)
	flash.LightEmission = 1
	flash.Parent = attachment
	flash:Emit(math.clamp(math.floor(payload.size.Magnitude * 2), 4, 10))

	task.delay(0.35, function()
		anchor:Destroy()
	end)
end

RunService.RenderStepped:Connect(function(deltaTime)
	camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if shakeTimeLeft > 0 then
		shakeTimeLeft -= deltaTime
		local fade = math.clamp(shakeTimeLeft / GameConfig.CameraShakeDuration, 0, 1)
		shakeOffset = Vector3.new(
			randomInRange(-1, 1),
			randomInRange(-1, 1),
			randomInRange(-1, 1)
		) * GameConfig.CameraShakeIntensity * fade

		camera.CFrame = camera.CFrame * CFrame.new(shakeOffset)
	else
		shakeIntensity = 0
		shakeOffset = Vector3.zero
	end
end)

breakFeedbackRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	spawnClientBurst(payload)

	if payload.hitterId ~= player.UserId then
		return
	end

	if payload.isDirectHit then
		startCameraShake(GameConfig.DirectCameraShakeIntensity, GameConfig.DirectCameraShakeDuration)
	else
		startCameraShake(GameConfig.CameraShakeIntensity, GameConfig.CameraShakeDuration)
	end
end)

return nil
