local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local XPGroundUtil = require(ReplicatedStorage.Shared.XPGroundUtil)
local XPScaleUtil = require(ReplicatedStorage.Shared.XPScaleUtil)

local XPService = {}

if not GameConfig.XPEnabled then
	function XPService.trySpawnFromBreak(_part: BasePart, _impactPoint: Vector3?) end
	return XPService
end

local XPPickup = require(script.Parent.XPPickup)

local xpTemplate: Model?
local poolFolder: Folder
local activeFolder: Folder
local availableOrbs: { Model } = {}
local boundOrbs: { [Model]: boolean } = {}

local random = Random.new()

local function randomInRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function resetOrbScale(model: Model)
	XPScaleUtil.resetPartScale(model)
end

local function findXpTemplate(experienceFolder: Instance): Model?
	local preferred = experienceFolder:FindFirstChild(GameConfig.XPTemplateName)
	if preferred and preferred:IsA("Model") then
		return preferred
	end

	for _, child in experienceFolder:GetChildren() do
		if child:IsA("Model") and string.lower(child.Name) == string.lower(GameConfig.XPTemplateName) then
			return child
		end
	end

	return nil
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getActiveOrbCount(): number
	local count = 0
	for _, child in activeFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("XPActive") == true then
			count += 1
		end
	end
	return count
end

local function buildRaycastIgnore(brokenPart: BasePart, orbModel: Model?): { Instance }
	local ignore: { Instance } = { activeFolder, poolFolder, brokenPart }

	if orbModel then
		table.insert(ignore, orbModel)
	end

	local brokenRoot = brokenPart:FindFirstAncestorWhichIsA("Model")
	if brokenRoot then
		table.insert(ignore, brokenRoot)
	end

	local debris = Workspace:FindFirstChild("BreakDebris")
	if debris then
		table.insert(ignore, debris)
	end

	return ignore
end

local function findGroundPosition(brokenPart: BasePart, horizontalOrigin: Vector3, model: Model): Vector3
	local partBottomY = brokenPart.Position.Y - brokenPart.Size.Y * 0.5
	local ignore = buildRaycastIgnore(brokenPart, model)
	local pivotPosition = XPGroundUtil.snapModelToGround(model, horizontalOrigin, ignore, partBottomY)
	return pivotPosition + Vector3.new(0, GameConfig.XPSpawnHeightOffset, 0)
end

local function getHorizontalSpawnOrigin(brokenPart: BasePart, impactPoint: Vector3?): Vector3
	if impactPoint then
		return Vector3.new(impactPoint.X, brokenPart.Position.Y - brokenPart.Size.Y * 0.5, impactPoint.Z)
	end

	return Vector3.new(
		brokenPart.Position.X,
		brokenPart.Position.Y - brokenPart.Size.Y * 0.5,
		brokenPart.Position.Z
	)
end

local function getOrbCountForPart(part: BasePart): number
	if GameConfig.XPOrbsPerBreakMax <= 0 then
		return 0
	end

	local volume = part.Size.X * part.Size.Y * part.Size.Z
	local scale = math.clamp(volume / GameConfig.XPBreakVolumeReference, 0.25, 1)
	local minCount = math.max(1, GameConfig.XPOrbsPerBreakMin)
	local scaledMax = math.floor(minCount + (GameConfig.XPOrbsPerBreakMax - minCount) * scale + 0.5)
	scaledMax = math.clamp(scaledMax, minCount, GameConfig.XPOrbsPerBreakMax)
	return math.random(minCount, scaledMax)
end

local function addToAvailable(model: Model)
	if table.find(availableOrbs, model) then
		return
	end
	table.insert(availableOrbs, model)
end

local function removeFromAvailable(model: Model)
	local index = table.find(availableOrbs, model)
	if index then
		table.remove(availableOrbs, index)
	end
end

local function ensureBaseSizes(model: Model)
	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart and typeof(firstPart:GetAttribute("XPBaseSize")) ~= "Vector3" then
		XPScaleUtil.stampBaseSizes(model)
	end
end

