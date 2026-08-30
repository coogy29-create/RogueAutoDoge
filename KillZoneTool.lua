local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "KillZoneToolUI"
local FOLDER_NAME = "LocalKillZoneEditor"

local DEFAULT_SIZE = Vector3.new(30, 10, 30)

local ZONE_TYPES = {
	CONFIDENTIAL = {
		Label = "기밀 킬존",
		Color = Color3.fromRGB(255, 70, 90)
	},
	ELECTRICAL = {
		Label = "전기부 킬존",
		Color = Color3.fromRGB(70, 170, 255)
	}
}

local Zones = {}
local SelectedZoneId = nil
local NextZoneId = 0

local oldGui = PlayerGui:FindFirstChild(GUI_NAME)
if oldGui then
	oldGui:Destroy()
end

local oldFolder = Workspace:FindFirstChild(FOLDER_NAME)
if oldFolder then
	oldFolder:Destroy()
end

local ZoneFolder = Instance.new("Folder")
ZoneFolder.Name = FOLDER_NAME
ZoneFolder.Parent = Workspace

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(330, 470)
Main.Position = UDim2.new(0.04, 0, 0.12, 0)
Main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(110, 150, 255)
MainStroke.Thickness = 2
MainStroke.Parent = Main

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 44)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = Main

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
Title.Size = UDim2.new(1, -48, 1, 0)
Title.Position = UDim2.fromOffset(12, 0)
Title.BackgroundTransparency = 1
Title.Text = "킬존 좌표 설정 툴"
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(32, 30)
Close.Position = UDim2.new(1, -38, 0, 6)
Close.BackgroundColor3 = Color3.fromRGB(175, 55, 55)
Close.BorderSizePixel = 0
Close.Text = "X"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.TextSize = 14
Close.Font = Enum.Font.GothamBold
Close.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 7)
CloseCorner.Parent = Close

local function makeLabel(text, x, y, w, h, parent)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(w, h)
	label.Position = UDim2.fromOffset(x, y)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(210, 210, 220)
	label.TextSize = 12
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeBox(text, x, y, w, h, parent)
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(w, h)
	box.Position = UDim2.fromOffset(x, y)
	box.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	box.BorderSizePixel = 0
	box.Text = text
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextSize = 12
	box.Font = Enum.Font.Gotham
	box.ClearTextOnFocus = false
	box.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 7)
	c.Parent = box

	return box
end

local function makeButton(text, x, y, w, h, color, parent)
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(w, h)
	button.Position = UDim2.fromOffset(x, y)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 12
	button.Font = Enum.Font.GothamBold
	button.Active = true
	button.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = button

	return button
end

makeLabel("박스 크기", 12, 54, 100, 24, Main)
makeLabel("X", 12, 82, 20, 28, Main)
makeLabel("Y", 114, 82, 20, 28, Main)
makeLabel("Z", 216, 82, 20, 28, Main)

local SizeX = makeBox(tostring(DEFAULT_SIZE.X), 34, 82, 68, 28, Main)
local SizeY = makeBox(tostring(DEFAULT_SIZE.Y), 136, 82, 68, 28, Main)
local SizeZ = makeBox(tostring(DEFAULT_SIZE.Z), 238, 82, 68, 28, Main)

local ConfidentialButton = makeButton(
	"기밀 킬존 소환",
	12, 120, 148, 36,
	ZONE_TYPES.CONFIDENTIAL.Color,
	Main
)

local ElectricalButton = makeButton(
	"전기부 킬존 소환",
	170, 120, 148, 36,
	ZONE_TYPES.ELECTRICAL.Color,
	Main
)

local MoveButton = makeButton(
	"선택 박스 → 현재 위치",
	12, 164, 148, 32,
	Color3.fromRGB(65, 120, 180),
	Main
)

local ResizeButton = makeButton(
	"선택 박스 크기 적용",
	170, 164, 148, 32,
	Color3.fromRGB(65, 120, 180),
	Main
)

local DeleteButton = makeButton(
	"선택 삭제",
	12, 204, 98, 30,
	Color3.fromRGB(160, 65, 65),
	Main
)

local DeleteAllButton = makeButton(
	"전체 삭제",
	116, 204, 98, 30,
	Color3.fromRGB(140, 55, 55),
	Main
)

local CopyButton = makeButton(
	"결과 복사",
	220, 204, 98, 30,
	Color3.fromRGB(45, 130, 70),
	Main
)

