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
local TweenService = game:GetService('TweenService')

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local IsComputer = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
local MouseSensitivity = UserInputService.MouseDeltaSensitivity

local Config = {
    Aimbot = false,
    Actuator = 'Camera',
    AimKey = 'MB2',
    OffAimbotAfterKill = false,
    AimParts = { Torso = true },
    PartFilterType = 'Allowlist',
    TargetLockEnabled = false,
    TargetLockOnly = false,
    TargetLockMode = 'Lock',
    TargetLockKey = 'F1',

    UseOffset = false,
    OffsetType = 'Static',
    StaticOffsetIncrement = 10,
    DynamicOffsetIncrement = 10,
    AutoOffset = false,
    MaxAutoOffset = 50,

    UseSensitivity = true,
    Sensitivity = 50,
    UseNoise = false,
    NoiseFrequency = 10,

    TriggerBot = false,
    TriggerKey = 'E',
    TriggerBotChance = 100,
    SmartTriggerBot = true,
    TriggerFoV = false,
    TriggerFoVCheck = false,
    TriggerFoVRadius = 80,
    TriggerFoVThickness = 1.5,
    TriggerFoVColour = Color3.fromRGB(245, 245, 245),
    TriggerFoVAccent = Color3.fromRGB(120, 170, 255),
    TriggerFoVGlow = true,

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
    TriggerMagnitude = 500,
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
local Triggering = false
local Target = nil
local Tween = nil
local LastTargetLockKey = false
local Connections = {}
local EspObjects = {}

local function notify(message)
    Library:Notify('[Aimwork] ' .. message, 2)
end

local function chance(percent)
    return math.random(1, 100) <= math.clamp(math.floor(percent), 1, 100)
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

    if Tween then
        Tween:Cancel()
        Tween = nil
    end

    UserInputService.MouseDeltaSensitivity = MouseSensitivity
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

local function applyAimActuation(worldPosition, viewportPosition, inViewport)
    if Config.Actuator == 'Mouse' and getfenv().mousemoverel and IsComputer then
        if inViewport then
            local mouseLocation = UserInputService:GetMouseLocation()
            local sensitivity = Config.UseSensitivity and Config.Sensitivity / 5 or 10
            getfenv().mousemoverel((viewportPosition.X - mouseLocation.X) / sensitivity, (viewportPosition.Y - mouseLocation.Y) / sensitivity)
        end
        return
    end

    UserInputService.MouseDeltaSensitivity = 0
    local targetCFrame = CFrame.new(Camera.CFrame.Position, worldPosition)
    if Config.UseSensitivity then
        if Tween then
            Tween:Cancel()
        end
        Tween = TweenService:Create(Camera, TweenInfo.new(math.clamp(Config.Sensitivity, 9, 99) / 100, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            CFrame = targetCFrame,
        })
        Tween:Play()
    else
        Camera.CFrame = targetCFrame
    end
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
})

