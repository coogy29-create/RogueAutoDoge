local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

local FireEvent = ReplicatedStorage:WaitForChild("발사S")

local AUTO_FIRE = false

local PROJECTILE_SPEED = 750
local FIRE_DELAY = 0.15
local MAX_DISTANCE = 500
local GUN2_SPREAD = 1.5

local GUN2_PROJECTILE_SPEED = 700
local NETWORK_LEAD = 0.08

local TEAM_CHECK = true
local WALL_CHECK = true
local KILL_ZONES = {
    { Type = "ELECTRICAL", Center = Vector3.new(60.167, 65.200, 55.529), Size = Vector3.new(30.000, 10.000, 30.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(37.379, 65.200, 64.720), Size = Vector3.new(30.000, 10.000, 30.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(33.919, 65.200, 71.670), Size = Vector3.new(30.000, 10.000, 30.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(32.796, 65.200, 80.773), Size = Vector3.new(50.000, 10.000, 35.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(33.730, 65.200, 61.322), Size = Vector3.new(30.000, 10.000, 30.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(60.577, 65.200, 46.547), Size = Vector3.new(50.000, 10.000, 35.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(75.402, 65.329, 84.449), Size = Vector3.new(50.000, 10.000, 35.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(70.680, 65.300, 110.399), Size = Vector3.new(44.000, 10.000, 35.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(80.927, 65.300, 137.995), Size = Vector3.new(44.000, 10.000, 35.000) },
    { Type = "ELECTRICAL", Center = Vector3.new(68.134, 65.300, 136.640), Size = Vector3.new(37.000, 10.000, 35.000) },
    { Type = "CONFIDENTIAL", Center = Vector3.new(63.859, 34.836, 137.331), Size = Vector3.new(50.000, 15.000, 40.000) },
    { Type = "CONFIDENTIAL", Center = Vector3.new(63.627, 40.572, 129.984), Size = Vector3.new(50.000, 15.000, 40.000) },
    { Type = "CONFIDENTIAL", Center = Vector3.new(63.735, 38.846, 122.885), Size = Vector3.new(50.000, 15.000, 32.000) },
    { Type = "CONFIDENTIAL", Center = Vector3.new(63.807, 34.836, 120.090), Size = Vector3.new(50.000, 15.000, 31.000) },
    { Type = "CONFIDENTIAL", Center = Vector3.new(66.731, 34.600, 99.788), Size = Vector3.new(17.000, 15.000, 10.000) },
}

local SHOW_KILL_ZONES = false
local KILL_CYBORG = true
local SECURITY_WHITELIST = true

local INPUT_LEAD_TIME = 0.020
local VELOCITY_SMOOTH = 0.35
local MAX_LEAD_PX = 22

local NEAR_DISTANCE = 15
local FAR_DISTANCE = 200
local NEAR_SPREAD_RATIO = 0.40
local FAR_SPREAD_RATIO = 1.15
local MIN_SPREAD_PX = 0.65
local MAX_SPREAD_PX = 16
local FAR_FORCE_START = 60
local FAR_FORCE_END = 220
local FAR_MIN_SPREAD_START = 1.2
local FAR_MIN_SPREAD_END = 7.5
local MOTION_SPEED_FULL = 700
local MOTION_SPREAD_REDUCTION = 0.45

local Whitelist = {}
local Blacklist = {}

local lastFireTime = 0

local CurrentTargetPlayer = nil
local CurrentTargetCharacter = nil
local CurrentTargetPart = nil
local CurrentTargetDistance = nil
local CurrentScreenDistance = nil

local TargetHighlight = nil

local NextTouchId = 5000

local Motion = {
	Player = nil,
	LastPosition = nil,
	LastTime = nil,
	Velocity = Vector2.zero
}

local oldGui = PlayerGui:FindFirstChild("SecurityAutoFireUI")
if oldGui then
	oldGui:Destroy()
end

for _, object in ipairs(Workspace:GetChildren()) do
	if object:IsA("BasePart") and object.Name == "VisualKillZonePart" then
		object:Destroy()
	end
end


for _, object in ipairs(Workspace:GetDescendants()) do
	if object:IsA("Highlight") and (object.Name == "SecurityTargetHighlight" or object.Name == "CyborgTargetHighlight") then
		object:Destroy()
	end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SecurityAutoFireUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.Parent = PlayerGui

local InsetProbe = Instance.new("Frame")
InsetProbe.Size = UDim2.fromOffset(1, 1)
InsetProbe.Position = UDim2.fromOffset(0, 0)
InsetProbe.BackgroundTransparency = 1
InsetProbe.BorderSizePixel = 0
InsetProbe.Active = false
InsetProbe.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(270, 455)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -227)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(70, 150, 255)
MainStroke.Thickness = 2
MainStroke.Parent = MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = TitleBar

local TitleFix = Instance.new("Frame")
TitleFix.Size = UDim2.new(1, 0, 0, 12)
TitleFix.Position = UDim2.new(0, 0, 1, -12)
TitleFix.BackgroundColor3 = TitleBar.BackgroundColor3
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.fromOffset(14, 0)
Title.BackgroundTransparency = 1
Title.Text = "보안직원 킬존 자동사격"
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.fromOffset(34, 30)
CloseButton.Position = UDim2.new(1, -39, 0, 6)
CloseButton.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.new(1, 1, 1)
CloseButton.TextSize = 15
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 7)
CloseCorner.Parent = CloseButton

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -24, 0, 42)
ToggleButton.Position = UDim2.fromOffset(12, 50)
ToggleButton.BackgroundColor3 = Color3.fromRGB(165, 55, 55)
ToggleButton.Text = "자동사격: 꺼짐"
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.TextSize = 16
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = MainFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 10)
ToggleCorner.Parent = ToggleButton

local KillZoneButton = Instance.new("TextButton")
KillZoneButton.Size = UDim2.new(1, -24, 0, 32)
KillZoneButton.Position = UDim2.fromOffset(12, 98)
KillZoneButton.BackgroundColor3 = Color3.fromRGB(85, 85, 95)
KillZoneButton.Text = "킬존 보기: OFF"
KillZoneButton.TextColor3 = Color3.new(1, 1, 1)
KillZoneButton.TextSize = 12
KillZoneButton.Font = Enum.Font.GothamBold
KillZoneButton.Parent = MainFrame
local KillZoneCorner = Instance.new("UICorner")
KillZoneCorner.CornerRadius = UDim.new(0, 8)
KillZoneCorner.Parent = KillZoneButton

local CyborgKillBtn = Instance.new("TextButton")
CyborgKillBtn.Size = UDim2.new(0.5, -14, 0, 30)
CyborgKillBtn.Position = UDim2.fromOffset(12, 136)
CyborgKillBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 60)
CyborgKillBtn.Text = "사이보그 사살: ON"
CyborgKillBtn.TextColor3 = Color3.new(1, 1, 1)
CyborgKillBtn.TextSize = 11
CyborgKillBtn.Font = Enum.Font.GothamBold
CyborgKillBtn.Parent = MainFrame
local CyborgKillCorner = Instance.new("UICorner")
CyborgKillCorner.CornerRadius = UDim.new(0, 7)
CyborgKillCorner.Parent = CyborgKillBtn

local SecurityWhiteBtn = Instance.new("TextButton")
SecurityWhiteBtn.Size = UDim2.new(0.5, -14, 0, 30)
SecurityWhiteBtn.Position = UDim2.new(0.5, 2, 0, 136)
SecurityWhiteBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 60)
SecurityWhiteBtn.AutoButtonColor = false
SecurityWhiteBtn.Active = false
SecurityWhiteBtn.Text = "보안 화이트: 고정"
SecurityWhiteBtn.TextColor3 = Color3.new(1, 1, 1)
SecurityWhiteBtn.TextSize = 11
SecurityWhiteBtn.Font = Enum.Font.GothamBold
SecurityWhiteBtn.Parent = MainFrame
local SecurityWhiteCorner = Instance.new("UICorner")
SecurityWhiteCorner.CornerRadius = UDim.new(0, 7)
SecurityWhiteCorner.Parent = SecurityWhiteBtn

local function createInput(labelText, defaultText, yPosition, parentFrame)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.45, 0, 0, 32)
	label.Position = UDim2.fromOffset(14, yPosition)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(220, 220, 225)
	label.TextSize = 13
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parentFrame

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.45, 0, 0, 28)
	box.Position = UDim2.new(0.52, 0, 0, yPosition + 2)
	box.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	box.Text = defaultText
	box.PlaceholderText = defaultText
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextSize = 13
	box.Font = Enum.Font.Gotham
	box.ClearTextOnFocus = false
	box.Parent = parentFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box

	return box
