local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local BreakCollision = require(ReplicatedStorage.Shared.BreakCollision)

BreakCollision.init()
BreakCollision.setupPlayers()

require(script.BreakRespawnService)
require(script.BreakService)
require(script.FallBreak)

if GameConfig.XPEnabled then
	require(script.XPService)
end
