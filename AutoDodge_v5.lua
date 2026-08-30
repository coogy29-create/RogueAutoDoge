local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ENABLED = false
local SHOW_PATH = true

local PLAYER_MINI_RADIUS = 0.25
local PLAYER_RADIUS_MIN = 0.10
local PLAYER_RADIUS_MAX = 0.50
local PLAYER_RADIUS_STEP = 0.05

local PLAN_HORIZON = 1.50
-- Variable time resolution: very fine near the player, progressively coarser farther out.
local PLAN_TIMES = {
	0.00,
	0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35,
	0.45, 0.55, 0.65, 0.75,
	1.00, 1.25, 1.50
}
local PLAN_STEPS = #PLAN_TIMES - 1
local EXTRA_ESCAPE_STEPS = 2
local ESCAPE_DT = 0.12
local PROJECTILE_SIM_DT = 0.025

-- Hierarchical threat processing. Exact collision tests are reserved for the near future.
local IMMEDIATE_THREAT_HORIZON = 0.45
local EXACT_THREAT_HORIZON = 0.90
local FAR_FIELD_CELL_SIZE = 4.0
local FAR_FIELD_INFLUENCE = 6.0
local FAR_FIELD_RISK_WEIGHT = 11.0
local FAR_ACTIVATION_RISK = 10.0
local ESCAPE_FAR_RISK_MAX = 12.0

-- Escape trend checkpoints. The planner prefers routes whose exits stay open over time.
local ESCAPE_TREND_TIMES = {0.55, 1.00, 1.50}
local ESCAPE_TREND_DROP_PENALTY = 62
local ESCAPE_TREND_FINAL_DROP_PENALTY = 92
local ESCAPE_TREND_GROWTH_REWARD = 7
local ESCAPE_TREND_LOW_OPTION_PENALTY = 70
local FINALIST_COUNT = 10
local DENSE_FINALIST_COUNT = 7

local PLAN_INTERVAL_IDLE = 0.055
local PLAN_INTERVAL_ACTIVE = 0.035
local PLAN_INTERVAL_URGENT = 0.018

local INITIAL_DIRECTIONS = 20
local ZERO_RESTART_DIRECTIONS = 8
local ESCAPE_DIRECTIONS = 16
local BEAM_WIDTH = 38
local DENSE_BEAM_WIDTH = 32
local DENSE_THREAT_COUNT = 22
local ACTIVATION_LOOKAHEAD = 0.78
local DENSE_ACTIVATION_LOOKAHEAD = 1.05
local BROAD_PHASE_EXTRA = 3.0
local ANALYTIC_TURN_RATE = math.rad(3.0)
local ANALYTIC_SPEED_ACCEL = 140
local ANALYTIC_VERTICAL_ACCEL = 180

local MIN_PROJECTILE_SPEED = 2.0
local VELOCITY_SMOOTH = 0.58
local TURN_SMOOTH = 0.34
local SPEED_ACCEL_SMOOTH = 0.22
local VERTICAL_ACCEL_SMOOTH = 0.18
local PREDICTION_ERROR_SMOOTH = 0.18
local MAX_SPEED_ACCEL = 6500
local MAX_VERTICAL_ACCEL = 6500
local MAX_TURN_RATE = math.rad(1080)

local PROJECTILE_RADIUS_SCALE = 1.0
local BASE_ERROR_MARGIN = 0.035
local MAX_ERROR_MARGIN = 0.48
local PREDICTION_ERROR_WEIGHT = 0.55
local SPEED_MARGIN_WEIGHT = 0.00045
local TURN_MARGIN_WEIGHT = 0.018

local NETWORK_LEAD_FALLBACK = 0.055
local NETWORK_LEAD_MIN = 0.010
local NETWORK_LEAD_MAX = 0.180

local PLAYER_RESPONSE_TIME = 0.095
local PLAYER_ACTUATION_DELAY = 0.040

local PROACTIVE_CLEARANCE = 0.42
local DENSE_PROACTIVE_CLEARANCE = 0.90
local NEAR_ZONE = 2.60

-- Persistent / area hitboxes (lasers, floor zones, walls, beams).
-- These must stay dangerous even when their translational speed is ~0.
local AREA_HAZARD_MIN_LONG_AXIS = 5.0
local AREA_HAZARD_ASPECT_RATIO = 2.6
local AREA_HAZARD_BROAD_FOOTPRINT = 3.25
local AREA_HAZARD_STATIONARY_SAMPLES = 3
local AREA_HAZARD_ERROR_MARGIN = 0.10
local AREA_HAZARD_INFLUENCE = 1.35
local AREA_HAZARD_NEAR_WEIGHT = 48
local AREA_HAZARD_VELOCITY_SMOOTH = 0.46
local HITBOX_TRACK_MIN_AXIS = 2.5
local AREA_HAZARD_NAME_HINTS = {
	"laser", "beam", "field", "zone", "aoe",
	"redwhite", "pillar", "line", "wall"
}

local HIT_PENALTY = 1000000
local WALL_HIT_PENALTY = 100000000
local NEAR_RISK_WEIGHT = 18
local MOVE_COST_WEIGHT = 0.28
local TURN_COST_WEIGHT = 1.65
local SPEED_CHANGE_COST_WEIGHT = 0.20
local STOP_BONUS = 0.35
local ESCAPE_OPTION_REWARD = 20
local NO_ESCAPE_PENALTY = 2400

local BARRIER_BODY_RADIUS = 1.00
local BARRIER_NEAR_DISTANCE = 3.0
local BARRIER_NEAR_WEIGHT = 12
local BARRIER_ESCAPE_DISTANCE = 4.8
local BARRIER_STICK_DISTANCE = 1.45
local BARRIER_APPROACH_WEIGHT = 260
local BARRIER_ESCAPE_REWARD = 62
local BARRIER_STICK_PENALTY = 560
local BARRIER_RAY_DISTANCE = 14
local BARRIER_RAY_COUNT = 12
local BARRIER_CLOSE_RAY_DISTANCE = 4.0
local BARRIER_CLOSE_RAY_PENALTY = 9

local EnemyProj = nil
local EnemyAddedConnection = nil
local EnemyRemovedConnection = nil
local ProjectileData = {}

-- Core__Game/Hitboxes is tracked separately because many persistent hazards
-- are not moving projectiles and therefore used to be filtered out.
local HitboxFolder = nil
local HitboxAddedConnection = nil
local HitboxRemovedConnection = nil
local HitboxData = {}

local BarrierSet = {}
local BarrierParts = {}
local ActiveBarrierParts = nil

local Controls = nil
local ControlsDisabled = false

local CurrentMove = Vector3.zero
local CurrentPath = nil
local LastPlanTime = 0
local LastThreatCount = 0
local LastProjectileCount = 0
local LastMinClearance = math.huge
local LastImpactTime = math.huge
local LastEscapeOptions = 0
local LastPlanMs = 0
local LastMode = "IDLE"
local LastError = ""
local LastImmediateThreatCount = 0
local LastNearThreatCount = 0
local LastFarThreatCount = 0
local LastAreaThreatCount = 0
local LastFarRisk = 0
local LastEscapeTrendText = "-"

local TOTAL_PREDICTION_STEPS = PLAN_STEPS + EXTRA_ESCAPE_STEPS

