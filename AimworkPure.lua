-- PureUI Aimwork adapter
-- Based on Stefanuk12/aimwork: https://github.com/Stefanuk12/aimwork
-- PureUI supplies the controls, target info, player list, custom game checks, and visuals.

local repo = getgenv().PureUIRepo or 'https://raw.githubusercontent.com/j0z4fx/PureUI-v2/main/'
if repo:sub(-1) ~= '/' then
    repo = repo .. '/'
end
local cacheBust = '?v=' .. tostring(os.time())

local Library = loadstring(game:HttpGet(repo .. 'Library.lua' .. cacheBust))()
local Toggles = getgenv().Toggles
local Options = getgenv().Options
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua' .. cacheBust))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua' .. cacheBust))()
local Aimwork = loadstring(game:HttpGet(repo .. 'addons/Aimwork.lua' .. cacheBust))()

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local IsComputer = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled

local Config = {
    Aimbot = false,
    Actuator = 'Camera',
    AimKey = 'MB2',
    OffAimbotAfterKill = false,
    AimParts = { Torso = true },
    PartFilterType = 'Allowlist',
    StickyAim = false,

    UseOffset = false,
    OffsetType = 'Static',
    StaticOffsetIncrement = 10,
    DynamicOffsetIncrement = 10,
    AutoOffset = false,
    MaxAutoOffset = 50,

    UseSensitivity = true,
    Sensitivity = 50,
    SmoothingType = 'Linear',
    UseNoise = false,
    NoiseFrequency = 10,

    AliveCheck = true,
    TeamCheck = false,
    FriendCheck = false,
    WallCheck = 'Off',
    ForceFieldCheck = true,
    KOCheck = true,
    HeldCheck = true,
    IgnoredCheck = true,
    FoVCheck = true,
    FoVRadius = 120,
    MagnitudeCheck = false,
    MaxDistance = 500,
    TransparencyCheck = false,
    IgnoredTransparency = 0.5,
    TargetPlayersCheck = false,
    TargetPlayers = {},
    IgnoredPlayersCheck = false,
    IgnoredPlayers = {},

    FoV = true,
    FoVThickness = 1.5,
    FoVFilled = false,
    FoVColour = Color3.fromRGB(245, 245, 245),
    FoVAccent = Color3.fromRGB(216, 114, 150),
    FoVGlow = true,
    FoVSmoothing = 0.12,
    FoVSweepSize = 0.16,

    ESP = false,
    ESPBox = true,
    ESPBoxFilled = false,
    NameESP = true,
    HealthESP = false,
    TracerESP = false,
    ESPThickness = 1,
    ESPOpacity = 0.8,
    ESPColour = Color3.fromRGB(245, 245, 245),
    ESPUseTeamColour = false,
}

local Aiming = false
local Target = nil
local LastTargetLockKey = false
local Connections = {}
local EspObjects = {}
local EspAccumulator = 0
local EspHidden = true

local function notify(message)
    Library:Notify('[Aimwork] ' .. message, 2)
end

local function localCharacter()
    return LocalPlayer.Character
end

local function getPart(character, name)
    return character and character:FindFirstChild(name)
end

local AimPartOrder = { 'Head', 'Torso', 'LeftArm', 'RightArm', 'LeftLeg', 'RightLeg' }
local AimPartMap = {
    Head = { 'Head' },
    Torso = { 'HumanoidRootPart', 'UpperTorso', 'Torso', 'LowerTorso' },
    LeftArm = { 'LeftHand', 'LeftLowerArm', 'LeftUpperArm', 'Left Arm', 'LeftArm' },
    RightArm = { 'RightHand', 'RightLowerArm', 'RightUpperArm', 'Right Arm', 'RightArm' },
    LeftLeg = { 'LeftFoot', 'LeftLowerLeg', 'LeftUpperLeg', 'Left Leg', 'LeftLeg' },
    RightLeg = { 'RightFoot', 'RightLowerLeg', 'RightUpperLeg', 'Right Leg', 'RightLeg' },
}

