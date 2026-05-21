local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local FallTracker = {}

export type ImpactHandler = (part: BasePart, contactPoint: Vector3, hitPart: BasePart) -> ()

type Entry = {
	peakY: number,
	lastTouch: number,
	done: boolean,
	minHeight: number,
	minSpeed: number,
	onImpact: ImpactHandler,
}

local entries: { [BasePart]: Entry } = {}
local heartbeatConn: RBXScriptConnection? = nil
local debrisFolderName = "BreakDebris"

local function disconnectHeartbeat()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function ensureHeartbeat()
	if heartbeatConn then
		return
	end

	heartbeatConn = RunService.Heartbeat:Connect(function()
		for part, entry in entries do
			if entry.done or not part.Parent then
				entries[part] = nil
			else
				entry.peakY = math.max(entry.peakY, part.Position.Y)
			end
		end

		if next(entries) == nil then
			disconnectHeartbeat()
		end
	end)
end

local function isFloorHit(hit: Instance, fallingPart: BasePart): boolean
	if not hit:IsA("BasePart") then
		return false
	end

	if hit == fallingPart then
		return false
	end

	if hit.AssemblyRootPart == fallingPart.AssemblyRootPart then
		return false
	end

	if hit.Name == "BreakDebris" then
		return false
	end

	local parent = hit.Parent
	if parent and parent.Name == debrisFolderName then
		return false
	end

	if hit:GetAttribute("Broken") then
		return false
	end

	return hit.CanCollide
end

function FallTracker.isWatching(part: BasePart?): boolean
	if not part then
		return false
	end

	local entry = entries[part]
	return entry ~= nil and not entry.done
end

function FallTracker.unwatch(part: BasePart?)
	if not part then
		return
	end

	entries[part] = nil
	if next(entries) == nil then
		disconnectHeartbeat()
	end
end

function FallTracker.clearAll()
	table.clear(entries)
	disconnectHeartbeat()
end

local function connectTouchWatch(
	anchorPart: BasePart,
	touchPart: BasePart,
	entry: Entry,
	onImpact: ImpactHandler
)
	touchPart.Touched:Connect(function(hit)
		if entry.done or not anchorPart.Parent then
			return
		end

		if os.clock() - entry.lastTouch < 0.15 then
			return
		end

		if not isFloorHit(hit, anchorPart) then
			return
		end

		local velocity = anchorPart.AssemblyLinearVelocity
		local fallDistance = entry.peakY - anchorPart.Position.Y
		local fallingFast = velocity.Y <= -entry.minSpeed
		local fellEnough = fallDistance >= entry.minHeight

		if not fallingFast and not fellEnough then
			return
		end

		entry.done = true
		entry.lastTouch = os.clock()
		FallTracker.unwatch(anchorPart)

		local contactPoint = touchPart.Position - Vector3.yAxis * (touchPart.Size.Y * 0.5)
		onImpact(anchorPart, contactPoint, hit)
	end)
end

function FallTracker.watch(
	part: BasePart,
	onImpact: ImpactHandler,
	options: {
		minHeight: number?,
		minSpeed: number?,
		touchParts: { BasePart }?,
	}?
)
	if FallTracker.isWatching(part) then
		return
	end

	local entry: Entry = {
		peakY = part.Position.Y,
		lastTouch = 0,
		done = false,
		minHeight = if options and options.minHeight then options.minHeight else GameConfig.FallShatterMinHeight,
		minSpeed = if options and options.minSpeed then options.minSpeed else GameConfig.FallShatterMinSpeed,
		onImpact = onImpact,
	}
	entries[part] = entry
	ensureHeartbeat()

	local touchParts = if options and options.touchParts then options.touchParts else { part }
	for _, touchPart in touchParts do
		connectTouchWatch(part, touchPart, entry, onImpact)
	end

	part.Destroying:Connect(function()
		entry.done = true
		FallTracker.unwatch(part)
	end)
end

return FallTracker