local function getPredictionTime(positionIndex)
	if positionIndex <= #PLAN_TIMES then
		return PLAN_TIMES[positionIndex]
	end
	return PLAN_HORIZON
		+ (positionIndex - #PLAN_TIMES) * ESCAPE_DT
end

local function getStepStartTime(stepIndex)
	return getPredictionTime(stepIndex)
end

local function getStepEndTime(stepIndex)
	return getPredictionTime(stepIndex + 1)
end

local function getStepDt(stepIndex)
	return math.max(
		0.001,
		getStepEndTime(stepIndex) - getStepStartTime(stepIndex)
	)
end

local function getNodeTime(depth)
	if depth <= 0 then
		return 0
	end
	return getPredictionTime(depth + 1)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rotateY(v, radians)
	local c = math.cos(radians)
	local s = math.sin(radians)
	return Vector3.new(
		v.X * c - v.Z * s,
		0,
		v.X * s + v.Z * c
	)
end

local function clampUnit(v)
	local f = flat(v)
	if f.Magnitude <= 0.0001 then
		return Vector3.zero
	end
	return f.Unit
end

local function signedAngleXZ(a, b)
	local aa = clampUnit(a)
	local bb = clampUnit(b)
	if aa.Magnitude < 0.01 or bb.Magnitude < 0.01 then
		return 0
	end
	local crossY = aa:Cross(bb).Y
	local dot = math.clamp(aa:Dot(bb), -1, 1)
	return math.atan2(crossY, dot)
end

local function getCharacter()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

task.spawn(function()
	pcall(function()
		local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
		if not playerScripts then
			return
		end
		local playerModule = playerScripts:WaitForChild("PlayerModule", 10)
		if not playerModule then
			return
		end
		Controls = require(playerModule):GetControls()
	end)
end)

local function disableControls()
	if Controls and not ControlsDisabled then
		pcall(function()
			Controls:Disable()
		end)
		ControlsDisabled = true
	end
end

local function enableControls()
	if Controls and ControlsDisabled then
		pcall(function()
			Controls:Enable()
		end)
		ControlsDisabled = false
	end
end

local function getNetworkLead()
	local lead = NETWORK_LEAD_FALLBACK
	pcall(function()
		local ping = LocalPlayer:GetNetworkPing()
		if type(ping) == "number" and ping > 0 then
			lead = ping
		end
	end)
	return math.clamp(lead, NETWORK_LEAD_MIN, NETWORK_LEAD_MAX)
end

local function getProjectilePart(obj)
	if obj:IsA("BasePart") then
		return obj
	end
	if obj:IsA("Model") and obj.PrimaryPart then
		return obj.PrimaryPart
	end
	return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function getProjectileCenterOffset(obj, part)
	if obj:IsA("Model") then
		local ok, cf = pcall(function()
			local boxCf = obj:GetBoundingBox()
			return boxCf
		end)
		if ok and cf then
			return part.CFrame:PointToObjectSpace(cf.Position)
		end
	end
	return Vector3.zero
end

local function getProjectileCenter(data)
	if not data.Part or not data.Part.Parent then
		return data.LastPosition
	end
	return data.Part.CFrame:PointToWorldSpace(data.CenterOffset)
end

local function getProjectileRadius(obj, part)
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
	if obj:IsA("Model") then
		local ok, _, size = pcall(function()
			return obj:GetBoundingBox()
		end)
		if ok and size then
			radius = math.max(
				radius,
				math.max(size.X, size.Y, size.Z) * 0.5
			)
		end
	end
	return radius * PROJECTILE_RADIUS_SCALE
end


local function getObjectBox(obj, part)
	if obj and obj:IsA("Model") then
		local ok, cf, size = pcall(function()
			return obj:GetBoundingBox()
		end)
		if ok and cf and size then
			return cf, size
		end
	end

	if part and part:IsA("BasePart") then
		return part.CFrame, part.Size
	end

	return nil, nil
end

local function hasAreaHazardName(obj, part)
	local name =
		string.lower(
			tostring(obj and obj.Name or "")
			.. " "
			.. tostring(part and part.Name or "")
		)

	for _, hint in ipairs(AREA_HAZARD_NAME_HINTS) do
		if string.find(name, hint, 1, true) then
			return true
		end
	end

	return false
end

local function isGeometricAreaHazard(size)
	if not size then
		return false
	end

	local horizontalLong = math.max(size.X, size.Z)
	local horizontalShort = math.max(math.min(size.X, size.Z), 0.05)
	local elongated =
		horizontalLong >= AREA_HAZARD_MIN_LONG_AXIS
		and horizontalLong / horizontalShort >= AREA_HAZARD_ASPECT_RATIO
	local broad =
		size.X >= AREA_HAZARD_BROAD_FOOTPRINT
		and size.Z >= AREA_HAZARD_BROAD_FOOTPRINT

	return elongated or broad
end

local function isLargeHitboxCandidate(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if hasAreaHazardName(part, part) then
		return true
	end

	local size = part.Size
	local maxAxis = math.max(size.X, size.Y, size.Z)
	return
		maxAxis >= HITBOX_TRACK_MIN_AXIS
		and (
			isGeometricAreaHazard(size)
			or size.X >= AREA_HAZARD_BROAD_FOOTPRINT
			or size.Z >= AREA_HAZARD_BROAD_FOOTPRINT
		)
end

local function pointBoxSignedDistance(boxCf, boxSize, point, expansion)
	if not boxCf or not boxSize then
		return math.huge
	end

	expansion = expansion or 0
	local localPoint = boxCf:PointToObjectSpace(point)
	local hx = boxSize.X * 0.5 + expansion
	local hy = boxSize.Y * 0.5 + expansion
	local hz = boxSize.Z * 0.5 + expansion

	local qx = math.abs(localPoint.X) - hx
	local qy = math.abs(localPoint.Y) - hy
	local qz = math.abs(localPoint.Z) - hz

	if qx <= 0 and qy <= 0 and qz <= 0 then
		return -math.min(-qx, -qy, -qz)
	end

	local ox = math.max(qx, 0)
	local oy = math.max(qy, 0)
	local oz = math.max(qz, 0)
	return math.sqrt(ox * ox + oy * oy + oz * oz)
end

local function predictAreaBox(data, t)
	local cf = data.BoxCFrame
	if not cf then
		return nil
	end

	local velocity = data.AreaVelocity or Vector3.zero
	return cf + velocity * t
end

local function addProjectile(obj)
	task.defer(function()
		local part = getProjectilePart(obj)
		if not part then
			task.wait(0.02)
			part = getProjectilePart(obj)
		end
		if not part or not obj.Parent then
			return
		end

		local centerOffset = getProjectileCenterOffset(obj, part)
		local center = part.CFrame:PointToWorldSpace(centerOffset)
		local initialVelocity = part.AssemblyLinearVelocity
		local initialFlat = flat(initialVelocity)
		local boxCf, boxSize = getObjectBox(obj, part)
		local baseAreaHazard =
			hasAreaHazardName(obj, part)
			or isGeometricAreaHazard(boxSize)

		ProjectileData[obj] = {
			Object = obj,
			Part = part,
			CenterOffset = centerOffset,
			Radius = getProjectileRadius(obj, part),
			LastPosition = center,
			PreviousPosition = center,
			Velocity = initialVelocity,
			RawVelocity = initialVelocity,
			LastRawVelocity = initialVelocity,
			SpeedAccel = 0,
			VerticalAccel = 0,
			TurnRate = 0,
			PredictionError = 0,
			PredictedNext = nil,
			Samples = 0,
			BaseAreaHazard = baseAreaHazard,
			IsAreaHazard = baseAreaHazard,
			BoxCFrame = boxCf,
			BoxSize = boxSize,
			LastBoxPosition = boxCf and boxCf.Position or center,
			AreaVelocity = initialVelocity,
			Ready =
				baseAreaHazard
				or initialFlat.Magnitude >= MIN_PROJECTILE_SPEED
		}
	end)
end

local function removeProjectile(obj)
	ProjectileData[obj] = nil
end

local function clearProjectileConnections()
	if EnemyAddedConnection then
		EnemyAddedConnection:Disconnect()
		EnemyAddedConnection = nil
	end
	if EnemyRemovedConnection then
		EnemyRemovedConnection:Disconnect()
		EnemyRemovedConnection = nil
	end
end

local function findEnemyProj()
	local core = workspace:FindFirstChild("Core__Game")
	if not core then
		return nil
	end
	return core:FindFirstChild("EnemyProj")
end

local function bindEnemyProj(folder)
	if EnemyProj == folder then
		return
	end

	clearProjectileConnections()
	table.clear(ProjectileData)
	EnemyProj = folder

	if not EnemyProj then
		return
	end

	for _, obj in ipairs(EnemyProj:GetChildren()) do
		addProjectile(obj)
	end

	EnemyAddedConnection = EnemyProj.ChildAdded:Connect(addProjectile)
	EnemyRemovedConnection = EnemyProj.ChildRemoved:Connect(removeProjectile)
end


local function clearHitboxConnections()
	if HitboxAddedConnection then
		HitboxAddedConnection:Disconnect()
		HitboxAddedConnection = nil
	end
	if HitboxRemovedConnection then
		HitboxRemovedConnection:Disconnect()
		HitboxRemovedConnection = nil
	end
end

local function findHitboxFolder()
	local core = workspace:FindFirstChild("Core__Game")
	if not core then
		return nil
	end
	return core:FindFirstChild("Hitboxes")
end

local function addHitboxPart(part)
	if not isLargeHitboxCandidate(part) then
		return
	end

	HitboxData[part] = {
		Part = part,
		BoxCFrame = part.CFrame,
		BoxSize = part.Size,
		LastBoxPosition = part.Position,
		AreaVelocity = part.AssemblyLinearVelocity,
		Samples = 0,
		Ready = true
	}
end

local function removeHitboxPart(part)
	HitboxData[part] = nil
end

local function bindHitboxFolder(folder)
	if HitboxFolder == folder then
		return
	end

	clearHitboxConnections()
	table.clear(HitboxData)
	HitboxFolder = folder

	if not HitboxFolder then
		return
	end

	for _, obj in ipairs(HitboxFolder:GetDescendants()) do
		if obj:IsA("BasePart") then
			addHitboxPart(obj)
		end
	end

	HitboxAddedConnection =
		HitboxFolder.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") then
				addHitboxPart(obj)
			end
		end)

	HitboxRemovedConnection =
		HitboxFolder.DescendantRemoving:Connect(function(obj)
			if obj:IsA("BasePart") then
				removeHitboxPart(obj)
			end
		end)
end

local function isActualBarrier(obj)
	return obj:IsA("BasePart") and string.lower(obj.Name) == "barrier"
end

local function rebuildBarrierParts()
	local list = {}
	for part in pairs(BarrierSet) do
		if part and part.Parent then
			list[#list + 1] = part
		end
	end
	BarrierParts = list
	ActiveBarrierParts = nil
end

local function scanBarriers()
	table.clear(BarrierSet)
	for _, obj in ipairs(workspace:GetDescendants()) do
		if isActualBarrier(obj) then
			BarrierSet[obj] = true
		end
	end
	rebuildBarrierParts()
end

scanBarriers()

workspace.DescendantAdded:Connect(function(obj)
	if isActualBarrier(obj) then
		BarrierSet[obj] = true
		rebuildBarrierParts()
	end
end)

workspace.DescendantRemoving:Connect(function(obj)
	if BarrierSet[obj] then
		BarrierSet[obj] = nil
		rebuildBarrierParts()
	end
end)

local function segmentMinDistance(relativeA, relativeB)
	local d = relativeB - relativeA
	local denom = d:Dot(d)
	if denom <= 1e-8 then
		return relativeA.Magnitude
	end
	local t = math.clamp(-relativeA:Dot(d) / denom, 0, 1)
	return (relativeA + d * t).Magnitude
end

local function pointBarrierDistance2D(part, worldPoint)
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local hx = part.Size.X * 0.5
	local hz = part.Size.Z * 0.5
	local dx = math.max(math.abs(localPoint.X) - hx, 0)
	local dz = math.max(math.abs(localPoint.Z) - hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function segmentIntersectsExpandedBarrier(part, worldA, worldB, expansion)
	local a = part.CFrame:PointToObjectSpace(worldA)
	local b = part.CFrame:PointToObjectSpace(worldB)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local hx = part.Size.X * 0.5 + expansion
	local hz = part.Size.Z * 0.5 + expansion
	local tMin = 0
	local tMax = 1

	local function axis(origin, delta, half)
		if math.abs(delta) < 1e-8 then
			return math.abs(origin) <= half
		end
		local t1 = (-half - origin) / delta
		local t2 = (half - origin) / delta
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tMin = math.max(tMin, t1)
		tMax = math.min(tMax, t2)
		return tMin <= tMax
	end

	if not axis(a.X, dx, hx) then
		return false
	end
	if not axis(a.Z, dz, hz) then
		return false
	end
	return tMax >= 0 and tMin <= 1
end

local function getBarrierList()
	if ActiveBarrierParts ~= nil then
		return ActiveBarrierParts
	end
	return BarrierParts
end

local function refreshActiveBarriers(position, walkSpeed)
	local active = {}
	local searchDistance =
		walkSpeed * PLAN_HORIZON
		+ BARRIER_RAY_DISTANCE
		+ 10

	for _, barrier in ipairs(BarrierParts) do
		if barrier and barrier.Parent then
			if pointBarrierDistance2D(barrier, position) <= searchDistance then
				active[#active + 1] = barrier
			end
		end
	end

	ActiveBarrierParts = active
end

local function expandedBarrierDepth2D(part, worldPoint, expansion)
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local hx = part.Size.X * 0.5 + expansion
	local hz = part.Size.Z * 0.5 + expansion
	local px = hx - math.abs(localPoint.X)
	local pz = hz - math.abs(localPoint.Z)

	if px >= 0 and pz >= 0 then
		return true, math.min(px, pz)
	end

	local dx = math.max(-px, 0)
	local dz = math.max(-pz, 0)
	return false, -math.sqrt(dx * dx + dz * dz)
end

local function pathHitsBarrier(a, b)
	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			if segmentIntersectsExpandedBarrier(
				barrier,
				a,
				b,
				BARRIER_BODY_RADIUS
			) then
				local startInside, startDepth =
					expandedBarrierDepth2D(
						barrier,
						a,
						BARRIER_BODY_RADIUS
					)
				local endInside, endDepth =
					expandedBarrierDepth2D(
						barrier,
						b,
						BARRIER_BODY_RADIUS
					)

				-- Critical anti-stick rule:
				-- if the character already starts inside the expanded wall margin,
				-- moving OUT of that margin must remain a valid candidate.
				if startInside then
					if not endInside then
						continue
					end

					if endDepth < startDepth - 0.015 then
						continue
					end
				end

				return true
			end
		end
	end
	return false
end

local function nearestBarrierDistance(position)
	local best = math.huge
	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			local d = pointBarrierDistance2D(barrier, position)
			if d < best then
				best = d
			end
		end
	end
	return best
end

local function rayBarrierDistance2D(part, origin, direction, maxDistance)
	local localOrigin = part.CFrame:PointToObjectSpace(origin)
	local localDirection = part.CFrame:VectorToObjectSpace(direction)
	local hx = part.Size.X * 0.5 + BARRIER_BODY_RADIUS
	local hz = part.Size.Z * 0.5 + BARRIER_BODY_RADIUS
	local tMin = 0
	local tMax = maxDistance

	local function axis(o, d, half)
		if math.abs(d) < 1e-8 then
			return math.abs(o) <= half
		end
		local t1 = (-half - o) / d
		local t2 = (half - o) / d
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tMin = math.max(tMin, t1)
		tMax = math.min(tMax, t2)
		return tMin <= tMax
	end

	if not axis(localOrigin.X, localDirection.X, hx) then
		return nil
	end
	if not axis(localOrigin.Z, localDirection.Z, hz) then
		return nil
	end
	if tMax < 0 or tMin > maxDistance then
		return nil
	end
	return math.max(0, tMin)
end

local function barrierOpenness(position)
	local barriers = getBarrierList()
	if #barriers == 0 then
		return BARRIER_RAY_DISTANCE, BARRIER_RAY_DISTANCE, 0
	end

	local total = 0
	local minimum = BARRIER_RAY_DISTANCE
	local closeRays = 0

	for i = 0, BARRIER_RAY_COUNT - 1 do
		local angle = i * math.pi * 2 / BARRIER_RAY_COUNT
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local nearest = BARRIER_RAY_DISTANCE

		for _, barrier in ipairs(barriers) do
			if barrier and barrier.Parent then
				local d = rayBarrierDistance2D(
					barrier,
					position,
					direction,
					BARRIER_RAY_DISTANCE
				)
				if d and d < nearest then
					nearest = d
				end
			end
		end

		total += nearest
		minimum = math.min(minimum, nearest)
		if nearest <= BARRIER_CLOSE_RAY_DISTANCE then
			closeRays += 1
		end
	end

	return total / BARRIER_RAY_COUNT, minimum, closeRays
end

local function predictTrackerNext(data, dt)
	local flatVelocity = flat(data.Velocity)
	local speed = flatVelocity.Magnitude
	local direction = speed > 0.01 and flatVelocity.Unit or Vector3.zero
	if direction.Magnitude > 0.01 and math.abs(data.TurnRate) > 0.001 then
		direction = rotateY(direction, data.TurnRate * dt)
	end
	speed = math.max(0, speed + data.SpeedAccel * dt)
	local vy = data.Velocity.Y + data.VerticalAccel * dt
	local predictedVelocity = direction * speed + Vector3.new(0, vy, 0)
	return data.LastPosition + predictedVelocity * dt
end

RunService.Heartbeat:Connect(function(dt)
	if not EnemyProj or not EnemyProj.Parent then
		local folder = findEnemyProj()
		if folder ~= EnemyProj then
			bindEnemyProj(folder)
		end
	end

	if not HitboxFolder or not HitboxFolder.Parent then
		local folder = findHitboxFolder()
		if folder ~= HitboxFolder then
			bindHitboxFolder(folder)
		end
	end

	if dt <= 0 or dt > 0.25 then
		return
	end

	local count = 0

	for obj, data in pairs(ProjectileData) do
		if not obj.Parent then
			ProjectileData[obj] = nil
			continue
		end

		local part = data.Part
		if not part or not part.Parent then
			part = getProjectilePart(obj)
			if not part then
				ProjectileData[obj] = nil
				continue
			end
			data.Part = part
			data.CenterOffset = getProjectileCenterOffset(obj, part)
			data.Radius = getProjectileRadius(obj, part)
			data.LastPosition = part.CFrame:PointToWorldSpace(data.CenterOffset)
			data.PreviousPosition = data.LastPosition

			local boxCf, boxSize = getObjectBox(obj, part)
			data.BoxCFrame = boxCf
			data.BoxSize = boxSize
			data.LastBoxPosition =
				boxCf and boxCf.Position or data.LastPosition
			data.AreaVelocity = part.AssemblyLinearVelocity
			data.BaseAreaHazard =
				hasAreaHazardName(obj, part)
				or isGeometricAreaHazard(boxSize)
			data.IsAreaHazard = data.BaseAreaHazard
			data.Samples = 0
			data.Ready = data.IsAreaHazard
			continue
		end

		count += 1

		local position = getProjectileCenter(data)
		local boxCf, boxSize = getObjectBox(obj, part)

		if data.PredictedNext then
			local error = (position - data.PredictedNext).Magnitude
			data.PredictionError +=
				(error - data.PredictionError) * PREDICTION_ERROR_SMOOTH
		end

		local rawVelocity = (position - data.LastPosition) / dt
		local oldRaw = data.RawVelocity
		local oldFlat = flat(oldRaw)
		local newFlat = flat(rawVelocity)
		local oldSpeed = oldFlat.Magnitude
		local newSpeed = newFlat.Magnitude

		if oldSpeed >= MIN_PROJECTILE_SPEED and newSpeed >= MIN_PROJECTILE_SPEED then
			local rawTurn = signedAngleXZ(oldFlat, newFlat) / dt
			rawTurn = math.clamp(rawTurn, -MAX_TURN_RATE, MAX_TURN_RATE)
			data.TurnRate +=
				(rawTurn - data.TurnRate) * TURN_SMOOTH

			local rawSpeedAccel = (newSpeed - oldSpeed) / dt
			rawSpeedAccel = math.clamp(
				rawSpeedAccel,
				-MAX_SPEED_ACCEL,
				MAX_SPEED_ACCEL
			)
			data.SpeedAccel +=
				(rawSpeedAccel - data.SpeedAccel) * SPEED_ACCEL_SMOOTH
		end

		local rawVerticalAccel = (rawVelocity.Y - oldRaw.Y) / dt
		rawVerticalAccel = math.clamp(
			rawVerticalAccel,
			-MAX_VERTICAL_ACCEL,
			MAX_VERTICAL_ACCEL
		)
		data.VerticalAccel +=
			(rawVerticalAccel - data.VerticalAccel) * VERTICAL_ACCEL_SMOOTH

		if data.Samples == 0 then
			data.Velocity = rawVelocity
		else
			data.Velocity =
				data.Velocity:Lerp(rawVelocity, VELOCITY_SMOOTH)
		end

		if boxCf and boxSize then
			local oldBoxPosition =
				data.LastBoxPosition or boxCf.Position
			local rawAreaVelocity =
				(boxCf.Position - oldBoxPosition) / dt

			if data.Samples == 0 then
				data.AreaVelocity = rawAreaVelocity
			else
				data.AreaVelocity =
					(data.AreaVelocity or Vector3.zero):Lerp(
						rawAreaVelocity,
						AREA_HAZARD_VELOCITY_SMOOTH
					)
			end

			data.BoxCFrame = boxCf
			data.BoxSize = boxSize
			data.LastBoxPosition = boxCf.Position
			data.BaseAreaHazard =
				hasAreaHazardName(obj, part)
				or isGeometricAreaHazard(boxSize)
		end

		data.PreviousPosition = data.LastPosition
		data.LastPosition = position
		data.LastRawVelocity = data.RawVelocity
		data.RawVelocity = rawVelocity
		data.Samples += 1

		data.IsAreaHazard =
			data.BaseAreaHazard
			or (
				data.Samples >= AREA_HAZARD_STATIONARY_SAMPLES
				and newFlat.Magnitude < MIN_PROJECTILE_SPEED
			)

		data.Ready =
			data.Samples >= 2
			and (
				data.IsAreaHazard
				or flat(data.Velocity).Magnitude >= MIN_PROJECTILE_SPEED
			)

		data.PredictedNext = predictTrackerNext(data, dt)
	end

	for part, data in pairs(HitboxData) do
		if not part.Parent then
			HitboxData[part] = nil
			continue
		end

		local cf = part.CFrame
		local rawVelocity =
			(cf.Position - data.LastBoxPosition) / dt

		if data.Samples == 0 then
			data.AreaVelocity = rawVelocity
		else
			data.AreaVelocity =
				(data.AreaVelocity or Vector3.zero):Lerp(
					rawVelocity,
					AREA_HAZARD_VELOCITY_SMOOTH
				)
		end

		data.BoxCFrame = cf
		data.BoxSize = part.Size
		data.LastBoxPosition = cf.Position
		data.Samples += 1
		data.Ready = true
	end

	LastProjectileCount = count
end)

task.spawn(function()
	while true do
		local folder = findEnemyProj()
		if folder ~= EnemyProj then
			bindEnemyProj(folder)
		end

		local hitboxes = findHitboxFolder()
		if hitboxes ~= HitboxFolder then
			bindHitboxFolder(hitboxes)
		end

		task.wait(0.35)
	end
end)

local function projectileCanReachEnvelope(
	data,
	rootPosition,
	maxPlayerReach,
	networkLead
)
	local position = getProjectileCenter(data)
	local distance = (position - rootPosition).Magnitude
	local speed = flat(data.Velocity).Magnitude
	local t = PLAN_HORIZON + networkLead

	local horizontalTravel =
		speed * t
		+ 0.5 * math.abs(data.SpeedAccel or 0) * t * t

	local verticalTravel =
		math.abs(data.Velocity.Y) * t
		+ 0.5 * math.abs(data.VerticalAccel or 0) * t * t

	local maxTravel = horizontalTravel + verticalTravel
	local reach =
		(data.Radius or 0)
		+ PLAYER_MINI_RADIUS
		+ MAX_ERROR_MARGIN
		+ NEAR_ZONE
		+ maxPlayerReach
		+ maxTravel
		+ BROAD_PHASE_EXTRA

	return distance <= reach
end

local function analyticTravelDistance(speed, acceleration, t)
	if acceleration < 0 and speed > 0 then
		local stopTime = speed / -acceleration
		if t > stopTime then
			t = stopTime
		end
	end
	return math.max(
		0,
		speed * t + 0.5 * acceleration * t * t
	)
end

local function simulateProjectilePositions(data, networkLead)
	local positions = table.create(TOTAL_PREDICTION_STEPS + 1)

	local origin = getProjectileCenter(data)
	local flatVelocity = flat(data.Velocity)
	local speed = flatVelocity.Magnitude
	local direction =
		speed > 0.01
		and flatVelocity.Unit
		or Vector3.new(0, 0, -1)

	local vy = data.Velocity.Y
	local speedAccel = data.SpeedAccel or 0
	local verticalAccel = data.VerticalAccel or 0
	local turnRate = data.TurnRate or 0

	local useAnalytic =
		math.abs(turnRate) <= ANALYTIC_TURN_RATE
		and math.abs(speedAccel) <= ANALYTIC_SPEED_ACCEL
		and math.abs(verticalAccel) <= ANALYTIC_VERTICAL_ACCEL

	if useAnalytic then
		for positionIndex = 1, TOTAL_PREDICTION_STEPS + 1 do
			local t = networkLead + getPredictionTime(positionIndex)
			local travel =
				analyticTravelDistance(
					speed,
					speedAccel,
					t
				)
			local y =
				origin.Y
				+ vy * t
				+ 0.5 * verticalAccel * t * t

			positions[positionIndex] =
				Vector3.new(
					origin.X + direction.X * travel,
					y,
					origin.Z + direction.Z * travel
				)
		end

		return positions
	end

	local position = origin
	local currentTime = 0
	local adaptiveStep =
		math.clamp(
			math.rad(7.0)
				/ math.max(math.abs(turnRate), 0.001),
			0.014,
			0.10
		)
	adaptiveStep =
		math.min(
			adaptiveStep,
			PROJECTILE_SIM_DT * 1.6
		)

	local function advanceTo(targetTime)
		while currentTime + 1e-6 < targetTime do
			local step =
				math.min(
					adaptiveStep,
					targetTime - currentTime
				)

			if math.abs(turnRate) > 0.001 then
				direction =
					rotateY(
						direction,
						turnRate * step
					)
				if direction.Magnitude > 0.01 then
					direction = direction.Unit
				end
			end

			speed =
				math.max(
					0,
					speed + speedAccel * step
				)
			vy += verticalAccel * step

			position +=
				(
					direction * speed
					+ Vector3.new(0, vy, 0)
				) * step

			currentTime += step
		end
	end

	for positionIndex = 1, TOTAL_PREDICTION_STEPS + 1 do
		local targetTime =
			networkLead + getPredictionTime(positionIndex)
		advanceTo(targetTime)
		positions[positionIndex] = position
	end

	return positions
end

local function farFieldKey(ix, iz)
	return tostring(ix) .. ":" .. tostring(iz)
end

local function addFarFieldSample(bucket, position, dangerRadius)
	local ix = math.floor(position.X / FAR_FIELD_CELL_SIZE)
	local iz = math.floor(position.Z / FAR_FIELD_CELL_SIZE)
	local key = farFieldKey(ix, iz)
	local cell = bucket[key]

	if not cell then
		cell = {
			X = (ix + 0.5) * FAR_FIELD_CELL_SIZE,
			Z = (iz + 0.5) * FAR_FIELD_CELL_SIZE,
			YSum = 0,
			Count = 0,
			MaxRadius = 0
		}
		bucket[key] = cell
	end

	cell.Count += 1
	cell.YSum += position.Y
	cell.MaxRadius = math.max(cell.MaxRadius, dangerRadius)
end

local function evaluateFarField(position, stepIndex, threats)
	local fields = threats.FarField
	local bucket = fields and fields[stepIndex]
	if not bucket then
		return 0
	end

	local ix = math.floor(position.X / FAR_FIELD_CELL_SIZE)
	local iz = math.floor(position.Z / FAR_FIELD_CELL_SIZE)
	local risk = 0

	for dx = -1, 1 do
		for dz = -1, 1 do
			local cell = bucket[farFieldKey(ix + dx, iz + dz)]
			if cell then
				local y = cell.YSum / math.max(cell.Count, 1)
				local delta =
					Vector3.new(cell.X, y, cell.Z) - position
				local distance = delta.Magnitude
				local radius =
					cell.MaxRadius
					+ FAR_FIELD_CELL_SIZE * 0.58
				local influence = radius + FAR_FIELD_INFLUENCE

				if distance < influence then
					local near =
						1 - math.clamp(
							(distance - radius)
								/ math.max(FAR_FIELD_INFLUENCE, 0.001),
							0,
							1
						)
					risk +=
						near * near
						* FAR_FIELD_RISK_WEIGHT
						* math.sqrt(cell.Count)
				end
			end
		end
	end

	return risk
end

local function buildAreaThreat(
	sourceData,
	sourceName,
	root,
	humanoid,
	networkLead,
	rootFlatSpeed,
	areaByStep
)
	if not sourceData
		or not sourceData.Ready
		or not sourceData.BoxCFrame
		or not sourceData.BoxSize
	then
		return nil
	end

	local boxes = table.create(TOTAL_PREDICTION_STEPS + 1)
	for positionIndex = 1, TOTAL_PREDICTION_STEPS + 1 do
		local t =
			networkLead
			+ getPredictionTime(positionIndex)
		boxes[positionIndex] =
			predictAreaBox(sourceData, t)
	end

	local threat = {
		IsArea = true,
		SourceName = sourceName,
		Boxes = boxes,
		BoxSize = sourceData.BoxSize,
		AreaVelocity = sourceData.AreaVelocity or Vector3.zero,
		Tier = "Far",
		EarliestRelevantTime = math.huge
	}

	local expansion =
		PLAYER_MINI_RADIUS
		+ AREA_HAZARD_ERROR_MARGIN
	local canMatter = false

	for stepIndex = 1, TOTAL_PREDICTION_STEPS do
		local box0 = boxes[stepIndex]
		local box1 = boxes[stepIndex + 1]
		if box0 and box1 then
			local t = getStepEndTime(stepIndex)
			local reach =
				humanoid.WalkSpeed * t
				+ rootFlatSpeed * math.min(t, 0.18)

			local d0 =
				pointBoxSignedDistance(
					box0,
					sourceData.BoxSize,
					root.Position,
					expansion
				)
			local d1 =
				pointBoxSignedDistance(
					box1,
					sourceData.BoxSize,
					root.Position,
					expansion
				)
			local distance = math.min(d0, d1)

			if distance <= reach + AREA_HAZARD_INFLUENCE + 0.75 then
				canMatter = true
				threat.EarliestRelevantTime =
					math.min(
						threat.EarliestRelevantTime,
						t
					)
				areaByStep[stepIndex][#areaByStep[stepIndex] + 1] =
					threat
			end
		end
	end

	if not canMatter then
		return nil
	end

	if threat.EarliestRelevantTime <= IMMEDIATE_THREAT_HORIZON then
		threat.Tier = "Immediate"
	elseif threat.EarliestRelevantTime <= EXACT_THREAT_HORIZON then
		threat.Tier = "Near"
	else
		threat.Tier = "Far"
	end

	return threat
end

local function buildThreatSnapshot(root, humanoid)
	local threats = {}
	local byStep = table.create(TOTAL_PREDICTION_STEPS)
	local areaByStep = table.create(TOTAL_PREDICTION_STEPS)
	local farField = table.create(TOTAL_PREDICTION_STEPS)

	for i = 1, TOTAL_PREDICTION_STEPS do
		byStep[i] = {}
		areaByStep[i] = {}
		farField[i] = {}
	end

	local networkLead = getNetworkLead()
	local rootFlatSpeed =
		flat(root.AssemblyLinearVelocity).Magnitude
	local maxPlayerReach =
		humanoid.WalkSpeed * PLAN_HORIZON
		+ rootFlatSpeed * 0.15

	local immediateCount = 0
	local nearCount = 0
	local farCount = 0
	local areaCount = 0

	local function registerAreaThreat(threat)
		if not threat then
			return
		end

		areaCount += 1
		threats[#threats + 1] = threat

		if threat.Tier == "Immediate" then
			immediateCount += 1
		elseif threat.Tier == "Near" then
			nearCount += 1
		else
			farCount += 1
		end
	end

	for _, data in pairs(ProjectileData) do
		if data.Ready
			and data.Part
			and data.Part.Parent
		then
			if data.IsAreaHazard then
				registerAreaThreat(
					buildAreaThreat(
						data,
						tostring(data.Object and data.Object.Name or "AreaProjectile"),
						root,
						humanoid,
						networkLead,
						rootFlatSpeed,
						areaByStep
					)
				)
			elseif flat(data.Velocity).Magnitude >= MIN_PROJECTILE_SPEED
				and projectileCanReachEnvelope(
					data,
					root.Position,
					maxPlayerReach,
					networkLead
				)
			then
				local radius = data.Radius or 0
				local speed = flat(data.Velocity).Magnitude

				local errorMargin =
					math.clamp(
						BASE_ERROR_MARGIN
							+ (data.PredictionError or 0)
								* PREDICTION_ERROR_WEIGHT
							+ speed * SPEED_MARGIN_WEIGHT
							+ math.abs(data.TurnRate or 0)
								* TURN_MARGIN_WEIGHT,
						BASE_ERROR_MARGIN,
						MAX_ERROR_MARGIN
					)

				local dangerRadius =
					radius
						+ PLAYER_MINI_RADIUS
						+ errorMargin

				local positions =
					simulateProjectilePositions(
						data,
						networkLead
					)

				local threat = {
					Data = data,
					Positions = positions,
					DangerRadius = dangerRadius,
					ErrorMargin = errorMargin,
					Speed = speed,
					Tier = "Far",
					EarliestRelevantTime = math.huge
				}

				local canMatter = false

				for stepIndex = 1, TOTAL_PREDICTION_STEPS do
					local p0 = positions[stepIndex]
					local p1 = positions[stepIndex + 1]
					if p0 and p1 then
						local relativeA = p0 - root.Position
						local relativeB = p1 - root.Position
						local stationaryDistance =
							segmentMinDistance(
								relativeA,
								relativeB
							)

						local t = getStepEndTime(stepIndex)
						local reachable =
							humanoid.WalkSpeed * t
								+ rootFlatSpeed
									* math.min(t, 0.18)

						if stationaryDistance
							<= dangerRadius
								+ NEAR_ZONE
								+ reachable
								+ 0.75
						then
							canMatter = true
							threat.EarliestRelevantTime =
								math.min(
									threat.EarliestRelevantTime,
									t
								)

							if t <= EXACT_THREAT_HORIZON then
								local bucket = byStep[stepIndex]
								bucket[#bucket + 1] = threat
							else
								addFarFieldSample(
									farField[stepIndex],
									p1,
									dangerRadius
								)
							end
						end
					end
				end

				if canMatter then
					if threat.EarliestRelevantTime <= IMMEDIATE_THREAT_HORIZON then
						threat.Tier = "Immediate"
						immediateCount += 1
					elseif threat.EarliestRelevantTime <= EXACT_THREAT_HORIZON then
						threat.Tier = "Near"
						nearCount += 1
					else
						threat.Tier = "Far"
						farCount += 1
					end

					threats[#threats + 1] = threat
				end
			end
		end
	end

	-- The actual Core__Game/Hitboxes folder is used as a second, authoritative
	-- source for large persistent attack volumes. This catches stationary lasers
	-- and floor/line attacks that have no useful projectile velocity.
	for part, data in pairs(HitboxData) do
		if part.Parent and data.Ready and isLargeHitboxCandidate(part) then
			registerAreaThreat(
				buildAreaThreat(
					data,
					tostring(part.Name),
					root,
					humanoid,
					networkLead,
					rootFlatSpeed,
					areaByStep
				)
			)
		end
	end

	threats.ByStep = byStep
	threats.AreaByStep = areaByStep
	threats.FarField = farField
	LastThreatCount = #threats
	LastImmediateThreatCount = immediateCount
	LastNearThreatCount = nearCount
	LastFarThreatCount = farCount
	LastAreaThreatCount = areaCount
	return threats
end

local function simulatePlayerStep(position, velocity, inputDirection, walkSpeed, dt, firstStep)
	local target = inputDirection * walkSpeed
	local newPosition = position
	local newVelocity = velocity
	local remaining = dt

	if firstStep and PLAYER_ACTUATION_DELAY > 0 then
		local delay = math.min(PLAYER_ACTUATION_DELAY, remaining)
		newPosition += newVelocity * delay
		remaining -= delay
	end

	if remaining > 0 then
		local alpha =
			1 - math.exp(-remaining / math.max(PLAYER_RESPONSE_TIME, 0.001))
		local targetVelocity =
			newVelocity:Lerp(target, alpha)
		local averageVelocity =
			(newVelocity + targetVelocity) * 0.5
		newPosition += averageVelocity * remaining
		newVelocity = targetVelocity
	end

	return newPosition, newVelocity
end

local function evaluateThreatSegment(
	oldPlayerPosition,
	newPlayerPosition,
	stepIndex,
	threats
)
	local risk = 0
	local hits = 0
	local minClearance = math.huge

	local activeThreats =
		(threats.ByStep and threats.ByStep[stepIndex])
		or threats

	for _, threat in ipairs(activeThreats) do
		local oldProjectile = threat.Positions[stepIndex]
		local newProjectile = threat.Positions[stepIndex + 1]

		local relativeA = oldProjectile - oldPlayerPosition
		local relativeB = newProjectile - newPlayerPosition
		local distance = segmentMinDistance(relativeA, relativeB)
		local clearance = distance - threat.DangerRadius

		if clearance < minClearance then
			minClearance = clearance
		end

		if clearance <= 0 then
			hits += 1
			local penetration =
				math.min(-clearance, threat.DangerRadius + 1)
			risk +=
				HIT_PENALTY
					+ penetration * 8000
					+ threat.Speed * 4
		elseif clearance < NEAR_ZONE then
			local near = 1 - clearance / NEAR_ZONE
			local timeFactor =
				1.0
					+ (1 - math.clamp(
						getStepStartTime(stepIndex) / PLAN_HORIZON,
						0,
						1
					)) * 0.8
			risk +=
				near * near
					* NEAR_RISK_WEIGHT
					* timeFactor
		end
	end

	local areaThreats =
		threats.AreaByStep
		and threats.AreaByStep[stepIndex]
		or nil

	if areaThreats then
		local playerMid =
			(oldPlayerPosition + newPlayerPosition) * 0.5
		local expansion =
			PLAYER_MINI_RADIUS
			+ AREA_HAZARD_ERROR_MARGIN

		for _, threat in ipairs(areaThreats) do
			local oldBox = threat.Boxes[stepIndex]
			local newBox = threat.Boxes[stepIndex + 1]

			if oldBox and newBox then
				local midBox = oldBox:Lerp(newBox, 0.5)
				local d0 =
					pointBoxSignedDistance(
						oldBox,
						threat.BoxSize,
						oldPlayerPosition,
						expansion
					)
				local dm =
					pointBoxSignedDistance(
						midBox,
						threat.BoxSize,
						playerMid,
						expansion
					)
				local d1 =
					pointBoxSignedDistance(
						newBox,
						threat.BoxSize,
						newPlayerPosition,
						expansion
					)

				local clearance = math.min(d0, dm, d1)
				minClearance = math.min(minClearance, clearance)

				if clearance <= 0 then
					hits += 1
					risk +=
						HIT_PENALTY * 1.25
						+ math.min(-clearance, 4) * 12000
				elseif clearance < AREA_HAZARD_INFLUENCE then
					local near =
						1
						- clearance
							/ AREA_HAZARD_INFLUENCE
					risk +=
						near * near
						* AREA_HAZARD_NEAR_WEIGHT
				end
			end
		end
	end

	local farRisk =
		evaluateFarField(
			newPlayerPosition,
			stepIndex,
			threats
		)

	risk += farRisk

	return risk, hits, minClearance, farRisk
end

local function evaluateBarrierSegment(oldPosition, newPosition)
	if pathHitsBarrier(oldPosition, newPosition) then
		return WALL_HIT_PENALTY, true, 0
	end

	local oldClearance = nearestBarrierDistance(oldPosition)
	local clearance = nearestBarrierDistance(newPosition)
	local risk = 0

	if clearance < BARRIER_NEAR_DISTANCE then
		local near =
			1 - math.clamp(
				clearance / BARRIER_NEAR_DISTANCE,
				0,
				1
			)
		risk +=
			near * near
			* BARRIER_NEAR_WEIGHT
	end

	-- If already near a wall, staying glued to it or moving closer is expensive.
	-- Moving away is explicitly rewarded so the planner can regain dodge space.
	if oldClearance < BARRIER_ESCAPE_DISTANCE then
		local delta = clearance - oldClearance

		if delta < -0.01 then
			local closeness =
				1
				- math.clamp(
					oldClearance / BARRIER_ESCAPE_DISTANCE,
					0,
					1
				)
			risk +=
				(-delta)
				* BARRIER_APPROACH_WEIGHT
				* (0.6 + closeness)
		elseif delta > 0.01 then
			risk -=
				math.min(
					delta * BARRIER_ESCAPE_REWARD,
					95
				)
		end

		if clearance <= BARRIER_STICK_DISTANCE
			and delta <= 0.035
		then
			local stuck =
				1
				- math.clamp(
					clearance / BARRIER_STICK_DISTANCE,
					0,
					1
				)
			risk +=
				BARRIER_STICK_PENALTY
				* (0.55 + stuck)
		end
	end

	return risk, false, clearance
end

local function makeAbsoluteDirections(count)
	local list = table.create(count + 1)
	for i = 0, count - 1 do
		local angle = i * math.pi * 2 / count
		list[#list + 1] =
			Vector3.new(math.cos(angle), 0, math.sin(angle))
	end
	list[#list + 1] = Vector3.zero
	return list
end

local InitialDirectionList = makeAbsoluteDirections(INITIAL_DIRECTIONS)
local ZeroRestartDirectionList =
	makeAbsoluteDirections(ZERO_RESTART_DIRECTIONS)
local EscapeDirectionList = makeAbsoluteDirections(ESCAPE_DIRECTIONS)

local SteeringAnglesNear = {
	0,
	math.rad(-22.5),
	math.rad(22.5),
	math.rad(-45),
	math.rad(45),
	math.rad(-90),
	math.rad(90)
}

local SteeringAnglesFar = {
	0,
	math.rad(-22.5),
	math.rad(22.5),
	math.rad(-45),
	math.rad(45)
}

local function getNextInputs(previousDirection, depth, emergency)
	if depth == 1 then
		return InitialDirectionList
	end

	if previousDirection.Magnitude < 0.01 then
		return ZeroRestartDirectionList
	end

	local farPhase = getStepEndTime(depth) > EXACT_THREAT_HORIZON
	local steeringAngles = farPhase and SteeringAnglesFar or SteeringAnglesNear
	local extra = emergency and 2 or 1
	local list = table.create(#steeringAngles + extra)
	local unit = previousDirection.Unit

	for _, angle in ipairs(steeringAngles) do
		list[#list + 1] = rotateY(unit, angle)
	end

	if emergency then
		list[#list + 1] =
			rotateY(unit, math.pi)
	end

	list[#list + 1] = Vector3.zero
	return list
end

local function getAdaptiveBeamWidth(threatCount)
	-- Spend more search width in moderate situations, but cap work in bullet floods.
	if threatCount <= 4 then
		return 24
	elseif threatCount <= 10 then
		return 30
	elseif threatCount <= 20 then
		return 34
	elseif threatCount <= 35 then
		return 32
	elseif threatCount <= 60 then
		return 28
	end
	return 24
end

local function nodeSort(a, b)
	if a.WallHits ~= b.WallHits then
		return a.WallHits < b.WallHits
	end
	if a.Hits ~= b.Hits then
		return a.Hits < b.Hits
	end
	if math.abs(a.Cost - b.Cost) > 0.001 then
		return a.Cost < b.Cost
	end
	return a.MinClearance > b.MinClearance
end

local function evaluateBaseline(root, humanoid, threats)
	local position = root.Position
	local velocity = flat(root.AssemblyLinearVelocity)
	local minClearance = math.huge
	local hits = 0
	local earliestImpact = math.huge
	local totalFarRisk = 0
	local inputDirection = Vector3.zero

	for stepIndex = 1, PLAN_STEPS do
		local dt = getStepDt(stepIndex)
		local newPosition, newVelocity =
			simulatePlayerStep(
				position,
				velocity,
				inputDirection,
				humanoid.WalkSpeed,
				dt,
				stepIndex == 1
			)

		local _, stepHits, stepClearance, farRisk =
			evaluateThreatSegment(
				position,
				newPosition,
				stepIndex,
				threats
			)

		hits += stepHits
		totalFarRisk += farRisk or 0
		minClearance = math.min(minClearance, stepClearance)

		if stepHits > 0 and earliestImpact == math.huge then
			earliestImpact = getStepEndTime(stepIndex)
		end

		position = newPosition
		velocity = newVelocity
	end

	return {
		Hits = hits,
		MinClearance = minClearance,
		EarliestImpact = earliestImpact,
		FarRisk = totalFarRisk
	}
end

local function countEscapeOptionsAtNode(node, humanoid, threats)
	local count = 0
	local firstStep = node.Depth + 1
	if firstStep > TOTAL_PREDICTION_STEPS then
		return 0
	end

	local secondStep = firstStep + 1
	local firstDt = getStepDt(firstStep)
	local secondDt =
		secondStep <= TOTAL_PREDICTION_STEPS
		and getStepDt(secondStep)
		or ESCAPE_DT

	for _, inputDirection in ipairs(EscapeDirectionList) do
		local newPosition, newVelocity =
			simulatePlayerStep(
				node.Pos,
				node.Vel,
				inputDirection,
				humanoid.WalkSpeed,
				firstDt,
				false
			)

		if not pathHitsBarrier(node.Pos, newPosition) then
			local _, hits, _, farRisk =
				evaluateThreatSegment(
					node.Pos,
					newPosition,
					firstStep,
					threats
				)

			if hits == 0 and (farRisk or 0) <= ESCAPE_FAR_RISK_MAX then
				local valid = true

				if secondStep <= TOTAL_PREDICTION_STEPS then
					local secondPosition =
						select(
							1,
							simulatePlayerStep(
								newPosition,
								newVelocity,
								inputDirection,
								humanoid.WalkSpeed,
								secondDt,
								false
							)
						)

					if pathHitsBarrier(newPosition, secondPosition) then
						valid = false
					else
						local _, secondHits, _, secondFarRisk =
							evaluateThreatSegment(
								newPosition,
								secondPosition,
								secondStep,
								threats
							)

						if secondHits > 0
							or (secondFarRisk or 0) > ESCAPE_FAR_RISK_MAX
						then
							valid = false
						end
					end
				end

				if valid then
					count += 1
				end
			end
		end
	end

	return count
end

local function findNodeNearTime(finalNode, targetTime)
	local cursor = finalNode
	local best = finalNode
	local bestDelta = math.huge

	while cursor do
		local t = getNodeTime(cursor.Depth or 0)
		local delta = math.abs(t - targetTime)
		if delta < bestDelta then
			best = cursor
			bestDelta = delta
		end
		cursor = cursor.Parent
	end

	return best
end

local function evaluateEscapeTrend(finalNode, humanoid, threats)
	local values = {}
	local penalty = 0

	for i, targetTime in ipairs(ESCAPE_TREND_TIMES) do
		local node = findNodeNearTime(finalNode, targetTime)
		values[i] = countEscapeOptionsAtNode(node, humanoid, threats)
	end

	for i = 2, #values do
		local delta = values[i] - values[i - 1]
		if delta < 0 then
			local weight =
				i == #values
				and ESCAPE_TREND_FINAL_DROP_PENALTY
				or ESCAPE_TREND_DROP_PENALTY
			penalty += -delta * weight
		elseif delta > 0 then
			penalty -= delta * ESCAPE_TREND_GROWTH_REWARD
		end
	end

	local minimum = math.huge
	for _, value in ipairs(values) do
		minimum = math.min(minimum, value)
	end

	if minimum < 3 then
		penalty +=
			(3 - minimum)
			* ESCAPE_TREND_LOW_OPTION_PENALTY
	end

	return values, penalty
end

local function reconstructPath(node)
	local reverse = {}
	local cursor = node

	while cursor and cursor.Depth and cursor.Depth > 0 do
		reverse[#reverse + 1] = cursor.Pos
		cursor = cursor.Parent
	end

	local path = {}
	for i = #reverse, 1, -1 do
		path[#path + 1] = reverse[i]
	end
	return path
end

local function planPath(root, humanoid, threats)
	local beamWidth =
		getAdaptiveBeamWidth(
			LastImmediateThreatCount + LastNearThreatCount
		)

	local rootVelocity = flat(root.AssemblyLinearVelocity)

	local beam = {
		{
			Pos = root.Position,
			Vel = rootVelocity,
			Dir = Vector3.zero,
			FirstDir = Vector3.zero,
			Cost = 0,
			Hits = 0,
			WallHits = 0,
			MinClearance = math.huge,
			Depth = 0,
			Parent = nil
		}
	}

	for depth = 1, PLAN_STEPS do
		local nextBeam = {}

		for _, node in ipairs(beam) do
			local emergency =
				node.Hits > 0
				or node.MinClearance < 0.20
			local inputs =
				getNextInputs(
					node.Dir,
					depth,
					emergency
				)

			for _, inputDirection in ipairs(inputs) do
				local direction = clampUnit(inputDirection)

				local stepDt = getStepDt(depth)
				local newPosition, newVelocity =
					simulatePlayerStep(
						node.Pos,
						node.Vel,
						direction,
						humanoid.WalkSpeed,
						stepDt,
						depth == 1
					)

				local threatRisk, stepHits, stepClearance =
					evaluateThreatSegment(
						node.Pos,
						newPosition,
						depth,
						threats
					)

				local barrierRisk, wallHit =
					evaluateBarrierSegment(
						node.Pos,
						newPosition
					)

				local moveDistance =
					(flat(newPosition - node.Pos)).Magnitude

				local turnCost = 0
				if node.Dir.Magnitude > 0.01
					and direction.Magnitude > 0.01
				then
					local dot =
						math.clamp(
							node.Dir.Unit:Dot(direction.Unit),
							-1,
							1
						)
					turnCost =
						(1 - dot)
						* TURN_COST_WEIGHT
				elseif node.Dir.Magnitude > 0.01
					and direction.Magnitude <= 0.01
				then
					turnCost = TURN_COST_WEIGHT * 0.28
				end

				if depth == 1
					and CurrentMove.Magnitude > 0.01
					and direction.Magnitude > 0.01
				then
					local dot =
						math.clamp(
							CurrentMove.Unit:Dot(direction.Unit),
							-1,
							1
						)
					turnCost +=
						(1 - dot)
						* TURN_COST_WEIGHT
						* 1.7
				end

				local speedChange =
					math.abs(
						newVelocity.Magnitude
						- node.Vel.Magnitude
					)

				local moveCost =
					moveDistance * MOVE_COST_WEIGHT
					+ speedChange * SPEED_CHANGE_COST_WEIGHT
					+ turnCost

				if direction.Magnitude <= 0.01 then
					moveCost -= STOP_BONUS
				end

				local newNode = {
					Pos = newPosition,
					Vel = newVelocity,
					Dir = direction,
					FirstDir =
						depth == 1
						and direction
						or node.FirstDir,
					Cost =
						node.Cost
						+ threatRisk
						+ barrierRisk
						+ moveCost,
					Hits = node.Hits + stepHits,
					WallHits =
						node.WallHits
						+ (wallHit and 1 or 0),
					MinClearance =
						math.min(
							node.MinClearance,
							stepClearance
						),
					Depth = depth,
					Parent = node
				}

				nextBeam[#nextBeam + 1] = newNode
			end
		end

		table.sort(nextBeam, nodeSort)

		beam = {}
		local keep = math.min(beamWidth, #nextBeam)
		for i = 1, keep do
			beam[i] = nextBeam[i]
		end

		if #beam == 0 then
			return nil
		end
	end

	local dense =
		(LastImmediateThreatCount + LastNearThreatCount)
			>= DENSE_THREAT_COUNT
	local finalistLimit =
		dense and DENSE_FINALIST_COUNT or FINALIST_COUNT
	local finalistCount = math.min(#beam, finalistLimit)
	local finalists = {}

	for i = 1, finalistCount do
		local node = beam[i]
		local escapeTrend, trendPenalty =
			evaluateEscapeTrend(node, humanoid, threats)
		local escapeOptions = escapeTrend[#escapeTrend] or 0

		local averageOpen, minimumOpen, closeRays =
			barrierOpenness(node.Pos)

		local trapCost = trendPenalty

		if escapeOptions == 0 then
			trapCost += NO_ESCAPE_PENALTY
		else
			trapCost -= escapeOptions * ESCAPE_OPTION_REWARD
		end

		trapCost +=
			math.max(0, 4.0 - minimumOpen) * 18
			+ closeRays * BARRIER_CLOSE_RAY_PENALTY
			+ math.max(0, 7.0 - averageOpen) * 1.8

		finalists[#finalists + 1] = {
			Node = node,
			FinalCost = node.Cost + trapCost,
			EscapeOptions = escapeOptions,
			EscapeTrend = escapeTrend
		}
	end

	table.sort(finalists, function(a, b)
		if a.Node.WallHits ~= b.Node.WallHits then
			return a.Node.WallHits < b.Node.WallHits
		end
		if a.Node.Hits ~= b.Node.Hits then
			return a.Node.Hits < b.Node.Hits
		end
		if math.abs(a.FinalCost - b.FinalCost) > 0.001 then
			return a.FinalCost < b.FinalCost
		end
		return a.Node.MinClearance > b.Node.MinClearance
	end)

	local best = finalists[1]
	if not best then
		return nil
	end

	return {
		Direction = best.Node.FirstDir,
		Path = reconstructPath(best.Node),
		Hits = best.Node.Hits,
		WallHits = best.Node.WallHits,
		MinClearance = best.Node.MinClearance,
		EscapeOptions = best.EscapeOptions,
		EscapeTrend = best.EscapeTrend,
		Cost = best.FinalCost
	}
end

local DebugFolder = workspace:FindFirstChild("AutoDodge_Debug")
if DebugFolder then
	DebugFolder:Destroy()
end

DebugFolder = Instance.new("Folder")
DebugFolder.Name = "AutoDodge_Debug"
DebugFolder.Parent = workspace

local PathParts = {}

local function ensurePathPart(index)
	local part = PathParts[index]
	if part and part.Parent then
		return part
	end

	part = Instance.new("Part")
	part.Name = "P" .. tostring(index)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.34, 0.34, 0.34)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Parent = DebugFolder
	PathParts[index] = part
	return part
end

local function clearPathVisual()
	for _, part in ipairs(PathParts) do
		if part and part.Parent then
			part.Transparency = 1
		end
	end
end

local function updatePathVisual(path)
	if not SHOW_PATH or not path then
		clearPathVisual()
		return
	end

	for i, position in ipairs(path) do
		local part = ensurePathPart(i)
		part.Position =
			position + Vector3.new(0, 0.25, 0)
		part.Transparency = 0.18
	end

	for i = #path + 1, #PathParts do
		local part = PathParts[i]
		if part and part.Parent then
			part.Transparency = 1
		end
	end
end

local oldGui = PlayerGui:FindFirstChild("AutoDodgeUI")
if oldGui then
	oldGui:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AutoDodgeUI"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.DisplayOrder = 999999
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(260, 278)
Main.Position = UDim2.new(0.5, -130, 0.62, 0)
Main.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 13)
MainCorner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(75, 75, 88)
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 28)
Title.Position = UDim2.fromOffset(10, 5)
Title.BackgroundTransparency = 1
Title.Text = "AUTO DODGE"
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 20)
Status.Position = UDim2.fromOffset(10, 34)
Status.BackgroundTransparency = 1
Status.Text = "EnemyProj 대기 중..."
Status.TextColor3 = Color3.fromRGB(230, 190, 80)
Status.TextSize = 12
Status.Font = Enum.Font.Gotham
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

local Info = Instance.new("TextLabel")
Info.Size = UDim2.new(1, -20, 0, 66)
Info.Position = UDim2.fromOffset(10, 55)
Info.BackgroundTransparency = 1
Info.Text = "Projectile 0 / Threat 0"
Info.TextColor3 = Color3.fromRGB(165, 165, 178)
Info.TextSize = 11
Info.Font = Enum.Font.Code
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.TextYAlignment = Enum.TextYAlignment.Top
Info.Parent = Main

local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(1, -20, 0, 38)
Toggle.Position = UDim2.fromOffset(10, 124)
Toggle.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
Toggle.BorderSizePixel = 0
Toggle.Text = "OFF"
Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
Toggle.TextSize = 15
Toggle.Font = Enum.Font.GothamBold
Toggle.Parent = Main

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 9)
ToggleCorner.Parent = Toggle

local RadiusLabel = Instance.new("TextLabel")
RadiusLabel.Size = UDim2.new(1, -84, 0, 34)
RadiusLabel.Position = UDim2.fromOffset(42, 169)
RadiusLabel.BackgroundColor3 = Color3.fromRGB(43, 43, 50)
RadiusLabel.BorderSizePixel = 0
RadiusLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
RadiusLabel.TextSize = 13
RadiusLabel.Font = Enum.Font.GothamBold
RadiusLabel.Parent = Main

local RadiusCorner = Instance.new("UICorner")
RadiusCorner.CornerRadius = UDim.new(0, 8)
RadiusCorner.Parent = RadiusLabel

local Minus = Instance.new("TextButton")
Minus.Size = UDim2.fromOffset(28, 34)
Minus.Position = UDim2.fromOffset(10, 169)
Minus.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
Minus.BorderSizePixel = 0
Minus.Text = "-"
Minus.TextColor3 = Color3.fromRGB(255, 255, 255)
Minus.TextSize = 18
Minus.Font = Enum.Font.GothamBold
Minus.Parent = Main

local MinusCorner = Instance.new("UICorner")
MinusCorner.CornerRadius = UDim.new(0, 8)
MinusCorner.Parent = Minus

local Plus = Instance.new("TextButton")
Plus.Size = UDim2.fromOffset(28, 34)
Plus.Position = UDim2.new(1, -38, 0, 169)
Plus.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
Plus.BorderSizePixel = 0
Plus.Text = "+"
Plus.TextColor3 = Color3.fromRGB(255, 255, 255)
Plus.TextSize = 18
Plus.Font = Enum.Font.GothamBold
Plus.Parent = Main

local PlusCorner = Instance.new("UICorner")
PlusCorner.CornerRadius = UDim.new(0, 8)
PlusCorner.Parent = Plus

local PathToggle = Instance.new("TextButton")
PathToggle.Size = UDim2.new(1, -20, 0, 34)
PathToggle.Position = UDim2.fromOffset(10, 210)
PathToggle.BackgroundColor3 = Color3.fromRGB(72, 82, 100)
PathToggle.BorderSizePixel = 0
PathToggle.Text = "PATH 표시 ON"
PathToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
PathToggle.TextSize = 13
PathToggle.Font = Enum.Font.GothamBold
PathToggle.Parent = Main

local PathCorner = Instance.new("UICorner")
PathCorner.CornerRadius = UDim.new(0, 8)
PathCorner.Parent = PathToggle

local Footer = Instance.new("TextLabel")
Footer.Size = UDim2.new(1, -20, 0, 24)
Footer.Position = UDim2.fromOffset(10, 249)
Footer.BackgroundTransparency = 1
Footer.Text = "1.5s MPC / Area Hitbox / Wall Escape"
Footer.TextColor3 = Color3.fromRGB(120, 120, 135)
Footer.TextSize = 10
Footer.Font = Enum.Font.Gotham
Footer.TextXAlignment = Enum.TextXAlignment.Left
Footer.Parent = Main

local dragging = false
local dragStart = nil
local startPosition = nil
local dragInput = nil

Main.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragging = true
		dragStart = input.Position
		startPosition = Main.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

Main.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging
		or input ~= dragInput
		or not dragStart
		or not startPosition
	then
		return
	end

	local delta = input.Position - dragStart
	Main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end)

local function refreshRadiusLabel()
	RadiusLabel.Text =
		string.format("Player Mini Radius  %.2f", PLAYER_MINI_RADIUS)
end

refreshRadiusLabel()

Minus.Activated:Connect(function()
	PLAYER_MINI_RADIUS =
		math.max(
			PLAYER_RADIUS_MIN,
			math.floor(
				(PLAYER_MINI_RADIUS - PLAYER_RADIUS_STEP)
				/ PLAYER_RADIUS_STEP
				+ 0.5
			) * PLAYER_RADIUS_STEP
		)
	refreshRadiusLabel()
end)

Plus.Activated:Connect(function()
	PLAYER_MINI_RADIUS =
		math.min(
			PLAYER_RADIUS_MAX,
			math.floor(
				(PLAYER_MINI_RADIUS + PLAYER_RADIUS_STEP)
				/ PLAYER_RADIUS_STEP
				+ 0.5
			) * PLAYER_RADIUS_STEP
		)
	refreshRadiusLabel()
end)

PathToggle.Activated:Connect(function()
	SHOW_PATH = not SHOW_PATH

	if SHOW_PATH then
		PathToggle.Text = "PATH 표시 ON"
		PathToggle.BackgroundColor3 =
			Color3.fromRGB(72, 82, 100)
		updatePathVisual(CurrentPath)
	else
		PathToggle.Text = "PATH 표시 OFF"
		PathToggle.BackgroundColor3 =
			Color3.fromRGB(58, 58, 66)
		clearPathVisual()
	end
end)

Toggle.Activated:Connect(function()
	ENABLED = not ENABLED

	if ENABLED then
		Toggle.Text = "ON"
		Toggle.BackgroundColor3 =
			Color3.fromRGB(50, 145, 80)
		disableControls()
	else
		Toggle.Text = "OFF"
		Toggle.BackgroundColor3 =
			Color3.fromRGB(58, 58, 66)
		CurrentMove = Vector3.zero
		CurrentPath = nil
		clearPathVisual()
		enableControls()

		local _, humanoid = getCharacter()
		if humanoid then
			humanoid:Move(Vector3.zero, false)
		end
	end
end)

local function formatImpact(value)
	if value == math.huge then
		return "-"
	end
	return string.format("%.2f", value)
end

local function formatClearance(value)
	if value == math.huge then
		return "-"
	end
	return string.format("%.2f", value)
end

local function getPlanInterval()
	if LastImpactTime ~= math.huge
		and LastImpactTime <= 0.32
	then
		return PLAN_INTERVAL_URGENT
	end

	if LastThreatCount > 0 then
		return PLAN_INTERVAL_ACTIVE
	end

	return PLAN_INTERVAL_IDLE
end

local planning = false

local function decisionStep()
	if not ENABLED or planning then
		return
	end

	local character, humanoid, root = getCharacter()
	if not character then
		CurrentMove = Vector3.zero
		CurrentPath = nil
		enableControls()
		return
	end

	disableControls()

	local now = os.clock()
	if now - LastPlanTime < getPlanInterval() then
		humanoid:Move(CurrentMove, false)
		return
	end

	LastPlanTime = now
	planning = true

	local started = os.clock()

	local ok, err = pcall(function()
		refreshActiveBarriers(
			root.Position,
			humanoid.WalkSpeed
		)

		local threats = buildThreatSnapshot(root, humanoid)

		if #threats == 0 then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastMinClearance = math.huge
			LastImpactTime = math.huge
			LastEscapeOptions = 0
			LastFarRisk = 0
			LastEscapeTrendText = "-"
			LastMode = "IDLE"
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		local baseline = evaluateBaseline(root, humanoid, threats)
		LastMinClearance = baseline.MinClearance
		LastImpactTime = baseline.EarliestImpact
		LastFarRisk = baseline.FarRisk or 0

		local exactThreatCount =
			LastImmediateThreatCount + LastNearThreatCount
		local activationLookahead =
			exactThreatCount >= DENSE_THREAT_COUNT
			and DENSE_ACTIVATION_LOOKAHEAD
			or ACTIVATION_LOOKAHEAD

		local needPlan =
			(
				baseline.Hits > 0
				and baseline.EarliestImpact
					<= activationLookahead
			)
			or baseline.MinClearance
				<= PROACTIVE_CLEARANCE
			or (
				(LastImmediateThreatCount + LastNearThreatCount)
					>= DENSE_THREAT_COUNT
				and baseline.MinClearance
					<= DENSE_PROACTIVE_CLEARANCE
			)
			or (baseline.FarRisk or 0) >= FAR_ACTIVATION_RISK

		if not needPlan then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastEscapeOptions = 0
			LastEscapeTrendText = "-"
			LastMode = "HOLD"
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		local plan = planPath(root, humanoid, threats)

		if not plan then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastEscapeOptions = 0
			LastEscapeTrendText = "-"
			LastMode = "NO PLAN"
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		CurrentMove = plan.Direction
		CurrentPath = plan.Path
		LastMinClearance = plan.MinClearance
		LastEscapeOptions = plan.EscapeOptions
		if plan.EscapeTrend then
			local trendText = {}
			for i, value in ipairs(plan.EscapeTrend) do
				trendText[i] = tostring(value)
			end
			LastEscapeTrendText = table.concat(trendText, ">")
		else
			LastEscapeTrendText = "-"
		end

		if plan.Hits > 0 then
			LastMode = "RESCUE"
		elseif CurrentMove.Magnitude <= 0.01 then
			LastMode = "STOP"
		elseif baseline.Hits == 0
			and (baseline.FarRisk or 0) >= FAR_ACTIVATION_RISK
		then
			LastMode = "PREP"
		elseif (LastImmediateThreatCount + LastNearThreatCount)
			>= DENSE_THREAT_COUNT
		then
			LastMode = "DENSE"
		else
			LastMode = "DODGE"
		end

		updatePathVisual(CurrentPath)
		humanoid:Move(CurrentMove, false)
	end)

	LastPlanMs = (os.clock() - started) * 1000

	if not ok then
		LastError = tostring(err)
		LastMode = "ERROR"
	else
		LastError = ""
	end

	planning = false
end

RunService:BindToRenderStep(
	"AutoDodgePlanner",
	Enum.RenderPriority.Last.Value,
	function()
		if ENABLED then
			decisionStep()

			local _, humanoid = getCharacter()
			if humanoid then
				disableControls()
				humanoid:Move(CurrentMove, false)
			end
		else
			enableControls()
		end
	end
)

task.spawn(function()
	while Gui.Parent do
		if EnemyProj and EnemyProj.Parent then
			Status.Text =
				ENABLED
				and ("실행중 / " .. LastMode)
				or "준비됨"
			Status.TextColor3 =
				ENABLED
				and Color3.fromRGB(110, 225, 145)
				or Color3.fromRGB(165, 165, 175)
		else
			Status.Text = "EnemyProj 대기 중..."
			Status.TextColor3 =
				Color3.fromRGB(230, 190, 80)
		end

		Info.Text =
			"P "
			.. tostring(LastProjectileCount)
			.. " / I "
			.. tostring(LastImmediateThreatCount)
			.. " N "
			.. tostring(LastNearThreatCount)
			.. " F "
			.. tostring(LastFarThreatCount)
			.. " A "
			.. tostring(LastAreaThreatCount)
			.. "\nImpact "
			.. formatImpact(LastImpactTime)
			.. " / Clear "
			.. formatClearance(LastMinClearance)
			.. " / Far "
			.. string.format("%.1f", LastFarRisk)
			.. "\nEscape "
			.. tostring(LastEscapeOptions)
			.. " ["
			.. LastEscapeTrendText
			.. "] / "
			.. string.format("%.1fms", LastPlanMs)
			.. (
				LastError ~= ""
				and ("\n" .. string.sub(LastError, 1, 42))
				or ""
			)

		task.wait(0.10)
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	CurrentMove = Vector3.zero
	CurrentPath = nil
	LastImpactTime = math.huge
	LastMinClearance = math.huge
	LastEscapeOptions = 0
	clearPathVisual()
	task.wait(0.5)
	if ENABLED then
		disableControls()
	end
end)

bindEnemyProj(findEnemyProj())
bindHitboxFolder(findHitboxFolder())