local function getOriginPart(character)
    return getPart(character, 'HumanoidRootPart')
        or getPart(character, 'UpperTorso')
        or getPart(character, 'Torso')
        or getPart(character, 'Head')
end

local function normalizeAimParts(value)
    local normalized = {}

    if type(value) == 'table' then
        for key, enabled in pairs(value) do
            if type(key) == 'number' then
                normalized[tostring(enabled)] = true
            elseif enabled then
                normalized[tostring(key)] = true
            end
        end
    end

    if next(normalized) == nil then
        normalized.Torso = true
    end

    Config.AimParts = normalized

    for _, key in ipairs(AimPartOrder) do
        if normalized[key] then
            Config.AimPart = key
            return normalized
        end
    end

    Config.AimPart = 'Torso'
    return normalized
end

local function keyNameToInput(name)
    if name == 'MB1' then
        return Enum.UserInputType.MouseButton1
    elseif name == 'MB2' then
        return Enum.UserInputType.MouseButton2
    end

    return Enum.KeyCode[name] or Enum.KeyCode.F1
end

local function getArmorValue(character)
    local effects = character and character:FindFirstChild('BodyEffects')
    local armor = effects and effects:FindFirstChild('Armor')

    if armor and (armor:IsA('NumberValue') or armor:IsA('IntValue')) then
        return math.max(tonumber(armor.Value) or 0, 0)
    end

    return 0
end

local function resetAimbot(saveAiming, saveTarget)
    Aiming = saveAiming and Aiming or false
    Target = saveTarget and Target or nil
end

local function getAimAlpha(delta)
    if not Config.UseSensitivity then
        return 1
    end

    local smoothing = math.clamp((tonumber(Config.Sensitivity) or 50) / 100, 0, 0.98)
    local alpha = math.clamp(1 - smoothing, 0.02, 1)
    alpha = 1 - math.pow(1 - alpha, math.max((delta or 0) * 60, 1))

    if Config.SmoothingType == 'Ease out' then
        alpha = 1 - math.pow(1 - alpha, 2)
    elseif Config.SmoothingType == 'Ease in out' then
        alpha = alpha < 0.5 and 2 * alpha * alpha or 1 - math.pow(-2 * alpha + 2, 2) / 2
    end

    return math.clamp(alpha, 0.02, 1)
end

local function getAimWorldPosition(selected)
    local targetPart = selected and selected.part
    local character = selected and selected.character
    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    local worldPosition = targetPart and targetPart.Position or Vector3.zero
    local offset = Vector3.zero

    if Config.UseOffset then
        local static = Vector3.new(0, targetPart.Position.Y * Config.StaticOffsetIncrement / 10, 0)
        local dynamic = humanoid and humanoid.MoveDirection * Config.DynamicOffsetIncrement / 10 or Vector3.zero
        local nativePart = getOriginPart(localCharacter())

        if Config.AutoOffset and nativePart then
            local autoY = math.min(targetPart.Position.Y * Config.StaticOffsetIncrement * (targetPart.Position - nativePart.Position).Magnitude / 1000, Config.MaxAutoOffset)
            offset = Vector3.new(0, autoY, 0) + dynamic
        elseif Config.OffsetType == 'Dynamic' then
            offset = dynamic
        elseif Config.OffsetType == 'Both' then
            offset = static + dynamic
        else
            offset = static
        end
    end

    local noise = Vector3.zero
    if Config.UseNoise then
        local n = Config.NoiseFrequency / 100
        noise = Vector3.new(math.random() * n * 2 - n, math.random() * n * 2 - n, math.random() * n * 2 - n)
    end

    return worldPosition + offset + noise
end

local function applyAimActuation(worldPosition, viewportPosition, inViewport, delta)
    local alpha = getAimAlpha(delta)

    if Config.Actuator == 'Mouse' and getfenv().mousemoverel and IsComputer then
        if inViewport then
            local mouseLocation = UserInputService:GetMouseLocation()
            local delta2 = Vector2.new(viewportPosition.X, viewportPosition.Y) - mouseLocation
            getfenv().mousemoverel(delta2.X * alpha, delta2.Y * alpha)
        end
        return
    end

    local targetCFrame = CFrame.new(Camera.CFrame.Position, worldPosition)
    Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, alpha)