end

local SpeedBox = createInput("기본 탄속", tostring(PROJECTILE_SPEED), 174, MainFrame)
local DelayBox = createInput("발사 간격", tostring(FIRE_DELAY), 208, MainFrame)
local DistanceBox = createInput("최대 거리", tostring(MAX_DISTANCE), 242, MainFrame)
local SpreadBox = createInput("Gun2 퍼짐 배율", tostring(GUN2_SPREAD), 276, MainFrame)
local ZoneInfoLabel = Instance.new("TextLabel")
ZoneInfoLabel.Size = UDim2.new(1, -24, 0, 30)
ZoneInfoLabel.Position = UDim2.fromOffset(12, 310)
ZoneInfoLabel.BackgroundTransparency = 1
ZoneInfoLabel.Text = "전기부 10 | 기밀 5 | 전기부 전략/기술 화이트"
ZoneInfoLabel.TextColor3 = Color3.fromRGB(175, 205, 255)
ZoneInfoLabel.TextSize = 11
ZoneInfoLabel.Font = Enum.Font.Gotham
ZoneInfoLabel.TextWrapped = true
ZoneInfoLabel.Parent = MainFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -24, 0, 92)
StatusLabel.Position = UDim2.fromOffset(12, 340)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "대상 탐색 중"
StatusLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

local ListFrame = Instance.new("Frame")
ListFrame.Name = "ListFrame"
ListFrame.Size = UDim2.fromOffset(240, 370)
ListFrame.Position = UDim2.new(0.5, 20, 0.5, -185)
ListFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
ListFrame.BorderSizePixel = 0
ListFrame.Active = true
ListFrame.Parent = ScreenGui

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 12)
ListCorner.Parent = ListFrame

local ListStroke = Instance.new("UIStroke")
ListStroke.Color = Color3.fromRGB(180, 70, 255)
ListStroke.Thickness = 2
ListStroke.Parent = ListFrame

