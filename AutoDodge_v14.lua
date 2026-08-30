local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

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

-- Planner optimization: heavy MPC work runs outside RenderStep and yields in slices.
local PLANNER_SLICE_BUDGET = 0.0035
local PLANNER_CLOCK_CHECK_EVERY = 40

-- Adaptive frame budget: the counter only gates os.clock() sampling.
-- Actual yielding is determined by recent frame time and Immediate-MPC load.
local PLANNER_SLICE_MIN = 0.00115
local PLANNER_SLICE_MAX = 0.00350
local PREPROCESS_SLICE_MIN = 0.00085
local FRAME_TARGET_DT = 1 / 60
local FRAME_DT_EMA_ALPHA = 0.08
local IMMEDIATE_MS_EMA_ALPHA = 0.12

-- Shared 2D broad-phase grids. Exact CCD/OBB tests still make final decisions.
local PROJECTILE_GRID_CELL = 12.0
local BARRIER_GRID_CELL = 14.0
local BARRIER_GRID_MAX_CELLS_PER_PART = 196
local SPATIAL_QUERY_PADDING = 8.0
local SPATIAL_MAX_QUERY_RADIUS = 360.0
local SPATIAL_TYPICAL_SPEED_CAP = 140.0
local SPATIAL_TYPICAL_ACCEL_CAP = 500.0
local DOMINANCE_CELL = 1.05
local DOMINANCE_DIR_BINS = 16
local ESCAPE_CACHE_CELL = 1.10
local OPENNESS_CACHE_CELL = 1.35

-- Dense Front Escape: recognize slow, connected fan/wall patterns and route around an edge.
local FAN_SAMPLE_TIME = 0.55
local FAN_MAX_DISTANCE = 52
local FAN_MAX_SPEED = 115
local FAN_MIN_PROJECTILES = 10
local FAN_MIN_APPROACH_DOT = 0.08
local FAN_ANGLE_BINS = 72
local FAN_MIN_ARC_DEGREES = 40
local FAN_MAX_ARC_DEGREES = 235
local FAN_ESCAPE_EVAL_TIME = 0.70
local FAN_ESCAPE_COMMIT_TIME = 0.85
local FAN_DIRECTION_WEIGHT = 34
local FAN_REVERSE_EXTRA = 82
local FAN_STOP_PENALTY = 44
local FAN_PROGRESS_WEIGHT = 28
local FAN_PROGRESS_REWARD = 7
local FAN_DEEPER_WEIGHT = 38
local FAN_OUTWARD_REWARD = 11
local FAN_CENTER_WEIGHT = 26
local FAN_IMMEDIATE_SCALE = 0.82

-- FAN is environmental information for MPC, not a separate movement mode.
-- Only a tiny preference hysteresis remains to stop symmetric left/right
-- estimates from flipping on every planning pass.
local FAN_INFO_GRACE = 0.24
local FAN_SWITCH_ADVANTAGE = 0.24
local FAN_SWITCH_MIN_SCORE = 8
local FAN_DIRECTION_SMOOTH = 0.18
local FAN_COST_HORIZON = 1.10

-- Proactive FAN forecast for the MPC input. This does not move the character
-- directly; it only feeds future fan geometry into both MPC layers early.
local FAN_FORECAST_TIMES = {0.18, 0.32, 0.48, 0.68, 0.90}
local FAN_FORECAST_MAX_DISTANCE = 60
local FAN_FORECAST_SCAN_DISTANCE = 72
local FAN_FORECAST_MIN_PROJECTILES = 8
local FAN_FORECAST_MIN_ARC_DEGREES = 30
local FAN_FORECAST_MAX_ARC_DEGREES = 255
local FAN_FORECAST_MAX_SPEED = 125
local FAN_FORECAST_DISTANCE_SLACK = 1.8
local FAN_FORECAST_MIN_STRENGTH = 0.72
local FAN_FORECAST_EARLY_BONUS = 0.10

local PLAN_INTERVAL_IDLE = 0.055
local PLAN_INTERVAL_ACTIVE = 0.035
local PLAN_INTERVAL_URGENT = 0.018

-- Two-stage MPC.
-- Stage 1 is a real, non-yielding MPC over the immediate future. It decides
-- movement first. Stage 2 then refines the route out to the full 1.5 seconds.
local IMMEDIATE_MPC_HORIZON = 0.55
local IMMEDIATE_MPC_INTERVAL = 0.018
local IMMEDIATE_MPC_DIRECTIONS = 16
local IMMEDIATE_MPC_BEAM_WIDTH = 20
local IMMEDIATE_MPC_DENSE_BEAM_WIDTH = 16
local IMMEDIATE_MPC_MAX_THREATS = 80
local IMMEDIATE_MPC_TRIGGER_CLEARANCE = 0.72
local IMMEDIATE_MPC_NEAR_ZONE = 1.80
local IMMEDIATE_MPC_WALL_WEIGHT = 24
local IMMEDIATE_MPC_TURN_WEIGHT = 1.05
local IMMEDIATE_MPC_STOP_PENALTY = 4.0
local IMMEDIATE_MPC_PROACTIVE_DENSE = 1.10
local PREPROCESS_CLOCK_CHECK_EVERY = 24

-- Native game Focus/Slow action. The game toggles it with one LeftShift press.
-- MPC chooses the Focus state; movement speed is NOT faked by scaling Move().
local FOCUS_FALLBACK_SPEED_RATIO = 0.42
local FOCUS_MIN_HOLD_TIME = 0.16
local FOCUS_TOGGLE_COST = 5.5
local FOCUS_ACTIVE_COST_PER_SECOND = 3.2
local FOCUS_CONSIDER_CLEARANCE = 1.45
local FOCUS_CONSIDER_THREATS = 7
local FOCUS_SPEED_SAMPLE_DELAY = 0.18
local FOCUS_SPEED_SMOOTH = 0.18
local FOCUS_KEY = Enum.KeyCode.LeftShift

local INITIAL_DIRECTIONS = 20
local ZERO_RESTART_DIRECTIONS = 8
local ESCAPE_DIRECTIONS = 16
local BEAM_WIDTH = 38
local DENSE_BEAM_WIDTH = 32
local DENSE_THREAT_COUNT = 22
local ACTIVATION_LOOKAHEAD = 0.78
local DENSE_ACTIVATION_LOOKAHEAD = 1.05
local BROAD_PHASE_EXTRA = 3.0

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

-- Persistent / area attacks inside EnemyProj (lasers, floor zones, beams).
-- These remain dangerous even when their translational speed is ~0.
local AREA_HAZARD_MIN_LONG_AXIS = 5.0
local AREA_HAZARD_ASPECT_RATIO = 2.6
local AREA_HAZARD_BROAD_FOOTPRINT = 3.25
local AREA_HAZARD_STATIONARY_SAMPLES = 3
local AREA_HAZARD_ERROR_MARGIN = 0.10
local AREA_HAZARD_INFLUENCE = 1.35
local AREA_HAZARD_NEAR_WEIGHT = 48
local AREA_HAZARD_VELOCITY_SMOOTH = 0.46
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

local ProjectileSpatialGrid = {}
local ProjectileSpatialReady = false
local ProjectileAreaList = {}
local ProjectileExtremeList = {}
local SpatialMaxSpeed = 0
local SpatialMaxAbsAccel = 0
local SpatialMaxRadius = 0
local LastSpatialQueryCount = 0

local FrameDtEMA = FRAME_TARGET_DT
local ImmediateMsEMA = 0
local LastPlannerSliceBudgetMs = PLANNER_SLICE_BUDGET * 1000

local BarrierSet = {}
local BarrierParts = {}
local ActiveBarrierParts = nil
local BarrierSpatialGrid = {}
local BarrierSpatialReady = false
local DynamicBarrierParts = {}
local LargeBarrierParts = {}

local Controls = nil
local ControlsDisabled = false

local CurrentMove = Vector3.zero
local CurrentPath = nil

local CurrentPlanFocus = false
local ImmediateMPCMove = Vector3.zero
local ImmediateMPCFocus = false
local ImmediateMPCActive = false

-- AppliedFocus tracks toggles generated by this script. Start the bot with the
-- game's Slow/Focus toggle OFF; after that the script restores NORMAL on disable.
local AppliedFocus = false
local LastFocusToggleAt = -math.huge
local NormalSpeedEstimate = nil
local FocusSpeedEstimate = nil
local LastFocusInputError = ""
local LastImmediateMPCTime = 0
local LastImmediateMPCThreats = 0
local LastImmediateMPCClearance = math.huge
local LastImmediateMPCMs = 0
local LastAppliedMove = Vector3.zero

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
local LastFanCount = 0
local LastFanArc = 0
local LastFanDirection = Vector3.zero
local CurrentFanInfo = nil
local LastFanSeenAt = 0
local LastFanForecastTime = 0

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

local function getPositionIndexNearTime(targetTime)
	local bestIndex = 1
	local bestDelta = math.huge
	for i = 1, TOTAL_PREDICTION_STEPS + 1 do
		local delta = math.abs(getPredictionTime(i) - targetTime)
		if delta < bestDelta then
			bestDelta = delta
			bestIndex = i
		end
	end
	return bestIndex
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

local function spatialCell(value, cellSize)
	return math.floor(value / cellSize)
end