end

local FovCircle = Library:CreateFovCircle({
    Visible = false,
    Radius = Config.FoVRadius,
    Sides = 72,
    Color = Config.FoVColour,
    AccentColor = Config.FoVAccent,
    Thickness = Config.FoVThickness,
    Filled = Config.FoVFilled,
    Glow = Config.FoVGlow,
    Smoothing = Config.FoVSmoothing,
    SweepSize = Config.FoVSweepSize,
})

local function newDrawing(kind)
    if not (getfenv().Drawing and getfenv().Drawing.new) then
        return nil
    end

    local drawing = getfenv().Drawing.new(kind)
    drawing.Visible = false
    return drawing
end

local function clearEsp()
    for _, objectSet in pairs(EspObjects) do
        for _, drawing in pairs(objectSet) do
            pcall(function()
                drawing.Visible = false
                drawing:Remove()
            end)
        end
    end
    table.clear(EspObjects)
end

local function getEsp(player)
    if EspObjects[player] then
        return EspObjects[player]
    end

    local set = {
        Box = newDrawing('Square'),
        Name = newDrawing('Text'),
        Health = newDrawing('Text'),
        Tracer = newDrawing('Line'),
    }

    if set.Name then
        set.Name.Center = true
        set.Name.Outline = true
        set.Name.Size = 14
    end
    if set.Health then
        set.Health.Center = true
        set.Health.Outline = true
        set.Health.Size = 13
    end
    if set.Box then
        set.Box.Filled = false
    end

    EspObjects[player] = set
    return set
end

local function isGuiVisible(gui)
    local current = gui

    while current and current ~= Library.ScreenGui do
        if current:IsA('GuiObject') and not current.Visible then
            return false
        end

        current = current.Parent
    end

    return true
end

local function rectsOverlap(aPosition, aSize, bPosition, bSize)
    return aPosition.X < bPosition.X + bSize.X
        and aPosition.X + aSize.X > bPosition.X
        and aPosition.Y < bPosition.Y + bSize.Y
        and aPosition.Y + aSize.Y > bPosition.Y
end

local function espOverlapsPureUi(position, size)
    local screenGui = Library.ScreenGui
    if not screenGui then
        return false
    end

    for _, gui in ipairs(screenGui:GetDescendants()) do
        if gui:IsA('GuiObject') and isGuiVisible(gui) then
            local guiSize = gui.AbsoluteSize
            if guiSize.X > 0 and guiSize.Y > 0 and rectsOverlap(position, size, gui.AbsolutePosition, guiSize) then
                return true
            end
        end
    end

    return false
end

