local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ENABLED = false
local SHOW_PATH = true
local GRAZE_MODE = false

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
local TURN_ACCEL_SMOOTH = 0.26
local MAX_TURN_ACCEL = math.rad(22000)
local WAVE_TURN_DEADBAND = math.rad(14)
local WAVE_MIN_MEAN_TURN = math.rad(26)
local WAVE_MIN_HALF_PERIOD = 0.075
local WAVE_MAX_HALF_PERIOD = 0.72
local WAVE_HALF_PERIOD_SMOOTH = 0.42
local WAVE_CONFIDENCE_ON = 0.58
local WAVE_CONFIDENCE_OFF = 0.42
local WAVE_MAX_CROSSINGS = 5
local WAVE_MAX_RATE = math.rad(1080)
local WAVE_MAX_PREDICTION_TIME = 1.35
local CURVE_TURN_THRESHOLD = math.rad(12)
local WAVE_EXTRA_MARGIN = 0.075

local V41 = {
	C = {
		CORNER_MIN_OPEN = 3.4,
		CORNER_CLOSE_RAYS = 3,
		CORNER_RELEASE_OPEN = 5.3,
		CORNER_EXIT_MIN_CLEARANCE = 2.2,
		CORNER_PROBE_DISTANCE = 14.0,
		CORNER_PROBE_DIRECTIONS = 16,
		CORNER_SIDE_PROBE_ANGLE = math.rad(22.5),
		CORNER_PROGRESS_REWARD = 8.0,
		CORNER_OPPOSITE_PENALTY = 18.0,
		CORNER_FINAL_REWARD = 18.0,

		SHIELD_RADIUS = 5.0,
		SHIELD_DURATION = 2.05,
		SHIELD_COOLDOWN = 30.0,
		SHIELD_ACTIVATION_DELAY = 0.10,
		SHIELD_PRESS_TIME = 0.05,
		SHIELD_REQUIRED_CHARGE = 2,
		SHIELD_TRIGGER_IMPACT = 0.60,
		SHIELD_MIN_REMOVED = 1,
		SHIELD_PLAN_HOLD = 0.12,

		FINE_STEER_END = 0.55,
		DIVERSITY_START_DEPTH = 4,
		DIVERSITY_SECTORS = 8,
		DIVERSITY_RESERVE = 6,
		DIVERSITY_COST_SLACK = 10.0,
		ROBUST_COST_EPSILON = 3.5,
		ROBUST_NEAR_CLEARANCE = 0.55,
		ROBUST_CURRENT_MOVE_EPSILON = 2.0,

		GRAZE_TARGET_CLEARANCE = 0.12,
		GRAZE_MAX_CLEARANCE = 0.50,
		GRAZE_HARD_FLOOR = 0.045,
		GRAZE_REWARD = 22.0,
		GRAZE_TOO_CLOSE_PENALTY = 34.0,
		GRAZE_EARLY_WEIGHT = 0.30
	},
	State = {
		CornerActive = false,
		CornerDirection = nil,

		ShieldPart = nil,
		ShieldCenter = nil,
		ShieldUntil = 0,
		ShieldLastUse = -math.huge,
		ShieldPlanHoldUntil = 0,
		ShieldUseCount = 0,
		ShieldLastRemoved = 0,
		ShieldLastDecision = "IDLE",
		ShieldSimMs = 0,

		DiversityInjected = 0,
		NearMissBest = 0,
		FineSteerActive = false,

		GrazeScoreBest = 0,
		GrazePlanning = false,

		WallConstraintState = "FREE",
		WallConstraintCount = 0,
		WallConstraintClearance = math.huge,

		TrajectoryStraight = 0,
		TrajectoryCurve = 0,
		TrajectoryWave = 0
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

local BARRIER_BODY_RADIUS = 1.20
local BARRIER_EXECUTION_RADIUS = 1.34
local BARRIER_EXECUTION_LOOKAHEAD = 0.12
local BARRIER_ESCAPE_EPSILON = 0.025
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
			TurnAccel = 0,
			LastRawTurnRate = 0,
			TurnSignState = 0,
			TurnCrossings = {},
			WaveHalfPeriod = 0,
			WaveConfidence = 0,
			MotionClass = "STRAIGHT",
			PredictionError = 0,
			PredictedNext = nil,
			Samples = 0,
			Ready = initialFlat.Magnitude >= MIN_PROJECTILE_SPEED
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

local function barrierMotionUnsafe(
	a,
	b,
	expansion
)
	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			if segmentIntersectsExpandedBarrier(
				barrier,
				a,
				b,
				expansion
			) then
				local currentDistance =
					pointBarrierDistance2D(
						barrier,
						a
					)

				local nextDistance =
					pointBarrierDistance2D(
						barrier,
						b
					)

				if currentDistance <= expansion then
					if nextDistance
						+ BARRIER_ESCAPE_EPSILON
						< currentDistance
					then
						return true
					end
				else
					return true
				end
			end
		end
	end

	return false
end

local function minimumBarrierSurfaceDistance(position)
	local best = math.huge

	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			best =
				math.min(
					best,
					pointBarrierDistance2D(
						barrier,
						position
					)
				)
		end
	end

	return best
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

function V41.directionOpenDistance(position, direction)
	local nearest = V41.C.CORNER_PROBE_DISTANCE

	for _, barrier in ipairs(getBarrierList()) do
		if barrier and barrier.Parent then
			local d =
				rayBarrierDistance2D(
					barrier,
					position,
					direction,
					V41.C.CORNER_PROBE_DISTANCE
				)

			if d and d < nearest then
				nearest = d
			end
		end
	end

	return nearest
end

function V41.bestCornerExit(position)
	local bestDirection = nil
	local bestScore = -math.huge

	for i = 0, V41.C.CORNER_PROBE_DIRECTIONS - 1 do
		local angle =
			i * math.pi * 2
				/ V41.C.CORNER_PROBE_DIRECTIONS

		local direction =
			Vector3.new(
				math.cos(angle),
				0,
				math.sin(angle)
			)

		local center =
			V41.directionOpenDistance(
				position,
				direction
			)

		local left =
			V41.directionOpenDistance(
				position,
				rotateY(
					direction,
					V41.C.CORNER_SIDE_PROBE_ANGLE
				)
			)

		local right =
			V41.directionOpenDistance(
				position,
				rotateY(
					direction,
					-V41.C.CORNER_SIDE_PROBE_ANGLE
				)
			)

		-- Prefer a genuinely wide channel, not one lucky thin ray.
		local score =
			center * 1.0
				+ math.min(left, right) * 0.55
				+ (left + right) * 0.12

		if CurrentMove.Magnitude > 0.01 then
			score +=
				math.max(
					0,
					CurrentMove.Unit:Dot(direction)
				) * 0.25
		end

		if score > bestScore then
			bestScore = score
			bestDirection = direction
		end
	end

	return bestDirection
end

function V41.updateCornerObjective(position)
	local _, minimumOpen, closeRays =
		barrierOpenness(position)

	-- Once we have actually left the corner, release the objective.
	if minimumOpen >= V41.C.CORNER_RELEASE_OPEN
		and closeRays < V41.C.CORNER_CLOSE_RAYS
	then
		V41.State.CornerActive = false
		V41.State.CornerDirection = nil
		return nil
	end

	local trapped =
		minimumOpen < V41.C.CORNER_MIN_OPEN
		and closeRays >= V41.C.CORNER_CLOSE_RAYS

	-- Critical anti-wiggle behavior:
	-- keep the SAME exit direction as long as that channel still exists.
	if V41.State.CornerActive
		and V41.State.CornerDirection
	then
		local clearance =
			V41.directionOpenDistance(
				position,
				V41.State.CornerDirection
			)

		if clearance
			>= V41.C.CORNER_EXIT_MIN_CLEARANCE
		then
			return V41.State.CornerDirection
		end

		-- Chosen exit became physically blocked; only now may it switch.
		V41.State.CornerDirection = nil
	end

	if not trapped then
		return nil
	end

	local direction =
		V41.bestCornerExit(position)

	if direction then
		V41.State.CornerActive = true
		V41.State.CornerDirection = direction
	end

	return direction
end

function V41.cornerRouteCost(
	oldPosition,
	newPosition,
	direction,
	cornerDirection
)
	if not cornerDirection then
		return 0
	end

	local progress =
		flat(newPosition - oldPosition)
			:Dot(cornerDirection)

	local cost =
		-progress
			* V41.C.CORNER_PROGRESS_REWARD

	if direction.Magnitude > 0.01 then
		local dot =
			direction.Unit:Dot(cornerDirection)

		if dot < 0 then
			cost +=
				(-dot)
					* V41.C.CORNER_OPPOSITE_PENALTY
		end
	end

	return cost
end


local function pushTurnCrossing(data, now)
	local list = data.TurnCrossings
	if not list then
		list = {}
		data.TurnCrossings = list
	end

	list[#list + 1] = now

	while #list > WAVE_MAX_CROSSINGS do
		table.remove(list, 1)
	end
end

local function estimateWaveHalfPeriod(data)
	local list = data.TurnCrossings
	if not list or #list < 2 then
		return nil, 0
	end

	local intervals = {}

	for i = 2, #list do
		local d = list[i] - list[i - 1]
		if d >= WAVE_MIN_HALF_PERIOD
			and d <= WAVE_MAX_HALF_PERIOD
		then
			intervals[#intervals + 1] = d
		end
	end

	if #intervals == 0 then
		return nil, 0
	end

	table.sort(intervals)
	local median =
		intervals[
			math.floor((#intervals + 1) * 0.5)
		]

	local deviation = 0
	for _, d in ipairs(intervals) do
		deviation += math.abs(d - median)
	end
	deviation /= #intervals

	local consistency =
		1 - math.clamp(
			deviation / math.max(median * 0.45, 0.001),
			0,
			1
		)

	return median, consistency
end

local function updateMotionClass(data, rawTurn, dt, now)
	local previous =
		data.TurnSignState or 0
	local nextState = previous

	if rawTurn >= WAVE_TURN_DEADBAND then
		nextState = 1
	elseif rawTurn <= -WAVE_TURN_DEADBAND then
		nextState = -1
	end

	if previous ~= 0
		and nextState ~= 0
		and previous ~= nextState
	then
		pushTurnCrossing(data, now)
	end

	data.TurnSignState = nextState

	local halfPeriod, consistency =
		estimateWaveHalfPeriod(data)

	if halfPeriod then
		if (data.WaveHalfPeriod or 0) <= 0 then
			data.WaveHalfPeriod = halfPeriod
		else
			data.WaveHalfPeriod +=
				(halfPeriod - data.WaveHalfPeriod)
					* WAVE_HALF_PERIOD_SMOOTH
		end
	end

	local crossingCount =
		data.TurnCrossings
			and #data.TurnCrossings
			or 0

	local amplitudeScore =
		math.clamp(
			math.abs(data.TurnRate or 0)
				/ math.max(WAVE_MIN_MEAN_TURN, 0.001),
			0,
			1
		)

	local crossingScore =
		math.clamp(
			(crossingCount - 1) / 2,
			0,
			1
		)

	local confidence =
		0.48 * consistency
			+ 0.34 * crossingScore
			+ 0.18 * amplitudeScore

	if crossingCount < 2 then
		confidence *= 0.30
	end

	data.WaveConfidence +=
		(confidence - (data.WaveConfidence or 0))
			* math.clamp(dt * 8, 0, 1)

	if data.MotionClass == "WAVE" then
		if data.WaveConfidence >= WAVE_CONFIDENCE_OFF
			and (data.WaveHalfPeriod or 0) > 0
		then
			return
		end
	elseif data.WaveConfidence >= WAVE_CONFIDENCE_ON
		and (data.WaveHalfPeriod or 0) > 0
	then
		data.MotionClass = "WAVE"
		return
	end

	if math.abs(data.TurnRate or 0)
		>= CURVE_TURN_THRESHOLD
	then
		data.MotionClass = "CURVE"
	else
		data.MotionClass = "STRAIGHT"
	end
end

local function getWaveTurnRateAt(data, t)
	local r0 =
		math.clamp(
			data.TurnRate or 0,
			-WAVE_MAX_RATE,
			WAVE_MAX_RATE
		)

	local halfPeriod = data.WaveHalfPeriod or 0
	if halfPeriod <= 0 then
		return r0
	end

	local omega = math.pi / halfPeriod
	local a0 =
		math.clamp(
			data.TurnAccel or 0,
			-MAX_TURN_ACCEL,
			MAX_TURN_ACCEL
		)

	local rate =
		r0 * math.cos(omega * t)
			+ (a0 / omega)
				* math.sin(omega * t)

	return math.clamp(
		rate,
		-WAVE_MAX_RATE,
		WAVE_MAX_RATE
	)
end

local function predictTrackerNext(data, dt)
	local flatVelocity = flat(data.Velocity)
	local speed = flatVelocity.Magnitude
	local direction =
		speed > 0.01
			and flatVelocity.Unit
			or Vector3.zero

	local turnRate = data.TurnRate or 0

	if data.MotionClass == "WAVE" then
		turnRate =
			0.5
				* (
					getWaveTurnRateAt(data, 0)
					+ getWaveTurnRateAt(data, dt)
				)
	end

	if direction.Magnitude > 0.01
		and math.abs(turnRate) > 0.001
	then
		direction =
			rotateY(direction, turnRate * dt)
	end

	speed =
		math.max(
			0,
			speed + data.SpeedAccel * dt
		)

	local vy =
		data.Velocity.Y
			+ data.VerticalAccel * dt

	return
		data.LastPosition
			+ (
				direction * speed
				+ Vector3.new(0, vy, 0)
			) * dt
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
			data.Ready = false
			data.TurnRate = 0
			data.TurnAccel = 0
			data.LastRawTurnRate = 0
			data.TurnSignState = 0
			data.TurnCrossings = {}
			data.WaveHalfPeriod = 0
			data.WaveConfidence = 0
			data.MotionClass = "STRAIGHT"
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

		if oldSpeed >= MIN_PROJECTILE_SPEED
			and newSpeed >= MIN_PROJECTILE_SPEED
		then
			local rawTurn =
				signedAngleXZ(oldFlat, newFlat) / dt

			rawTurn =
				math.clamp(
					rawTurn,
					-MAX_TURN_RATE,
					MAX_TURN_RATE
				)

			local oldRawTurn =
				data.LastRawTurnRate or rawTurn

			local rawTurnAccel =
				(rawTurn - oldRawTurn) / dt

			rawTurnAccel =
				math.clamp(
					rawTurnAccel,
					-MAX_TURN_ACCEL,
					MAX_TURN_ACCEL
				)

			data.TurnAccel +=
				(
					rawTurnAccel
						- (data.TurnAccel or 0)
				) * TURN_ACCEL_SMOOTH

			data.TurnRate +=
				(rawTurn - data.TurnRate)
					* TURN_SMOOTH

			updateMotionClass(
				data,
				rawTurn,
				dt,
				os.clock()
			)

			data.LastRawTurnRate = rawTurn

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
		data.Ready =
			data.Samples >= 2
			and flat(data.Velocity).Magnitude >= MIN_PROJECTILE_SPEED

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
	local positions =
		table.create(
			TOTAL_PREDICTION_STEPS + 1
		)

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

	local useWave =
		data.MotionClass == "WAVE"
			and (data.WaveHalfPeriod or 0) > 0

	local useAnalytic =
		not useWave
		and math.abs(turnRate) <= ANALYTIC_TURN_RATE
		and math.abs(speedAccel) <= ANALYTIC_SPEED_ACCEL
		and math.abs(verticalAccel) <= ANALYTIC_VERTICAL_ACCEL

	if useAnalytic then
		for positionIndex = 1, TOTAL_PREDICTION_STEPS + 1 do
			local t =
				networkLead
					+ getPredictionTime(positionIndex)

			local travel =
				analyticTravelDistance(
					speed,
					speedAccel,
					t
				)

			positions[positionIndex] =
				Vector3.new(
					origin.X + direction.X * travel,
					origin.Y
						+ vy * t
						+ 0.5 * verticalAccel * t * t,
					origin.Z + direction.Z * travel
				)
		end

		return positions
	end

	local position = origin
	local currentTime = 0
	local adaptiveStep

	if useWave then
		adaptiveStep =
			math.clamp(
				(data.WaveHalfPeriod or 0.2) / 7,
				0.010,
				0.045
			)
	else
		adaptiveStep =
			math.clamp(
				math.rad(7)
					/ math.max(
						math.abs(turnRate),
						0.001
					),
				0.014,
				0.10
			)

		adaptiveStep =
			math.min(
				adaptiveStep,
				PROJECTILE_SIM_DT * 1.6
			)
	end

	local function advanceTo(targetTime)
		while currentTime + 1e-6 < targetTime do
			local step =
				math.min(
					adaptiveStep,
					targetTime - currentTime
				)

			local appliedTurn = turnRate

			if useWave
				and currentTime <= WAVE_MAX_PREDICTION_TIME
			then
				appliedTurn =
					0.5
						* (
							getWaveTurnRateAt(
								data,
								currentTime
							)
							+ getWaveTurnRateAt(
								data,
								currentTime + step
							)
						)
			end

			if math.abs(appliedTurn) > 0.001 then
				direction =
					rotateY(
						direction,
						appliedTurn * step
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
			networkLead
				+ getPredictionTime(positionIndex)

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
	local byStep = table.create(TOTAL_PREDICTION_STEPS)
	local farField = table.create(TOTAL_PREDICTION_STEPS)

	for i = 1, TOTAL_PREDICTION_STEPS do
		byStep[i] = {}
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

	local straightCount = 0
	local curveCount = 0
	local waveCount = 0

	for _, data in pairs(ProjectileData) do
		if data.Ready
			and data.Part
			and data.Part.Parent
			and flat(data.Velocity).Magnitude >= MIN_PROJECTILE_SPEED
			and projectileCanReachEnvelope(
				data,
				root.Position,
				maxPlayerReach,
				networkLead
			)
		then
			if data.MotionClass == "WAVE" then
				waveCount += 1
			elseif data.MotionClass == "CURVE" then
				curveCount += 1
			else
				straightCount += 1
			end

			local radius = data.Radius or 0
			local speed = flat(data.Velocity).Magnitude

			local errorMargin =
				math.clamp(
					BASE_ERROR_MARGIN
						+ (data.PredictionError or 0)
							* PREDICTION_ERROR_WEIGHT
						+ speed * SPEED_MARGIN_WEIGHT
						+ math.abs(data.TurnRate or 0)
							* TURN_MARGIN_WEIGHT
						+ (
							data.MotionClass == "WAVE"
								and WAVE_EXTRA_MARGIN
									* math.clamp(
										data.WaveConfidence or 0,
										0,
										1
									)
								or 0
						),
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
							-- Far-future bullets are compressed into a spatial density field.
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

	threats.ByStep = byStep
	threats.FarField = farField
	LastThreatCount = #threats
	LastImmediateThreatCount = immediateCount
	LastNearThreatCount = nearCount
	LastFarThreatCount = farCount

	V41.State.TrajectoryStraight = straightCount
	V41.State.TrajectoryCurve = curveCount
	V41.State.TrajectoryWave = waveCount

	return threats
end

function V41.getShieldCharge()
	local screen = PlayerGui:FindFirstChild("ScreenGui")
	if not screen then
		return 0, 0
	end

	local bar = screen:FindFirstChild("AbilityBar")
	if not bar then
		return 0, 0
	end

	local ability = bar:FindFirstChild("Ability5")
	if not ability then
		return 0, 0
	end

	local label = ability:FindFirstChild("AbilityCharge")
	if not label or not label:IsA("TextLabel") then
		return 0, 0
	end

	local current, maximum =
		string.match(
			tostring(label.Text),
			"(%d+)%s*/%s*(%d+)"
		)

	return tonumber(current) or 0, tonumber(maximum) or 0
end

function V41.getShieldCooldownRemaining()
	return math.max(
		0,
		V41.C.SHIELD_COOLDOWN
			- (os.clock() - V41.State.ShieldLastUse)
	)
end

function V41.findShieldPart()
	local core = workspace:FindFirstChild("Core__Game")
	if not core then
		return nil
	end

	local effects = core:FindFirstChild("Effects")
	if not effects then
		return nil
	end

	local shield = effects:FindFirstChild("LunaBorder")
	if shield and shield:IsA("BasePart") then
		return shield
	end

	return nil
end

function V41.getActiveShieldModel()
	local now = os.clock()
	local shield = V41.findShieldPart()

	if shield then
		if V41.State.ShieldPart ~= shield then
			V41.State.ShieldPart = shield
			V41.State.ShieldCenter = shield.Position
			V41.State.ShieldUntil =
				now + V41.C.SHIELD_DURATION

			-- Also catches a manual shield use while the bot is running.
			if now - V41.State.ShieldLastUse > 1.0 then
				V41.State.ShieldLastUse = now
			end
		else
			V41.State.ShieldCenter = shield.Position
		end

		local remaining =
			math.max(
				0,
				V41.State.ShieldUntil - now
			)

		if remaining > 0 then
			return {
				Center = V41.State.ShieldCenter,
				StartDelay = 0,
				Duration = remaining
			}
		end

		return nil
	end

	if V41.State.ShieldPart ~= nil then
		V41.State.ShieldPart = nil
		V41.State.ShieldCenter = nil
		V41.State.ShieldUntil = 0
	end

	return nil
end

function V41.canUseShield()
	local charge =
		select(1, V41.getShieldCharge())

	if charge < V41.C.SHIELD_REQUIRED_CHARGE then
		V41.State.ShieldLastDecision = "NO CHARGE"
		return false
	end

	if V41.getShieldCooldownRemaining() > 0 then
		V41.State.ShieldLastDecision = "COOLDOWN"
		return false
	end

	if V41.getActiveShieldModel() then
		V41.State.ShieldLastDecision = "ACTIVE"
		return false
	end

	local remotes =
		game:GetService("ReplicatedStorage")
			:FindFirstChild("Remotes")

	local event =
		remotes and remotes:FindFirstChild("UseAbility")

	if not event or not event:IsA("RemoteEvent") then
		V41.State.ShieldLastDecision = "NO REMOTE"
		return false
	end

	return true
end

function V41.useShield(root)
	if not root or not root.Parent then
		return false
	end

	if not V41.canUseShield() then
		return false
	end

	local remotes =
		game:GetService("ReplicatedStorage")
			:FindFirstChild("Remotes")

	local event =
		remotes and remotes:FindFirstChild("UseAbility")

	if not event then
		return false
	end

	local now = os.clock()

	V41.State.ShieldLastUse = now
	V41.State.ShieldCenter = root.Position
	V41.State.ShieldUntil =
		now
			+ V41.C.SHIELD_ACTIVATION_DELAY
			+ V41.C.SHIELD_DURATION

	V41.State.ShieldPlanHoldUntil =
		now + V41.C.SHIELD_PLAN_HOLD

	V41.State.ShieldUseCount += 1
	V41.State.ShieldLastDecision = "FIRED"

	event:FireServer(5, true)

	task.delay(
		V41.C.SHIELD_PRESS_TIME,
		function()
			if event and event.Parent then
				event:FireServer(5, false)
			end
		end
	)

	return true
end

function V41.makeShieldThreatView(
	threats,
	center,
	startDelay,
	duration
)
	if not threats
		or not center
		or duration <= 0
	then
		return threats, 0
	end

	local shieldEnd =
		startDelay + duration

	local deletedAt = {}
	local removed = 0

	for _, threat in ipairs(threats) do
		local positions = threat.Positions

		if positions then
			for stepIndex = 1,
				TOTAL_PREDICTION_STEPS
			do
				local t0 =
					getStepStartTime(stepIndex)

				local t1 =
					getStepEndTime(stepIndex)

				if t1 >= startDelay
					and t0 <= shieldEnd
				then
					local p0 =
						positions[stepIndex]

					local p1 =
						positions[stepIndex + 1]

					if p0 and p1 then
						local distance =
							segmentMinDistance(
								p0 - center,
								p1 - center
							)

						if distance
							<= V41.C.SHIELD_RADIUS
						then
							deletedAt[threat] =
								stepIndex

							removed += 1
							break
						end
					end
				end
			end
		end
	end

	local view = {}

	for i, threat in ipairs(threats) do
		view[i] = threat
	end

	local byStep =
		table.create(
			TOTAL_PREDICTION_STEPS
		)

	for stepIndex = 1,
		TOTAL_PREDICTION_STEPS
	do
		local source =
			threats.ByStep
				and threats.ByStep[stepIndex]
				or {}

		local bucket = {}

		for _, threat in ipairs(source) do
			local deleteStep =
				deletedAt[threat]

			if not deleteStep
				or stepIndex < deleteStep
			then
				bucket[#bucket + 1] =
					threat
			end
		end

		byStep[stepIndex] = bucket
	end

	view.ByStep = byStep

	-- Keep the original far field intentionally.
	-- This makes shield simulation conservative rather than over-trusting it.
	view.FarField = threats.FarField
	view.ShieldDeletedAt = deletedAt

	return view, removed
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

local WallConstraintAngles = {
	0,
	math.rad(-15),
	math.rad(15),
	math.rad(-30),
	math.rad(30),
	math.rad(-45),
	math.rad(45),
	math.rad(-60),
	math.rad(60),
	math.rad(-90),
	math.rad(90),
	math.pi
}

local function constrainMoveAgainstBarriers(
	root,
	humanoid,
	requestedMove
)
	if not root
		or not humanoid
		or requestedMove.Magnitude <= 0.01
	then
		V41.State.WallConstraintState = "FREE"
		return requestedMove
	end

	local origin = root.Position
	local currentVelocity = flat(
		root.AssemblyLinearVelocity
	)

	local lookahead =
		BARRIER_EXECUTION_LOOKAHEAD

	local function endpoint(direction)
		return origin
			+ currentVelocity
				* math.min(0.055, lookahead)
			+ direction
				* humanoid.WalkSpeed
				* lookahead
	end

	local requested =
		clampUnit(requestedMove)

	local requestedEnd =
		endpoint(requested)

	V41.State.WallConstraintClearance =
		minimumBarrierSurfaceDistance(origin)

	if not barrierMotionUnsafe(
		origin,
		requestedEnd,
		BARRIER_EXECUTION_RADIUS
	) then
		V41.State.WallConstraintState = "FREE"
		return requested
	end

	local bestDirection = nil
	local bestScore = -math.huge
	local base = requested.Unit
	local currentClearance =
		minimumBarrierSurfaceDistance(origin)

	for _, angle in ipairs(WallConstraintAngles) do
		local candidate =
			rotateY(base, angle)

		local candidateEnd =
			endpoint(candidate)

		if not barrierMotionUnsafe(
			origin,
			candidateEnd,
			BARRIER_EXECUTION_RADIUS
		) then
			local alignment =
				candidate:Dot(base)

			local endClearance =
				minimumBarrierSurfaceDistance(
					candidateEnd
				)

			local outwardGain =
				math.max(
					0,
					endClearance
						- currentClearance
				)

			local closeFactor =
				1 - math.clamp(
					(
						currentClearance
							- BARRIER_EXECUTION_RADIUS
					) / 1.5,
					0,
					1
				)

			local score =
				alignment * 5.0
				+ outwardGain
					* (1.5 + closeFactor * 4.5)
				+ math.min(
					endClearance,
					4
				) * 0.12

			if score > bestScore then
				bestScore = score
				bestDirection = candidate
			end
		end
	end

	V41.State.WallConstraintCount += 1

	if bestDirection then
		V41.State.WallConstraintState = "SLIDE"
		return bestDirection
	end

	V41.State.WallConstraintState = "STOP"
	return Vector3.zero
end

local function applyCurrentMove(
	humanoid,
	root
)
	if not humanoid then
		return
	end

	if not root then
		humanoid:Move(
			Vector3.zero,
			false
		)
		return
	end

	local safeMove =
		constrainMoveAgainstBarriers(
			root,
			humanoid,
			CurrentMove
		)

	humanoid:Move(
		safeMove,
		false
	)
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

local SteeringAnglesFine = {
	0,
	math.rad(-11.25),
	math.rad(11.25),
	math.rad(-22.5),
	math.rad(22.5),
	math.rad(-45),
	math.rad(45),
	math.rad(-90),
	math.rad(90)
}

local function getNextInputs(previousDirection, depth, emergency)
	if depth == 1 then
		return InitialDirectionList
	end

	if previousDirection.Magnitude < 0.01 then
		return ZeroRestartDirectionList
	end

	local stepEnd = getStepEndTime(depth)
	local farPhase = stepEnd > EXACT_THREAT_HORIZON
	local finePhase =
		not emergency
		and stepEnd <= V41.C.FINE_STEER_END

	local steeringAngles =
		farPhase
			and SteeringAnglesFar
			or (
				finePhase
					and SteeringAnglesFine
					or SteeringAnglesNear
			)

	V41.State.FineSteerActive = finePhase

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

local function evaluateGrazeStep(
	stepHits,
	clearance,
	depth,
	grazePlanning
)
	if not grazePlanning
		or stepHits > 0
		or clearance == math.huge
		or clearance >= V41.C.GRAZE_MAX_CLEARANCE
	then
		return 0, 0
	end

	-- Never reward paths that are effectively touching the predicted
	-- collision boundary. A small positive buffer is preserved even
	-- in intentionally risky graze mode.
	if clearance <= V41.C.GRAZE_HARD_FLOOR then
		local danger =
			1 - math.clamp(
				clearance
					/ V41.C.GRAZE_HARD_FLOOR,
				0,
				1
			)

		return
			V41.C.GRAZE_TOO_CLOSE_PENALTY
				* (0.35 + danger * danger),
			0
	end

	local target =
		V41.C.GRAZE_TARGET_CLEARANCE

	local width =
		math.max(
			0.01,
			V41.C.GRAZE_MAX_CLEARANCE
				- target
		)

	local normalized =
		math.abs(clearance - target)
			/ width

	local closeness =
		1 - math.clamp(
			normalized,
			0,
			1
		)

	local time =
		math.clamp(
			getStepEndTime(depth)
				/ PLAN_HORIZON,
			0,
			1
		)

	local timeWeight =
		1
			+ (1 - time)
				* V41.C.GRAZE_EARLY_WEIGHT

	local score =
		closeness * closeness
			* timeWeight

	local reward =
		score * V41.C.GRAZE_REWARD

	-- Negative cost means "desirable", but Hits still sort before Cost,
	-- so a collision can never beat a zero-hit graze route.
	return -reward, score
end

local function nodeSort(a, b)
	if a.WallHits ~= b.WallHits then
		return a.WallHits < b.WallHits
	end

	if a.Hits ~= b.Hits then
		return a.Hits < b.Hits
	end

	if GRAZE_MODE
		and not V41.State.CornerActive
		and a.Hits == 0
		and b.Hits == 0
		and math.abs(a.Cost - b.Cost) <= 1.5
		and math.abs(
			(a.GrazeScore or 0)
				- (b.GrazeScore or 0)
		) > 0.05
	then
		return
			(a.GrazeScore or 0)
				> (b.GrazeScore or 0)
	end

	if math.abs(a.Cost - b.Cost) > 0.001 then
		return a.Cost < b.Cost
	end

	return a.MinClearance > b.MinClearance
end

local function firstDirectionSector(direction)
	if not direction
		or direction.Magnitude <= 0.01
	then
		return 0
	end

	local angle =
		math.atan2(
			direction.Z,
			direction.X
		)

	local normalized =
		(angle + math.pi)
			/ (math.pi * 2)

	return
		(
			math.floor(
				normalized
					* V41.C.DIVERSITY_SECTORS
			)
			% V41.C.DIVERSITY_SECTORS
		) + 1
end

local function pruneBeamWithDiversity(
	sortedNodes,
	beamWidth,
	depth
)
	local keep =
		math.min(
			beamWidth,
			#sortedNodes
		)

	local beam = {}

	for i = 1, keep do
		beam[i] = sortedNodes[i]
	end

	if depth < V41.C.DIVERSITY_START_DEPTH
		or keep < 4
	then
		return beam, 0
	end

	local sectorCounts = {}

	for _, node in ipairs(beam) do
		local sector =
			firstDirectionSector(node.FirstDir)

		sectorCounts[sector] =
			(sectorCounts[sector] or 0) + 1
	end

	local missingBest = {}

	for i = keep + 1, #sortedNodes do
		local node = sortedNodes[i]
		local sector =
			firstDirectionSector(node.FirstDir)

		if sector ~= 0
			and not sectorCounts[sector]
			and not missingBest[sector]
		then
			missingBest[sector] = node
		end
	end

	local injected = 0

	for sector, candidate in pairs(missingBest) do
		if injected
			>= V41.C.DIVERSITY_RESERVE
		then
			break
		end

		local replaceIndex = nil

		for i = #beam, 1, -1 do
			local current = beam[i]
			local currentSector =
				firstDirectionSector(
					current.FirstDir
				)

			if (sectorCounts[currentSector] or 0) > 1
				and current.WallHits == candidate.WallHits
				and current.Hits == candidate.Hits
				and candidate.Cost
					<= current.Cost
						+ V41.C.DIVERSITY_COST_SLACK
			then
				replaceIndex = i
				break
			end
		end

		if replaceIndex then
			local oldSector =
				firstDirectionSector(
					beam[replaceIndex].FirstDir
				)

			sectorCounts[oldSector] -= 1
			beam[replaceIndex] = candidate
			sectorCounts[sector] = 1
			injected += 1
		end
	end

	table.sort(beam, nodeSort)

	return beam, injected
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

local function planPath(root, humanoid, threats, cornerDirection)
	local beamWidth =
		getAdaptiveBeamWidth(
			LastImmediateThreatCount + LastNearThreatCount
		)

	local rootVelocity = flat(root.AssemblyLinearVelocity)

	V41.State.DiversityInjected = 0
	V41.State.NearMissBest = 0
	V41.State.FineSteerActive = false
	V41.State.GrazeScoreBest = 0

	local grazePlanning =
		GRAZE_MODE
			and not V41.State.CornerActive

	V41.State.GrazePlanning = grazePlanning

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
			NearMisses = 0,
			GrazeScore = 0,
			FirstImpactTime = math.huge,
			Depth = 0,
			Parent = nil
		}
	}

	for depth = 1, PLAN_STEPS do
		local nextBeam = {}

		for _, node in ipairs(beam) do
			local emergencyClearance =
				grazePlanning
					and V41.C.GRAZE_HARD_FLOOR
					or 0.20

			local emergency =
				node.Hits > 0
				or node.MinClearance
					< emergencyClearance
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

				if wallHit then
					continue
				end

				local grazeCost,
					grazeScore =
					evaluateGrazeStep(
						stepHits,
						stepClearance,
						depth,
						grazePlanning
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
					V41.cornerRouteCost(
						node.Pos,
						newPosition,
						direction,
						cornerDirection
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
						+ grazeCost,
					Hits = node.Hits + stepHits,
					WallHits =
						node.WallHits
						+ (wallHit and 1 or 0),
					MinClearance =
						math.min(
							node.MinClearance,
							stepClearance
						),
					NearMisses =
						node.NearMisses
						+ (
							stepHits == 0
							and stepClearance
								< V41.C.ROBUST_NEAR_CLEARANCE
							and 1
							or 0
						),
					GrazeScore =
						(node.GrazeScore or 0)
							+ grazeScore,
					FirstImpactTime =
						node.FirstImpactTime ~= math.huge
							and node.FirstImpactTime
							or (
								stepHits > 0
									and getStepEndTime(depth)
									or math.huge
							),
					Depth = depth,
					Parent = node
				}

				nextBeam[#nextBeam + 1] = newNode
			end
		end

		table.sort(nextBeam, nodeSort)

		local injected
		beam, injected =
			pruneBeamWithDiversity(
				nextBeam,
				beamWidth,
				depth
			)

		V41.State.DiversityInjected =
			math.max(
				V41.State.DiversityInjected,
				injected or 0
			)

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

		if cornerDirection then
			local progress =
				flat(node.Pos - root.Position)
					:Dot(cornerDirection)

			trapCost -=
				progress
					* V41.C.CORNER_FINAL_REWARD
		end

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

		if a.Node.Hits > 0
			and a.Node.FirstImpactTime
				~= b.Node.FirstImpactTime
		then
			return
				a.Node.FirstImpactTime
					> b.Node.FirstImpactTime
		end

		local costDelta =
			a.FinalCost - b.FinalCost

		if math.abs(costDelta)
			<= V41.C.ROBUST_COST_EPSILON
		then
			if grazePlanning
				and a.Node.Hits == 0
				and b.Node.Hits == 0
				and math.abs(
					(a.Node.GrazeScore or 0)
						- (b.Node.GrazeScore or 0)
				) > 0.05
			then
				return
					(a.Node.GrazeScore or 0)
						> (b.Node.GrazeScore or 0)
			end

			if not grazePlanning
				and a.Node.NearMisses
					~= b.Node.NearMisses
			then
				return
					a.Node.NearMisses
						< b.Node.NearMisses
			end

			if math.abs(
				a.Node.MinClearance
					- b.Node.MinClearance
			) > 0.05
			then
				return
					a.Node.MinClearance
						> b.Node.MinClearance
			end

			if a.EscapeOptions
				~= b.EscapeOptions
			then
				return
					a.EscapeOptions
						> b.EscapeOptions
			end

			if CurrentMove.Magnitude > 0.01
				and a.Node.FirstDir.Magnitude > 0.01
				and b.Node.FirstDir.Magnitude > 0.01
				and math.abs(costDelta)
					<= V41.C.ROBUST_CURRENT_MOVE_EPSILON
			then
				local aDot =
					CurrentMove.Unit:Dot(
						a.Node.FirstDir.Unit
					)

				local bDot =
					CurrentMove.Unit:Dot(
						b.Node.FirstDir.Unit
					)

				if math.abs(aDot - bDot) > 0.03 then
					return aDot > bDot
				end
			end
		end

		if math.abs(costDelta) > 0.001 then
			return costDelta < 0
		end

		return
			a.Node.MinClearance
				> b.Node.MinClearance
	end)

	local best = finalists[1]
	if not best then
		return nil
	end

	V41.State.NearMissBest =
		best.Node.NearMisses or 0

	V41.State.GrazeScoreBest =
		best.Node.GrazeScore or 0

	return {
		Direction = best.Node.FirstDir,
		Path = reconstructPath(best.Node),
		Hits = best.Node.Hits,
		WallHits = best.Node.WallHits,
		MinClearance = best.Node.MinClearance,
		GrazeScore = best.Node.GrazeScore or 0,
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
Main.Size = UDim2.fromOffset(260, 391)
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
Title.Text = "AUTO DODGE V41"
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
Info.Size = UDim2.new(1, -20, 0, 138)
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
Toggle.Position = UDim2.fromOffset(10, 196)
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

local GrazeToggle = Instance.new("TextButton")
GrazeToggle.Size = UDim2.new(1, -20, 0, 34)
GrazeToggle.Position = UDim2.fromOffset(10, 241)
GrazeToggle.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
GrazeToggle.BorderSizePixel = 0
GrazeToggle.Text = "GRAZE MODE  OFF"
GrazeToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
GrazeToggle.TextSize = 13
GrazeToggle.Font = Enum.Font.GothamBold
GrazeToggle.Parent = Main

local GrazeCorner = Instance.new("UICorner")
GrazeCorner.CornerRadius = UDim.new(0, 8)
GrazeCorner.Parent = GrazeToggle

local RadiusLabel = Instance.new("TextLabel")
RadiusLabel.Size = UDim2.new(1, -84, 0, 34)
RadiusLabel.Position = UDim2.fromOffset(42, 282)
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
Minus.Position = UDim2.fromOffset(10, 282)
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
Plus.Position = UDim2.new(1, -38, 0, 282)
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
PathToggle.Position = UDim2.fromOffset(10, 323)
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
Footer.Position = UDim2.fromOffset(10, 362)
Footer.BackgroundTransparency = 1
Footer.Text = "v41 / Auto Trajectory + Robust Beam + Graze"
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

GrazeToggle.Activated:Connect(function()
	GRAZE_MODE = not GRAZE_MODE

	if GRAZE_MODE then
		GrazeToggle.Text = "GRAZE MODE  ON"
		GrazeToggle.BackgroundColor3 =
			Color3.fromRGB(150, 105, 55)
	else
		GrazeToggle.Text = "GRAZE MODE  OFF"
		GrazeToggle.BackgroundColor3 =
			Color3.fromRGB(58, 58, 66)
	end

	-- Force immediate replanning so the mode switch is felt instantly.
	LastPlanTime = -math.huge
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
		V41.State.CornerActive = false
		V41.State.CornerDirection = nil
		V41.State.ShieldPlanHoldUntil = 0
		V41.State.ShieldLastDecision = "IDLE"
		V41.State.WallConstraintState = "FREE"
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

	if now < V41.State.ShieldPlanHoldUntil then
		applyCurrentMove(humanoid, root)
		return
	end

	if now - LastPlanTime < getPlanInterval() then
		applyCurrentMove(humanoid, root)
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

		local activeShield =
			V41.getActiveShieldModel()

		local effectiveThreats = threats
		local activeShieldRemoved = 0

		if activeShield then
			effectiveThreats,
				activeShieldRemoved =
				V41.makeShieldThreatView(
					threats,
					activeShield.Center,
					activeShield.StartDelay,
					activeShield.Duration
				)

			V41.State.ShieldLastRemoved =
				activeShieldRemoved
		end

		if #threats == 0
			and not (
				activeShield
				and V41.State.CornerActive
			)
		then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastMinClearance = math.huge
			LastImpactTime = math.huge
			LastEscapeOptions = 0
			LastFarRisk = 0
			LastEscapeTrendText = "-"
			LastMode = "IDLE"
			V41.State.CornerActive = false
			V41.State.CornerDirection = nil
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		local baseline = evaluateBaseline(root, humanoid, effectiveThreats)
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
			or (
				activeShield ~= nil
				and V41.State.CornerActive
			)

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

		local cornerDirection =
			V41.updateCornerObjective(
				root.Position
			)

		local plan =
			planPath(
				root,
				humanoid,
				effectiveThreats,
				cornerDirection
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

		local shieldUsed = false

		if not activeShield
			and plan.Hits > 0
			and V41.canUseShield()
		then
			local urgentEnough =
				baseline.EarliestImpact ~= math.huge
				and baseline.EarliestImpact
					<= V41.C.SHIELD_TRIGGER_IMPACT

			local cornerEmergency =
				V41.State.CornerActive
				and plan.EscapeOptions <= 1

			if urgentEnough or cornerEmergency then
				local simStarted = os.clock()

				local shieldThreats,
					removed =
					V41.makeShieldThreatView(
						threats,
						root.Position,
						V41.C.SHIELD_ACTIVATION_DELAY,
						V41.C.SHIELD_DURATION
					)

				local shieldPlan = nil

				if removed
					>= V41.C.SHIELD_MIN_REMOVED
				then
					shieldPlan =
						planPath(
							root,
							humanoid,
							shieldThreats,
							cornerDirection
						)
				end

				V41.State.ShieldSimMs =
					(os.clock() - simStarted)
						* 1000

				V41.State.ShieldLastRemoved =
					removed

				-- Scarce 30s resource:
				-- only spend it if the normal best route predicts a hit
				-- and the same MPC becomes zero-hit after shield deletion.
				if shieldPlan
					and shieldPlan.Hits == 0
					and shieldPlan.WallHits == 0
				then
					if V41.useShield(root) then
						plan = shieldPlan
						shieldUsed = true
						V41.State.ShieldLastDecision =
							"BREAKOUT"
					end
				else
					V41.State.ShieldLastDecision =
						"SIM NO SAVE"
				end
			else
				V41.State.ShieldLastDecision =
					"WAIT"
			end
		elseif activeShield then
			V41.State.ShieldLastDecision =
				"ACTIVE"
		elseif plan.Hits == 0 then
			V41.State.ShieldLastDecision =
				"SAVE"
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

		if shieldUsed then
			LastMode = "SHIELD BREAKOUT"
		elseif GRAZE_MODE
			and V41.State.GrazePlanning
			and plan.Hits == 0
			and (plan.GrazeScore or 0) > 0.25
		then
			LastMode = "GRAZE"
		elseif activeShield
			and V41.State.CornerActive
		then
			LastMode = "SHIELD EXIT"
		elseif plan.Hits > 0 then
			LastMode = "RESCUE"
		elseif V41.State.CornerActive then
			LastMode = "EXIT CORNER"
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
		applyCurrentMove(humanoid, root)
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

			local _, humanoid, root =
				getCharacter()

			if humanoid and root then
				disableControls()

				if ActiveBarrierParts == nil then
					refreshActiveBarriers(
						root.Position,
						humanoid.WalkSpeed
					)
				end

				applyCurrentMove(
					humanoid,
					root
				)
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
			.. "\nShield "
			.. tostring(
				select(
					1,
					V41.getShieldCharge()
				)
			)
			.. "/2 "
			.. (
				V41.getActiveShieldModel()
					and "ACTIVE"
					or (
						V41.getShieldCooldownRemaining() > 0
							and (
								"CD "
								.. string.format(
									"%.0f",
									V41.getShieldCooldownRemaining()
								)
							)
							or V41.State.ShieldLastDecision
					)
			)
			.. " / Del "
			.. tostring(V41.State.ShieldLastRemoved)
			.. " / Sim "
			.. string.format(
				"%.1fms",
				V41.State.ShieldSimMs
			)
			.. "\nSearch D"
			.. tostring(V41.State.DiversityInjected)
			.. " / NM "
			.. tostring(V41.State.NearMissBest)
			.. " / Fine "
			.. (
				V41.State.FineSteerActive
					and "ON"
					or "-"
			)
			.. "\nGraze "
			.. (
				GRAZE_MODE
					and (
						V41.State.GrazePlanning
							and "HUNT"
							or "SAFE/EXIT"
					)
					or "OFF"
			)
			.. " / G "
			.. string.format(
				"%.1f",
				V41.State.GrazeScoreBest
			)
			.. "\nWall "
			.. V41.State.WallConstraintState
			.. " / "
			.. (
				V41.State.WallConstraintClearance
					== math.huge
					and "-"
					or string.format(
						"%.2f",
						V41.State.WallConstraintClearance
					)
			)
			.. " / Fix "
			.. tostring(
				V41.State.WallConstraintCount
			)
			.. "\nTraj S"
			.. tostring(
				V41.State.TrajectoryStraight
			)
			.. " C"
			.. tostring(
				V41.State.TrajectoryCurve
			)
			.. " W"
			.. tostring(
				V41.State.TrajectoryWave
			)
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
	V41.State.CornerActive = false
	V41.State.CornerDirection = nil
	V41.State.ShieldPart = nil
	V41.State.ShieldCenter = nil
	V41.State.ShieldUntil = 0
	V41.State.ShieldPlanHoldUntil = 0
	V41.State.ShieldLastDecision = "IDLE"
	V41.State.WallConstraintState = "FREE"
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