local ListTitleBar = Instance.new("Frame")
ListTitleBar.Size = UDim2.new(1, 0, 0, 42)
ListTitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
ListTitleBar.BorderSizePixel = 0
ListTitleBar.Active = true
ListTitleBar.Parent = ListFrame

local ListTitleCorner = Instance.new("UICorner")
ListTitleCorner.CornerRadius = UDim.new(0, 12)
ListTitleCorner.Parent = ListTitleBar

local ListTitleFix = Instance.new("Frame")
ListTitleFix.Size = UDim2.new(1, 0, 0, 12)
ListTitleFix.Position = UDim2.new(0, 0, 1, -12)
ListTitleFix.BackgroundColor3 = ListTitleBar.BackgroundColor3
ListTitleFix.BorderSizePixel = 0
ListTitleFix.Parent = ListTitleBar

local ListTitle = Instance.new("TextLabel")
ListTitle.Size = UDim2.new(1, -20, 1, 0)
ListTitle.Position = UDim2.fromOffset(14, 0)
ListTitle.BackgroundTransparency = 1
ListTitle.Text = "타겟 필터 설정"
ListTitle.TextColor3 = Color3.fromRGB(240, 240, 245)
ListTitle.TextSize = 16
ListTitle.Font = Enum.Font.GothamBold
ListTitle.TextXAlignment = Enum.TextXAlignment.Left
ListTitle.Parent = ListTitleBar

local NameInput = Instance.new("TextBox")
NameInput.Size = UDim2.new(1, -24, 0, 34)
NameInput.Position = UDim2.fromOffset(12, 50)
NameInput.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
NameInput.Text = ""
NameInput.PlaceholderText = "플레이어 이름 입력..."
NameInput.TextColor3 = Color3.new(1, 1, 1)
NameInput.TextSize = 13
NameInput.Font = Enum.Font.Gotham
NameInput.ClearTextOnFocus = false
NameInput.Parent = ListFrame

local NameInputCorner = Instance.new("UICorner")
NameInputCorner.CornerRadius = UDim.new(0, 8)
NameInputCorner.Parent = NameInput

local AddWhiteBtn = Instance.new("TextButton")
AddWhiteBtn.Size = UDim2.new(0.5, -14, 0, 32)
AddWhiteBtn.Position = UDim2.fromOffset(12, 90)
AddWhiteBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 60)
AddWhiteBtn.Text = "🟢 화이트"
AddWhiteBtn.TextColor3 = Color3.new(1, 1, 1)
AddWhiteBtn.TextSize = 13
AddWhiteBtn.Font = Enum.Font.GothamBold
AddWhiteBtn.Parent = ListFrame

local AddWhiteCorner = Instance.new("UICorner")
AddWhiteCorner.CornerRadius = UDim.new(0, 6)
AddWhiteCorner.Parent = AddWhiteBtn

local AddBlackBtn = Instance.new("TextButton")
AddBlackBtn.Size = UDim2.new(0.5, -14, 0, 32)
AddBlackBtn.Position = UDim2.new(0.5, 2, 0, 90)
AddBlackBtn.BackgroundColor3 = Color3.fromRGB(165, 55, 55)
AddBlackBtn.Text = "🔴 블랙"
AddBlackBtn.TextColor3 = Color3.new(1, 1, 1)
AddBlackBtn.TextSize = 13
AddBlackBtn.Font = Enum.Font.GothamBold
AddBlackBtn.Parent = ListFrame

local AddBlackCorner = Instance.new("UICorner")
AddBlackCorner.CornerRadius = UDim.new(0, 6)
AddBlackCorner.Parent = AddBlackBtn

local RemoveBtn = Instance.new("TextButton")
RemoveBtn.Size = UDim2.new(1, -24, 0, 30)
RemoveBtn.Position = UDim2.fromOffset(12, 126)
RemoveBtn.BackgroundColor3 = Color3.fromRGB(85, 85, 95)
RemoveBtn.Text = "⚪ 타겟 해제/제거"
RemoveBtn.TextColor3 = Color3.new(1, 1, 1)
RemoveBtn.TextSize = 13
RemoveBtn.Font = Enum.Font.GothamBold
RemoveBtn.Parent = ListFrame

local RemoveCorner = Instance.new("UICorner")
RemoveCorner.CornerRadius = UDim.new(0, 6)
RemoveCorner.Parent = RemoveBtn

local ListDisplay = Instance.new("TextLabel")
ListDisplay.Size = UDim2.new(1, -24, 0, 196)
ListDisplay.Position = UDim2.fromOffset(12, 164)
ListDisplay.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
ListDisplay.Text = "🟢 화이트리스트 (제외)\n없음\n\n🔴 블랙리스트 (최우선)\n없음"
ListDisplay.TextColor3 = Color3.fromRGB(200, 200, 210)
ListDisplay.TextSize = 12
ListDisplay.Font = Enum.Font.Gotham
ListDisplay.TextXAlignment = Enum.TextXAlignment.Left
ListDisplay.TextYAlignment = Enum.TextYAlignment.Top
ListDisplay.TextWrapped = true
ListDisplay.Parent = ListFrame

local ListDisplayCorner = Instance.new("UICorner")
ListDisplayCorner.CornerRadius = UDim.new(0, 6)
ListDisplayCorner.Parent = ListDisplay