local function updateEsp()
    if not (getfenv().Drawing and getfenv().Drawing.new) then
        return
    end

    if not Config.ESP then
        if not EspHidden then
            for _, set in pairs(EspObjects) do
                for _, drawing in pairs(set) do
                    drawing.Visible = false
                end
            end
            EspHidden = true
        end
        return
    end
    EspHidden = false

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local set = getEsp(player)
            local character = player.Character
            local head = character and character:FindFirstChild('Head')
            local root = character and character:FindFirstChild('HumanoidRootPart')
            local humanoid = character and character:FindFirstChildOfClass('Humanoid')
            local show = false

            if character and head and root and humanoid then
                local ready = true
                local rootPos, inViewport = Camera:WorldToViewportPoint(root.Position)
                local headPos = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local bottomPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

                show = ready and inViewport
                if show then
                    local height = math.abs(headPos.Y - bottomPos.Y)
                    local width = math.clamp(2350 / math.max(rootPos.Z, 1), 12, 400)
                    local color = Config.ESPUseTeamColour and player.TeamColor.Color or Config.ESPColour
                    local boxPosition = Vector2.new(rootPos.X - width / 2, rootPos.Y - height / 2)
                    local occupiedPosition = boxPosition - Vector2.new(0, 18)
                    local occupiedSize = Vector2.new(width, height + 40)

                    if espOverlapsPureUi(occupiedPosition, occupiedSize) then
                        show = false
                    end

                    if show and set.Box then
                        set.Box.Position = boxPosition
                        set.Box.Size = Vector2.new(width, height)
                        set.Box.Thickness = Config.ESPThickness
                        set.Box.Transparency = Config.ESPOpacity
                        set.Box.Filled = Config.ESPBoxFilled
                        set.Box.Color = color
                        set.Box.Visible = Config.ESPBox
                    end

                    if show and set.Name then
                        set.Name.Text = player.Name
                        set.Name.Position = Vector2.new(rootPos.X, rootPos.Y - height / 2 - 14)
                        set.Name.Color = color
                        set.Name.Transparency = Config.ESPOpacity
                        set.Name.Visible = Config.NameESP
                    end

                    if show and set.Health then
                        set.Health.Text = ('%d/%d'):format(math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
                        set.Health.Position = Vector2.new(rootPos.X, rootPos.Y + height / 2 + 2)
                        set.Health.Color = color
                        set.Health.Transparency = Config.ESPOpacity
                        set.Health.Visible = Config.HealthESP
                    end

                    if show and set.Tracer then
                        set.Tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        set.Tracer.To = Vector2.new(rootPos.X, rootPos.Y + height / 2)
                        set.Tracer.Thickness = Config.ESPThickness
                        set.Tracer.Color = color
                        set.Tracer.Transparency = Config.ESPOpacity
                        set.Tracer.Visible = Config.TracerESP
                    end
                end
            end

            if not show then
                for _, drawing in pairs(set) do
                    drawing.Visible = false
                end
            end
        end
    end
end

local function setDrawingFovVisible(value)
    FovCircle:SetVisible(value and Config.FoV)
end

local function makeMouseFov(id, radiusGetter, enabledGetter)
    return {
        id = id,
        Update = function() end,
        Destroy = function() end,
        InsideFOV = function(_, position)
            local distance = (UserInputService:GetMouseLocation() - position).Magnitude
            if not enabledGetter() then
                return true, distance
            end

            local radius = radiusGetter()
            return distance <= radius, distance
        end,
    }
end

local function selectedIsValid(selected)
    return selected
        and selected.player
        and selected.player ~= LocalPlayer
        and selected.character
        and selected.part
end

local function getAimPartNameMap()
    local names = {}
    normalizeAimParts(Config.AimParts)

    for key, enabled in pairs(Config.AimParts) do
        if enabled then
            for _, partName in ipairs(AimPartMap[key] or { key }) do
                names[partName] = true
            end
        end
    end

    return names
end

local function buildAimworkSettings()
    return {
        TargetLock = {
            Enabled = Config.StickyAim,
            LockOnly = false,
            Mode = 'Lock',
            Bind = keyNameToInput(Config.AimKey),
        },
        Checks = {
            ForceField = Config.ForceFieldCheck,
            Friend = Config.FriendCheck,
            Dead = Config.AliveCheck,
            Invisible = Config.TransparencyCheck,
            TransparencyLimit = Config.IgnoredTransparency,
            Magnitude = Config.MagnitudeCheck,
            MaxMagnitude = Config.MaxDistance,
            Ignored = Config.IgnoredCheck,
            WallCheck = Config.WallCheck == 'Off' and false or Config.WallCheck,
            KO = Config.KOCheck,
            Held = Config.HeldCheck,
        },
        PartFilter = {
            Type = Config.PartFilterType,
            Name = getAimPartNameMap(),
        },
        Ignored = {
            IgnoreLocalTeam = Config.TeamCheck,
            AllowlistEnabledFor = {
                Teams = false,
                Players = Config.TargetPlayersCheck,
            },
            Teams = {},
            Players = Config.TargetPlayersCheck and Config.TargetPlayers or (Config.IgnoredPlayersCheck and Config.IgnoredPlayers or {}),
        },
    }
end

local AimworkTarget = Aimwork.new(buildAimworkSettings())

local AimFovObject = makeMouseFov('AimFOV', function()
    return Config.FoVRadius
end, function()
    return Config.FoVCheck
end)

AimworkTarget:RegisterCustomFov(AimFovObject)

local function syncAimworkSettings()
    local instance = AimworkTarget
    local settings = instance.settings
    settings.TargetLock.Enabled = Config.StickyAim
    settings.TargetLock.LockOnly = Config.StickyAim
    settings.TargetLock.Mode = 'Lock'
    settings.TargetLock.Bind = keyNameToInput(Config.AimKey)
    settings.Checks.ForceField = Config.ForceFieldCheck
    settings.Checks.Friend = Config.FriendCheck
    settings.Checks.Dead = Config.AliveCheck
    settings.Checks.Invisible = Config.TransparencyCheck
    settings.Checks.TransparencyLimit = Config.IgnoredTransparency
    settings.Checks.Magnitude = Config.MagnitudeCheck
    settings.Checks.MaxMagnitude = Config.MaxDistance
    settings.Checks.Ignored = Config.IgnoredCheck
    settings.Checks.WallCheck = Config.WallCheck == 'Off' and false or Config.WallCheck
    settings.Checks.KO = Config.KOCheck
    settings.Checks.Held = Config.HeldCheck
    settings.Ignored.IgnoreLocalTeam = Config.TeamCheck
    settings.Ignored.AllowlistEnabledFor.Players = Config.TargetPlayersCheck
    settings.Ignored.Players = Config.TargetPlayersCheck and Config.TargetPlayers or (Config.IgnoredPlayersCheck and Config.IgnoredPlayers or {})
    instance:SetPartFilter(getAimPartNameMap(), Config.PartFilterType)
end

local Window = Library:CreateWindow({
    Title = 'Pure Aimwork',
    Center = true,
    AutoShow = true,
    MenuFadeTime = 0.2,
})

local TargetInfo = Library:CreateTargetInfo({
    Player = LocalPlayer,
    Armor = getArmorValue(LocalPlayer.Character),
    ArmorMax = 200,
})

local PlayerList = Library:CreatePlayerList({
    Title = 'Players',
    Size = UDim2.fromOffset(300, 432),
})

local EspPreview = Window:AddEspPreview({
    Title = 'ESP Preview',
    AvatarScale = 0.58,
})
if type(EspPreview.SetEspConfigProvider) == 'function' then
    EspPreview:SetEspConfigProvider(function()
        return Config
    end)
end

local Tabs = {
    Aimbot = Window:AddTab('Aimbot'),
    Visuals = Window:AddTab('Visuals'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

EspPreview:SetVisible(false)
Window:OnTabChanged(function(name)
    EspPreview:SetVisible(name == 'Visuals')
end)

local function removeValue(list, value)
    for index = #list, 1, -1 do
        if list[index] == value then
            table.remove(list, index)
        end
    end
end

local function updateTargetFilters()
    Config.IgnoredPlayersCheck = #Config.IgnoredPlayers > 0
    Config.TargetPlayersCheck = #Config.TargetPlayers > 0
end

local function setPlayerDisposition(player, value)
    if not player then
        return
    end

    removeValue(Config.IgnoredPlayers, player.Name)
    removeValue(Config.TargetPlayers, player.Name)

    if value == 'Whitelist' then
        table.insert(Config.IgnoredPlayers, player.Name)
    elseif value == 'Enemy' or value == 'Sentry' or value == 'Sentry (Passive)' then
        table.insert(Config.TargetPlayers, player.Name)
    end

    updateTargetFilters()
end

local LastTargetInfoPlayer
local function updateTargetInfo()
    local player = Target and Players:GetPlayerFromCharacter(Target)
    player = player or PlayerList:GetSelectedPlayer() or LocalPlayer

    if player ~= LastTargetInfoPlayer then
        LastTargetInfoPlayer = player
        TargetInfo:SetPlayer(player)
    end

    TargetInfo.ArmorMax = 200
    TargetInfo:SetArmor(getArmorValue(player.Character))
end

PlayerList:AddButton({
    Text = 'Target selected',
    Func = function(player)
        if player and player.Character then
            Target = player.Character
            TargetInfo:SetPlayer(player)
            LastTargetInfoPlayer = player
            notify('targeting ' .. player.Name)
        else
            notify('no character to target')
        end
    end,
})

PlayerList:AddButton({
    Text = 'Teleport',
    Func = function(player)
        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
        local targetRoot = player and player.Character and player.Character:FindFirstChild('HumanoidRootPart')

        if localRoot and targetRoot then
            localRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -3)
        end
    end,
})

PlayerList:AddButton({
    Text = 'Fling',
    Func = function(player)
        notify(player and ('fling selected: ' .. player.Name) or 'no player selected')
    end,
})

PlayerList:AddToggle('OA_SpectatePlayer', {
    Text = 'Spectate',
    Default = false,
    Callback = function(value, player)
        local camera = workspace.CurrentCamera
        local subjectCharacter = value and player and player.Character or LocalPlayer.Character
        local humanoid = subjectCharacter and subjectCharacter:FindFirstChildOfClass('Humanoid')

        if camera and humanoid then
            camera.CameraSubject = humanoid
        end
    end,
})

PlayerList:AddDropdown('OA_PlayerDisposition', {
    Values = { 'None', 'Whitelist', 'Enemy', 'Sentry', 'Sentry (Passive)' },
    Default = 'None',
    Callback = function(value, player)
        setPlayerDisposition(player, value)
    end,
})

local AimbotTabbox = Tabs.Aimbot:AddLeftTabbox('Aimbot')
local AimBox = AimbotTabbox:AddTab('Aim')
local PartFilterBox = AimbotTabbox:AddTab('Aim Part')
local FovBox = AimbotTabbox:AddTab('FOV')
local ChecksBox = AimbotTabbox:AddTab('Checks')

local AimbotToggle = AimBox:AddToggle('AW_Aimbot', {
    Text = 'Aimbot',
    Default = Config.Aimbot,
    Callback = function(value)
        Config.Aimbot = value
        if not value then resetAimbot() end
    end,
})
AimbotToggle:AddKeyPicker('AW_AimKey', {
    Default = Config.AimKey,
    Mode = 'Hold',
    Modes = { 'Hold' },
    Text = 'Target select',
    NoUI = false,
    Callback = function(value)
        Config.AimKey = value
    end,
})

AimBox:AddToggle('AW_StickyAim', {
    Text = 'Sticky aim',
    Default = Config.StickyAim,
    Callback = function(value)
        Config.StickyAim = value
        if not value then
            AimworkTarget._lockTarget = nil
        end
    end,
})

AimBox:AddDropdown('AW_Actuator', {
    Text = 'Aim method',
    Values = getfenv().mousemoverel and { 'Mouse', 'Camera' } or { 'Camera' },
    Default = Config.Actuator,
    Callback = function(value) Config.Actuator = value end,
})

AimBox:AddToggle('AW_UseSensitivity', {
    Text = 'Smooth aim',
    Default = Config.UseSensitivity,
    Callback = function(value) Config.UseSensitivity = value end,
})
AimBox:AddSlider('AW_Sensitivity', {
    Text = 'Smoothing',
    Default = Config.Sensitivity,
    Min = 0,
    Max = 98,
    Rounding = 0,
    Callback = function(value) Config.Sensitivity = value end,
})
AimBox:AddDropdown('AW_SmoothingType', {
    Text = 'Smoothing type',
    Values = { 'Linear', 'Ease out', 'Ease in out' },
    Default = Config.SmoothingType,
    Callback = function(value) Config.SmoothingType = value end,
})

PartFilterBox:AddBodySelector('AW_AimParts', {
    Default = Config.AimParts,
    Height = 204,
    Callback = function(value)
        normalizeAimParts(value)
    end,
})

FovBox:AddToggle('AW_FovCheck', { Text = 'FOV check', Default = Config.FoVCheck, Callback = function(value) Config.FoVCheck = value end })
FovBox:AddSlider('AW_FovRadiusCheck', {
    Text = 'FOV radius',
    Default = Config.FoVRadius,
    Min = 20,
    Max = 500,
    Rounding = 0,
    Callback = function(value)
        Config.FoVRadius = value
        FovCircle:Set('Radius', value)
    end,
})
FovBox:AddToggle('AW_FovVisible', {
    Text = 'Show FOV',
    Default = Config.FoV,
    Callback = function(value)
        Config.FoV = value
        setDrawingFovVisible(value)
    end,
})
FovBox:AddToggle('AW_FovFilled', {
    Text = 'Soft fill',
    Default = Config.FoVFilled,
    Callback = function(value)
        Config.FoVFilled = value
        FovCircle:Set('Filled', value)
    end,
})
FovBox:AddToggle('AW_FovGlow', {
    Text = 'Glow',
    Default = Config.FoVGlow,
    Callback = function(value)
        Config.FoVGlow = value
        FovCircle:Set('Glow', value)
    end,
})
FovBox:AddSlider('AW_FovThickness', {
    Text = 'Thickness',
    Default = Config.FoVThickness,
    Min = 1,
    Max = 5,
    Rounding = 1,
    Callback = function(value)
        Config.FoVThickness = value
        FovCircle:Set('Thickness', value)
    end,
})
FovBox:AddSlider('AW_FovSweepSize', {
    Text = 'Accent length',
    Default = Config.FoVSweepSize,
    Min = 0.04,
    Max = 0.5,
    Rounding = 2,
    Callback = function(value)
        Config.FoVSweepSize = value
        FovCircle:Set('SweepSize', value)
    end,
})
FovBox:AddSlider('AW_FovSmoothing', {
    Text = 'Mouse smoothing',
    Default = Config.FoVSmoothing,
    Min = 0,
    Max = 0.98,
    Rounding = 2,
    Callback = function(value)
        Config.FoVSmoothing = value
        FovCircle:Set('Smoothing', value)
    end,
})
FovBox:AddLabel('Ring color'):AddColorPicker('AW_FovColor', {
    Default = Config.FoVColour,
    Title = 'FOV ring color',
    Callback = function(value)
        Config.FoVColour = value
        FovCircle:Set('Color', value)
    end,
})
FovBox:AddLabel('Accent color'):AddColorPicker('AW_FovAccent', {
    Default = Config.FoVAccent,
    Title = 'FOV accent color',
    Callback = function(value)
        Config.FoVAccent = value
        FovCircle:Set('AccentColor', value)
    end,
})

ChecksBox:AddToggle('AW_CheckDead', { Text = 'Alive check', Default = Config.AliveCheck, Callback = function(value) Config.AliveCheck = value end })
ChecksBox:AddToggle('AW_CheckForceField', { Text = 'Forcefield check', Default = Config.ForceFieldCheck, Callback = function(value) Config.ForceFieldCheck = value end })
ChecksBox:AddToggle('AW_CheckKO', { Text = 'K.O. check', Default = Config.KOCheck, Callback = function(value) Config.KOCheck = value end })
ChecksBox:AddToggle('AW_CheckHeld', { Text = 'Held check', Default = Config.HeldCheck, Callback = function(value) Config.HeldCheck = value end })
local DistanceToggle = ChecksBox:AddToggle('AW_CheckMagnitude', { Text = 'Distance check', Default = Config.MagnitudeCheck, Callback = function(value) Config.MagnitudeCheck = value end })
local DistanceDependency = ChecksBox:AddDependencyBox()
DistanceDependency:AddSlider('AW_MaxMagnitude', {
    Text = 'Max distance',
    Default = Config.MaxDistance,
    Min = 25,
    Max = 2000,
    Rounding = 0,
    Callback = function(value) Config.MaxDistance = value end,
})
DistanceDependency:SetupDependencies({ { DistanceToggle, true } })

local EspBox = Tabs.Visuals:AddLeftGroupbox('ESP')
EspBox:AddToggle('OA_ESP', { Text = 'Enable ESP', Default = Config.ESP, Callback = function(value) Config.ESP = value end })
EspBox:AddToggle('OA_ESPBox', { Text = 'Boxes', Default = Config.ESPBox, Callback = function(value) Config.ESPBox = value end })
EspBox:AddToggle('OA_ESPBoxFilled', { Text = 'Filled boxes', Default = Config.ESPBoxFilled, Callback = function(value) Config.ESPBoxFilled = value end })
EspBox:AddToggle('OA_NameESP', { Text = 'Names', Default = Config.NameESP, Callback = function(value) Config.NameESP = value end })
EspBox:AddToggle('OA_HealthESP', { Text = 'Health', Default = Config.HealthESP, Callback = function(value) Config.HealthESP = value end })
EspBox:AddToggle('OA_TracerESP', { Text = 'Tracers', Default = Config.TracerESP, Callback = function(value) Config.TracerESP = value end })
EspBox:AddToggle('OA_ESPTeamColor', { Text = 'Team color', Default = Config.ESPUseTeamColour, Callback = function(value) Config.ESPUseTeamColour = value end })
EspBox:AddSlider('OA_ESPThickness', { Text = 'Thickness', Default = Config.ESPThickness, Min = 1, Max = 5, Rounding = 1, Callback = function(value) Config.ESPThickness = value end })
EspBox:AddSlider('OA_ESPOpacity', { Text = 'Opacity', Default = Config.ESPOpacity, Min = 0, Max = 1, Rounding = 2, Callback = function(value) Config.ESPOpacity = value end })
EspBox:AddLabel('ESP color'):AddColorPicker('OA_ESPColor', {
    Default = Config.ESPColour,
    Title = 'ESP color',
    Callback = function(value) Config.ESPColour = value end,
})

local SettingsBox = Tabs['UI Settings']:AddLeftGroupbox('Menu')
SettingsBox:AddButton('Unload', function()
    Library:Unload()
end)
SettingsBox:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', {
    Default = 'End',
    NoUI = true,
    Text = 'Menu keybind',
})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder('PureAimwork')
SaveManager:SetFolder('PureAimwork/' .. tostring(game.GameId))
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])

