local ReplicatedStorage = game:GetService("ReplicatedStorage")

local XPSound = require(script.Parent.XPSound)

local xpCollectedRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("XPCollected") :: RemoteEvent

xpCollectedRemote.OnClientEvent:Connect(function()
	XPSound.play()
end)

return nil
