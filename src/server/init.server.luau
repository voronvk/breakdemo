local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

require(script.BreakRespawnService)
require(script.BreakService)
require(script.FallBreak)

if GameConfig.XPEnabled then
	require(script.XPService)
end
