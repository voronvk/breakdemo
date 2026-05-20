local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local xpSoundTemplate = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Xp") :: Sound

local lastPlayTime = -math.huge

local XPSound = {}

function XPSound.play()
	local now = os.clock()
	if now - lastPlayTime < GameConfig.XPPickupSoundCooldown then
		return
	end

	lastPlayTime = now

	local sound = xpSoundTemplate:Clone()
	local character = player.Character
	local parent = if character
		then character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		else nil

	sound.Parent = parent or player:WaitForChild("PlayerGui")
	sound:Play()

	Debris:AddItem(sound, math.max(sound.TimeLength, 0.5) + 0.2)
end

return XPSound
