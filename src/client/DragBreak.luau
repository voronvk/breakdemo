local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BreakSound = require(script.Parent.BreakSound)

local player = Players.LocalPlayer
local dragBreakRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DragBreak") :: RemoteEvent

local hookedDetectors: { [DragDetector]: boolean } = {}

local function resolveDragPart(dragDetector: DragDetector, clickedPart: Instance?): BasePart?
	if clickedPart and clickedPart:IsA("BasePart") then
		return clickedPart
	end

	local parent = dragDetector.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end

	if parent and parent:IsA("Model") then
		if parent.PrimaryPart then
			return parent.PrimaryPart
		end

		for _, child in parent:GetChildren() do
			if child:IsA("BasePart") then
				return child
			end
		end
	end

	return nil
end

local function requestDragBreak(part: BasePart)
	if not part:IsDescendantOf(Workspace) then
		return
	end

	dragBreakRemote:FireServer(part)
end

local function hookDragDetector(dragDetector: DragDetector)
	if hookedDetectors[dragDetector] then
		return
	end
	hookedDetectors[dragDetector] = true

	dragDetector.DragStart:Connect(function(playerWhoDragged, _, _, _, clickedPart)
		if playerWhoDragged ~= player then
			return
		end

		local targetPart = resolveDragPart(dragDetector, clickedPart)
		if targetPart then
			requestDragBreak(targetPart)
		end
	end)

	dragDetector.Destroying:Connect(function()
		hookedDetectors[dragDetector] = nil
	end)
end

local function registerDragDetector(dragDetector: DragDetector)
	hookDragDetector(dragDetector)
end

local function scanForDragDetectors(root: Instance)
	if root:IsA("DragDetector") then
		registerDragDetector(root)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("DragDetector") then
			registerDragDetector(descendant)
		end
	end
end

dragBreakRemote.OnClientEvent:Connect(function()
	BreakSound.play()
end)

scanForDragDetectors(Workspace)

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("DragDetector") then
		registerDragDetector(descendant)
	end
end)

return nil
