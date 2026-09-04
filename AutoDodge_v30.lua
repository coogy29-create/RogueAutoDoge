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

local V30 = {
	C = {
		-- Geometry-only projectile classification. Names are never used.
		GEOMETRY_REFRESH = 0.075,
		GEOMETRY_VELOCITY_SMOOTH = 0.46,
		GEOMETRY_YAW_SMOOTH = 0.32,

		CIRCLE_MAX_LONG_AXIS = 3.2,
		CAPSULE_MIN_ASPECT = 1.45,
		CAPSULE_MAX_LONG_AXIS = 6.0,
		OBB_MIN_SHORT_AXIS = 2.8,
		OBB_MIN_AREA = 13.0,
		OBB_FORCE_LONG_AXIS = 6.0,

		SHAPE_ERROR_MARGIN = 0.10,
		SHAPE_INFLUENCE = 1.45,
		SHAPE_NEAR_WEIGHT = 52,
		CAPSULE_SWEEP_SAMPLES = 5,

		CORNER_SOFT_DISTANCE = 5.5,
		CORNER_CRITICAL_DISTANCE = 2.2,
		CORNER_APPROACH_WEIGHT = 24,
		CORNER_CRITICAL_WEIGHT = 18,
		CORNER_OPEN_LOSS_WEIGHT = 8.5,
		CORNER_MIN_OPEN_LOSS_WEIGHT = 24,
		CORNER_CLOSE_RAY_EXTRA = 10,

		FAN_SAMPLE_TIME = 0.55,
		FAN_MAX_DISTANCE = 52,
		FAN_MAX_SPEED = 90,
		FAN_MIN_PROJECTILES = 9,
		FAN_MIN_APPROACH_DOT = -0.08,
		FAN_BINS = 72,
		FAN_MIN_ARC = 42,
		FAN_MAX_ARC = 235,
		FAN_GRACE = 0.20,
		FAN_SWITCH_ADVANTAGE = 0.18,
		FAN_AWAY_BLEND = 0.28,
		FAN_EDGE_MARGIN = 1.25,
		FAN_DIRECTION_WEIGHT = 14,
		FAN_PROGRESS_WEIGHT = 23,
		FAN_STOP_PENALTY = 20,
		FAN_PROGRESS_FRACTION = 0.31,
		FAN_COST_HORIZON = 1.05
	},
	State = {
		CircleThreats = 0,
		CapsuleThreats = 0,
		OBBThreats = 0,
		FanCount = 0,
		FanArc = 0,
		FanSide = "-",
		FanDirection = nil,
		FanGraceUntil = 0,
		FanEdgeTime = math.huge,
		FanClosingTime = math.huge
	}
}

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
local BARRIER_RAY_DISTANCE = 14
local BARRIER_RAY_COUNT = 12
local BARRIER_CLOSE_RAY_DISTANCE = 4.0
local BARRIER_CLOSE_RAY_PENALTY = 9

local EnemyProj = nil
local EnemyAddedConnection = nil
local EnemyRemovedConnection = nil
local ProjectileData = {}

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

function V30.getObjectBox(obj, part)
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

function V30.classifyGeometry(size)
	if not size then
		return "Circle"
	end

	local x = math.max(size.X, 0.05)
	local z = math.max(size.Z, 0.05)
	local longAxis = math.max(x, z)
	local shortAxis = math.min(x, z)
	local aspect = longAxis / shortAxis
	local area = x * z

	-- Large plates / zones / very long laser-like shapes use their oriented box.
	if shortAxis >= V30.C.OBB_MIN_SHORT_AXIS
		or area >= V30.C.OBB_MIN_AREA
		or longAxis >= V30.C.OBB_FORCE_LONG_AXIS
	then
		return "OBB"
	end

	-- Narrow elongated bullets use an oriented capsule.
	if aspect >= V30.C.CAPSULE_MIN_ASPECT
		and longAxis <= V30.C.CAPSULE_MAX_LONG_AXIS
	then
		return "Capsule"
	end

	return "Circle"
end

function V30.getGeometryRadius(size)
	if not size then
		return 0.5
	end

	return math.max(size.X, size.Z) * 0.5
end

function V30.getBroadRadius(size)
	if not size then
		return 0.5
	end

	local hx = size.X * 0.5
	local hz = size.Z * 0.5
	return math.sqrt(hx * hx + hz * hz)
end

function V30.getLongAxis(cf, size)
	if not cf or not size then
		return Vector3.new(1, 0, 0)
	end

	local axis

	if size.X >= size.Z then
		axis = flat(cf.RightVector)
	else
		axis = flat(-cf.LookVector)
	end

	if axis.Magnitude < 0.01 then
		return Vector3.new(1, 0, 0)
	end

	return axis.Unit
end