local function showManagedWindows()
    Library:SetManagedWindowVisible('Keybinds', true)
    Library:SetManagedWindowVisible('PlayerList', true)
    Library:SetManagedWindowVisible('TargetInfo', true)
end

showManagedWindows()
task.delay(0.35, showManagedWindows)

table.insert(Connections, Players.PlayerRemoving:Connect(function(player)
    local set = EspObjects[player]
    if set then
        for _, drawing in pairs(set) do
            pcall(function()
                drawing.Visible = false
                drawing:Remove()
            end)
        end
        EspObjects[player] = nil
    end
end))

table.insert(Connections, RunService.RenderStepped:Connect(function(Delta)
    Camera = workspace.CurrentCamera
    if not Camera or Library.Unloaded then
        return
    end

    syncAimworkSettings()
    setDrawingFovVisible(Config.FoV)
    EspAccumulator = EspAccumulator + Delta
    if EspAccumulator >= 0.05 then
        EspAccumulator = 0
        updateEsp()
    end

    local lockKeyDown = Config.Aimbot and Config.StickyAim and Options.AW_AimKey and Options.AW_AimKey:GetState() or false
    if lockKeyDown and not LastTargetLockKey then
        AimworkTarget:LockTarget()
    end
    LastTargetLockKey = lockKeyDown

    local nextAiming = Config.Aimbot
    if Aiming and not nextAiming then
        resetAimbot()
    end

    Aiming = nextAiming
    local aimSelected = AimworkTarget:Iterate()

    if not Config.Aimbot then
        if Aiming then resetAimbot() end
        updateTargetInfo()
        return
    end

    if not Aiming then
        resetAimbot()
        updateTargetInfo()
        return
    end

    if selectedIsValid(aimSelected) then
        Target = aimSelected.character
        local worldPosition = getAimWorldPosition(aimSelected)
        local viewportPosition, inViewport = Camera:WorldToViewportPoint(worldPosition)
        applyAimActuation(worldPosition, viewportPosition, inViewport, Delta)
    else
        resetAimbot(true)
    end

    updateTargetInfo()
end))

Library:OnUnload(function()
    resetAimbot()
    FovCircle:Destroy()
    AimworkTarget:Destroy()
    clearEsp()
    pcall(function()
        TargetInfo:Destroy()
    end)
    pcall(function()
        PlayerList:Destroy()
    end)
    pcall(function()
        EspPreview:Destroy()
    end)
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
end)

notify('loaded')
