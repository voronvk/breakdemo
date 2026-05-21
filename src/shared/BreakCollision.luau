local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local GameConfig = require(script.Parent.GameConfig)

local BreakCollision = {}

local initialized = false

local function registerCollisionGroup(name: string)
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	if not ok then
		pcall(function()
			PhysicsService:CreateCollisionGroup(name)
		end)
	end
end

function BreakCollision.init()
	if initialized then
		return
	end
	initialized = true

	local playerGroup = GameConfig.PlayerCollisionGroup
	local brokenGroup = GameConfig.BrokenBreakableCollisionGroup

	registerCollisionGroup(playerGroup)
	registerCollisionGroup(brokenGroup)

	PhysicsService:CollisionGroupSetCollidable(brokenGroup, playerGroup, false)
end

local function applyCollisionGroupToPartTree(part: BasePart, groupName: string)
	part.CollisionGroup = groupName

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

function BreakCollision.applyBrokenPart(part: BasePart)
	BreakCollision.init()
	applyCollisionGroupToPartTree(part, GameConfig.BrokenBreakableCollisionGroup)
end

function BreakCollision.applyBrokenCluster(cluster: { BasePart })
	BreakCollision.init()
	for _, clusterPart in cluster do
		BreakCollision.applyBrokenPart(clusterPart)
	end
end

function BreakCollision.restorePart(part: BasePart, collisionGroup: string?)
	part.CollisionGroup = collisionGroup or "Default"

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = part.CollisionGroup
		end
	end
end

local function applyPlayerCollisionToCharacter(character: Model)
	BreakCollision.init()

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GameConfig.PlayerCollisionGroup
		end
	end

	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GameConfig.PlayerCollisionGroup
		end
	end)
end

function BreakCollision.setupPlayers()
	BreakCollision.init()

	local function onPlayerAdded(player: Player)
		local function onCharacterAdded(character: Model)
			applyPlayerCollisionToCharacter(character)
		end

		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return BreakCollision
