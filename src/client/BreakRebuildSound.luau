local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local buildSoundTemplate = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Build") :: Sound

local loopSound: Sound? = nil
local isLoopPlaying = false

local BreakRebuildSound = {}

local function getSoundParent(): Instance
	local character = player.Character
	if character then
		local head = character:FindFirstChild("Head")
		if head then
			return head
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			return root
		end
	end

	return player:WaitForChild("PlayerGui")
end

function BreakRebuildSound.startLoop()
	if isLoopPlaying then
		return
	end

	local sound = buildSoundTemplate:Clone()
	sound.Looped = true
	sound.Parent = getSoundParent()
	sound:Play()
	loopSound = sound
	isLoopPlaying = true
end

function BreakRebuildSound.stopLoop()
	if not isLoopPlaying then
		return
	end

	if loopSound then
		loopSound:Stop()
		loopSound:Destroy()
		loopSound = nil
	end

	isLoopPlaying = false
end

local function shouldPlayBuildLoop(): boolean
	if ReplicatedStorage:GetAttribute("RespawnWaveInProgress") == true then
		return true
	end

	if ReplicatedStorage:GetAttribute("MapRestoring") == true then
		return true
	end

	local nextRespawnTime = ReplicatedStorage:GetAttribute("NextRespawnTime")
	if typeof(nextRespawnTime) ~= "number" then
		return false
	end

	return nextRespawnTime - workspace:GetServerTimeNow() <= 0
end

local function syncBuildLoop()
	if shouldPlayBuildLoop() then
		BreakRebuildSound.startLoop()
	else
		BreakRebuildSound.stopLoop()
	end
end

ReplicatedStorage:GetAttributeChangedSignal("NextRespawnTime"):Connect(syncBuildLoop)
ReplicatedStorage:GetAttributeChangedSignal("RespawnWaveInProgress"):Connect(syncBuildLoop)
ReplicatedStorage:GetAttributeChangedSignal("MapRestoring"):Connect(syncBuildLoop)

RunService.RenderStepped:Connect(syncBuildLoop)

task.defer(syncBuildLoop)

return BreakRebuildSound