local function bindOrb(model: Model)
	if boundOrbs[model] then
		return
	end
	boundOrbs[model] = true

	ensureBaseSizes(model)
	model:SetAttribute("XPOrb", true)
	model:SetAttribute("XPActive", false)
	resetOrbScale(model)

	model:GetAttributeChangedSignal("XPActive"):Connect(function()
		if model:GetAttribute("XPActive") then
			removeFromAvailable(model)
			if model.Parent ~= activeFolder then
				model.Parent = activeFolder
			end
		else
			resetOrbScale(model)
			if model.Parent ~= poolFolder then
				model.Parent = poolFolder
			end
			addToAvailable(model)
		end
	end)
end

local function createOrbModel(): Model?
	if not xpTemplate then
		return nil
	end

	if #availableOrbs + getActiveOrbCount() >= GameConfig.XPMaxPoolOrbs then
		return nil
	end

	local clone = xpTemplate:Clone()
	clone.Name = GameConfig.XPTemplateName

	if not clone.PrimaryPart then
		local firstPart = clone:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			clone.PrimaryPart = firstPart
		end
	end

	XPScaleUtil.stampBaseSizes(clone)
	XPScaleUtil.resetPartScale(clone)
	clone.Parent = poolFolder
	bindOrb(clone)
	addToAvailable(clone)
	return clone
end

local function acquireOrb(): Model?
	while #availableOrbs > 0 do
		local model = table.remove(availableOrbs, 1) :: Model
		if model.Parent then
			resetOrbScale(model)
			return model
		end
	end

	return createOrbModel()
end

local function placeOrb(model: Model, brokenPart: BasePart, impactPoint: Vector3?)
	resetOrbScale(model)

	local spread = GameConfig.XPSpawnSpreadRadius
	local horizontalOrigin = getHorizontalSpawnOrigin(brokenPart, impactPoint)
	local offset = Vector3.new(randomInRange(-spread, spread), 0, randomInRange(-spread, spread))
	local groundPosition = findGroundPosition(brokenPart, horizontalOrigin + offset, model)

	local drift = Vector3.new(
		randomInRange(-GameConfig.XPFallHorizontalDrift, GameConfig.XPFallHorizontalDrift),
		0,
		randomInRange(-GameConfig.XPFallHorizontalDrift, GameConfig.XPFallHorizontalDrift)
	)
	local fallHeight = randomInRange(GameConfig.XPFallStartHeightMin, GameConfig.XPFallStartHeightMax)
	local fallStart = Vector3.new(
		groundPosition.X + drift.X,
		math.max(brokenPart.Position.Y + 0.5, groundPosition.Y) + fallHeight,
		groundPosition.Z + drift.Z
	)

	model.Parent = activeFolder
	XPPickup.launchOrb(model, fallStart, groundPosition)
end

function XPService.trySpawnFromBreak(part: BasePart, impactPoint: Vector3?)
	if not xpTemplate or getActiveOrbCount() >= GameConfig.XPMaxActiveOrbs then
		return
	end

	local orbCount = getOrbCountForPart(part)

	for _ = 1, orbCount do
		if getActiveOrbCount() >= GameConfig.XPMaxActiveOrbs then
			break
		end

		local orb = acquireOrb()
		if not orb then
			break
		end

		placeOrb(orb, part, impactPoint)
	end
end

local function warmPool()
	for _ = 1, GameConfig.XPInitialPoolSize do
		if #availableOrbs + getActiveOrbCount() >= GameConfig.XPMaxPoolOrbs then
			break
		end
		createOrbModel()
	end
end

local function initPool()
	local experienceFolder = ReplicatedStorage:WaitForChild(GameConfig.XPExperienceFolderName, 30)
	if not experienceFolder then
		warn(`[XPService] No se encontró ReplicatedStorage.{GameConfig.XPExperienceFolderName}`)
		return
	end

	xpTemplate = findXpTemplate(experienceFolder)
	if not xpTemplate then
		warn(`[XPService] No se encontró el modelo {GameConfig.XPTemplateName} en ReplicatedStorage.{GameConfig.XPExperienceFolderName}`)
		return
	end

	poolFolder = getOrCreateFolder(ServerStorage, GameConfig.XPPoolFolderName)
	activeFolder = getOrCreateFolder(Workspace, GameConfig.XPActiveFolderName)

	for _, child in activeFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("XPOrb") then
			bindOrb(child)
		end
	end

	for _, child in poolFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("XPOrb") then
			bindOrb(child)
		elseif child:IsA("Model") then
			bindOrb(child)
		end
	end

	warmPool()
	XPPickup.init(activeFolder)
end

task.spawn(initPool)

return XPService
