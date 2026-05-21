local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BreakSound = require(script.Parent.BreakSound)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local breakPartRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BreakPart") :: RemoteFunction
local aimState = require(script.Parent.CrosshairHighlight)

local hammerNames: { [string]: boolean } = {}
for _, name in GameConfig.HammerToolNames do
	hammerNames[name] = true
end

local hookedTools: { [Tool]: boolean } = {}
local animatingTools: { [Tool]: boolean } = {}
local lastBreakTime = 0

local SWING_DOWN = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWING_UP = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BREAK_COOLDOWN = 0.05

local function isHammer(tool: Instance): boolean
	return tool:IsA("Tool") and hammerNames[tool.Name] == true
end

local function tryBreakTarget(tool: Tool): boolean
	if os.clock() - lastBreakTime < BREAK_COOLDOWN then
		return false
	end

	local target = aimState.target
	if not target or not aimState.inRange then
		return false
	end

	if target:GetAttribute("Broken")
		or target:GetAttribute("HiddenForRespawn")
		or target:GetAttribute("TreeForming")
	then
		return false
	end

	lastBreakTime = os.clock()

	local ok = breakPartRemote:InvokeServer(target) == true
	if ok then
		BreakSound.play(tool)
	end

	return ok
end

local function playSwingAnimation(tool: Tool)
	if animatingTools[tool] then
		return
	end
	animatingTools[tool] = true

	local restGrip = tool.Grip
	local hitGrip = restGrip * CFrame.Angles(math.rad(-65), math.rad(6), 0)

	local down = TweenService:Create(tool, SWING_DOWN, { Grip = hitGrip })
	local up = TweenService:Create(tool, SWING_UP, { Grip = restGrip })

	down:Play()
	down.Completed:Once(function()
		up:Play()
	end)
	up.Completed:Once(function()
		animatingTools[tool] = nil
	end)
end

local function hookTool(tool: Tool)
	if not isHammer(tool) or hookedTools[tool] then
		return
	end
	hookedTools[tool] = true

	tool.Activated:Connect(function()
		tryBreakTarget(tool)
		task.spawn(playSwingAnimation, tool)
	end)

	tool.Destroying:Connect(function()
		hookedTools[tool] = nil
		animatingTools[tool] = nil
	end)
end

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			hookTool(child)
		end
	end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
end

watchContainer(player:WaitForChild("Backpack"))

local function onCharacter(character: Model)
	watchContainer(character)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

return nil
