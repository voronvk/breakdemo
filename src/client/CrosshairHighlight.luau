local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BreakableUtil = require(ReplicatedStorage.Shared.BreakableUtil)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local highlight = Instance.new("Highlight")
highlight.Name = "CrosshairTargetHighlight"
highlight.FillTransparency = 1
highlight.OutlineTransparency = 0
highlight.Enabled = false
highlight.Parent = player:WaitForChild("PlayerGui")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local aimState = {
	target = nil :: BasePart?,
	inRange = false,
}

local function getPartFromHit(hit: Instance): BasePart?
	if hit:IsA("BasePart") then
		return hit
	end
	return hit:FindFirstAncestorWhichIsA("BasePart")
end

local function getMouseTarget(): BasePart?
	if not camera then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	rayParams.FilterDescendantsInstances = { character }

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	if not result then
		return nil
	end

	local part = getPartFromHit(result.Instance)
	if not part or not BreakableUtil.isBreakable(part) or BreakableUtil.isPartBrokenState(part) then
		return nil
	end

	if not BreakableUtil.isInBreakRange(player, part) then
		return nil
	end

	return part
end

local function updateHighlight(part: BasePart?)
	aimState.target = part
	aimState.inRange = part ~= nil

	if not part then
		highlight.Enabled = false
		highlight.Adornee = nil
		return
	end

	highlight.Adornee = part
	highlight.Enabled = true
	highlight.OutlineColor = GameConfig.HighlightHoverColor
end

RunService.RenderStepped:Connect(function()
	camera = workspace.CurrentCamera
	if not camera then
		updateHighlight(nil)
		return
	end

	updateHighlight(getMouseTarget())
end)

return aimState