local Info = Instance.new("TextLabel")
Info.Size = UDim2.new(1, -24, 0, 34)
Info.Position = UDim2.fromOffset(12, 242)
Info.BackgroundTransparency = 1
Info.Text = "박스를 터치하면 선택됩니다."
Info.TextColor3 = Color3.fromRGB(190, 190, 205)
Info.TextSize = 11
Info.Font = Enum.Font.Gotham
Info.TextWrapped = true
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.Parent = Main

local Result = Instance.new("TextBox")
Result.Size = UDim2.new(1, -24, 0, 174)
Result.Position = UDim2.fromOffset(12, 282)
Result.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
Result.BorderSizePixel = 0
Result.Text = "-- 설치된 킬존 없음"
Result.TextColor3 = Color3.fromRGB(220, 220, 225)
Result.TextSize = 10
Result.Font = Enum.Font.Code
Result.TextXAlignment = Enum.TextXAlignment.Left
Result.TextYAlignment = Enum.TextYAlignment.Top
Result.TextWrapped = false
Result.MultiLine = true
Result.ClearTextOnFocus = false
Result.Parent = Main

local ResultCorner = Instance.new("UICorner")
ResultCorner.CornerRadius = UDim.new(0, 7)
ResultCorner.Parent = Result

local ResultPadding = Instance.new("UIPadding")
ResultPadding.PaddingTop = UDim.new(0, 7)
ResultPadding.PaddingBottom = UDim.new(0, 7)
ResultPadding.PaddingLeft = UDim.new(0, 7)
ResultPadding.PaddingRight = UDim.new(0, 7)
ResultPadding.Parent = Result

local dragging = false
local dragInput = nil
local dragStart = nil
local startPosition = nil

TitleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then

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

TitleBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseMovement then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInput then
		local delta = input.Position - dragStart

		Main.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end
end)

local function getRoot()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function readSize()
	local x = tonumber(SizeX.Text)
	local y = tonumber(SizeY.Text)
	local z = tonumber(SizeZ.Text)

	if not x or not y or not z then
		return nil
	end

	x = math.max(0.1, math.abs(x))
	y = math.max(0.1, math.abs(y))
	z = math.max(0.1, math.abs(z))

	SizeX.Text = string.format("%.2f", x)
	SizeY.Text = string.format("%.2f", y)
	SizeZ.Text = string.format("%.2f", z)

	return Vector3.new(x, y, z)
end

local function sortedZones()
	local list = {}

	for _, zone in pairs(Zones) do
		table.insert(list, zone)
	end

	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)

	return list
end

local function buildResult()
	local list = sortedZones()

	if #list == 0 then
		return "-- 설치된 킬존 없음"
	end

	local lines = {
		"local KILL_ZONES = {"
	}

	for _, zone in ipairs(list) do
		local p = zone.Part.Position
		local s = zone.Part.Size

		table.insert(
			lines,
			string.format(
				'    { Type = "%s", Center = Vector3.new(%.3f, %.3f, %.3f), Size = Vector3.new(%.3f, %.3f, %.3f) },',
				zone.Type,
				p.X, p.Y, p.Z,
				s.X, s.Y, s.Z
			)
		)
	end

	table.insert(lines, "}")

	return table.concat(lines, "\n")
end

local function refreshResult()
	Result.Text = buildResult()

	local selected = SelectedZoneId and Zones[SelectedZoneId]

	if selected and selected.Part and selected.Part.Parent then
		local p = selected.Part.Position
		local s = selected.Part.Size

		Info.Text = string.format(
			"선택: #%d %s | 위치 %.1f, %.1f, %.1f | 크기 %.1f, %.1f, %.1f",
			selected.Id,
			ZONE_TYPES[selected.Type].Label,
			p.X, p.Y, p.Z,
			s.X, s.Y, s.Z
		)
	else
		Info.Text = string.format(
			"설치된 박스: %d | 박스를 터치하면 선택",
			#sortedZones()
		)
	end
end

local function updateSelectionVisual()
	for id, zone in pairs(Zones) do
		if zone.Selection then
			zone.Selection.Visible = (id == SelectedZoneId)
		end
	end
end

local function selectZone(id)
	if not Zones[id] then
		return
	end

	SelectedZoneId = id
	updateSelectionVisual()
	refreshResult()
end