function V30.pointSegmentDistance2D(point, a, b)
	local p = flat(point)
	local aa = flat(a)
	local bb = flat(b)
	local d = bb - aa
	local denom = d:Dot(d)

	if denom <= 1e-8 then
		return (p - aa).Magnitude
	end

	local t =
		math.clamp(
			(p - aa):Dot(d) / denom,
			0,
			1
		)

	return (p - (aa + d * t)).Magnitude
end

function V30.pointBoxSignedDistance2D(boxCf, boxSize, point, expansion)
	if not boxCf or not boxSize then
		return math.huge
	end

	expansion = expansion or 0

	local p = boxCf:PointToObjectSpace(point)
	local hx = boxSize.X * 0.5 + expansion
	local hz = boxSize.Z * 0.5 + expansion
	local qx = math.abs(p.X) - hx
	local qz = math.abs(p.Z) - hz

	if qx <= 0 and qz <= 0 then
		return -math.min(-qx, -qz)
	end

	local ox = math.max(qx, 0)
	local oz = math.max(qz, 0)
	return math.sqrt(ox * ox + oz * oz)
end

function V30.getCapsuleSegment(cf, size, expansion)
	if not cf or not size then
		return nil, nil, 0
	end

	expansion = expansion or 0

	local longAxis = math.max(size.X, size.Z)
	local shortAxis = math.min(size.X, size.Z)
	local radius = shortAxis * 0.5 + expansion
	local halfSegment =
		math.max(
			0,
			longAxis * 0.5 - shortAxis * 0.5
		)

	local axis = V30.getLongAxis(cf, size)
	local center = cf.Position

	return
		center - axis * halfSegment,
		center + axis * halfSegment,
		radius
end

function V30.capsuleSignedDistance2D(cf, size, point, expansion)
	local a, b, radius =
		V30.getCapsuleSegment(
			cf,
			size,
			expansion
		)

	if not a then
		return math.huge
	end

	return
		V30.pointSegmentDistance2D(
			point,
			a,
			b
		) - radius
end

function V30.predictGeometryFrame(data, predictedPosition, t)
	local base = data.BoxCFrame

	if not base or not predictedPosition then
		return nil
	end

	local rotation =
		base - base.Position

	local yaw =
		(data.ShapeYawRate or 0) * t

	return
		CFrame.new(predictedPosition)
		* CFrame.Angles(0, yaw, 0)
		* rotation
end

function V30.refreshGeometryTracking(data, obj, part, dt)
	local now = os.clock()

	if now < (data.NextGeometryRefresh or 0) then
		return
	end

	data.NextGeometryRefresh =
		now + V30.C.GEOMETRY_REFRESH

	local boxCf, boxSize =
		V30.getObjectBox(obj, part)

	if not boxCf or not boxSize then
		return
	end

	local previousPosition =
		data.LastBoxPosition or boxCf.Position

	local previousAxis =
		data.ShapeAxis
			or V30.getLongAxis(boxCf, boxSize)

	local newAxis =
		V30.getLongAxis(boxCf, boxSize)

	if dt and dt > 0 then
		local rawVelocity =
			(boxCf.Position - previousPosition) / dt

		data.GeometryVelocity =
			(data.GeometryVelocity or rawVelocity):Lerp(
				rawVelocity,
				V30.C.GEOMETRY_VELOCITY_SMOOTH
			)

		if previousAxis.Magnitude > 0.01
			and newAxis.Magnitude > 0.01
		then
			local rawYaw =
				signedAngleXZ(
					previousAxis,
					newAxis
				) / dt

			rawYaw =
				math.clamp(
					rawYaw,
					-MAX_TURN_RATE,
					MAX_TURN_RATE
				)

			data.ShapeYawRate =
				(data.ShapeYawRate or rawYaw)
					+ (
						rawYaw
							- (data.ShapeYawRate or rawYaw)
					)
						* V30.C.GEOMETRY_YAW_SMOOTH
		end
	end

	data.BoxCFrame = boxCf
	data.BoxSize = boxSize
	data.ShapeType =
		V30.classifyGeometry(boxSize)
	data.ShapeRadius =
		V30.getGeometryRadius(boxSize)
	data.BroadRadius =
		V30.getBroadRadius(boxSize)
	data.ShapeAxis = newAxis
	data.LastBoxPosition = boxCf.Position
end

function V30.shapeSignedDistance(
	shapeType,
	cf,
	size,
	point,
	expansion
)
	if shapeType == "OBB" then
		return
			V30.pointBoxSignedDistance2D(
				cf,
				size,
				point,
				expansion
			)
	elseif shapeType == "Capsule" then
		return
			V30.capsuleSignedDistance2D(
				cf,
				size,
				point,
				expansion
			)
	end

	local radius =
		V30.getGeometryRadius(size)
			+ (expansion or 0)

	return
		(flat(point - cf.Position)).Magnitude
			- radius
end

