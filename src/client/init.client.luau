local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

require(script.FirstPerson)
require(script.BreakRebuildSound)
require(script.BreakRespawnVFX)
require(script.CrosshairHighlight)
require(script.BreakVFX)
require(script.BreakCashLabel)
require(script.HammerSwing)

if GameConfig.XPEnabled then
	require(script.XPPickup)
end