local function spatialInsert(grid, cellSize, position, value)
	local ix = spatialCell(position.X, cellSize)
	local iz = spatialCell(position.Z, cellSize)

	local column = grid[ix]
	if not column then
		column = {}
		grid[ix] = column
	end

	local bucket = column[iz]
	if not bucket then
		bucket = {}
		column[iz] = bucket
	end

	bucket[#bucket + 1] = value
end

local function spatialQuery(grid, cellSize, center, radius, result, seen)
	result = result or {}
	seen = seen or {}

	local minX = spatialCell(center.X - radius, cellSize)
	local maxX = spatialCell(center.X + radius, cellSize)
	local minZ = spatialCell(center.Z - radius, cellSize)
	local maxZ = spatialCell(center.Z + radius, cellSize)
	local radiusSq = (radius + cellSize * 0.8) ^ 2

	for ix = minX, maxX do
		local column = grid[ix]
		if column then
			for iz = minZ, maxZ do
				local bucket = column[iz]
				if bucket then
					for _, value in ipairs(bucket) do
						if not seen[value] then
							local p = value.LastPosition
							if p then
								local dx = p.X - center.X
								local dz = p.Z - center.Z
								if dx * dx + dz * dz <= radiusSq then
									seen[value] = true
									result[#result + 1] = value
								end
							end
						end
					end
				end
			end
		end
	end

	return result, seen
end

local function getPlannerSliceBudget()
	local frameLoad =
		math.max(
			1,
			FrameDtEMA / FRAME_TARGET_DT
		)

	local budget =
		PLANNER_SLICE_BUDGET
			/ (frameLoad ^ 1.35)

	if ImmediateMsEMA > 4.0 then
		budget *= 0.72
	elseif ImmediateMsEMA > 2.5 then
		budget *= 0.86
	end

	budget =
		math.clamp(
			budget,
			PLANNER_SLICE_MIN,
			PLANNER_SLICE_MAX
		)

	LastPlannerSliceBudgetMs = budget * 1000
	return budget
end

local function getPreprocessSliceBudget()
	return
		math.max(
			PREPROCESS_SLICE_MIN,
			getPlannerSliceBudget() * 0.68
		)
end

local function getProjectileSpatialQueryRadius(
	root,
	humanoid,
	horizon,
	networkLead,
	extra
)
	local t = horizon + networkLead
	local playerReach =
		math.max(
			humanoid.WalkSpeed,
			NormalSpeedEstimate or 0
		) * horizon
		+ flat(root.AssemblyLinearVelocity).Magnitude
			* math.min(horizon, 0.18)

	local projectileReach =
		SpatialMaxSpeed * t
		+ 0.5 * SpatialMaxAbsAccel * t * t

	return
		math.clamp(
			playerReach
				+ projectileReach
				+ SpatialMaxRadius
				+ (extra or 0)
				+ SPATIAL_QUERY_PADDING,
			24,
			SPATIAL_MAX_QUERY_RADIUS
		)
end

local function queryProjectileSpatial(center, radius)
	if not ProjectileSpatialReady then
		local fallback = {}
		for _, data in pairs(ProjectileData) do
			fallback[#fallback + 1] = data
		end
		LastSpatialQueryCount = #fallback
		return fallback
	end

	local result, seen =
		spatialQuery(
			ProjectileSpatialGrid,
			PROJECTILE_GRID_CELL,
			center,
			radius
		)

	-- Large/stationary area attacks can cross the player even with a far center.
	for _, data in ipairs(ProjectileAreaList) do
		if not seen[data] then
			seen[data] = true
			result[#result + 1] = data
		end
	end

	-- Outlier movers bypass normal radius so broad-phase never drops them.
	for _, data in ipairs(ProjectileExtremeList) do
		if not seen[data] then
			seen[data] = true
			result[#result + 1] = data
		end
	end

	LastSpatialQueryCount = #result
	return result
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


local function sendFocusToggle()
	local ok, err = pcall(function()
		VirtualInputManager:SendKeyEvent(
			true,
			FOCUS_KEY,
			false,
			game
		)
		VirtualInputManager:SendKeyEvent(
			false,
			FOCUS_KEY,
			false,
			game
		)
	end)

	if ok then
		LastFocusInputError = ""
	else
		LastFocusInputError = tostring(err)
	end

	return ok
end

local function applyFocusState(wanted, force)
	wanted = wanted == true

	if wanted == AppliedFocus then
		return true
	end

	local now = os.clock()
	if not force
		and now - LastFocusToggleAt < FOCUS_MIN_HOLD_TIME
	then
		return false
	end

	if sendFocusToggle() then
		AppliedFocus = wanted
		LastFocusToggleAt = now
		return true
	end

	return false
end

local function getPredictedWalkSpeed(humanoid, focus)
	local currentWalkSpeed = math.max(0.5, humanoid.WalkSpeed)

	if not AppliedFocus then
		NormalSpeedEstimate =
			NormalSpeedEstimate
			and (
				NormalSpeedEstimate * 0.94
				+ currentWalkSpeed * 0.06
			)
			or currentWalkSpeed
	elseif not FocusSpeedEstimate then
		-- If the game exposes Slow by changing WalkSpeed, learn it immediately.
		if NormalSpeedEstimate
			and currentWalkSpeed < NormalSpeedEstimate * 0.88
		then
			FocusSpeedEstimate = currentWalkSpeed
		end
	end

	local normal =
		NormalSpeedEstimate
		or (
			AppliedFocus
			and currentWalkSpeed
				/ math.max(FOCUS_FALLBACK_SPEED_RATIO, 0.05)
			or currentWalkSpeed
		)

	if not focus then
		return math.max(0.5, normal)
	end

	local focused =
		FocusSpeedEstimate
		or normal * FOCUS_FALLBACK_SPEED_RATIO

	return math.max(0.5, math.min(focused, normal))
end

local function updateFocusSpeedEstimate(humanoid, root)
	if os.clock() - LastFocusToggleAt < FOCUS_SPEED_SAMPLE_DELAY then
		return
	end

	local currentWalkSpeed = math.max(0.5, humanoid.WalkSpeed)

	if AppliedFocus then
		if NormalSpeedEstimate
			and currentWalkSpeed < NormalSpeedEstimate * 0.90
		then
			FocusSpeedEstimate =
				FocusSpeedEstimate
				and (
					FocusSpeedEstimate
						* (1 - FOCUS_SPEED_SMOOTH)
					+ currentWalkSpeed
						* FOCUS_SPEED_SMOOTH
				)
				or currentWalkSpeed
		elseif LastAppliedMove.Magnitude > 0.85 then
			-- Some games implement Focus outside Humanoid.WalkSpeed. In that
			-- case learn from sustained real movement after the toggle settles.
			local realSpeed = flat(root.AssemblyLinearVelocity).Magnitude
			if realSpeed > 0.75
				and (
					not NormalSpeedEstimate
					or realSpeed < NormalSpeedEstimate * 0.92
				)
			then
				FocusSpeedEstimate =
					FocusSpeedEstimate
					and (
						FocusSpeedEstimate
							* (1 - FOCUS_SPEED_SMOOTH)
						+ realSpeed
							* FOCUS_SPEED_SMOOTH
					)
					or realSpeed
			end
		end
	else
		NormalSpeedEstimate =
			NormalSpeedEstimate
			and (
				NormalSpeedEstimate
					* (1 - FOCUS_SPEED_SMOOTH)
				+ currentWalkSpeed
					* FOCUS_SPEED_SMOOTH
			)
			or currentWalkSpeed
	end
end

local function getFocusOptions(node, allowFocus, emergency)
	local current = node.Focus == true
	local age = node.FocusAge or math.huge

	if age < FOCUS_MIN_HOLD_TIME and not emergency then
		return {current}
	end

	if current then
		-- Always let MPC leave Slow once precision is no longer worth it.
		return {true, false}
	end

	if allowFocus then
		return {false, true}
	end

	return {false}
end

local function focusTransitionCost(oldFocus, newFocus, dt, emergency)
	local cost = 0

	if newFocus then
		cost += FOCUS_ACTIVE_COST_PER_SECOND * dt
	end

	if oldFocus ~= newFocus then
		cost +=
			emergency
			and FOCUS_TOGGLE_COST * 0.35
			or FOCUS_TOGGLE_COST
	end

	return cost
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


local function isActualBarrier(obj)
	return obj:IsA("BasePart") and string.lower(obj.Name) == "barrier"
end

local function rebuildBarrierParts()
	local list = {}
	local grid = {}
	local dynamic = {}
	local large = {}

	for part in pairs(BarrierSet) do
		if part and part.Parent then
			list[#list + 1] = part

			-- Moving barriers are never baked into the static grid.
			if not part.Anchored then
				dynamic[#dynamic + 1] = part
				continue
			end

			local cf = part.CFrame
			local hx = part.Size.X * 0.5 + BARRIER_BODY_RADIUS
			local hz = part.Size.Z * 0.5 + BARRIER_BODY_RADIUS

			local worldHX =
				math.abs(cf.RightVector.X) * hx
				+ math.abs(cf.LookVector.X) * hz
			local worldHZ =
				math.abs(cf.RightVector.Z) * hx
				+ math.abs(cf.LookVector.Z) * hz

			local minX =
				spatialCell(
					cf.Position.X - worldHX,
					BARRIER_GRID_CELL
				)
			local maxX =
				spatialCell(
					cf.Position.X + worldHX,
					BARRIER_GRID_CELL
				)
			local minZ =
				spatialCell(
					cf.Position.Z - worldHZ,
					BARRIER_GRID_CELL
				)
			local maxZ =
				spatialCell(
					cf.Position.Z + worldHZ,
					BARRIER_GRID_CELL
				)

			local cellCount =
				(maxX - minX + 1)
				* (maxZ - minZ + 1)

			if cellCount > BARRIER_GRID_MAX_CELLS_PER_PART then
				-- Large world-boundary parts are few, so keeping them in a tiny
				-- exact-check list is much cheaper than rasterizing their whole
				-- footprint into the grid.
				large[#large + 1] = part
			else
				for ix = minX, maxX do
					local column = grid[ix]
					if not column then
						column = {}
						grid[ix] = column
					end

					for iz = minZ, maxZ do
						local bucket = column[iz]
						if not bucket then
							bucket = {}
							column[iz] = bucket
						end
						bucket[#bucket + 1] = part
					end
				end
			end
		end
	end

	BarrierParts = list
	BarrierSpatialGrid = grid
	DynamicBarrierParts = dynamic
	LargeBarrierParts = large
	BarrierSpatialReady = true
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

task.defer(scanBarriers)

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
	local searchDistance =
		walkSpeed * PLAN_HORIZON
		+ BARRIER_RAY_DISTANCE
		+ 10

	if not BarrierSpatialReady then
		ActiveBarrierParts = BarrierParts
		return
	end

	local active = {}
	local seen = {}
	local minX = spatialCell(position.X - searchDistance, BARRIER_GRID_CELL)
	local maxX = spatialCell(position.X + searchDistance, BARRIER_GRID_CELL)
	local minZ = spatialCell(position.Z - searchDistance, BARRIER_GRID_CELL)
	local maxZ = spatialCell(position.Z + searchDistance, BARRIER_GRID_CELL)

	for ix = minX, maxX do
		local column = BarrierSpatialGrid[ix]
		if column then
			for iz = minZ, maxZ do
				local bucket = column[iz]
				if bucket then
					for _, barrier in ipairs(bucket) do
						if not seen[barrier]
							and barrier
							and barrier.Parent
						then
							seen[barrier] = true
							if pointBarrierDistance2D(
								barrier,
								position
							) <= searchDistance
							then
								active[#active + 1] = barrier
							end
						end
					end
				end
			end
		end
	end

	-- Large static barriers are deliberately not rasterized into every cell.
	for _, barrier in ipairs(LargeBarrierParts) do
		if barrier
			and barrier.Parent
			and not seen[barrier]
			and pointBarrierDistance2D(
				barrier,
				position
			) <= searchDistance
		then
			seen[barrier] = true
			active[#active + 1] = barrier
		end
	end

	-- Moving barriers are always rechecked from their live CFrame because their
	-- prebuilt grid cells can become stale.
	for _, barrier in ipairs(DynamicBarrierParts) do
		if barrier
			and barrier.Parent
			and not seen[barrier]
			and pointBarrierDistance2D(
				barrier,
				position
			) <= searchDistance
		then
			seen[barrier] = true
			active[#active + 1] = barrier
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


	if dt <= 0 or dt > 0.25 then
		return
	end

	FrameDtEMA +=
		(dt - FrameDtEMA) * FRAME_DT_EMA_ALPHA

	local count = 0
	local newSpatialGrid = {}
	local newAreaList = {}
	local newExtremeList = {}
	local frameMaxSpeed = 0
	local frameMaxAbsAccel = 0
	local frameMaxRadius = 0

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

		-- GetBoundingBox() on hundreds of ordinary bullets every Heartbeat is expensive.
		-- Refresh box geometry only for actual/potential persistent area hazards.
		local boxCf, boxSize = nil, nil
		local needsAreaBox =
			data.BaseAreaHazard
			or data.IsAreaHazard
			or newSpeed < MIN_PROJECTILE_SPEED * 1.5
			or data.Samples < 2

		if needsAreaBox then
			boxCf, boxSize = getObjectBox(obj, part)
		end

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

		spatialInsert(
			newSpatialGrid,
			PROJECTILE_GRID_CELL,
			position,
			data
		)

		local trackedSpeed =
			flat(data.Velocity or Vector3.zero).Magnitude
		local trackedAbsAccel =
			math.abs(data.SpeedAccel or 0)

		frameMaxSpeed =
			math.max(
				frameMaxSpeed,
				math.min(
					trackedSpeed,
					SPATIAL_TYPICAL_SPEED_CAP
				)
			)
		frameMaxAbsAccel =
			math.max(
				frameMaxAbsAccel,
				math.min(
					trackedAbsAccel,
					SPATIAL_TYPICAL_ACCEL_CAP
				)
			)
		frameMaxRadius =
			math.max(
				frameMaxRadius,
				data.Radius or 0
			)

		if data.IsAreaHazard then
			newAreaList[#newAreaList + 1] = data
		end

		if trackedSpeed > SPATIAL_TYPICAL_SPEED_CAP
			or trackedAbsAccel > SPATIAL_TYPICAL_ACCEL_CAP
		then
			newExtremeList[#newExtremeList + 1] = data
		end
	end

	ProjectileSpatialGrid = newSpatialGrid
	ProjectileAreaList = newAreaList
	ProjectileExtremeList = newExtremeList
	ProjectileSpatialReady = true
	SpatialMaxSpeed = frameMaxSpeed
	SpatialMaxAbsAccel = frameMaxAbsAccel
	SpatialMaxRadius = frameMaxRadius
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

local function closedFormProjectilePosition(data, t)
	local origin = getProjectileCenter(data)
	local velocity = data.Velocity or Vector3.zero
	local horizontal = flat(velocity)
	local speed = horizontal.Magnitude
	local direction =
		speed > 0.01
		and horizontal.Unit
		or Vector3.new(0, 0, -1)

	local speedAccel = data.SpeedAccel or 0
	local verticalAccel = data.VerticalAccel or 0
	local turnRate = data.TurnRate or 0

	local horizontalTime = t
	if speedAccel < 0 and speed > 0 then
		local stopTime = speed / -speedAccel
		horizontalTime = math.min(horizontalTime, stopTime)
	end

	local horizontalDelta = Vector3.zero

	if speed > 0.01 or speedAccel > 0 then
		if math.abs(turnRate) <= 1e-4 then
			local travel =
				analyticTravelDistance(
					speed,
					speedAccel,
					horizontalTime
				)
			horizontalDelta = direction * travel
		else
			local w = turnRate
			local wt = w * horizontalTime
			local sinWT = math.sin(wt)
			local cosWT = math.cos(wt)
			local invW = 1 / w
			local invW2 = invW * invW

			local along =
				speed * sinWT * invW
				+ speedAccel
					* (
						horizontalTime * sinWT * invW
						+ (cosWT - 1) * invW2
					)

			local side =
				speed * (1 - cosWT) * invW
				+ speedAccel
					* (
						-horizontalTime * cosWT * invW
						+ sinWT * invW2
					)

			local perpendicular =
				Vector3.new(
					-direction.Z,
					0,
					direction.X
				)

			horizontalDelta =
				direction * along
				+ perpendicular * side
		end
	end

	local y =
		origin.Y
			+ velocity.Y * t
			+ 0.5 * verticalAccel * t * t

	return Vector3.new(
		origin.X + horizontalDelta.X,
		y,
		origin.Z + horizontalDelta.Z
	)
end

local function simulateProjectilePositions(data, networkLead)
	local positions =
		table.create(TOTAL_PREDICTION_STEPS + 1)

	for positionIndex = 1, TOTAL_PREDICTION_STEPS + 1 do
		local t =
			networkLead
				+ getPredictionTime(positionIndex)

		positions[positionIndex] =
			closedFormProjectilePosition(data, t)
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

local function buildThreatSnapshot(root, humanoid, yieldCallback)
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

	local processedProjectiles = 0
	local spatialRadius =
		getProjectileSpatialQueryRadius(
			root,
			humanoid,
			PLAN_HORIZON,
			networkLead,
			NEAR_ZONE + BROAD_PHASE_EXTRA
		)
	local spatialCandidates =
		queryProjectileSpatial(
			root.Position,
			spatialRadius
		)

	for _, data in ipairs(spatialCandidates) do
		processedProjectiles += 1
		if yieldCallback
			and processedProjectiles % PREPROCESS_CLOCK_CHECK_EVERY == 0
		then
			yieldCallback()
		end

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

local function quickEscapeDirectionScore(root, humanoid, threats, direction)
	local position = root.Position
	local velocity = flat(root.AssemblyLinearVelocity)
	local cost = 0
	local elapsed = 0
	local minClearance = math.huge

	for stepIndex = 1, PLAN_STEPS do
		if elapsed >= FAN_ESCAPE_EVAL_TIME then
			break
		end

		local dt = getStepDt(stepIndex)
		local newPosition, newVelocity =
			simulatePlayerStep(
				position,
				velocity,
				direction,
				humanoid.WalkSpeed,
				dt,
				stepIndex == 1
			)

		local threatRisk, hits, clearance, farRisk =
			evaluateThreatSegment(
				position,
				newPosition,
				stepIndex,
				threats
			)

		local barrierRisk, wallHit =
			evaluateBarrierSegment(position, newPosition)

		cost += threatRisk + barrierRisk + (farRisk or 0) * 0.8
		if hits > 0 then
			cost += hits * HIT_PENALTY
		end
		if wallHit then
			cost += WALL_HIT_PENALTY
		end

		minClearance = math.min(minClearance, clearance)
		position = newPosition
		velocity = newVelocity
		elapsed += dt
	end

	local wallClearance = nearestBarrierDistance(position)
	cost -= math.min(wallClearance, 8) * 2.2
	cost -= math.max(-1, math.min(minClearance, 4)) * 3.0
	return cost
end

local function analyzeDenseFront(root, humanoid, threats, yieldCallback)
	local sampleIndex = getPositionIndexNearTime(FAN_SAMPLE_TIME)
	local occupied = table.create(FAN_ANGLE_BINS, false)
	local candidateCount = 0
	local incomingSum = Vector3.zero
	local centroidSum = Vector3.zero
	local speedSum = 0
	local binAngle = math.pi * 2 / FAN_ANGLE_BINS

	local scannedThreats = 0
	for _, threat in ipairs(threats) do
		scannedThreats += 1
		if yieldCallback
			and scannedThreats % PREPROCESS_CLOCK_CHECK_EVERY == 0
		then
			yieldCallback()
		end

		if not threat.IsArea
			and threat.Positions
			and threat.Positions[sampleIndex]
			and (threat.Speed or math.huge) <= FAN_MAX_SPEED
		then
			local projectilePosition = threat.Positions[sampleIndex]
			local relative = flat(projectilePosition - root.Position)
			local distance = relative.Magnitude

			if distance >= 1.0 and distance <= FAN_MAX_DISTANCE then
				local velocity =
					threat.Data
					and flat(threat.Data.Velocity)
					or Vector3.zero

				local approach = 1
				if velocity.Magnitude > 0.01 then
					approach =
						velocity.Unit:Dot((-relative).Unit)
				end

				if approach >= FAN_MIN_APPROACH_DOT then
					candidateCount += 1
					centroidSum += projectilePosition
					speedSum += threat.Speed or 0

					if velocity.Magnitude > 0.01 then
						incomingSum += velocity.Unit
					end

					local angle = math.atan2(relative.Z, relative.X)
					local normalized = (angle + math.pi) / (math.pi * 2)
					local centerBin =
						(math.floor(normalized * FAN_ANGLE_BINS) % FAN_ANGLE_BINS) + 1

					local angularRadius =
						math.asin(
							math.clamp(
								((threat.DangerRadius or 0.5) + 0.28)
									/ math.max(distance, 0.5),
								0,
								0.98
							)
						)
					local halfBins = math.max(1, math.ceil(angularRadius / binAngle))

					for offset = -halfBins, halfBins do
						local index = ((centerBin - 1 + offset) % FAN_ANGLE_BINS) + 1
						occupied[index] = true
					end
				end
			end
		end
	end

	if candidateCount < FAN_MIN_PROJECTILES then
		return nil
	end

	local longest = 0
	local current = 0
	for i = 1, FAN_ANGLE_BINS * 2 do
		local index = ((i - 1) % FAN_ANGLE_BINS) + 1
		if occupied[index] then
			current += 1
			longest = math.max(longest, math.min(current, FAN_ANGLE_BINS))
		else
			current = 0
		end
	end

	local arcDegrees = longest * 360 / FAN_ANGLE_BINS
	if arcDegrees < FAN_MIN_ARC_DEGREES
		or arcDegrees > FAN_MAX_ARC_DEGREES
	then
		return nil
	end

	local centroid = centroidSum / candidateCount
	local away = clampUnit(root.Position - centroid)
	local incoming = clampUnit(incomingSum)
	if incoming.Magnitude < 0.01 then
		incoming = away.Magnitude > 0.01 and -away or Vector3.new(0, 0, -1)
	end

	local tangent = Vector3.new(-incoming.Z, 0, incoming.X)
	local candidates = {}
	local function addCandidate(v)
		v = clampUnit(v)
		if v.Magnitude < 0.01 then
			return
		end
		for _, existing in ipairs(candidates) do
			if existing:Dot(v) > 0.995 then
				return
			end
		end
		candidates[#candidates + 1] = v
	end

	addCandidate(tangent)
	addCandidate(-tangent)
	addCandidate(away)
	addCandidate(tangent * 0.82 + away * 0.58)
	addCandidate(-tangent * 0.82 + away * 0.58)

	local bestDirection = nil
	local bestScore = math.huge
	for _, direction in ipairs(candidates) do
		local score =
			quickEscapeDirectionScore(
				root,
				humanoid,
				threats,
				direction
			)

		if score < bestScore then
			bestScore = score
			bestDirection = direction
		end
	end

	if not bestDirection then
		return nil
	end

	return {
		Active = true,
		PreferredDirection = bestDirection,
		BestScore = bestScore,
		Count = candidateCount,
		ArcDegrees = arcDegrees,
		AverageSpeed = speedSum / math.max(candidateCount, 1),
		ForecastTime = FAN_SAMPLE_TIME,
		Centroid = centroid,
		Incoming = incoming,
		Away = away,
		Origin = root.Position,
		Strength =
			math.clamp(
				(candidateCount / math.max(FAN_MIN_PROJECTILES, 1))
					* (arcDegrees / 110),
				0.65,
				2.25
			)
	}
end

local function clearFanModel()
	CurrentFanInfo = nil
	LastFanSeenAt = 0
	LastFanCount = 0
	LastFanArc = 0
	LastFanDirection = Vector3.zero
	LastFanForecastTime = 0
end

local function updateFanModel(detectedFront, root, humanoid, threats, now)
	if not detectedFront then
		if CurrentFanInfo
			and now - LastFanSeenAt <= FAN_INFO_GRACE
		then
			local age =
				math.clamp(
					(now - LastFanSeenAt) / FAN_INFO_GRACE,
					0,
					1
				)
			CurrentFanInfo.Strength =
				math.max(
					0,
					(CurrentFanInfo.BaseStrength or 1)
						* (1 - age)
				)
			return CurrentFanInfo
		end

		clearFanModel()
		return nil
	end

	local proposed =
		clampUnit(detectedFront.PreferredDirection)
	if proposed.Magnitude < 0.01 then
		clearFanModel()
		return nil
	end

	local chosen = proposed

	if CurrentFanInfo
		and CurrentFanInfo.PreferredDirection
		and CurrentFanInfo.PreferredDirection.Magnitude > 0.01
	then
		local previous =
			CurrentFanInfo.PreferredDirection.Unit
		local dot =
			math.clamp(previous:Dot(proposed), -1, 1)

		if dot < 0.35 then
			-- This is only preference hysteresis inside MPC. It never owns the
			-- character. Switch sides only if the new side is clearly cheaper.
			local previousScore =
				quickEscapeDirectionScore(
					root,
					humanoid,
					threats,
					previous
				)
			local newScore =
				detectedFront.BestScore
				or quickEscapeDirectionScore(
					root,
					humanoid,
					threats,
					proposed
				)

			local requiredAdvantage =
				math.max(
					FAN_SWITCH_MIN_SCORE,
					math.abs(previousScore)
						* FAN_SWITCH_ADVANTAGE
				)

			if previousScore - newScore
				< requiredAdvantage
			then
				chosen = previous
			end
		else
			local blended =
				previous * (1 - FAN_DIRECTION_SMOOTH)
				+ proposed * FAN_DIRECTION_SMOOTH
			if blended.Magnitude > 0.01 then
				chosen = blended.Unit
			end
		end
	end

	detectedFront.PreferredDirection = chosen
	detectedFront.BaseStrength =
		detectedFront.Strength or 1
	detectedFront.Strength =
		detectedFront.BaseStrength
	detectedFront.LastSeenAt = now

	CurrentFanInfo = detectedFront
	LastFanSeenAt = now
	LastFanCount = detectedFront.Count or 0
	LastFanArc = detectedFront.ArcDegrees or 0
	LastFanDirection = chosen
	LastFanForecastTime = detectedFront.ForecastTime or FAN_SAMPLE_TIME

	return CurrentFanInfo
end

local function getFanInfo(now)
	if not CurrentFanInfo then
		return nil
	end

	now = now or os.clock()
	if now - LastFanSeenAt > FAN_INFO_GRACE then
		return nil
	end

	if (CurrentFanInfo.Strength or 0) <= 0.01 then
		return nil
	end

	return CurrentFanInfo
end

local function evaluateFanAwareCost(
	oldPosition,
	newPosition,
	direction,
	stepEndTime,
	fanInfo,
	scale
)
	if not fanInfo
		or not fanInfo.PreferredDirection
		or fanInfo.PreferredDirection.Magnitude < 0.01
	then
		return 0
	end

	scale = scale or 1
	local strength =
		math.clamp(fanInfo.Strength or 1, 0, 2.5)
	if strength <= 0.01 then
		return 0
	end

	local timeWeight =
		1
			- 0.30
				* math.clamp(
					stepEndTime / FAN_COST_HORIZON,
					0,
					1
				)

	local preferred = fanInfo.PreferredDirection.Unit
	local away =
		fanInfo.Away
		and fanInfo.Away.Magnitude > 0.01
		and fanInfo.Away.Unit
		or preferred

	local cost = 0

	if direction.Magnitude <= 0.01 then
		cost += FAN_STOP_PENALTY
	else
		local dot =
			math.clamp(
				direction.Unit:Dot(preferred),
				-1,
				1
			)
		cost +=
			(1 - dot)
				* FAN_DIRECTION_WEIGHT

		if dot < 0 then
			cost +=
				(-dot)
					* FAN_REVERSE_EXTRA
		end
	end

	local move = flat(newPosition - oldPosition)
	if move.Magnitude > 0.001 then
		local progress =
			move:Dot(preferred)

		if progress < 0 then
			cost +=
				(-progress)
					* FAN_PROGRESS_WEIGHT
		else
			cost -=
				progress
					* FAN_PROGRESS_REWARD
		end

		if fanInfo.Centroid then
			local toCenter =
				flat(fanInfo.Centroid - oldPosition)
			if toCenter.Magnitude > 0.01 then
				local centerDot =
					move.Unit:Dot(toCenter.Unit)
				if centerDot > 0 then
					cost +=
						centerDot
							* move.Magnitude
							* FAN_CENTER_WEIGHT
				end
			end
		end
	end

	if fanInfo.Centroid then
		local oldDistance =
			flat(oldPosition - fanInfo.Centroid).Magnitude
		local newDistance =
			flat(newPosition - fanInfo.Centroid).Magnitude
		local outwardGain =
			newDistance - oldDistance

		if outwardGain < 0 then
			cost +=
				(-outwardGain)
					* FAN_DEEPER_WEIGHT
		else
			cost -=
				outwardGain
					* FAN_OUTWARD_REWARD
		end
	end

	if direction.Magnitude > 0.01 then
		local awayDot =
			direction.Unit:Dot(away)
		if awayDot < -0.25 then
			cost +=
				(-awayDot - 0.25)
					* FAN_CENTER_WEIGHT
		end
	end

	return cost * strength * timeWeight * scale
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
local ImmediateMPCDirectionList =
	makeAbsoluteDirections(IMMEDIATE_MPC_DIRECTIONS)

local function immediateProjectilePosition(data, t)
	return closedFormProjectilePosition(data, t)
end

local function analyzeProactiveFanRaw(root, humanoid, threats)
	local rootPosition = root.Position
	local rootVelocity = flat(root.AssemblyLinearVelocity)
	local binAngle = math.pi * 2 / FAN_ANGLE_BINS
	local best = nil
	local bestStrength = -math.huge

	local fanCandidates =
		queryProjectileSpatial(
			rootPosition,
			FAN_FORECAST_SCAN_DISTANCE
				+ SPATIAL_QUERY_PADDING
		)

	for _, forecastTime in ipairs(FAN_FORECAST_TIMES) do
		local occupied = table.create(FAN_ANGLE_BINS, false)
		local candidateCount = 0
		local centroidSum = Vector3.zero
		local incomingSum = Vector3.zero
		local speedSum = 0
		local nearestDistance = math.huge

		-- Continue-current-motion is enough for feature extraction. MPC itself
		-- will test alternate player paths after this forecast is built.
		local futureRoot =
			rootPosition
				+ rootVelocity
					* math.min(forecastTime, 0.24)

		for _, data in ipairs(fanCandidates) do
			if data.Part
				and data.Part.Parent
				and not data.IsAreaHazard
				and (data.Samples or 0) >= 1
			then
				local velocity = data.Velocity or Vector3.zero
				local flatVelocity = flat(velocity)
				local speed = flatVelocity.Magnitude

				if speed >= MIN_PROJECTILE_SPEED
					and speed <= FAN_FORECAST_MAX_SPEED
				then
					local currentPosition =
						getProjectileCenter(data)
					local currentRelative =
						flat(currentPosition - rootPosition)
					local currentDistance =
						currentRelative.Magnitude

					if currentDistance <= FAN_FORECAST_SCAN_DISTANCE then
						local futurePosition =
							immediateProjectilePosition(
								data,
								forecastTime
							)
						local relative =
							flat(futurePosition - futureRoot)
						local distance = relative.Magnitude

						if distance >= 0.8
							and distance <= FAN_FORECAST_MAX_DISTANCE
							and distance
								<= currentDistance
									+ FAN_FORECAST_DISTANCE_SLACK
						then
							-- Reject bullets that are strongly escaping from the
							-- player, but keep sideways/sweeping slow fan walls.
							local approach = 0
							if flatVelocity.Magnitude > 0.01
								and currentRelative.Magnitude > 0.01
							then
								approach =
									flatVelocity.Unit:Dot(
										(-currentRelative).Unit
									)
							end

							local closing =
								currentDistance - distance

							if approach >= -0.18
								or closing >= 0.35
							then
								candidateCount += 1
								centroidSum += futurePosition
								speedSum += speed
								nearestDistance =
									math.min(
										nearestDistance,
										distance
									)

								if flatVelocity.Magnitude > 0.01 then
									incomingSum += flatVelocity.Unit
								end

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
												* FAN_ANGLE_BINS
										)
										% FAN_ANGLE_BINS
									) + 1

								local dangerRadius =
									immediateDangerRadius(data)
								local angularRadius =
									math.asin(
										math.clamp(
											(dangerRadius + 0.34)
												/ math.max(distance, 0.5),
											0,
											0.98
										)
									)
								local halfBins =
									math.max(
										1,
										math.ceil(
											angularRadius / binAngle
										)
									)

								for offset = -halfBins, halfBins do
									local bin =
										(
											(centerBin - 1 + offset)
											% FAN_ANGLE_BINS
										) + 1
									occupied[bin] = true
								end
							end
						end
					end
				end
			end
		end

		if candidateCount >= FAN_FORECAST_MIN_PROJECTILES then
			local longest = 0
			local run = 0

			for i = 1, FAN_ANGLE_BINS * 2 do
				local bin =
					((i - 1) % FAN_ANGLE_BINS) + 1
				if occupied[bin] then
					run += 1
					longest =
						math.max(
							longest,
							math.min(run, FAN_ANGLE_BINS)
						)
				else
					run = 0
				end
			end

			local arcDegrees =
				longest * 360 / FAN_ANGLE_BINS

			if arcDegrees >= FAN_FORECAST_MIN_ARC_DEGREES
				and arcDegrees <= FAN_FORECAST_MAX_ARC_DEGREES
			then
				local centroid =
					centroidSum / candidateCount
				local away =
					clampUnit(rootPosition - centroid)
				local incoming =
					clampUnit(incomingSum)

				if incoming.Magnitude < 0.01 then
					incoming =
						away.Magnitude > 0.01
						and -away
						or Vector3.new(0, 0, -1)
				end

				local tangent =
					Vector3.new(
						-incoming.Z,
						0,
						incoming.X
					)

				local candidates = {}
				local function addCandidate(v)
					v = clampUnit(v)
					if v.Magnitude < 0.01 then
						return
					end
					for _, existing in ipairs(candidates) do
						if existing:Dot(v) > 0.995 then
							return
						end
					end
					candidates[#candidates + 1] = v
				end

				addCandidate(tangent)
				addCandidate(-tangent)
				addCandidate(away)
				addCandidate(
					tangent * 0.82
						+ away * 0.58
				)
				addCandidate(
					-tangent * 0.82
						+ away * 0.58
				)

				local preferred = nil
				local preferredScore = math.huge
				for _, direction in ipairs(candidates) do
					local score =
						quickEscapeDirectionScore(
							root,
							humanoid,
							threats,
							direction
						)
					if score < preferredScore then
						preferredScore = score
						preferred = direction
					end
				end

				if preferred then
					local countStrength =
						candidateCount
							/ FAN_FORECAST_MIN_PROJECTILES
					local arcStrength =
						arcDegrees / 95
					local proximityStrength =
						1
							+ math.clamp(
								(
									FAN_FORECAST_MAX_DISTANCE
										- nearestDistance
								)
									/ FAN_FORECAST_MAX_DISTANCE,
								0,
								1
							) * 0.55
					local earlyBonus =
						1
							+ (
								1
									- forecastTime
										/ FAN_FORECAST_TIMES[
											#FAN_FORECAST_TIMES
										]
							)
								* FAN_FORECAST_EARLY_BONUS

					local strength =
						countStrength
							* arcStrength
							* proximityStrength
							* earlyBonus

					if strength >= FAN_FORECAST_MIN_STRENGTH
						and strength > bestStrength
					then
						bestStrength = strength
						best = {
							Active = true,
							PreferredDirection = preferred,
							BestScore = preferredScore,
							Count = candidateCount,
							ArcDegrees = arcDegrees,
							AverageSpeed =
								speedSum
									/ math.max(
										candidateCount,
										1
									),
							ForecastTime = forecastTime,
							Centroid = centroid,
							Incoming = incoming,
							Away = away,
							Origin = rootPosition,
							Strength =
								math.clamp(
									strength,
									0.72,
									2.45
								)
						}
					end
				end
			end
		end
	end

	return best
end

local function immediateDangerRadius(data)
	local speed = flat(data.Velocity or Vector3.zero).Magnitude
	local errorMargin =
		math.clamp(
			BASE_ERROR_MARGIN
				+ (data.PredictionError or 0) * PREDICTION_ERROR_WEIGHT
				+ speed * SPEED_MARGIN_WEIGHT
				+ math.abs(data.TurnRate or 0) * TURN_MARGIN_WEIGHT,
			BASE_ERROR_MARGIN,
			MAX_ERROR_MARGIN
		)

	return
		(data.Radius or 0)
		+ PLAYER_MINI_RADIUS
		+ errorMargin
end

local function getImmediateStepCount()
	local count = 0
	for i = 1, PLAN_STEPS do
		if getStepEndTime(i) <= IMMEDIATE_MPC_HORIZON + 1e-5 then
			count = i
		else
			break
		end
	end
	return math.max(1, count)
end

local IMMEDIATE_MPC_STEPS = getImmediateStepCount()

local function buildImmediateMPCSnapshot(root, humanoid)
	local threats = {}
	local byStep = table.create(TOTAL_PREDICTION_STEPS)
	local areaByStep = table.create(TOTAL_PREDICTION_STEPS)
	local farField = table.create(TOTAL_PREDICTION_STEPS)

	for i = 1, TOTAL_PREDICTION_STEPS do
		byStep[i] = {}
		areaByStep[i] = {}
		farField[i] = {}
	end

	local rootPosition = root.Position
	local rootVelocity = flat(root.AssemblyLinearVelocity)
	local networkLead = getNetworkLead()
	local candidates = {}
	local spatialRadius =
		getProjectileSpatialQueryRadius(
			root,
			humanoid,
			IMMEDIATE_MPC_HORIZON,
			networkLead,
			IMMEDIATE_MPC_NEAR_ZONE + 2.0
		)
	local spatialCandidates =
		queryProjectileSpatial(
			rootPosition,
			spatialRadius
		)

	for _, data in ipairs(spatialCandidates) do
		if data.Part and data.Part.Parent then
			if data.IsAreaHazard and data.BoxCFrame and data.BoxSize then
				local expansion =
					PLAYER_MINI_RADIUS
					+ AREA_HAZARD_ERROR_MARGIN

				local currentClearance =
					pointBoxSignedDistance(
						data.BoxCFrame,
						data.BoxSize,
						rootPosition,
						expansion
					)

				local futureBox =
					predictAreaBox(
						data,
						IMMEDIATE_MPC_HORIZON
					)

				local futurePlayer =
					rootPosition
					+ rootVelocity * IMMEDIATE_MPC_HORIZON

				local futureClearance =
					futureBox
					and pointBoxSignedDistance(
						futureBox,
						data.BoxSize,
						futurePlayer,
						expansion
					)
					or currentClearance

				local urgency =
					math.min(
						currentClearance,
						futureClearance
					)

				if urgency <= AREA_HAZARD_INFLUENCE + 1.0 then
					candidates[#candidates + 1] = {
						Data = data,
						IsArea = true,
						Urgency = urgency
					}
				end
			else
				local velocity = data.Velocity or Vector3.zero
				local speed = flat(velocity).Magnitude

				if speed >= MIN_PROJECTILE_SPEED
					and (data.Samples or 0) >= 1
				then
					local relative =
						getProjectileCenter(data)
						- rootPosition
					local relativeVelocity =
						velocity - rootVelocity
					local denom =
						relativeVelocity:Dot(relativeVelocity)

					local closestTime = 0
					if denom > 1e-5 then
						closestTime =
							math.clamp(
								-relative:Dot(relativeVelocity) / denom,
								0,
								IMMEDIATE_MPC_HORIZON
							)
					end

					local predictedRelative =
						relative
						+ relativeVelocity * closestTime
					local clearance =
						predictedRelative.Magnitude
						- immediateDangerRadius(data)

					local reachable =
						humanoid.WalkSpeed * closestTime

					if clearance
						<= IMMEDIATE_MPC_NEAR_ZONE
							+ reachable
					then
						candidates[#candidates + 1] = {
							Data = data,
							IsArea = false,
							Urgency =
								clearance
								+ closestTime * 0.55
						}
					end
				end
			end
		end
	end

	if #candidates > IMMEDIATE_MPC_MAX_THREATS then
		table.sort(candidates, function(a, b)
			return a.Urgency < b.Urgency
		end)
		for i = #candidates, IMMEDIATE_MPC_MAX_THREATS + 1, -1 do
			candidates[i] = nil
		end
	end

	for _, candidate in ipairs(candidates) do
		local data = candidate.Data

		if candidate.IsArea then
			local boxes = {}
			local threat = {
				Data = data,
				IsArea = true,
				Boxes = boxes,
				BoxSize = data.BoxSize,
				Tier = "Immediate",
				EarliestRelevantTime = 0
			}

			for stepIndex = 1, IMMEDIATE_MPC_STEPS + 1 do
				local t =
					stepIndex == 1
					and 0
					or getStepEndTime(stepIndex - 1)

				boxes[stepIndex] =
					predictAreaBox(data, t + networkLead)
			end

			threats[#threats + 1] = threat

			for stepIndex = 1, IMMEDIATE_MPC_STEPS do
				local box0 = boxes[stepIndex]
				local box1 = boxes[stepIndex + 1]
				if box0 and box1 then
					local t = getStepEndTime(stepIndex)
					local reachable =
						humanoid.WalkSpeed * t
							+ rootVelocity.Magnitude
								* math.min(t, 0.16)

					local d0 =
						pointBoxSignedDistance(
							box0,
							data.BoxSize,
							rootPosition,
							PLAYER_MINI_RADIUS
								+ AREA_HAZARD_ERROR_MARGIN
						)
					local d1 =
						pointBoxSignedDistance(
							box1,
							data.BoxSize,
							rootPosition,
							PLAYER_MINI_RADIUS
								+ AREA_HAZARD_ERROR_MARGIN
						)

					if math.min(d0, d1)
						<= AREA_HAZARD_INFLUENCE
							+ reachable
							+ 0.65
					then
						areaByStep[stepIndex][#areaByStep[stepIndex] + 1] =
							threat
					end
				end
			end
		else
			local positions = {}
			local dangerRadius = immediateDangerRadius(data)

			for stepIndex = 1, IMMEDIATE_MPC_STEPS + 1 do
				local t =
					stepIndex == 1
					and 0
					or getStepEndTime(stepIndex - 1)

				positions[stepIndex] =
					immediateProjectilePosition(
						data,
						t + networkLead
					)
			end

			local threat = {
				Data = data,
				IsArea = false,
				Positions = positions,
				DangerRadius = dangerRadius,
				ErrorMargin = math.max(
					0,
					dangerRadius
						- (data.Radius or 0)
						- PLAYER_MINI_RADIUS
				),
				Speed = flat(data.Velocity).Magnitude,
				Tier = "Immediate",
				EarliestRelevantTime = 0
			}

			threats[#threats + 1] = threat

			for stepIndex = 1, IMMEDIATE_MPC_STEPS do
				local p0 = positions[stepIndex]
				local p1 = positions[stepIndex + 1]
				if p0 and p1 then
					local relativeA = p0 - rootPosition
					local relativeB = p1 - rootPosition
					local stationaryDistance =
						segmentMinDistance(
							relativeA,
							relativeB
						)

					local t = getStepEndTime(stepIndex)
					local reachable =
						humanoid.WalkSpeed * t
							+ rootVelocity.Magnitude
								* math.min(t, 0.16)

					if stationaryDistance
						<= dangerRadius
							+ IMMEDIATE_MPC_NEAR_ZONE
							+ reachable
							+ 0.45
					then
						byStep[stepIndex][#byStep[stepIndex] + 1] =
							threat
					end
				end
			end
		end
	end

	threats.ByStep = byStep
	threats.AreaByStep = areaByStep
	threats.FarField = farField
	return threats
end

local function evaluateImmediateMPCBaseline(root, humanoid, threats)
	local position = root.Position
	local velocity = flat(root.AssemblyLinearVelocity)
	local hits = 0
	local minClearance = math.huge
	local earliestImpact = math.huge

	for stepIndex = 1, IMMEDIATE_MPC_STEPS do
		local dt = getStepDt(stepIndex)
		local newPosition, newVelocity =
			simulatePlayerStep(
				position,
				velocity,
				Vector3.zero,
				getPredictedWalkSpeed(humanoid, AppliedFocus),
				dt,
				stepIndex == 1
			)

		local _, stepHits, clearance =
			evaluateThreatSegment(
				position,
				newPosition,
				stepIndex,
				threats
			)

		hits += stepHits
		minClearance = math.min(minClearance, clearance)

		if stepHits > 0 and earliestImpact == math.huge then
			earliestImpact = getStepEndTime(stepIndex)
		end

		position = newPosition
		velocity = newVelocity
	end

	return {
		Hits = hits,
		MinClearance = minClearance,
		EarliestImpact = earliestImpact
	}
end

local function immediateMPCNodeBetter(a, b)
	if not b then
		return true
	end
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

local function immediateMPCDominanceKey(node)
	local px =
		math.floor(node.Pos.X / DOMINANCE_CELL + 0.5)
	local pz =
		math.floor(node.Pos.Z / DOMINANCE_CELL + 0.5)

	local dirBin = 0
	if node.Dir.Magnitude > 0.01 then
		local angle =
			math.atan2(node.Dir.Z, node.Dir.X)
		local normalized =
			(angle + math.pi) / (math.pi * 2)
		dirBin =
			math.floor(
				normalized * DOMINANCE_DIR_BINS
			) % DOMINANCE_DIR_BINS
	end

	return
		tostring(px)
		.. ":"
		.. tostring(pz)
		.. ":"
		.. tostring(dirBin)
		.. ":"
		.. (node.Focus and "F" or "N")
end

local function getImmediateMPCInputs(previousDirection, depth, emergency, fanInfo)
	if depth == 1 then
		if fanInfo
			and fanInfo.PreferredDirection
			and fanInfo.PreferredDirection.Magnitude > 0.01
		then
			local preferred = fanInfo.PreferredDirection.Unit
			local list = {
				preferred,
				rotateY(preferred, math.rad(-22.5)),
				rotateY(preferred, math.rad(22.5))
			}
			for _, candidate in ipairs(ImmediateMPCDirectionList) do
				list[#list + 1] = candidate
			end
			return list
		end
		return ImmediateMPCDirectionList
	end

	if previousDirection.Magnitude < 0.01 then
		return ZeroRestartDirectionList
	end

	local unit = previousDirection.Unit
	local list = {
		unit,
		rotateY(unit, math.rad(-22.5)),
		rotateY(unit, math.rad(22.5)),
		rotateY(unit, math.rad(-45)),
		rotateY(unit, math.rad(45)),
		Vector3.zero
	}

	if emergency then
		list[#list + 1] = rotateY(unit, math.rad(-90))
		list[#list + 1] = rotateY(unit, math.rad(90))
		list[#list + 1] = -unit
	end

	return list
end

local function planImmediateMPC(root, humanoid, threats, fanInfo)
	local dense =
		#threats >= math.min(
			DENSE_THREAT_COUNT,
			math.floor(IMMEDIATE_MPC_MAX_THREATS * 0.35)
		)

	local beamWidth =
		dense
		and IMMEDIATE_MPC_DENSE_BEAM_WIDTH
		or IMMEDIATE_MPC_BEAM_WIDTH

	local rootVelocity = flat(root.AssemblyLinearVelocity)

	local beam = {
		{
			Pos = root.Position,
			Vel = rootVelocity,
			Dir = Vector3.zero,
			FirstDir = Vector3.zero,
			Focus = AppliedFocus,
			FirstFocus = AppliedFocus,
			FocusAge = os.clock() - LastFocusToggleAt,
			Cost = 0,
			Hits = 0,
			WallHits = 0,
			MinClearance = math.huge,
			Depth = 0
		}
	}

	for depth = 1, IMMEDIATE_MPC_STEPS do
		local dominance = {}

		for _, node in ipairs(beam) do
			local emergency =
				node.Hits > 0
				or node.MinClearance < 0.18

			local inputs =
				getImmediateMPCInputs(
					node.Dir,
					depth,
					emergency,
					fanInfo
				)

			local allowFocus =
				dense
				or fanInfo ~= nil
				or emergency
				or node.MinClearance <= FOCUS_CONSIDER_CLEARANCE
				or #threats >= FOCUS_CONSIDER_THREATS

			for _, inputDirection in ipairs(inputs) do
				local direction = clampUnit(inputDirection)
				local focusOptions =
					getFocusOptions(
						node,
						allowFocus,
						emergency
					)

				for _, focusWanted in ipairs(focusOptions) do
					local dt = getStepDt(depth)
					local predictedWalkSpeed =
						getPredictedWalkSpeed(
							humanoid,
							focusWanted
						)

					local newPosition, newVelocity =
						simulatePlayerStep(
							node.Pos,
							node.Vel,
							direction,
							predictedWalkSpeed,
							dt,
							depth == 1
						)

				local threatRisk, stepHits, clearance =
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
					flat(newPosition - node.Pos).Magnitude

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
						* IMMEDIATE_MPC_TURN_WEIGHT
				end

				if depth == 1
					and LastAppliedMove.Magnitude > 0.01
					and direction.Magnitude > 0.01
				then
					local dot =
						math.clamp(
							LastAppliedMove.Unit:Dot(direction.Unit),
							-1,
							1
						)
					turnCost +=
						(1 - dot)
						* IMMEDIATE_MPC_TURN_WEIGHT
						* 1.25
				end

				local stopCost =
					direction.Magnitude <= 0.01
					and (
						(stepHits > 0 or clearance < 0.25)
						and IMMEDIATE_MPC_STOP_PENALTY
						or 0
					)
					or 0

				local fanCost =
					evaluateFanAwareCost(
						node.Pos,
						newPosition,
						direction,
						getStepEndTime(depth),
						fanInfo,
						FAN_IMMEDIATE_SCALE
					)

					local focusCost =
						focusTransitionCost(
							node.Focus,
							focusWanted,
							dt,
							emergency
						)

					local newNode = {
						Pos = newPosition,
						Vel = newVelocity,
						Dir = direction,
						FirstDir =
							depth == 1
							and direction
							or node.FirstDir,
						Focus = focusWanted,
						FirstFocus =
							depth == 1
							and focusWanted
							or node.FirstFocus,
						FocusAge =
							node.Focus == focusWanted
							and ((node.FocusAge or 0) + dt)
							or 0,
						Cost =
							node.Cost
							+ threatRisk
							+ barrierRisk
							+ moveDistance * MOVE_COST_WEIGHT
							+ turnCost
							+ stopCost
							+ fanCost
							+ focusCost,
					Hits = node.Hits + stepHits,
					WallHits =
						node.WallHits
						+ (wallHit and 1 or 0),
					MinClearance =
						math.min(
							node.MinClearance,
							clearance
						),
					Depth = depth
				}

				local key =
					immediateMPCDominanceKey(newNode)
				local existing = dominance[key]

					if not existing
						or immediateMPCNodeBetter(
							newNode,
							existing
						)
					then
						dominance[key] = newNode
					end
				end
			end
		end

		local nextBeam = {}
		for _, node in pairs(dominance) do
			nextBeam[#nextBeam + 1] = node
		end

		table.sort(nextBeam, immediateMPCNodeBetter)

		beam = {}
		local keep = math.min(beamWidth, #nextBeam)
		for i = 1, keep do
			beam[i] = nextBeam[i]
		end

		if #beam == 0 then
			return nil
		end
	end

	local best = beam[1]
	if not best then
		return nil
	end

	local bestMoving = nil
	for _, candidate in ipairs(beam) do
		if candidate.FirstDir.Magnitude > 0.01 then
			bestMoving = candidate
			break
		end
	end

	return {
		Direction = best.FirstDir,
		Focus = best.FirstFocus,
		MovingAlternative = bestMoving,
		Hits = best.Hits,
		WallHits = best.WallHits,
		MinClearance = best.MinClearance,
		Cost = best.Cost
	}
end

local function runImmediateMPC()
	if not ENABLED then
		ImmediateMPCActive = false
		ImmediateMPCMove = Vector3.zero
		ImmediateMPCFocus = AppliedFocus
		return
	end

	local now = os.clock()
	if now - LastImmediateMPCTime < IMMEDIATE_MPC_INTERVAL then
		return
	end
	LastImmediateMPCTime = now

	local _, humanoid, root = getCharacter()
	if not humanoid or not root then
		ImmediateMPCActive = false
		ImmediateMPCMove = Vector3.zero
		ImmediateMPCFocus = AppliedFocus
		return
	end

	local started = os.clock()
	local function recordImmediateTiming()
		LastImmediateMPCMs =
			(os.clock() - started) * 1000
		ImmediateMsEMA +=
			(LastImmediateMPCMs - ImmediateMsEMA)
				* IMMEDIATE_MS_EMA_ALPHA
	end


	refreshActiveBarriers(
		root.Position,
		humanoid.WalkSpeed
	)

	local threats =
		buildImmediateMPCSnapshot(
			root,
			humanoid
		)

	LastImmediateMPCThreats = #threats

	-- FAN forecasting belongs to the MPC perception stage. It is intentionally
	-- computed here so the 0.55s MPC does not have to wait for the slower 1.5s
	-- planner to notice a dense wall first.
	local proactiveFan =
		analyzeProactiveFanRaw(
			root,
			humanoid,
			threats
		)

	local fanInfo
	if proactiveFan then
		fanInfo =
			updateFanModel(
				proactiveFan,
				root,
				humanoid,
				threats,
				now
			)
	else
		fanInfo = getFanInfo(now)
	end

	if #threats == 0 and not fanInfo then
		ImmediateMPCActive = false
		ImmediateMPCMove = Vector3.zero
		ImmediateMPCFocus = AppliedFocus
		LastImmediateMPCClearance = math.huge
		recordImmediateTiming()
		return
	end

	local baseline =
		evaluateImmediateMPCBaseline(
			root,
			humanoid,
			threats
		)

	LastImmediateMPCClearance =
		baseline.MinClearance

	local dense = #threats >= DENSE_THREAT_COUNT
	local urgent =
		fanInfo ~= nil
		or baseline.Hits > 0
		or baseline.MinClearance
			<= (
				dense
				and IMMEDIATE_MPC_PROACTIVE_DENSE
				or IMMEDIATE_MPC_TRIGGER_CLEARANCE
			)

	if not urgent then
		ImmediateMPCActive = false
		ImmediateMPCMove = Vector3.zero
		recordImmediateTiming()
		return
	end

	local plan =
		planImmediateMPC(
			root,
			humanoid,
			threats,
			fanInfo
		)

	if plan then
		local chosenDirection = plan.Direction
		local chosenFocus = plan.Focus == true

		if baseline.Hits > 0
			and chosenDirection.Magnitude <= 0.01
			and plan.MovingAlternative
		then
			chosenDirection =
				plan.MovingAlternative.FirstDir
			chosenFocus =
				plan.MovingAlternative.FirstFocus == true
		end

		ImmediateMPCMove = chosenDirection
		ImmediateMPCFocus = chosenFocus
		ImmediateMPCActive =
			ImmediateMPCMove.Magnitude > 0.01
	else
		ImmediateMPCActive = false
		ImmediateMPCMove = Vector3.zero
		ImmediateMPCFocus = AppliedFocus
	end

	recordImmediateTiming()
end

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

local function appendUniqueDirection(list, direction)
	direction = clampUnit(direction)
	if direction.Magnitude < 0.01 then
		return
	end
	for _, existing in ipairs(list) do
		if existing.Magnitude > 0.01
			and existing.Unit:Dot(direction) > 0.997
		then
			return
		end
	end
	list[#list + 1] = direction
end

local function getNextInputs(previousDirection, depth, emergency, denseFront)
	local list = {}

	if depth == 1 then
		if denseFront and denseFront.Active then
			local preferred = denseFront.PreferredDirection
			appendUniqueDirection(list, preferred)
			appendUniqueDirection(list, rotateY(preferred, math.rad(-18)))
			appendUniqueDirection(list, rotateY(preferred, math.rad(18)))
			appendUniqueDirection(list, rotateY(preferred, math.rad(-38)))
			appendUniqueDirection(list, rotateY(preferred, math.rad(38)))
		end

		for _, direction in ipairs(InitialDirectionList) do
			if direction.Magnitude < 0.01 then
				list[#list + 1] = Vector3.zero
			else
				appendUniqueDirection(list, direction)
			end
		end
		return list
	end

	if previousDirection.Magnitude < 0.01 then
		for _, direction in ipairs(ZeroRestartDirectionList) do
			if direction.Magnitude < 0.01 then
				list[#list + 1] = Vector3.zero
			else
				appendUniqueDirection(list, direction)
			end
		end
	else
		local farPhase = getStepEndTime(depth) > EXACT_THREAT_HORIZON
		local steeringAngles = farPhase and SteeringAnglesFar or SteeringAnglesNear
		local unit = previousDirection.Unit

		for _, angle in ipairs(steeringAngles) do
			appendUniqueDirection(list, rotateY(unit, angle))
		end

		if emergency then
			appendUniqueDirection(list, rotateY(unit, math.pi))
		end
	end

	if denseFront
		and denseFront.Active
		and getStepEndTime(depth) <= FAN_ESCAPE_COMMIT_TIME
	then
		appendUniqueDirection(list, denseFront.PreferredDirection)
		if previousDirection.Magnitude > 0.01 then
			appendUniqueDirection(
				list,
				previousDirection.Unit * 0.55
					+ denseFront.PreferredDirection * 0.75
			)
		end
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

local function quantizedDirectionBin(direction, bins)
	if direction.Magnitude < 0.01 then
		return -1
	end
	local angle = math.atan2(direction.Z, direction.X)
	local normalized = (angle + math.pi) / (math.pi * 2)
	return math.floor(normalized * bins + 0.5) % bins
end

local function dominanceKey(node)
	local ix = math.floor(node.Pos.X / DOMINANCE_CELL + 0.5)
	local iz = math.floor(node.Pos.Z / DOMINANCE_CELL + 0.5)
	local dirBin = quantizedDirectionBin(node.Dir, DOMINANCE_DIR_BINS)
	return
		tostring(ix)
		.. ":"
		.. tostring(iz)
		.. ":"
		.. tostring(dirBin)
		.. ":"
		.. (node.Focus and "F" or "N")
end

local function escapeCacheKey(node)
	local ix = math.floor(node.Pos.X / ESCAPE_CACHE_CELL + 0.5)
	local iz = math.floor(node.Pos.Z / ESCAPE_CACHE_CELL + 0.5)
	local dirBin = quantizedDirectionBin(node.Dir, 12)
	return tostring(node.Depth or 0) .. ":" .. tostring(ix) .. ":" .. tostring(iz) .. ":" .. tostring(dirBin)
end

local function opennessCacheKey(position)
	local ix = math.floor(position.X / OPENNESS_CACHE_CELL + 0.5)
	local iz = math.floor(position.Z / OPENNESS_CACHE_CELL + 0.5)
	return tostring(ix) .. ":" .. tostring(iz)
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
				getPredictedWalkSpeed(humanoid, AppliedFocus),
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
				getPredictedWalkSpeed(humanoid, node.Focus == true),
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
								getPredictedWalkSpeed(humanoid, node.Focus == true),
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

local function evaluateEscapeTrend(finalNode, humanoid, threats, escapeCache)
	local values = {}
	local penalty = 0

	for i, targetTime in ipairs(ESCAPE_TREND_TIMES) do
		local node = findNodeNearTime(finalNode, targetTime)
		local key = escapeCacheKey(node)
		local cached = escapeCache and escapeCache[key]
		if cached == nil then
			cached = countEscapeOptionsAtNode(node, humanoid, threats)
			if escapeCache then
				escapeCache[key] = cached
			end
		end
		values[i] = cached
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

local function planPath(root, humanoid, threats, denseFront)
	local beamWidth =
		getAdaptiveBeamWidth(
			LastImmediateThreatCount + LastNearThreatCount
		)

	local rootVelocity = flat(root.AssemblyLinearVelocity)
	local escapeCache = {}
	local opennessCache = {}
	local sliceStarted = os.clock()
	local expansionCounter = 0

	local function maybeYield()
		expansionCounter += 1

		-- Counter is only a cheap clock-sampling gate; the actual budget adapts.
		if expansionCounter % PLANNER_CLOCK_CHECK_EVERY == 0 then
			local budget = getPlannerSliceBudget()
			if os.clock() - sliceStarted >= budget then
				RunService.Heartbeat:Wait()
				sliceStarted = os.clock()
			end
		end
	end

	local beam = {
		{
			Pos = root.Position,
			Vel = rootVelocity,
			Dir = Vector3.zero,
			FirstDir = Vector3.zero,
			Focus = AppliedFocus,
			FirstFocus = AppliedFocus,
			FocusAge = os.clock() - LastFocusToggleAt,
			Cost = 0,
			Hits = 0,
			WallHits = 0,
			MinClearance = math.huge,
			Depth = 0,
			Parent = nil
		}
	}

	for depth = 1, PLAN_STEPS do
		local dominance = {}

		for _, node in ipairs(beam) do
			local emergency =
				node.Hits > 0
				or node.MinClearance < 0.20
			local inputs =
				getNextInputs(
					node.Dir,
					depth,
					emergency,
					denseFront
				)

			local allowFocus =
				denseFront ~= nil
				or emergency
				or node.MinClearance <= FOCUS_CONSIDER_CLEARANCE
				or (
					LastImmediateThreatCount
						+ LastNearThreatCount
				) >= FOCUS_CONSIDER_THREATS

			for _, inputDirection in ipairs(inputs) do
				local direction = clampUnit(inputDirection)
				local focusOptions =
					getFocusOptions(
						node,
						allowFocus,
						emergency
					)

				for _, focusWanted in ipairs(focusOptions) do
					local stepDt = getStepDt(depth)
					local predictedWalkSpeed =
						getPredictedWalkSpeed(
							humanoid,
							focusWanted
						)
					local newPosition, newVelocity =
						simulatePlayerStep(
							node.Pos,
							node.Vel,
							direction,
							predictedWalkSpeed,
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

				local continuityMove =
					ImmediateMPCActive
					and ImmediateMPCMove
					or CurrentMove

				if depth == 1
					and continuityMove.Magnitude > 0.01
					and direction.Magnitude > 0.01
				then
					local dot =
						math.clamp(
							continuityMove.Unit:Dot(direction.Unit),
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

				local fanCost =
					evaluateFanAwareCost(
						node.Pos,
						newPosition,
						direction,
						getStepEndTime(depth),
						denseFront,
						1
					)

					local focusCost =
						focusTransitionCost(
							node.Focus,
							focusWanted,
							stepDt,
							emergency
						)

					local newNode = {
						Pos = newPosition,
						Vel = newVelocity,
						Dir = direction,
						FirstDir =
							depth == 1
							and direction
							or node.FirstDir,
						Focus = focusWanted,
						FirstFocus =
							depth == 1
							and focusWanted
							or node.FirstFocus,
						FocusAge =
							node.Focus == focusWanted
							and ((node.FocusAge or 0) + stepDt)
							or 0,
						Cost =
							node.Cost
							+ threatRisk
							+ barrierRisk
							+ moveCost
							+ fanCost
							+ focusCost,
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

				local key = dominanceKey(newNode)
				local existing = dominance[key]
				if not existing or nodeSort(newNode, existing) then
					dominance[key] = newNode
				end

					maybeYield()
				end
			end
		end

		local nextBeam = {}
		for _, node in pairs(dominance) do
			nextBeam[#nextBeam + 1] = node
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

		if os.clock() - sliceStarted >= PLANNER_SLICE_BUDGET then
			RunService.Heartbeat:Wait()
			sliceStarted = os.clock()
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
			evaluateEscapeTrend(
				node,
				humanoid,
				threats,
				escapeCache
			)
		local escapeOptions = escapeTrend[#escapeTrend] or 0

		local openKey = opennessCacheKey(node.Pos)
		local openness = opennessCache[openKey]
		if not openness then
			local averageOpen, minimumOpen, closeRays =
				barrierOpenness(node.Pos)
			openness = {averageOpen, minimumOpen, closeRays}
			opennessCache[openKey] = openness
		end

		local averageOpen = openness[1]
		local minimumOpen = openness[2]
		local closeRays = openness[3]

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

		maybeYield()
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
		Focus = best.Node.FirstFocus,
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
Footer.Text = "Spatial MPC / Large-Barrier Safe / Native Focus"
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
		ImmediateMPCMove = Vector3.zero
		ImmediateMPCFocus = false
		ImmediateMPCActive = false
		CurrentPlanFocus = false
		LastAppliedMove = Vector3.zero
		clearFanModel()
		clearPathVisual()
		applyFocusState(false, true)
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
		return
	end

	local now = os.clock()
	if now - LastPlanTime < getPlanInterval() then
		return
	end

	LastPlanTime = now
	planning = true

	local started = os.clock()
	local preprocessSliceStarted = started

	local function preprocessYield()
		local budget = getPreprocessSliceBudget()
		if os.clock() - preprocessSliceStarted >= budget then
			RunService.Heartbeat:Wait()
			preprocessSliceStarted = os.clock()
		end
	end

	local ok, err = pcall(function()
		refreshActiveBarriers(
			root.Position,
			humanoid.WalkSpeed
		)

		local threats = buildThreatSnapshot(root, humanoid, preprocessYield)

		if #threats == 0 then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastMinClearance = math.huge
			LastImpactTime = math.huge
			LastEscapeOptions = 0
			LastFarRisk = 0
			LastEscapeTrendText = "-"
			clearFanModel()
			LastMode = "IDLE"
			clearPathVisual()
			return
		end

		local baseline = evaluateBaseline(root, humanoid, threats)
		LastMinClearance = baseline.MinClearance
		LastImpactTime = baseline.EarliestImpact
		LastFarRisk = baseline.FarRisk or 0

		local detectedDenseFront =
			analyzeDenseFront(
				root,
				humanoid,
				threats,
				preprocessYield
			)

		local fanInfo =
			updateFanModel(
				detectedDenseFront,
				root,
				humanoid,
				threats,
				os.clock()
			)

		local exactThreatCount =
			LastImmediateThreatCount + LastNearThreatCount
		local activationLookahead =
			exactThreatCount >= DENSE_THREAT_COUNT
			and DENSE_ACTIVATION_LOOKAHEAD
			or ACTIVATION_LOOKAHEAD

		local needPlan =
			fanInfo ~= nil
			or (
				baseline.Hits > 0
				and baseline.EarliestImpact <= activationLookahead
			)
			or baseline.MinClearance <= PROACTIVE_CLEARANCE
			or (
				exactThreatCount >= DENSE_THREAT_COUNT
				and baseline.MinClearance <= DENSE_PROACTIVE_CLEARANCE
			)
			or (baseline.FarRisk or 0) >= FAR_ACTIVATION_RISK

		if not needPlan then
			CurrentMove = Vector3.zero
			CurrentPlanFocus = false
			CurrentPath = nil
			LastEscapeOptions = 0
			LastEscapeTrendText = "-"
			LastMode = "HOLD"
			clearPathVisual()
			return
		end

		local plan = planPath(root, humanoid, threats, fanInfo)

		if not plan then
			-- Keep the last valid movement instead of freezing while a new plan fails.
			LastEscapeOptions = 0
			LastEscapeTrendText = "-"
			LastMode =
				fanInfo
				and "FAN MPC HOLD"
				or "NO PLAN"
			return
		end


		-- Full-plan buffer: CurrentMove changes only after a complete 1.5s plan exists.
		-- The independent 0.55s MPC can still override movement immediately.
		CurrentMove = plan.Direction
		CurrentPlanFocus = plan.Focus == true
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
			LastMode = "FAN MPC"
		elseif plan.Hits > 0 then
			LastMode = "RESCUE"
		elseif CurrentMove.Magnitude <= 0.01 then
			LastMode = "STOP"
		elseif baseline.Hits == 0
			and (baseline.FarRisk or 0) >= FAR_ACTIVATION_RISK
		then
			LastMode = "PREP"
		elseif exactThreatCount >= DENSE_THREAT_COUNT then
			LastMode = "DENSE"
		else
			LastMode = "DODGE"
		end

		updatePathVisual(CurrentPath)
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

-- Stage 1: non-yielding shallow MPC. It keeps running even while the full
-- 1.5-second planner is yielding, so a newly-arriving bullet does not wait for
-- the old deep search to finish.
RunService.Heartbeat:Connect(function()
	if ENABLED then
		runImmediateMPC()
	else
		ImmediateMPCActive = false
		ImmediateMPCMove = Vector3.zero
		ImmediateMPCFocus = AppliedFocus
	end
end)

-- Planner loop: heavy search is deliberately outside RenderStep.
task.spawn(function()
	while Gui.Parent do
		if ENABLED then
			decisionStep()
		end
		RunService.Heartbeat:Wait()
	end
end)

-- RenderStep performs no search: it applies MPC NOW when urgent, otherwise the last full plan.
RunService:BindToRenderStep(
	"AutoDodgeMove",
	Enum.RenderPriority.Last.Value,
	function()
		if ENABLED then
			local _, humanoid = getCharacter()
			if humanoid then
				disableControls()

				local appliedMove =
					ImmediateMPCActive
					and ImmediateMPCMove
					or CurrentMove
				local wantedFocus =
					ImmediateMPCActive
					and ImmediateMPCFocus
					or CurrentPlanFocus

				applyFocusState(wantedFocus, false)

				local _, _, root = getCharacter()
				if root then
					updateFocusSpeedEstimate(humanoid, root)
				end

				LastAppliedMove = appliedMove
				humanoid:Move(appliedMove, false)
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
				and (
					ImmediateMPCActive
					and "실행중 / MPC NOW"
					or ("실행중 / " .. LastMode)
				)
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
			.. "\nMPC0.55 "
			.. (ImmediateMPCActive and "ON" or "OFF")
			.. " / M "
			.. tostring(LastImmediateMPCThreats)
			.. " / MC "
			.. formatClearance(LastImmediateMPCClearance)
			.. " / "
			.. string.format("%.1fms", LastImmediateMPCMs)
			.. "\nEscape "
			.. tostring(LastEscapeOptions)
			.. " ["
			.. LastEscapeTrendText
			.. "] / "
			.. string.format("%.1fms", LastPlanMs)
			.. "\nFan "
			.. (getFanInfo(os.clock()) and "MPC" or "OFF")
			.. " / "
			.. tostring(LastFanCount)
			.. " / "
			.. string.format("%.0f°", LastFanArc)
			.. " / +"
			.. string.format("%.2fs", LastFanForecastTime)
			.. "\nGrid "
			.. tostring(LastSpatialQueryCount)
			.. " / LB "
			.. tostring(#LargeBarrierParts)
			.. " / Slice "
			.. string.format("%.2fms", LastPlannerSliceBudgetMs)
			.. " / FPS~"
			.. string.format("%.0f", 1 / math.max(FrameDtEMA, 0.001))
			.. "\nFocus "
			.. (AppliedFocus and "SLOW" or "NORMAL")
			.. " / N "
			.. (
				NormalSpeedEstimate
				and string.format("%.1f", NormalSpeedEstimate)
				or "-"
			)
			.. " / S "
			.. (
				FocusSpeedEstimate
				and string.format("%.1f", FocusSpeedEstimate)
				or "-"
			)
			.. (
				LastFocusInputError ~= ""
				and (" / KEY ERR")
				or ""
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
	ImmediateMPCMove = Vector3.zero
	ImmediateMPCFocus = false
	ImmediateMPCActive = false
	CurrentPlanFocus = false
	LastAppliedMove = Vector3.zero
	LastImpactTime = math.huge
	LastMinClearance = math.huge
	LastEscapeOptions = 0
	clearFanModel()
	clearPathVisual()
	AppliedFocus = false
	LastFocusToggleAt = -math.huge
	task.wait(0.5)
	if ENABLED then
		disableControls()
	end
end)

bindEnemyProj(findEnemyProj())