function V30.evaluateCapsuleSweep(
	oldCf,
	newCf,
	size,
	oldPlayer,
	newPlayer,
	expansion
)
	if not oldCf or not newCf then
		return math.huge
	end

	local minimum = math.huge
	local samples =
		V30.C.CAPSULE_SWEEP_SAMPLES

	-- Continuous sweeps of several points along the capsule centerline.
	for sampleIndex = 0, samples - 1 do
		local alpha =
			samples == 1
				and 0.5
				or sampleIndex / (samples - 1)

		local oldA, oldB, radius =
			V30.getCapsuleSegment(
				oldCf,
				size,
				expansion
			)

		local newA, newB =
			V30.getCapsuleSegment(
				newCf,
				size,
				expansion
			)

		local oldPoint =
			oldA:Lerp(oldB, alpha)
		local newPoint =
			newA:Lerp(newB, alpha)

		local clearance =
			segmentMinDistance(
				oldPoint - oldPlayer,
				newPoint - newPlayer
			) - radius

		minimum =
			math.min(
				minimum,
				clearance
			)
	end

	-- Also sample the full capsule segment at mid-time. This fills any gap
	-- between the swept centerline samples when the projectile rotates.
	local middleCf =
		oldCf:Lerp(newCf, 0.5)

	local middlePlayer =
		oldPlayer:Lerp(newPlayer, 0.5)

	minimum =
		math.min(
			minimum,
			V30.capsuleSignedDistance2D(
				middleCf,
				size,
				middlePlayer,
				expansion
			)
		)

	return minimum
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

		local centerOffset =
			getProjectileCenterOffset(obj, part)

		local center =
			part.CFrame:PointToWorldSpace(
				centerOffset
			)

		local initialVelocity =
			part.AssemblyLinearVelocity

		local initialFlat =
			flat(initialVelocity)

		local boxCf, boxSize =
			V30.getObjectBox(obj, part)

		local shapeType =
			V30.classifyGeometry(boxSize)

		ProjectileData[obj] = {
			Object = obj,
			Part = part,
			CenterOffset = centerOffset,

			-- Legacy radius remains only as a fallback. Geometry fields below
			-- are the actual collision representation in v30.
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

			BoxCFrame = boxCf,
			BoxSize = boxSize,
			ShapeType = shapeType,
			ShapeRadius =
				V30.getGeometryRadius(boxSize),
			BroadRadius =
				V30.getBroadRadius(boxSize),
			ShapeAxis =
				V30.getLongAxis(boxCf, boxSize),
			ShapeYawRate = 0,
			GeometryVelocity = initialVelocity,
			LastBoxPosition =
				boxCf and boxCf.Position or center,
			NextGeometryRefresh = 0,

			Ready =
				boxCf ~= nil
				or initialFlat.Magnitude
					>= MIN_PROJECTILE_SPEED
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

local function pathHitsBarrier(a, b)
	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			if segmentIntersectsExpandedBarrier(
				barrier,
				a,
				b,
				BARRIER_BODY_RADIUS
			) then
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

function V30.directionBarrierClearance(origin, direction, maxDistance)
	local best = maxDistance

	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			local d =
				rayBarrierDistance2D(
					barrier,
					origin,
					direction,
					maxDistance
				)

			if d and d < best then
				best = d
			end
		end
	end

	return best
end

function V30.positionIndexNearTime(targetTime)
	local bestIndex = 1
	local bestDelta = math.huge

	for i = 1, TOTAL_PREDICTION_STEPS + 1 do
		local delta =
			math.abs(
				getPredictionTime(i) - targetTime
			)

		if delta < bestDelta then
			bestDelta = delta
			bestIndex = i
		end
	end

	return bestIndex
end

function V30.analyzeSlowFan(root, humanoid, threats)
	local sampleIndex =
		V30.positionIndexNearTime(
			V30.C.FAN_SAMPLE_TIME
		)

	local rootPosition = root.Position
	local rootVelocity =
		flat(root.AssemblyLinearVelocity)

	local futureRoot =
		rootPosition
			+ rootVelocity
				* math.min(
					V30.C.FAN_SAMPLE_TIME,
					0.20
				)

	local occupied =
		table.create(V30.C.FAN_BINS, false)

	local binAngle =
		math.pi * 2 / V30.C.FAN_BINS

	local count = 0
	local centroid = Vector3.zero
	local nearest = math.huge
	local closingSum = 0
	local speedSum = 0

	for _, threat in ipairs(threats) do
		if threat.ShapeType ~= "OBB"
			and threat.Positions
			and (threat.Speed or math.huge)
				<= V30.C.FAN_MAX_SPEED
		then
			local future =
				threat.Positions[sampleIndex]
			local current =
				threat.Positions[1]

			if future and current then
				local relative =
					flat(future - futureRoot)

				local currentRelative =
					flat(current - rootPosition)

				local distance = relative.Magnitude
				local velocity =
					flat(
						threat.Data
							and threat.Data.Velocity
							or Vector3.zero
					)

				local approach = 0
				local radialClosing = 0

				if velocity.Magnitude > 0.01
					and currentRelative.Magnitude > 0.01
				then
					approach =
						velocity.Unit:Dot(
							(-currentRelative).Unit
						)

					radialClosing =
						math.max(
							0,
							-velocity:Dot(
								currentRelative.Unit
							)
						)
				end

				if distance >= 0.8
					and distance
						<= V30.C.FAN_MAX_DISTANCE
					and approach
						>= V30.C.FAN_MIN_APPROACH_DOT
				then
					count += 1
					centroid += future
					nearest =
						math.min(nearest, distance)
					closingSum += radialClosing
					speedSum += threat.Speed or 0

					local angle =
						math.atan2(
							relative.Z,
							relative.X
						)

					local normalized =
						(angle + math.pi)
							/ (math.pi * 2)

					local centerBin =
						(
							math.floor(
								normalized
									* V30.C.FAN_BINS
							)
							% V30.C.FAN_BINS
						) + 1

					local angularRadius =
						math.asin(
							math.clamp(
								(
									(threat.DangerRadius or 0)
										+ 0.30
								)
									/ math.max(
										distance,
										0.5
									),
								0,
								0.98
							)
						)

					local halfBins =
						math.max(
							1,
							math.ceil(
								angularRadius
									/ binAngle
							)
						)

					for offset = -halfBins,
						halfBins
					do
						local bin =
							(
								(centerBin - 1 + offset)
									% V30.C.FAN_BINS
							) + 1

						occupied[bin] = true
					end
				end
			end
		end
	end

	if count < V30.C.FAN_MIN_PROJECTILES then
		if os.clock()
			<= V30.State.FanGraceUntil
			and V30.State.FanDirection
		then
			return {
				PreferredDirection =
					V30.State.FanDirection,
				Count = V30.State.FanCount,
				ArcDegrees = V30.State.FanArc,
				TimeToEdge =
					V30.State.FanEdgeTime,
				ClosingTime =
					V30.State.FanClosingTime
			}
		end

		V30.State.FanCount = 0
		V30.State.FanArc = 0
		V30.State.FanSide = "-"
		V30.State.FanDirection = nil
		return nil
	end

	local longest = 0
	local run = 0

	for i = 1, V30.C.FAN_BINS * 2 do
		local bin =
			((i - 1) % V30.C.FAN_BINS) + 1

		if occupied[bin] then
			run += 1
			longest =
				math.max(
					longest,
					math.min(
						run,
						V30.C.FAN_BINS
					)
				)
		else
			run = 0
		end
	end

	local arcDegrees =
		longest * 360 / V30.C.FAN_BINS

	if arcDegrees < V30.C.FAN_MIN_ARC
		or arcDegrees > V30.C.FAN_MAX_ARC
	then
		return nil
	end

	centroid /= count

	local toCenter =
		flat(centroid - futureRoot)

	if toCenter.Magnitude < 0.05 then
		return nil
	end

	local toward = toCenter.Unit
	local away = -toward
	local tangent =
		Vector3.new(
			-toward.Z,
			0,
			toward.X
		)

	local left =
		clampUnit(
			tangent
				+ away
					* V30.C.FAN_AWAY_BLEND
		)

	local right =
		clampUnit(
			-tangent
				+ away
					* V30.C.FAN_AWAY_BLEND
		)

	local centerDistance = toCenter.Magnitude
	local halfArc =
		math.rad(
			math.min(arcDegrees, 170) * 0.5
		)

	local lateralDistance =
		math.max(
			2.0,
			centerDistance * math.sin(halfArc)
				+ PLAYER_MINI_RADIUS
				+ V30.C.FAN_EDGE_MARGIN
		)

	local walkSpeed =
		math.max(humanoid.WalkSpeed, 1)

	local timeToEdge =
		lateralDistance / walkSpeed

	local averageClosing =
		closingSum / math.max(count, 1)

	local closingTime =
		averageClosing > 0.15
			and math.max(
				0,
				(
					nearest
						- PLAYER_MINI_RADIUS
						- V30.C.FAN_EDGE_MARGIN
				) / averageClosing
			)
			or math.huge

	local probe =
		math.min(
			BARRIER_RAY_DISTANCE,
			lateralDistance
				+ V30.C.FAN_EDGE_MARGIN
		)

	local leftOpen =
		V30.directionBarrierClearance(
			rootPosition,
			left,
			probe
		)

	local rightOpen =
		V30.directionBarrierClearance(
			rootPosition,
			right,
			probe
		)

	local leftBlocked =
		math.max(
			0,
			lateralDistance
				+ V30.C.FAN_EDGE_MARGIN
				- leftOpen
		)

	local rightBlocked =
		math.max(
			0,
			lateralDistance
				+ V30.C.FAN_EDGE_MARGIN
				- rightOpen
		)

	local leftScore =
		timeToEdge
			+ leftBlocked / walkSpeed * 2.8

	local rightScore =
		timeToEdge
			+ rightBlocked / walkSpeed * 2.8

	if CurrentMove.Magnitude > 0.01 then
		leftScore +=
			(1 - math.clamp(
				CurrentMove.Unit:Dot(left),
				-1,
				1
			)) * 0.07

		rightScore +=
			(1 - math.clamp(
				CurrentMove.Unit:Dot(right),
				-1,
				1
			)) * 0.07
	end

	local preferred =
		leftScore <= rightScore
			and left
			or right

	local side =
		leftScore <= rightScore
			and "L"
			or "R"

	-- Small hysteresis: do not swap flank on almost-equal scores.
	if V30.State.FanDirection
		and os.clock()
			<= V30.State.FanGraceUntil
	then
		local oldDirection =
			V30.State.FanDirection

		local oldIsLeft =
			oldDirection:Dot(left)
				>= oldDirection:Dot(right)

		local oldScore =
			oldIsLeft
				and leftScore
				or rightScore

		local newScore =
			side == "L"
				and leftScore
				or rightScore

		if newScore
			+ V30.C.FAN_SWITCH_ADVANTAGE
			>= oldScore
		then
			preferred = oldDirection
			side =
				oldIsLeft and "L" or "R"
		end
	end

	V30.State.FanCount = count
	V30.State.FanArc = arcDegrees
	V30.State.FanSide = side
	V30.State.FanDirection = preferred
	V30.State.FanGraceUntil =
		os.clock() + V30.C.FAN_GRACE
	V30.State.FanEdgeTime = timeToEdge
	V30.State.FanClosingTime = closingTime

	return {
		PreferredDirection = preferred,
		Count = count,
		ArcDegrees = arcDegrees,
		TimeToEdge = timeToEdge,
		ClosingTime = closingTime,
		Strength =
			math.clamp(
				count
					/ V30.C.FAN_MIN_PROJECTILES,
				1,
				2.2
			)
	}
end

function V30.fanCost(
	rootPosition,
	oldPosition,
	newPosition,
	direction,
	stepEndTime,
	walkSpeed,
	fanInfo
)
	if not fanInfo
		or not fanInfo.PreferredDirection
	then
		return 0
	end

	local preferred =
		fanInfo.PreferredDirection

	if preferred.Magnitude < 0.01 then
		return 0
	end

	local urgency = 1

	if fanInfo.ClosingTime ~= math.huge
		and fanInfo.TimeToEdge ~= math.huge
		and fanInfo.ClosingTime
			<= fanInfo.TimeToEdge + 0.35
	then
		urgency = 1.55
	end

	local timeWeight =
		1 - 0.35
			* math.clamp(
				stepEndTime
					/ V30.C.FAN_COST_HORIZON,
				0,
				1
			)

	local cost = 0

	if direction.Magnitude <= 0.01 then
		cost += V30.C.FAN_STOP_PENALTY
	else
		local dot =
			math.clamp(
				direction.Unit:Dot(preferred.Unit),
				-1,
				1
			)

		cost +=
			(1 - dot)
				* V30.C.FAN_DIRECTION_WEIGHT

		if dot < 0 then
			cost += (-dot) * 18
		end
	end

	local progress =
		flat(newPosition - rootPosition)
			:Dot(preferred.Unit)

	local required =
		walkSpeed
			* math.min(stepEndTime, 0.85)
			* V30.C.FAN_PROGRESS_FRACTION

	if progress < required then
		cost +=
			(required - progress)
				* V30.C.FAN_PROGRESS_WEIGHT
	end

	return cost
		* urgency
		* timeWeight
		* (fanInfo.Strength or 1)
end

function V30.cornerStepCost(
	oldClearance,
	newClearance
)
	if oldClearance == math.huge
		or newClearance == math.huge
	then
		return 0
	end

	local cost = 0

	if newClearance < oldClearance
		and newClearance
			< V30.C.CORNER_SOFT_DISTANCE
	then
		local approach =
			oldClearance - newClearance

		local nearFactor =
			1
				+ math.max(
					0,
					V30.C.CORNER_SOFT_DISTANCE
						- newClearance
				)
					/ V30.C.CORNER_SOFT_DISTANCE

		cost +=
			approach
				* V30.C.CORNER_APPROACH_WEIGHT
				* nearFactor
	end

	if newClearance
		< V30.C.CORNER_CRITICAL_DISTANCE
	then
		local depth =
			V30.C.CORNER_CRITICAL_DISTANCE
				- newClearance

		cost +=
			depth * depth
				* V30.C.CORNER_CRITICAL_WEIGHT
	end

	return cost
end

function V30.cornerFinalCost(
	rootAverage,
	rootMinimum,
	averageOpen,
	minimumOpen,
	closeRays
)
	local cost = 0

	if averageOpen < rootAverage then
		cost +=
			(rootAverage - averageOpen)
				* V30.C.CORNER_OPEN_LOSS_WEIGHT
	end

	if minimumOpen < rootMinimum then
		cost +=
			(rootMinimum - minimumOpen)
				* V30.C.CORNER_MIN_OPEN_LOSS_WEIGHT
	end

	cost +=
		closeRays
			* V30.C.CORNER_CLOSE_RAY_EXTRA

	return cost
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
			data.Samples = 0
			V30.refreshGeometryTracking(data, obj, part, dt)
			data.Ready = data.BoxCFrame ~= nil
			continue
		end

		count += 1

		local position = getProjectileCenter(data)

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

		data.PreviousPosition = data.LastPosition
		data.LastPosition = position
		data.LastRawVelocity = data.RawVelocity
		data.RawVelocity = rawVelocity
		data.Samples += 1

		V30.refreshGeometryTracking(
			data,
			obj,
			part,
			dt
		)

		data.Ready =
			data.BoxCFrame ~= nil
			or (
				data.Samples >= 2
				and flat(data.Velocity).Magnitude
					>= MIN_PROJECTILE_SPEED
			)

		data.PredictedNext = predictTrackerNext(data, dt)
	end

	LastProjectileCount = count
end)