local function createZone(zoneType)
	local config = ZONE_TYPES[zoneType]
	if not config then
		return
	end

	local root = getRoot()
	if not root then
		Info.Text = "HumanoidRootPart를 찾지 못했습니다."
		return
	end

	local size = readSize()
	if not size then
		Info.Text = "크기 X/Y/Z 값을 확인하세요."
		return
	end

	NextZoneId += 1
	local id = NextZoneId

	local part = Instance.new("Part")
	part.Name = string.format("KillZone_%s_%d", zoneType, id)
	part.Size = size
	part.CFrame = CFrame.new(root.Position)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0.72
	part.Color = config.Color
	part.Material = Enum.Material.ForceField
	part.Parent = ZoneFolder

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 1000
	click.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(150, 28)
	billboard.StudsOffset = Vector3.new(0, size.Y * 0.5 + 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.BackgroundTransparency = 0.22
	label.BorderSizePixel = 0
	label.Text = string.format("#%d %s", id, config.Label)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 12
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, 6)
	labelCorner.Parent = label

	local selection = Instance.new("SelectionBox")
	selection.Name = "Selected"
	selection.Adornee = part
	selection.Color3 = Color3.new(1, 1, 1)
	selection.LineThickness = 0.06
	selection.SurfaceTransparency = 1
	selection.Visible = false
	selection.Parent = part

	Zones[id] = {
		Id = id,
		Type = zoneType,
		Part = part,
		Billboard = billboard,
		Selection = selection
	}

	click.MouseClick:Connect(function()
		selectZone(id)
	end)

	SelectedZoneId = id
	updateSelectionVisual()
	refreshResult()
end

local function moveSelectedToCurrent()
	local zone = SelectedZoneId and Zones[SelectedZoneId]
	if not zone or not zone.Part or not zone.Part.Parent then
		Info.Text = "먼저 박스를 선택하세요."
		return
	end

	local root = getRoot()
	if not root then
		Info.Text = "HumanoidRootPart를 찾지 못했습니다."
		return
	end

	zone.Part.CFrame = CFrame.new(root.Position)
	refreshResult()
end

local function resizeSelected()
	local zone = SelectedZoneId and Zones[SelectedZoneId]
	if not zone or not zone.Part or not zone.Part.Parent then
		Info.Text = "먼저 박스를 선택하세요."
		return
	end

	local size = readSize()
	if not size then
		Info.Text = "크기 X/Y/Z 값을 확인하세요."
		return
	end

	zone.Part.Size = size

	if zone.Billboard then
		zone.Billboard.StudsOffset =
			Vector3.new(0, size.Y * 0.5 + 1.5, 0)
	end

	refreshResult()
end

local function deleteSelected()
	local zone = SelectedZoneId and Zones[SelectedZoneId]
	if not zone then
		return
	end

	if zone.Part then
		zone.Part:Destroy()
	end

	Zones[SelectedZoneId] = nil
	SelectedZoneId = nil
	updateSelectionVisual()
	refreshResult()
end

local function deleteAll()
	for id, zone in pairs(Zones) do
		if zone.Part then
			zone.Part:Destroy()
		end

		Zones[id] = nil
	end

	SelectedZoneId = nil
	refreshResult()
end

local function copyResult()
	local output = buildResult()
	Result.Text = output

	local copied = false

	if setclipboard then
		copied = pcall(function()
			setclipboard(output)
		end)
	elseif toclipboard then
		copied = pcall(function()
			toclipboard(output)
		end)
	end

	if copied then
		Info.Text = "설치된 킬존 값과 좌표를 클립보드에 복사했습니다."
	else
		Info.Text = "클립보드 API가 없어 결과창에서 직접 복사하세요."
	end
end

ConfidentialButton.MouseButton1Click:Connect(function()
	createZone("CONFIDENTIAL")
end)

ElectricalButton.MouseButton1Click:Connect(function()
	createZone("ELECTRICAL")
end)

MoveButton.MouseButton1Click:Connect(moveSelectedToCurrent)
ResizeButton.MouseButton1Click:Connect(resizeSelected)
DeleteButton.MouseButton1Click:Connect(deleteSelected)
DeleteAllButton.MouseButton1Click:Connect(deleteAll)
CopyButton.MouseButton1Click:Connect(copyResult)

Close.MouseButton1Click:Connect(function()
	ScreenGui:Destroy()
end)

refreshResult()
