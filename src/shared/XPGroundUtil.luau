local Workspace = game:GetService("Workspace")

local XPGroundUtil = {}

local function getPivotToBottomOffset(model: Model): number
	pcall(function()
		model:ScaleTo(1)
	end)

	local pivot = model:GetPivot()
	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y * 0.5
	return math.max(0, pivot.Position.Y - bottomY)
end

local function shouldIgnoreGroundHit(instance: Instance?): boolean
	if not instance then
		return true
	end

	if not instance:IsA("BasePart") then
		return false
	end

	if instance:GetAttribute("Broken") then
		return true
	end

	if instance:GetAttribute("XPOrb") then
		return true
	end

	return false
end

function XPGroundUtil.raycastSurfaceY(
	positionXZ: Vector3,
	ignoreList: { Instance },
	referenceY: number?
): number?
	local refY = if referenceY then referenceY else positionXZ.Y
	local rayOrigin = Vector3.new(positionXZ.X, refY + 128, positionXZ.Z)
	local rayDirection = Vector3.new(0, -512, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList

	local maxAttempts = 12
	for _ = 1, maxAttempts do
		local result = Workspace:Raycast(rayOrigin, rayDirection, params)
		if not result then
			return nil
		end

		if shouldIgnoreGroundHit(result.Instance) then
			table.insert(ignoreList, result.Instance)
			rayOrigin = result.Position - Vector3.new(0, 0.05, 0)
			continue
		end

		return result.Position.Y
	end

	return nil
end

function XPGroundUtil.getPivotOnSurface(model: Model, surfaceY: number, positionXZ: Vector3): Vector3
	local pivotToBottom = getPivotToBottomOffset(model)
	return Vector3.new(positionXZ.X, surfaceY + pivotToBottom, positionXZ.Z)
end

function XPGroundUtil.snapModelToGround(
	model: Model,
	positionXZ: Vector3,
	ignoreList: { Instance },
	referenceY: number?
): Vector3
	local surfaceY = XPGroundUtil.raycastSurfaceY(positionXZ, ignoreList, referenceY)
	local fallbackY = if referenceY then referenceY else positionXZ.Y
	local groundY = if surfaceY then surfaceY else fallbackY
	return XPGroundUtil.getPivotOnSurface(model, groundY, positionXZ)
end

return XPGroundUtil
