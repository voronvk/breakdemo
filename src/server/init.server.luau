local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local BreakCollision = require(ReplicatedStorage.Shared.BreakCollision)

BreakCollision.init()
BreakCollision.setupPlayers()

require(script.BreakRespawnService)
local CloneMapService = require(script.CloneMapService)
CloneMapService.init()
require(script.BreakService)
require(script.FallBreak)
require(script.DragBreak)

if GameConfig.XPEnabled then
	require(script.XPService)
end
