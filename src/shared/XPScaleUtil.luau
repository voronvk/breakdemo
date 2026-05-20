local GameConfig = require(script.Parent.GameConfig)

local XPScaleUtil = {}

function XPScaleUtil.stampBaseSizes(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("XPBaseSize", descendant.Size)
		end
	end
end

function XPScaleUtil.clearModelScaleFactor(model: Model)
	pcall(function()
		model:ScaleTo(1)
	end)
end

function XPScaleUtil.applyPartScale(model: Model, scale: number)
	scale = math.clamp(scale, GameConfig.XPMinScale, 1)

	XPScaleUtil.clearModelScaleFactor(model)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local baseSize = descendant:GetAttribute("XPBaseSize")
			if typeof(baseSize) == "Vector3" then
				descendant.Size = baseSize * scale
			end
		end
	end
end

function XPScaleUtil.resetPartScale(model: Model)
	XPScaleUtil.applyPartScale(model, 1)
end

return XPScaleUtil
