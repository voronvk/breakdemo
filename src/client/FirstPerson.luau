local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local function applyCameraDefaults()
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 128

	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

applyCameraDefaults()
player.CharacterAdded:Connect(applyCameraDefaults)

return nil