local TriggerFovCircle = Library:CreateFovCircle({
    Visible = false,
    Radius = Config.TriggerFoVRadius,
    Sides = 72,
    Color = Config.TriggerFoVColour,
    AccentColor = Config.TriggerFoVAccent,
    Thickness = Config.TriggerFoVThickness,
    Filled = false,
    Glow = Config.TriggerFoVGlow,
    Smoothing = Config.FoVSmoothing,
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

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local set = getEsp(player)
            local character = player.Character
            local head = character and character:FindFirstChild('Head')
            local root = character and character:FindFirstChild('HumanoidRootPart')
            local humanoid = character and character:FindFirstChildOfClass('Humanoid')
            local show = false

            if Config.ESP and character and head and root and humanoid then
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

local function setTriggerFovVisible(value)
    TriggerFovCircle:SetVisible(value and Config.TriggerFoV and Config.TriggerBot)
end

local function targetInsideTriggerFov(viewportPosition)
    if not Config.TriggerFoVCheck then
        return true
    end

    local mousePosition = UserInputService:GetMouseLocation()
    return (Vector2.new(viewportPosition.X, viewportPosition.Y) - mousePosition).Magnitude <= Config.TriggerFoVRadius
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
            Enabled = Config.TargetLockEnabled,
            LockOnly = Config.TargetLockOnly,
            Mode = Config.TargetLockMode,
            Bind = keyNameToInput(Config.TargetLockKey),
        },
        Checks = {
            ForceField = Config.ForceFieldCheck,
            Friend = Config.FriendCheck,
            Dead = Config.AliveCheck,
            Invisible = Config.TransparencyCheck,
            TransparencyLimit = Config.IgnoredTransparency,
            Magnitude = Config.MagnitudeCheck,
            MaxMagnitude = Config.TriggerMagnitude,
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
local AimworkTrigger = Aimwork.new(buildAimworkSettings())

local AimFovObject = makeMouseFov('AimFOV', function()
    return Config.FoVRadius
end, function()
    return Config.FoVCheck
end)

local TriggerFovObject = makeMouseFov('TriggerFOV', function()
    return Config.TriggerFoVRadius
end, function()
    return Config.TriggerFoVCheck
end)

AimworkTarget:RegisterCustomFov(AimFovObject)
AimworkTrigger:RegisterCustomFov(TriggerFovObject)

local function syncAimworkSettings()
    for _, instance in ipairs({ AimworkTarget, AimworkTrigger }) do
        local settings = instance.settings
        if instance == AimworkTarget then
            settings.TargetLock.Enabled = Config.TargetLockEnabled
            settings.TargetLock.LockOnly = Config.TargetLockOnly
            settings.TargetLock.Mode = Config.TargetLockMode
            settings.TargetLock.Bind = keyNameToInput(Config.TargetLockKey)
        else
            settings.TargetLock.Enabled = false
            settings.TargetLock.LockOnly = false
            settings.TargetLock.Mode = 'Lock'
        end
        settings.Checks.ForceField = Config.ForceFieldCheck
        settings.Checks.Friend = Config.FriendCheck
        settings.Checks.Dead = Config.AliveCheck
        settings.Checks.Invisible = Config.TransparencyCheck
        settings.Checks.TransparencyLimit = Config.IgnoredTransparency
        settings.Checks.Magnitude = Config.MagnitudeCheck
        settings.Checks.MaxMagnitude = Config.TriggerMagnitude
        settings.Checks.Ignored = Config.IgnoredCheck
        settings.Checks.WallCheck = Config.WallCheck == 'Off' and false or Config.WallCheck
        settings.Checks.KO = Config.KOCheck
        settings.Checks.Held = Config.HeldCheck
        settings.Ignored.IgnoreLocalTeam = Config.TeamCheck
        settings.Ignored.AllowlistEnabledFor.Players = Config.TargetPlayersCheck
        settings.Ignored.Players = Config.TargetPlayersCheck and Config.TargetPlayers or (Config.IgnoredPlayersCheck and Config.IgnoredPlayers or {})
        instance:SetPartFilter(getAimPartNameMap(), Config.PartFilterType)
    end
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

local AimbotTabbox = Tabs.Aimbot:AddLeftTabbox('Aimwork')
local TargetLockBox = AimbotTabbox:AddTab('Lock')
local ChecksBox = AimbotTabbox:AddTab('Checks')
local PartFilterBox = AimbotTabbox:AddTab('Parts')
local IgnoredBox = AimbotTabbox:AddTab('Ignored')
local FovBox = AimbotTabbox:AddTab('FOV')
local ActuatorBox = AimbotTabbox:AddTab('Act')
local TriggerBox = Tabs.Aimbot:AddRightGroupbox('Triggerbot')

local AimbotToggle = TargetLockBox:AddToggle('AW_Aimbot', {
    Text = 'Aimwork',
    Default = Config.Aimbot,
    Callback = function(value)
        Config.Aimbot = value
        if not value then resetAimbot() end
    end,
})
AimbotToggle:AddKeyPicker('AW_AimKey', {
    Default = Config.AimKey,
    Mode = 'Hold',
    Modes = { 'Always', 'Toggle', 'Hold' },
    Text = 'Aimwork',
    NoUI = false,
})

local TargetLockToggle = TargetLockBox:AddToggle('AW_TargetLockEnabled', {
    Text = 'TargetLock.Enabled',
    Default = Config.TargetLockEnabled,
    Callback = function(value)
        Config.TargetLockEnabled = value
        if not value then
            AimworkTarget._lockTarget = nil
        end
    end,
})
TargetLockToggle:AddKeyPicker('AW_TargetLockKey', {
    Default = Config.TargetLockKey,
    Mode = 'Hold',
    Modes = { 'Hold' },
    Text = 'TargetLock.Bind',
    NoUI = false,
    Callback = function(value)
        Config.TargetLockKey = value
    end,
})
TargetLockBox:AddToggle('AW_TargetLockOnly', {
    Text = 'TargetLock.LockOnly',
    Default = Config.TargetLockOnly,
    Callback = function(value) Config.TargetLockOnly = value end,
})
TargetLockBox:AddDropdown('AW_TargetLockMode', {
    Text = 'TargetLock.Mode',
    Values = { 'Lock', 'Unlock' },
    Default = Config.TargetLockMode,
    Callback = function(value) Config.TargetLockMode = value end,
})
TargetLockBox:AddToggle('AW_OffAfterKill', {
    Text = 'Off after kill',
    Default = Config.OffAimbotAfterKill,
    Callback = function(value) Config.OffAimbotAfterKill = value end,
})

ChecksBox:AddToggle('AW_CheckForceField', { Text = 'Checks.ForceField', Default = Config.ForceFieldCheck, Callback = function(value) Config.ForceFieldCheck = value end })
ChecksBox:AddToggle('AW_CheckFriend', { Text = 'Checks.Friend', Default = Config.FriendCheck, Callback = function(value) Config.FriendCheck = value end })
ChecksBox:AddToggle('AW_CheckDead', { Text = 'Checks.Dead', Default = Config.AliveCheck, Callback = function(value) Config.AliveCheck = value end })
ChecksBox:AddToggle('AW_CheckInvisible', { Text = 'Checks.Invisible', Default = Config.TransparencyCheck, Callback = function(value) Config.TransparencyCheck = value end })
ChecksBox:AddSlider('AW_TransparencyLimit', {
    Text = 'TransparencyLimit',
    Default = Config.IgnoredTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(value) Config.IgnoredTransparency = value end,
})
ChecksBox:AddToggle('AW_CheckIgnored', {
    Text = 'Checks.Ignored',
    Default = Config.IgnoredCheck,
    Callback = function(value) Config.IgnoredCheck = value end,
})
ChecksBox:AddDropdown('AW_WallCheck', {
    Text = 'Checks.WallCheck',
    Values = { 'Off', 'OnScreen', 'Full' },
    Default = Config.WallCheck,
    Callback = function(value)
        Config.WallCheck = value
    end,
})
ChecksBox:AddToggle('AW_CheckKO', { Text = 'Checks.K.O.', Default = Config.KOCheck, Callback = function(value) Config.KOCheck = value end })
ChecksBox:AddToggle('AW_CheckHeld', { Text = 'Checks.Held', Default = Config.HeldCheck, Callback = function(value) Config.HeldCheck = value end })
ChecksBox:AddToggle('AW_CheckMagnitude', { Text = 'Checks.Magnitude', Default = Config.MagnitudeCheck, Callback = function(value) Config.MagnitudeCheck = value end })
ChecksBox:AddSlider('AW_MaxMagnitude', {
    Text = 'MaxMagnitude',
    Default = Config.TriggerMagnitude,
    Min = 25,
    Max = 2000,
    Rounding = 0,
    Callback = function(value) Config.TriggerMagnitude = value end,
})

PartFilterBox:AddDropdown('AW_PartFilterType', {
    Text = 'PartFilter.Type',
    Values = { 'Allowlist', 'Blocklist' },
    Default = Config.PartFilterType,
    Callback = function(value) Config.PartFilterType = value end,
})
PartFilterBox:AddBodySelector('AW_AimParts', {
    Default = Config.AimParts,
    Height = 186,
    Callback = function(value)
        normalizeAimParts(value)
    end,
})

IgnoredBox:AddToggle('AW_IgnoreLocalTeam', {
    Text = 'Ignored.IgnoreLocalTeam',
    Default = Config.TeamCheck,
    Callback = function(value) Config.TeamCheck = value end,
})
IgnoredBox:AddToggle('AW_PlayerAllowlist', {
    Text = 'Allowlist.Players',
    Default = Config.TargetPlayersCheck,
    Callback = function(value)
        Config.TargetPlayersCheck = value
        if value then Config.IgnoredPlayersCheck = false end
    end,
})
IgnoredBox:AddToggle('AW_PlayerBlocklist', {
    Text = 'Blocklist.Players',
    Default = Config.IgnoredPlayersCheck,
    Callback = function(value)
        Config.IgnoredPlayersCheck = value
        if value then Config.TargetPlayersCheck = false end
    end,
})

ActuatorBox:AddDropdown('AW_Actuator', {
    Text = 'Pure actuator',
    Values = getfenv().mousemoverel and { 'Camera', 'Mouse' } or { 'Camera' },
    Default = Config.Actuator,
    Callback = function(value) Config.Actuator = value end,
})
ActuatorBox:AddToggle('AW_UseSensitivity', {
    Text = 'Smooth actuator',
    Default = Config.UseSensitivity,
    Callback = function(value) Config.UseSensitivity = value end,
})
ActuatorBox:AddSlider('AW_Sensitivity', {
    Text = 'Actuator smoothing',
    Default = Config.Sensitivity,
    Min = 9,
    Max = 99,
    Rounding = 0,
    Callback = function(value) Config.Sensitivity = value end,
})
ActuatorBox:AddToggle('AW_UseOffset', {
    Text = 'World offset',
    Default = Config.UseOffset,
    Callback = function(value) Config.UseOffset = value end,
})
ActuatorBox:AddDropdown('AW_OffsetType', {
    Text = 'Offset type',
    Values = { 'Static', 'Dynamic', 'Both' },
    Default = Config.OffsetType,
    Callback = function(value) Config.OffsetType = value end,
})
ActuatorBox:AddSlider('AW_StaticOffset', {
    Text = 'Static offset',
    Default = Config.StaticOffsetIncrement,
    Min = -50,
    Max = 50,
    Rounding = 0,
    Callback = function(value) Config.StaticOffsetIncrement = value end,
})
ActuatorBox:AddSlider('AW_DynamicOffset', {
    Text = 'Dynamic offset',
    Default = Config.DynamicOffsetIncrement,
    Min = -50,
    Max = 50,
    Rounding = 0,
    Callback = function(value) Config.DynamicOffsetIncrement = value end,
})
ActuatorBox:AddToggle('AW_Noise', {
    Text = 'Actuator noise',
    Default = Config.UseNoise,
    Callback = function(value) Config.UseNoise = value end,
})
ActuatorBox:AddSlider('AW_NoiseFrequency', {
    Text = 'Noise amount',
    Default = Config.NoiseFrequency,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(value) Config.NoiseFrequency = value end,
})

local TriggerToggle = TriggerBox:AddToggle('AW_TriggerBot', {
    Text = 'Triggerbot',
    Default = Config.TriggerBot,
    Callback = function(value)
        Config.TriggerBot = value
        if not value then Triggering = false end
        setTriggerFovVisible(Config.TriggerFoV)
    end,
})
TriggerToggle:AddKeyPicker('AW_TriggerKey', {
    Default = Config.TriggerKey,
    Mode = 'Toggle',
    Modes = { 'Always', 'Toggle', 'Hold' },
    Text = 'Triggerbot',
    NoUI = false,
})
TriggerBox:AddToggle('AW_SmartTrigger', {
    Text = 'Only while aiming',
    Default = Config.SmartTriggerBot,
    Callback = function(value) Config.SmartTriggerBot = value end,
})
TriggerBox:AddSlider('AW_TriggerChance', {
    Text = 'Click chance',
    Default = Config.TriggerBotChance,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Callback = function(value) Config.TriggerBotChance = value end,
})
TriggerBox:AddToggle('AW_TriggerFovCheck', {
    Text = 'FOV check',
    Default = Config.TriggerFoVCheck,
    Callback = function(value) Config.TriggerFoVCheck = value end,
})
TriggerBox:AddToggle('AW_TriggerFovVisible', {
    Text = 'Show FOV',
    Default = Config.TriggerFoV,
    Callback = function(value)
        Config.TriggerFoV = value
        setTriggerFovVisible(value)
    end,
})
TriggerBox:AddSlider('AW_TriggerFovRadius', {
    Text = 'FOV radius',
    Default = Config.TriggerFoVRadius,
    Min = 20,
    Max = 500,
    Rounding = 0,
    Callback = function(value)
        Config.TriggerFoVRadius = value
        TriggerFovCircle:Set('Radius', value)
    end,
})
TriggerBox:AddSlider('AW_TriggerFovThickness', {
    Text = 'FOV thickness',
    Default = Config.TriggerFoVThickness,
    Min = 1,
    Max = 5,
    Rounding = 1,
    Callback = function(value)
        Config.TriggerFoVThickness = value
        TriggerFovCircle:Set('Thickness', value)
    end,
})
TriggerBox:AddLabel('FOV color'):AddColorPicker('AW_TriggerFovColor', {
    Default = Config.TriggerFoVColour,
    Title = 'Trigger FOV color',
    Callback = function(value)
        Config.TriggerFoVColour = value
        TriggerFovCircle:Set('Color', value)
    end,
})
TriggerBox:AddLabel('FOV accent'):AddColorPicker('AW_TriggerFovAccent', {
    Default = Config.TriggerFoVAccent,
    Title = 'Trigger FOV accent',
    Callback = function(value)
        Config.TriggerFoVAccent = value
        TriggerFovCircle:Set('AccentColor', value)
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

table.insert(Connections, RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera
    if not Camera or Library.Unloaded then
        return
    end

    syncAimworkSettings()
    setDrawingFovVisible(Config.FoV)
    setTriggerFovVisible(Config.TriggerFoV)
    updateEsp()

    local lockKeyDown = Config.TargetLockEnabled and Options.AW_TargetLockKey and Options.AW_TargetLockKey:GetState() or false
    if lockKeyDown and not LastTargetLockKey then
        if Config.TargetLockMode == 'Unlock' then
            AimworkTarget._lockTarget = nil
        else
            AimworkTarget:LockTarget()
        end
    end
    LastTargetLockKey = lockKeyDown

    local nextAiming = Config.Aimbot and Options.AW_AimKey and Options.AW_AimKey:GetState() or false
    if Aiming and not nextAiming then
        resetAimbot()
    end

    Aiming = nextAiming
    Triggering = Config.TriggerBot and Options.AW_TriggerKey and Options.AW_TriggerKey:GetState() or false
    local aimSelected = AimworkTarget:Iterate()

    if Config.TriggerBot and Triggering and (not Config.SmartTriggerBot or Aiming) and getfenv().mouse1click then
        local triggerSelected = AimworkTrigger:Iterate()
        if selectedIsValid(triggerSelected) and targetInsideTriggerFov(triggerSelected.position) and chance(Config.TriggerBotChance) then
            getfenv().mouse1click()
        end
    end

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
        applyAimActuation(worldPosition, viewportPosition, inViewport)
    else
        resetAimbot(true)
    end

    updateTargetInfo()
end))

Library:OnUnload(function()
    resetAimbot()
    FovCircle:Destroy()
    TriggerFovCircle:Destroy()
    AimworkTarget:Destroy()
    AimworkTrigger:Destroy()
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