task.spawn(function()
	while true do
		local folder = findEnemyProj()
		if folder ~= EnemyProj then
			bindEnemyProj(folder)
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
	local position =
		getProjectileCenter(data)

	local distance =
		flat(position - rootPosition).Magnitude

	local speed =
		flat(data.Velocity).Magnitude

	local t =
		PLAN_HORIZON + networkLead

	local horizontalTravel =
		speed * t
		+ 0.5
			* math.abs(data.SpeedAccel or 0)
			* t * t

	local shapeRadius =
		data.BroadRadius
			or data.ShapeRadius
			or data.Radius
			or 0

	local reach =
		shapeRadius
		+ PLAYER_MINI_RADIUS
		+ MAX_ERROR_MARGIN
		+ NEAR_ZONE
		+ maxPlayerReach
		+ horizontalTravel
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

local function buildThreatSnapshot(root, humanoid)
	local threats = {}
	local byStep =
		table.create(TOTAL_PREDICTION_STEPS)
	local farField =
		table.create(TOTAL_PREDICTION_STEPS)

	for i = 1, TOTAL_PREDICTION_STEPS do
		byStep[i] = {}
		farField[i] = {}
	end

	local networkLead =
		getNetworkLead()

	local rootFlatSpeed =
		flat(
			root.AssemblyLinearVelocity
		).Magnitude

	local maxPlayerReach =
		humanoid.WalkSpeed * PLAN_HORIZON
		+ rootFlatSpeed * 0.15

	local immediateCount = 0
	local nearCount = 0
	local farCount = 0

	local circleCount = 0
	local capsuleCount = 0
	local obbCount = 0

	for _, data in pairs(ProjectileData) do
		local speed =
			flat(
				data.Velocity
					or Vector3.zero
			).Magnitude

		if data.Ready
			and data.Part
			and data.Part.Parent
			and projectileCanReachEnvelope(
				data,
				root.Position,
				maxPlayerReach,
				networkLead
			)
		then
			local positions =
				simulateProjectilePositions(
					data,
					networkLead
				)

			local shapeType =
				data.ShapeType or "Circle"

			local errorMargin =
				math.clamp(
					BASE_ERROR_MARGIN
						+ (data.PredictionError or 0)
							* PREDICTION_ERROR_WEIGHT
						+ speed
							* SPEED_MARGIN_WEIGHT
						+ math.abs(
							data.TurnRate or 0
						) * TURN_MARGIN_WEIGHT,
					BASE_ERROR_MARGIN,
					MAX_ERROR_MARGIN
				)

			local threat = {
				Data = data,
				Positions = positions,
				ShapeType = shapeType,
				BoxSize = data.BoxSize,
				Frames = nil,
				ErrorMargin = errorMargin,
				Speed = speed,
				Tier = "Far",
				EarliestRelevantTime =
					math.huge
			}

			if shapeType == "Circle" then
				threat.DangerRadius =
					(data.ShapeRadius
						or data.Radius
						or 0)
					+ PLAYER_MINI_RADIUS
					+ errorMargin

				circleCount += 1
			else
				local frames =
					table.create(
						TOTAL_PREDICTION_STEPS + 1
					)

				for positionIndex = 1,
					TOTAL_PREDICTION_STEPS + 1
				do
					local t =
						networkLead
							+ getPredictionTime(
								positionIndex
							)

					frames[positionIndex] =
						V30.predictGeometryFrame(
							data,
							positions[positionIndex],
							t
						)
				end

				threat.Frames = frames
				threat.DangerRadius =
					(data.BroadRadius or 0)
						+ PLAYER_MINI_RADIUS
						+ errorMargin

				if shapeType == "Capsule" then
					capsuleCount += 1
				else
					obbCount += 1
				end
			end

			local canMatter = false

			for stepIndex = 1,
				TOTAL_PREDICTION_STEPS
			do
				local t =
					getStepEndTime(stepIndex)

				local reachable =
					humanoid.WalkSpeed * t
					+ rootFlatSpeed
						* math.min(t, 0.18)

				local stationaryClearance =
					math.huge

				if shapeType == "Circle" then
					local p0 =
						positions[stepIndex]
					local p1 =
						positions[stepIndex + 1]

					if p0 and p1 then
						stationaryClearance =
							segmentMinDistance(
								p0 - root.Position,
								p1 - root.Position
							)
								- threat.DangerRadius
					end
				else
					local frame =
						threat.Frames[
							stepIndex + 1
						]

					if frame then
						stationaryClearance =
							V30.shapeSignedDistance(
								shapeType,
								frame,
								threat.BoxSize,
								root.Position,
								PLAYER_MINI_RADIUS
									+ errorMargin
							)
					end
				end

				if stationaryClearance
					<= NEAR_ZONE
						+ reachable
						+ 0.75
				then
					canMatter = true

					threat.EarliestRelevantTime =
						math.min(
							threat.EarliestRelevantTime,
							t
						)

					-- Geometry shapes stay exact for the full horizon.
					-- Circles preserve v4's far-field compression.
					if shapeType ~= "Circle"
						or t
							<= EXACT_THREAT_HORIZON
					then
						local bucket =
							byStep[stepIndex]

						bucket[#bucket + 1] =
							threat
					else
						addFarFieldSample(
							farField[stepIndex],
							positions[
								stepIndex + 1
							],
							threat.DangerRadius
						)
					end
				end
			end

			if canMatter then
				if threat.EarliestRelevantTime
					<= IMMEDIATE_THREAT_HORIZON
				then
					threat.Tier = "Immediate"
					immediateCount += 1
				elseif threat.EarliestRelevantTime
					<= EXACT_THREAT_HORIZON
				then
					threat.Tier = "Near"
					nearCount += 1
				else
					threat.Tier = "Far"
					farCount += 1
				end

				threats[#threats + 1] =
					threat
			end
		end
	end

	threats.ByStep = byStep
	threats.FarField = farField

	LastThreatCount = #threats
	LastImmediateThreatCount = immediateCount
	LastNearThreatCount = nearCount
	LastFarThreatCount = farCount

	V30.State.CircleThreats = circleCount
	V30.State.CapsuleThreats = capsuleCount
	V30.State.OBBThreats = obbCount

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
		(threats.ByStep
			and threats.ByStep[stepIndex])
		or threats

	for _, threat in ipairs(activeThreats) do
		local clearance = math.huge

		if threat.ShapeType == "Circle" then
			local oldProjectile =
				threat.Positions[stepIndex]

			local newProjectile =
				threat.Positions[stepIndex + 1]

			if oldProjectile
				and newProjectile
			then
				clearance =
					segmentMinDistance(
						oldProjectile
							- oldPlayerPosition,
						newProjectile
							- newPlayerPosition
					)
						- threat.DangerRadius
			end

		elseif threat.ShapeType == "Capsule" then
			local oldCf =
				threat.Frames
					and threat.Frames[stepIndex]

			local newCf =
				threat.Frames
					and threat.Frames[
						stepIndex + 1
					]

			if oldCf and newCf then
				clearance =
					V30.evaluateCapsuleSweep(
						oldCf,
						newCf,
						threat.BoxSize,
						oldPlayerPosition,
						newPlayerPosition,
						PLAYER_MINI_RADIUS
							+ threat.ErrorMargin
					)
			end

		else
			local oldCf =
				threat.Frames
					and threat.Frames[stepIndex]

			local newCf =
				threat.Frames
					and threat.Frames[
						stepIndex + 1
					]

			if oldCf and newCf then
				local middleCf =
					oldCf:Lerp(newCf, 0.5)

				local middlePlayer =
					oldPlayerPosition:Lerp(
						newPlayerPosition,
						0.5
					)

				local expansion =
					PLAYER_MINI_RADIUS
						+ threat.ErrorMargin

				clearance =
					math.min(
						V30.pointBoxSignedDistance2D(
							oldCf,
							threat.BoxSize,
							oldPlayerPosition,
							expansion
						),
						V30.pointBoxSignedDistance2D(
							middleCf,
							threat.BoxSize,
							middlePlayer,
							expansion
						),
						V30.pointBoxSignedDistance2D(
							newCf,
							threat.BoxSize,
							newPlayerPosition,
							expansion
						)
					)
			end
		end

		minClearance =
			math.min(
				minClearance,
				clearance
			)

		if clearance <= 0 then
			hits += 1

			local penetration =
				math.min(
					-clearance,
					4
				)

			risk +=
				HIT_PENALTY
					+ penetration * 10000
					+ threat.Speed * 4

		elseif clearance < NEAR_ZONE then
			local near =
				1 - clearance / NEAR_ZONE

			local timeFactor =
				1.0
					+ (
						1 - math.clamp(
							getStepStartTime(
								stepIndex
							) / PLAN_HORIZON,
							0,
							1
						)
					) * 0.8

			local shapeWeight =
				threat.ShapeType == "Circle"
					and 1.0
					or 1.18

			risk +=
				near * near
					* NEAR_RISK_WEIGHT
					* timeFactor
					* shapeWeight
		end
	end

	local farRisk =
		evaluateFarField(
			newPlayerPosition,
			stepIndex,
			threats
		)

	risk += farRisk

	return
		risk,
		hits,
		minClearance,
		farRisk
end

local function evaluateBarrierSegment(oldPosition, newPosition)
	if pathHitsBarrier(oldPosition, newPosition) then
		return WALL_HIT_PENALTY, true, 0
	end

	local clearance = nearestBarrierDistance(newPosition)
	local risk = 0

	if clearance < BARRIER_NEAR_DISTANCE then
		local near =
			1 - math.clamp(
				clearance / BARRIER_NEAR_DISTANCE,
				0,
				1
			)
		risk =
			near * near
			* BARRIER_NEAR_WEIGHT
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

local function planPath(root, humanoid, threats, fanInfo)
	local beamWidth =
		getAdaptiveBeamWidth(
			LastImmediateThreatCount + LastNearThreatCount
		)

	local rootVelocity = flat(root.AssemblyLinearVelocity)
	local rootBarrierClearance =
		nearestBarrierDistance(root.Position)
	local rootAverageOpen, rootMinimumOpen =
		barrierOpenness(root.Position)

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
			BarrierClearance = rootBarrierClearance,
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

			if depth == 1
				and fanInfo
				and fanInfo.PreferredDirection
			then
				local augmented = {}
				for _, value in ipairs(inputs) do
					augmented[#augmented + 1] = value
				end
				augmented[#augmented + 1] =
					fanInfo.PreferredDirection
				inputs = augmented
			end

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

				local barrierRisk,
					wallHit,
					barrierClearance =
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

				local cornerCost =
					V30.cornerStepCost(
						node.BarrierClearance,
						barrierClearance
					)

				local fanCost =
					V30.fanCost(
						root.Position,
						node.Pos,
						newPosition,
						direction,
						getStepEndTime(depth),
						humanoid.WalkSpeed,
						fanInfo
					)

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
						+ moveCost
						+ cornerCost
						+ fanCost,
					Hits = node.Hits + stepHits,
					WallHits =
						node.WallHits
						+ (wallHit and 1 or 0),
					MinClearance =
						math.min(
							node.MinClearance,
							stepClearance
						),
					BarrierClearance =
						barrierClearance,
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

		trapCost +=
			V30.cornerFinalCost(
				rootAverageOpen,
				rootMinimumOpen,
				averageOpen,
				minimumOpen,
				closeRays
			)

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
Main.Size = UDim2.fromOffset(260, 294)
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
Title.Text = "AUTO DODGE V30"
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
Info.Size = UDim2.new(1, -20, 0, 82)
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
Toggle.Position = UDim2.fromOffset(10, 140)
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
RadiusLabel.Position = UDim2.fromOffset(42, 185)
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
Minus.Position = UDim2.fromOffset(10, 185)
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
Plus.Position = UDim2.new(1, -38, 0, 185)
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
PathToggle.Position = UDim2.fromOffset(10, 226)
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
Footer.Position = UDim2.fromOffset(10, 265)
Footer.BackgroundTransparency = 1
Footer.Text = "v30 / V4 Brain / Geometry Hybrid + AntiCorner + Fan"
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
			V30.State.CircleThreats = 0
			V30.State.CapsuleThreats = 0
			V30.State.OBBThreats = 0
			V30.State.FanCount = 0
			V30.State.FanArc = 0
			V30.State.FanSide = "-"
			V30.State.FanDirection = nil
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

		local fanInfo =
			V30.analyzeSlowFan(
				root,
				humanoid,
				threats
			)

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
			or fanInfo ~= nil

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

		local plan =
			planPath(
				root,
				humanoid,
				threats,
				fanInfo
			)

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

		if fanInfo then
			LastMode = "FAN FLANK"
		elseif plan.Hits > 0 then
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
			.. "\nGeo C"
			.. tostring(V30.State.CircleThreats)
			.. " K"
			.. tostring(V30.State.CapsuleThreats)
			.. " B"
			.. tostring(V30.State.OBBThreats)
			.. "\nFan "
			.. tostring(V30.State.FanCount)
			.. " / "
			.. string.format(
				"%.0fdeg",
				V30.State.FanArc
			)
			.. " "
			.. V30.State.FanSide
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
