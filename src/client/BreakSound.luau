local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local breakSoundTemplate = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Break") :: Sound

local BreakSound = {}

function BreakSound.play(tool: Tool?)
	local sound = breakSoundTemplate:Clone()

	local parent: Instance? = nil
	if tool then
		parent = tool:FindFirstChild("Handle")
	end

	local character = player.Character
	if not parent and character then
		parent = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	end

	sound.Parent = parent or player:WaitForChild("PlayerGui")
	sound:Play()

	Debris:AddItem(sound, math.max(sound.TimeLength, 0.5) + 0.2)
end

return BreakSound