local UIPadding = Instance.new("UIPadding")
UIPadding.PaddingTop = UDim.new(0, 6)
UIPadding.PaddingBottom = UDim.new(0, 6)
UIPadding.PaddingLeft = UDim.new(0, 6)
UIPadding.PaddingRight = UDim.new(0, 6)
UIPadding.Parent = ListDisplay

local function getFullPlayerName(text)
	if text == "" then return nil end

	local lowerText = string.lower(text)

	for _, player in ipairs(Players:GetPlayers()) do
		if string.lower(player.Name):sub(1, #lowerText) == lowerText
			or string.lower(player.DisplayName):sub(1, #lowerText) == lowerText then
			return player.Name
		end
	end

	return text
end

local function updateListUI()
	local whiteText = "🟢 화이트리스트 (제외)\n"
	local whiteCount = 0

	for name in pairs(Whitelist) do
		whiteText = whiteText .. "- " .. name .. "\n"
		whiteCount += 1
	end

	if whiteCount == 0 then
		whiteText = whiteText .. "없음\n"
	end

	local blackText = "\n🔴 블랙리스트 (최우선)\n"
	local blackCount = 0

	for name in pairs(Blacklist) do
		blackText = blackText .. "- " .. name .. "\n"
		blackCount += 1
	end

	if blackCount == 0 then
		blackText = blackText .. "없음\n"
	end

	ListDisplay.Text = whiteText .. blackText
end

AddWhiteBtn.MouseButton1Click:Connect(function()
	local name = getFullPlayerName(NameInput.Text)

	if name then
		Whitelist[name] = true
		Blacklist[name] = nil
		NameInput.Text = ""
		updateListUI()
	end
end)

AddBlackBtn.MouseButton1Click:Connect(function()
	local name = getFullPlayerName(NameInput.Text)

	if name then
		Blacklist[name] = true
		Whitelist[name] = nil
		NameInput.Text = ""
		updateListUI()
	end
end)

RemoveBtn.MouseButton1Click:Connect(function()
	local name = getFullPlayerName(NameInput.Text)

	if name then
		Whitelist[name] = nil
		Blacklist[name] = nil
		NameInput.Text = ""
		updateListUI()
	end
end)

local function makeDraggable(frame, titleBar)
	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPosition = nil

	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			dragging = true
			dragStart = input.Position
			startPosition = frame.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	titleBar.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart

			frame.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

makeDraggable(MainFrame, TitleBar)
makeDraggable(ListFrame, ListTitleBar)

local function getKillZoneType(position)
	for _, zone in ipairs(KILL_ZONES) do
		local half = zone.Size * 0.5
		local d = position - zone.Center

		if math.abs(d.X) <= half.X
			and math.abs(d.Y) <= half.Y
			and math.abs(d.Z) <= half.Z then
			return zone.Type
		end
	end

	return nil
end

local function isPositionInKillZone(position)
	return getKillZoneType(position) ~= nil
end

local function clearKillZoneVisuals()
	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("BasePart") and object.Name == "VisualKillZonePart" then
			object:Destroy()
		end
	end
end

local function updateKillZoneVisuals()
	clearKillZoneVisuals()

	if not SHOW_KILL_ZONES then
		return
	end

	for _, zone in ipairs(KILL_ZONES) do
		local part = Instance.new("Part")
		part.Name = "VisualKillZonePart"
		part.Size = zone.Size
		part.CFrame = CFrame.new(zone.Center)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 0.82
		part.Material = Enum.Material.ForceField
		part.Color = zone.Type == "ELECTRICAL"
			and Color3.fromRGB(70, 170, 255)
			or Color3.fromRGB(255, 70, 90)
		part.Parent = Workspace
	end
end

KillZoneButton.MouseButton1Click:Connect(function()
	SHOW_KILL_ZONES = not SHOW_KILL_ZONES
	KillZoneButton.Text = SHOW_KILL_ZONES and "킬존 보기: ON" or "킬존 보기: OFF"
	KillZoneButton.BackgroundColor3 = SHOW_KILL_ZONES
		and Color3.fromRGB(65, 125, 180)
		or Color3.fromRGB(85, 85, 95)
	updateKillZoneVisuals()
end)

CyborgKillBtn.MouseButton1Click:Connect(function()
	KILL_CYBORG = not KILL_CYBORG
	CyborgKillBtn.Text = KILL_CYBORG and "사이보그 사살: ON" or "사이보그 사살: OFF"
	CyborgKillBtn.BackgroundColor3 = KILL_CYBORG
		and Color3.fromRGB(45,120,60)
		or Color3.fromRGB(165,55,55)
end)

local function teamNameContains(player, keyword)
	local team = player.Team
	if not team then return false end
	return string.find(team.Name, keyword, 1, true) ~= nil
end

local function hasConfidentialDocument(player)
	if not player then
		return false
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and backpack:FindFirstChild("기밀 서류") then
		return true
	end

	local character = player.Character
	if character and character:FindFirstChild("기밀 서류") then
		return true
	end

	return false
end

local function getCharacterInfo(player)
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return nil
	end

	return character, humanoid, rootPart
end

local function getFireOrigin()
	local character = LocalPlayer.Character
	if not character then return nil end

	local tool = character:FindFirstChildOfClass("Tool")

	if tool then
		local muzzle = tool:FindFirstChild("Muzzle", true)

		if muzzle then
			if muzzle:IsA("Attachment") then
				return muzzle.WorldPosition
			end

			if muzzle:IsA("BasePart") then
				return muzzle.Position
			end
		end
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart then
		return rootPart.Position
	end

	return nil
end

local function canSeeTarget(origin, targetPart, targetCharacter)
	if not WALL_CHECK then
		return true
	end

	local filterList = {}

	if LocalPlayer.Character then
		table.insert(filterList, LocalPlayer.Character)
	end

	for _, object in ipairs(Workspace:GetChildren()) do
		if object.Name == "VisualKillZonePart" then
			table.insert(filterList, object)
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local direction = targetPart.Position - origin
	local result = Workspace:Raycast(origin, direction, rayParams)

	if not result then
		return true
	end

	return result.Instance:IsDescendantOf(targetCharacter)
end

local function getScreenCenter()
	Camera = Workspace.CurrentCamera

	if not Camera then
		return Vector2.zero
	end

	return Vector2.new(
		Camera.ViewportSize.X / 2,
		Camera.ViewportSize.Y / 2
	)
end

local function getBestTarget(origin)
	Camera = Workspace.CurrentCamera

	if not Camera then
		return nil
	end

	local screenCenter = getScreenCenter()
	local confidentialDocTarget = nil
	local blacklistTarget = nil
	local cyborgTarget = nil
	local killZoneTarget = nil

	local confidentialDocScreenDistance = math.huge
	local blacklistScreenDistance = math.huge
	local cyborgScreenDistance = math.huge
	local killZoneScreenDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then
			continue
		end

		local hasSecretDocs = hasConfidentialDocument(player)
		local isBlacklisted = Blacklist[player.Name] ~= nil
		local isSecurity = teamNameContains(player, "보안")
		local isCyborg = teamNameContains(player, "사이보그")

		if not hasSecretDocs then
			if Whitelist[player.Name] then
				continue
			end

			if SECURITY_WHITELIST and isSecurity then
				continue
			end

			if TEAM_CHECK and LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then
				continue
			end
		end

		local character, humanoid, rootPart = getCharacterInfo(player)
		if not character or not humanoid or not rootPart then continue end

		local zoneType = getKillZoneType(rootPart.Position)
		local inKillZone = zoneType ~= nil

		if not hasSecretDocs then
			if inKillZone and teamNameContains(player, "기술") then
				continue
			end

			if zoneType == "ELECTRICAL" and teamNameContains(player, "전략") then
				continue
			end
		end

		local shouldTarget =
			hasSecretDocs
			or isBlacklisted
			or (KILL_CYBORG and isCyborg)
			or inKillZone

		if not shouldTarget then continue end

		local aimPart = rootPart
		local worldDistance = (aimPart.Position - origin).Magnitude

		if worldDistance > MAX_DISTANCE then
			continue
		end

		if not canSeeTarget(origin, aimPart, character) then
			continue
		end

		local screenPosition, onScreen = Camera:WorldToViewportPoint(aimPart.Position)

		if not onScreen or screenPosition.Z <= 0 then
			continue
		end

		local screenPoint = Vector2.new(screenPosition.X, screenPosition.Y)
		local screenDistance = (screenPoint - screenCenter).Magnitude

		local targetData = {
			Player = player,
			Character = character,
			Part = aimPart,
			WorldDistance = worldDistance,
			ScreenDistance = screenDistance,
			Humanoid = humanoid,
			ZoneType = zoneType,
			HasConfidentialDocument = hasSecretDocs
		}

		if hasSecretDocs then
			if screenDistance < confidentialDocScreenDistance then
				confidentialDocScreenDistance = screenDistance
				confidentialDocTarget = targetData
			end
		elseif isBlacklisted then
			if screenDistance < blacklistScreenDistance then
				blacklistScreenDistance = screenDistance
				blacklistTarget = targetData
			end
		elseif KILL_CYBORG and isCyborg then
			if screenDistance < cyborgScreenDistance then
				cyborgScreenDistance = screenDistance
				cyborgTarget = targetData
			end
		elseif inKillZone then
			if screenDistance < killZoneScreenDistance then
				killZoneScreenDistance = screenDistance
				killZoneTarget = targetData
			end
		end
	end

	if confidentialDocTarget then return confidentialDocTarget end
	if blacklistTarget then return blacklistTarget end
	if cyborgTarget then return cyborgTarget end
	return killZoneTarget
end

local function clearTargetHighlight()
	if TargetHighlight then
		TargetHighlight:Destroy()
		TargetHighlight = nil
	end

	CurrentTargetPlayer = nil
	CurrentTargetCharacter = nil
	CurrentTargetPart = nil
	CurrentTargetDistance = nil
	CurrentScreenDistance = nil
end

local function setTargetHighlight(targetData)
	if not targetData or not targetData.Character then
		clearTargetHighlight()
		return
	end

	if TargetHighlight and TargetHighlight.Adornee == targetData.Character then
		return
	end

	if TargetHighlight then
		TargetHighlight:Destroy()
		TargetHighlight = nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "SecurityTargetHighlight"
	highlight.Adornee = targetData.Character
	highlight.FillColor = Color3.fromRGB(255, 55, 90)
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = targetData.Character

	TargetHighlight = highlight
end

local function calculatePredictedPosition(origin, targetPart, humanoid, targetPlayer, currentSpeed, toolName)
	local targetPosition = targetPart.Position
	local targetVelocity = targetPart.AssemblyLinearVelocity

	local relativePosition = targetPosition - origin
	local distance = relativePosition.Magnitude

	local speedSquared = currentSpeed * currentSpeed
	local velocitySquared = targetVelocity:Dot(targetVelocity)

	local a = velocitySquared - speedSquared
	local b = 2 * relativePosition:Dot(targetVelocity)
	local c = relativePosition:Dot(relativePosition)

	local travelTime = nil

	if math.abs(a) < 0.001 then
		if math.abs(b) > 0.001 then
			local linearTime = -c / b

			if linearTime > 0 then
				travelTime = linearTime
			end
		end
	else
		local discriminant = b * b - 4 * a * c

		if discriminant >= 0 then
			local squareRoot = math.sqrt(discriminant)
			local t1 = (-b - squareRoot) / (2 * a)
			local t2 = (-b + squareRoot) / (2 * a)

			if t1 > 0 and t2 > 0 then
				travelTime = math.min(t1, t2)
			elseif t1 > 0 then
				travelTime = t1
			elseif t2 > 0 then
				travelTime = t2
			end
		end
	end

	if not travelTime then
		travelTime = distance / currentSpeed
	end

	travelTime = travelTime + NETWORK_LEAD
	travelTime = math.clamp(travelTime, 0, 3)

	local predictedPos = targetPosition + targetVelocity * travelTime

	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		local gravity = Vector3.new(0, -Workspace.Gravity, 0)
		predictedPos = predictedPos + 0.5 * gravity * (travelTime * travelTime)
	end

	if toolName == "Gun2" then
		predictedPos = predictedPos + Vector3.new(0, 1, 0)
	end

	return predictedPos
end

local function getGuiInset()
	local result = Vector2.zero

	pcall(function()
		local topLeft = select(1, GuiService:GetGuiInset())

		if typeof(topLeft) == "Vector2" then
			result = topLeft
		end
	end)

	return result
end

local function getSafeAreaInset()
	local result = Vector2.zero
	local absolute = InsetProbe.AbsolutePosition

	if typeof(absolute) == "Vector2" then
		result = Vector2.new(
			math.max(0, absolute.X),
			math.max(0, absolute.Y)
		)
	end

	pcall(function()
		local fullRect = GuiService:GetInsetArea(Enum.ScreenInsets.None)
		local safeRect = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)

		if fullRect and safeRect then
			local delta = safeRect.Min - fullRect.Min

			result = Vector2.new(
				math.max(result.X, delta.X),
				math.max(result.Y, delta.Y)
			)
		end
	end)

	return result
end

local function getInputInset()
	local gui = getGuiInset()
	local safe = getSafeAreaInset()

	return Vector2.new(
		math.max(gui.X, safe.X),
		math.max(gui.Y, safe.Y)
	)
end

local function getVimFromScreen(screenPosition)
	local inset = getInputInset()

	return Vector2.new(
		screenPosition.X + inset.X,
		screenPosition.Y + inset.Y
	)
end

local function getScreenFromWorld(worldPosition)
	local camera = Workspace.CurrentCamera

	if not camera then
		return nil, false
	end

	local point, visible = camera:WorldToScreenPoint(worldPosition)

	if point.Z <= 0 then
		return nil, false
	end

	return Vector2.new(point.X, point.Y), visible
end

local function resetMotion()
	Motion.Player = nil
	Motion.LastPosition = nil
	Motion.LastTime = nil
	Motion.Velocity = Vector2.zero
end

local function updateScreenVelocity(player, screenPosition)
	local now = os.clock()

	if Motion.Player ~= player then
		Motion.Player = player
		Motion.LastPosition = screenPosition
		Motion.LastTime = now
		Motion.Velocity = Vector2.zero
		return
	end

	if not Motion.LastPosition or not Motion.LastTime then
		Motion.LastPosition = screenPosition
		Motion.LastTime = now
		return
	end

	local dt = now - Motion.LastTime

	if dt > 0.001 and dt < 0.1 then
		local velocity = (screenPosition - Motion.LastPosition) / dt

		if velocity.Magnitude > 4500 then
			velocity = velocity.Unit * 4500
		end

		Motion.Velocity = Motion.Velocity:Lerp(
			velocity,
			VELOCITY_SMOOTH
		)
	end

	Motion.LastPosition = screenPosition
	Motion.LastTime = now
end

local function getLeadOffset()
	local lead = Motion.Velocity * INPUT_LEAD_TIME

	if lead.Magnitude > MAX_LEAD_PX then
		lead = lead.Unit * MAX_LEAD_PX
	end

	return lead
end

local function randomGaussian()
	local u1 = math.max(math.random(), 0.000001)
	local u2 = math.random()

	return math.sqrt(-2 * math.log(u1))
		* math.cos(2 * math.pi * u2)
end

local function getScreenRadius(character)
	local camera = Workspace.CurrentCamera

	if not camera or not character then
		return 4
	end

	local ok, cf, size = pcall(function()
		local c, s = character:GetBoundingBox()
		return c, s
	end)

	if not ok then
		return 4
	end

	local center = cf.Position
	local centerScreen = camera:WorldToScreenPoint(center)

	if centerScreen.Z <= 0 then
		return 4
	end

	local horizontal =
		center
		+ camera.CFrame.RightVector
		* math.max(size.X, size.Z)
		* 0.5

	local vertical =
		center
		+ camera.CFrame.UpVector
		* size.Y
		* 0.5

	local hp = camera:WorldToScreenPoint(horizontal)
	local vp = camera:WorldToScreenPoint(vertical)

	local rx = math.abs(hp.X - centerScreen.X)
	local ry = math.abs(vp.Y - centerScreen.Y)

	return math.max(
		1.5,
		math.min(rx, ry)
	)
end

local function getGun2Spread(character, distance)
	if GUN2_SPREAD <= 0 then
		return 0
	end

	local radius = getScreenRadius(character)
	local denominator = FAR_DISTANCE - NEAR_DISTANCE
	local t = 0

	if denominator > 0 then
		t = math.clamp(
			(distance - NEAR_DISTANCE) / denominator,
			0,
			1
		)
	end

	t = t ^ 0.65

	local ratio =
		NEAR_SPREAD_RATIO
		+ (FAR_SPREAD_RATIO - NEAR_SPREAD_RATIO)
		* t

	local sizeSpread = radius * ratio
	local farDenominator = FAR_FORCE_END - FAR_FORCE_START
	local farT = 0

	if farDenominator > 0 then
		farT = math.clamp(
			(distance - FAR_FORCE_START) / farDenominator,
			0,
			1
		)
	end

	local forced =
		FAR_MIN_SPREAD_START
		+ (FAR_MIN_SPREAD_END - FAR_MIN_SPREAD_START)
		* farT

	local sigma = math.max(sizeSpread, forced)

	local motionT = math.clamp(
		Motion.Velocity.Magnitude / MOTION_SPEED_FULL,
		0,
		1
	)

	local motionMultiplier =
		1 - MOTION_SPREAD_REDUCTION * motionT

	sigma =
		sigma
		* motionMultiplier
		* GUN2_SPREAD

	return math.clamp(
		sigma,
		MIN_SPREAD_PX * GUN2_SPREAD,
		MAX_SPREAD_PX * GUN2_SPREAD
	)
end

local function generateTouchId()
	NextTouchId += 1

	if NextTouchId > 2000000000 then
		NextTouchId = 5000
	end

	return NextTouchId
end

local function isBlockingGuiObject(object)
	if not object or not object:IsA("GuiObject") or not object.Visible then
		return false
	end

	if object:IsA("GuiButton") or object:IsA("TextBox") then
		return true
	end

	return object.Active == true
end

local function isTouchBlockedByUI(vimPoint)
	local inset = getInputInset()
	local points = {
		vimPoint,
		vimPoint - inset
	}

	for _, point in ipairs(points) do
		for _, rootGui in ipairs({PlayerGui, CoreGui}) do
			local ok, objects = pcall(function()
				return rootGui:GetGuiObjectsAtPosition(
					math.floor(point.X + 0.5),
					math.floor(point.Y + 0.5)
				)
			end)

			if ok and objects then
				for _, object in ipairs(objects) do
					if isBlockingGuiObject(object) then
						return true
					end
				end
			end
		end
	end

	return false
end

local function sendTouch(point, character, distance)
	local sigma =
		getGun2Spread(
			character,
			distance
		)

	local firePoint =
		Vector2.new(
			point.X
				+ randomGaussian()
					* sigma,

			point.Y
				+ randomGaussian()
					* sigma
		)

	local x =
		math.floor(
			firePoint.X + 0.5
		)

	local y =
		math.floor(
			firePoint.Y + 0.5
		)

	if isTouchBlockedByUI(Vector2.new(x, y)) then
		return false
	end

	local id =
		generateTouchId()

	local ok =
		pcall(function()
			VirtualInputManager:SendTouchEvent(
				id,
				Enum.UserInputState.Begin.Value,
				x,
				y
			)

			task.delay(
				0.018,
				function()
					pcall(function()
						VirtualInputManager:SendTouchEvent(
							id,
							Enum.UserInputState.End.Value,
							x,
							y
						)
					end)
				end
			)
		end)

	return ok
end

local function updateSettings()
	local newSpeed = tonumber(SpeedBox.Text)
	local newDelay = tonumber(DelayBox.Text)
	local newDistance = tonumber(DistanceBox.Text)
	local newSpread = tonumber(SpreadBox.Text)

	if newSpeed and newSpeed > 0 then
		PROJECTILE_SPEED = newSpeed
	else
		SpeedBox.Text = tostring(PROJECTILE_SPEED)
	end

	if newDelay and newDelay >= 0.03 then
		FIRE_DELAY = newDelay
	else
		DelayBox.Text = tostring(FIRE_DELAY)
	end

	if newDistance and newDistance > 0 then
		MAX_DISTANCE = newDistance
	else
		DistanceBox.Text = tostring(MAX_DISTANCE)
	end

	if newSpread and newSpread >= 0 then
		GUN2_SPREAD = newSpread
	else
		SpreadBox.Text = tostring(GUN2_SPREAD)
	end

end

SpeedBox.FocusLost:Connect(updateSettings)
DelayBox.FocusLost:Connect(updateSettings)
DistanceBox.FocusLost:Connect(updateSettings)
SpreadBox.FocusLost:Connect(updateSettings)

ToggleButton.MouseButton1Click:Connect(function()
	updateSettings()
	AUTO_FIRE = not AUTO_FIRE

	if AUTO_FIRE then
		ToggleButton.Text = "자동사격: 켜짐"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(45, 165, 90)
	else
		ToggleButton.Text = "자동사격: 꺼짐"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(165, 55, 55)
	end
end)

CloseButton.MouseButton1Click:Connect(function()
	AUTO_FIRE = false
	clearTargetHighlight()

	for _, object in ipairs(Workspace:GetChildren()) do
		if object.Name == "VisualKillZonePart" then
			object:Destroy()
		end
	end

	ScreenGui:Destroy()
end)

RunService.RenderStepped:Connect(function()
	if not ScreenGui.Parent then
		return
	end

	local origin = getFireOrigin()


	if not origin then
		StatusLabel.Text = "캐릭터 또는 발사 위치 없음"
		clearTargetHighlight()
		return
	end

	local targetData = getBestTarget(origin)

	if not targetData then
		StatusLabel.Text = string.format(
			"%s | 대상 없음\n고정 킬존: 전기 10 / 기밀 5 | 사이보그: %s\n전기부 전략/기술: 화이트 | 보안: 화이트",
			AUTO_FIRE and "자동사격 켜짐" or "자동사격 꺼짐",
			KILL_CYBORG and "ON" or "OFF"
		)

		clearTargetHighlight()
		return
	end

	CurrentTargetPlayer = targetData.Player
	CurrentTargetCharacter = targetData.Character
	CurrentTargetPart = targetData.Part
	CurrentTargetDistance = targetData.WorldDistance
	CurrentScreenDistance = targetData.ScreenDistance

	setTargetHighlight(targetData)

	local targetStatus = ""

	if targetData.HasConfidentialDocument then
		targetStatus = " [기밀 서류 소지]"
	elseif Blacklist[targetData.Player.Name] then
		targetStatus = " [블랙리스트]"
	elseif teamNameContains(targetData.Player, "사이보그") and KILL_CYBORG then
		targetStatus = " [사이보그]"
	elseif targetData.ZoneType == "ELECTRICAL" then
		targetStatus = " [전기부 킬존]"
	elseif targetData.ZoneType == "CONFIDENTIAL" then
		targetStatus = " [기밀 킬존]"
	end

	local character = LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")

	if tool and tool.Name == "Gun2" then
		targetStatus = targetStatus .. " [Gun2 터치/700]"
	end

	StatusLabel.Text = string.format(
		"%s | 대상: %s | %.1f studs%s\n사이보그: %s | 보안: 화이트\n기술: 전기부/기밀 화이트 | 전략: 전기부 화이트\n기밀 서류 소지: 최우선 공격",
		AUTO_FIRE and "사격 켜짐" or "사격 꺼짐",
		targetData.Player.Name,
		targetData.WorldDistance,
		targetStatus,
		KILL_CYBORG and "ON" or "OFF"
	)

	if not AUTO_FIRE then
		return
	end

	if not character or not tool or tool.Name ~= "Gun2" then
		return
	end


	if not CurrentTargetPart or not CurrentTargetPart.Parent then
		return
	end

	local humanoid =
		CurrentTargetCharacter
		and CurrentTargetCharacter:FindFirstChildOfClass("Humanoid")

	local predictedPosition =
		calculatePredictedPosition(
			origin,
			CurrentTargetPart,
			humanoid,
			CurrentTargetPlayer,
			GUN2_PROJECTILE_SPEED,
			tool.Name
		)

	local screenPosition, onScreen =
		getScreenFromWorld(predictedPosition)

	if not screenPosition or not onScreen then
		return
	end

	updateScreenVelocity(
		CurrentTargetPlayer,
		screenPosition
	)

	local predictedScreen =
		screenPosition + getLeadOffset()

	local now = os.clock()

	if now - lastFireTime < FIRE_DELAY then
		return
	end

	local touchPoint =
		getVimFromScreen(
			predictedScreen
		)

	if sendTouch(
		touchPoint,
		CurrentTargetPlayer.Character,
		CurrentTargetDistance
	) then
		lastFireTime = now
	end
end)

RunService.Heartbeat:Connect(function()
	if not AUTO_FIRE then
		return
	end

	if not CurrentTargetPart or not CurrentTargetPart.Parent then
		return
	end

	if os.clock() - lastFireTime < FIRE_DELAY then
		return
	end

	local character = LocalPlayer.Character

	if not character then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")

	if not tool then
		return
	end

	if tool.Name == "Gun2" then
		return
	end


	local origin = getFireOrigin()

	if not origin then
		return
	end

	local humanoid =
		CurrentTargetCharacter
		and CurrentTargetCharacter:FindFirstChildOfClass("Humanoid")

	if tool.Name == "GunSNIPE" then
		local activeSpeed = 1000

		local predictedPosition =
			calculatePredictedPosition(
				origin,
				CurrentTargetPart,
				humanoid,
				CurrentTargetPlayer,
				activeSpeed,
				tool.Name
			)

		FireEvent:FireServer(predictedPosition)
		lastFireTime = os.clock()
	else
		local activeSpeed = PROJECTILE_SPEED

		local predictedPosition =
			calculatePredictedPosition(
				origin,
				CurrentTargetPart,
				humanoid,
				CurrentTargetPlayer,
				activeSpeed,
				tool.Name
			)

		FireEvent:FireServer(predictedPosition)
		lastFireTime = os.clock()
	end
end)
