local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local contador = script.Parent

local label: TextLabel
if contador:IsA("TextLabel") then
	label = contador
else
	local found = contador:FindFirstChildWhichIsA("TextLabel", true)
	if not found then
		warn("[RespawnCounter] StarterGui.ScreenGui.Contador debe ser un TextLabel o contener uno")
		return
	end
	label = found
end

local function formatRespawnText(remainingSeconds: number): string
	local totalSeconds = math.max(0, math.ceil(remainingSeconds))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%02d:%02ds until Respawn", minutes, seconds)
end

RunService.RenderStepped:Connect(function()
	local nextRespawnTime = ReplicatedStorage:GetAttribute("NextRespawnTime")
	if typeof(nextRespawnTime) ~= "number" then
		label.Text = ""
		return
	end

	local remaining = nextRespawnTime - workspace:GetServerTimeNow()
	if remaining <= 0 then
		label.Text = "00:00s until Respawn"
		return
	end

	label.Text = formatRespawnText(remaining)
end)

return nil
