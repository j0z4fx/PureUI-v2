-- PureUI Open Aimbot adapter
-- Based on ttwizz/Open-Aimbot (MIT): https://github.com/ttwizz/Open-Aimbot
-- This keeps the core target/check/visual behavior and replaces the original Fluent UI with PureUI.

local repo = 'https://raw.githubusercontent.com/j0z4fx/PureUI-v2/main/'
local cacheBust = '?v=' .. tostring(os.time())

local Library = loadstring(game:HttpGet(repo .. 'Library.lua' .. cacheBust))()
local Toggles = getgenv().Toggles
local Options = getgenv().Options
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua' .. cacheBust))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua' .. cacheBust))()

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
    AimMode = 'Camera',
    AimKey = 'MB2',
    OnePressAimingMode = false,
    OffAimbotAfterKill = false,
    AimPart = 'HumanoidRootPart',

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

    AliveCheck = true,
    GodCheck = true,
    TeamCheck = false,
    FriendCheck = false,
    WallCheck = false,
    WaterCheck = false,
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
local Connections = {}
local EspObjects = {}

local function notify(message)
    Library:Notify('[Open Aimbot] ' .. message, 2)
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

local function resetAimbot(saveAiming, saveTarget)
    Aiming = saveAiming and Aiming or false
    Target = saveTarget and Target or nil

    if Tween then
        Tween:Cancel()
        Tween = nil
    end

    UserInputService.MouseDeltaSensitivity = MouseSensitivity
end

local function targetAllowed(player, character, targetPart)
    if not player or player == LocalPlayer then
        return false
    end

    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    if not humanoid then
        return false
    end

    if Config.AliveCheck and humanoid.Health <= 0 then
        return false
    end

    if Config.GodCheck and (humanoid.Health >= 10 ^ 36 or character:FindFirstChildOfClass('ForceField')) then
        return false
    end

    if Config.TeamCheck and player.TeamColor == LocalPlayer.TeamColor then
        return false
    end

    if Config.FriendCheck and player:IsFriendsWith(LocalPlayer.UserId) then
        return false
    end

    if Config.TransparencyCheck then
        local head = character:FindFirstChild('Head')
        if head and head:IsA('BasePart') and head.Transparency >= Config.IgnoredTransparency then
            return false
        end
    end

    if Config.IgnoredPlayersCheck and table.find(Config.IgnoredPlayers, player.Name) then
        return false
    end

    if Config.TargetPlayersCheck and not table.find(Config.TargetPlayers, player.Name) then
        return false
    end

    if Config.MagnitudeCheck then
        local nativePart = getPart(localCharacter(), Config.AimPart)
        if nativePart and (targetPart.Position - nativePart.Position).Magnitude > Config.TriggerMagnitude then
            return false
        end
    end

    if Config.WallCheck then
        local nativePart = getPart(localCharacter(), Config.AimPart)
        if nativePart then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { localCharacter() }
            params.IgnoreWater = not Config.WaterCheck

            local direction = targetPart.Position - nativePart.Position
            local result = workspace:Raycast(nativePart.Position, direction, params)
            if not result or not result.Instance or not result.Instance:IsDescendantOf(character) then
                return false
            end
        end
    end

    return true
end

local function resolveTarget(character)
    local localChar = localCharacter()
    local nativePart = getPart(localChar, Config.AimPart)
    local targetPart = getPart(character, Config.AimPart)
    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    local player = Players:GetPlayerFromCharacter(character)

    if not (localChar and nativePart and targetPart and targetPart:IsA('BasePart') and humanoid and player) then
        return false
    end

    if not targetAllowed(player, character, targetPart) then
        return false
    end

    local offset = Vector3.zero
    if Config.UseOffset then
        local static = Vector3.new(0, targetPart.Position.Y * Config.StaticOffsetIncrement / 10, 0)
        local dynamic = humanoid.MoveDirection * Config.DynamicOffsetIncrement / 10

        if Config.AutoOffset then
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

    local worldPosition = targetPart.Position + offset + noise
    local viewportPosition, inViewport = Camera:WorldToViewportPoint(worldPosition)
    local distance = (worldPosition - nativePart.Position).Magnitude

    return true, character, viewportPosition, inViewport, worldPosition, distance, targetPart
end

local function acquireTarget()
    local closest = math.huge
    local best = nil
    local mousePosition = UserInputService:GetMouseLocation()

    for _, player in ipairs(Players:GetPlayers()) do
        local ok, character, viewportPosition, inViewport = resolveTarget(player.Character)
        if ok and inViewport then
            local screenDistance = (Vector2.new(viewportPosition.X, viewportPosition.Y) - mousePosition).Magnitude
            if screenDistance <= closest and (not Config.FoVCheck or screenDistance <= Config.FoVRadius) then
                closest = screenDistance
                best = character
            end
        end
    end

    return best
end

local function aimAt(worldPosition, viewportPosition, inViewport)
    if Config.AimMode == 'Mouse' and getfenv().mousemoverel and IsComputer then
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
                local ready = not Config.SmartESP or select(1, resolveTarget(character))
                local rootPos, inViewport = Camera:WorldToViewportPoint(root.Position)
                local headPos = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local bottomPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

                show = ready and inViewport
                if show then
                    local height = math.abs(headPos.Y - bottomPos.Y)
                    local width = math.clamp(2350 / math.max(rootPos.Z, 1), 12, 400)
                    local color = Config.ESPUseTeamColour and player.TeamColor.Color or Config.ESPColour

                    if set.Box then
                        set.Box.Position = Vector2.new(rootPos.X - width / 2, rootPos.Y - height / 2)
                        set.Box.Size = Vector2.new(width, height)
                        set.Box.Thickness = Config.ESPThickness
                        set.Box.Transparency = Config.ESPOpacity
                        set.Box.Filled = Config.ESPBoxFilled
                        set.Box.Color = color
                        set.Box.Visible = Config.ESPBox
                    end

                    if set.Name then
                        set.Name.Text = player.Name
                        set.Name.Position = Vector2.new(rootPos.X, rootPos.Y - height / 2 - 14)
                        set.Name.Color = color
                        set.Name.Transparency = Config.ESPOpacity
                        set.Name.Visible = Config.NameESP
                    end

                    if set.Health then
                        set.Health.Text = ('%d/%d'):format(math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
                        set.Health.Position = Vector2.new(rootPos.X, rootPos.Y + height / 2 + 2)
                        set.Health.Color = color
                        set.Health.Transparency = Config.ESPOpacity
                        set.Health.Visible = Config.HealthESP
                    end

                    if set.Tracer then
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

local Window = Library:CreateWindow({
    Title = 'Pure Open Aimbot',
    Center = true,
    AutoShow = true,
    MenuFadeTime = 0.2,
})

local Tabs = {
    Aimbot = Window:AddTab('Aimbot'),
    Checks = Window:AddTab('Checks'),
    Visuals = Window:AddTab('Visuals'),
    Settings = Window:AddTab('Settings'),
}

local AimBox = Tabs.Aimbot:AddLeftGroupbox('Aimbot')
AimBox:AddToggle('OA_Aimbot', {
    Text = 'Aimbot',
    Default = Config.Aimbot,
    Callback = function(value)
        Config.Aimbot = value
        if not value then resetAimbot() end
    end,
})
AimBox:AddToggle('OA_OnePressAim', {
    Text = 'One-press aim',
    Default = Config.OnePressAimingMode,
    Callback = function(value) Config.OnePressAimingMode = value end,
})
AimBox:AddToggle('OA_OffAfterKill', {
    Text = 'Off after kill',
    Default = Config.OffAimbotAfterKill,
    Callback = function(value) Config.OffAimbotAfterKill = value end,
})
AimBox:AddDropdown('OA_AimMode', {
    Text = 'Aim mode',
    Values = getfenv().mousemoverel and { 'Camera', 'Mouse' } or { 'Camera' },
    Default = Config.AimMode,
    Callback = function(value) Config.AimMode = value end,
})
AimBox:AddDropdown('OA_AimPart', {
    Text = 'Aim part',
    Values = { 'Head', 'HumanoidRootPart', 'UpperTorso', 'Torso' },
    Default = Config.AimPart,
    Callback = function(value) Config.AimPart = value end,
})
AimBox:AddLabel('Aim key'):AddKeyPicker('OA_AimKey', {
    Default = Config.AimKey,
    Mode = 'Hold',
    Text = 'Aim key',
    NoUI = false,
    Callback = function(value)
        Aiming = Config.Aimbot and value or false
        if not Aiming then resetAimbot() end
    end,
})

local MovementBox = Tabs.Aimbot:AddRightGroupbox('Motion')
MovementBox:AddToggle('OA_UseSensitivity', {
    Text = 'Smooth camera',
    Default = Config.UseSensitivity,
    Callback = function(value) Config.UseSensitivity = value end,
})
MovementBox:AddSlider('OA_Sensitivity', {
    Text = 'Sensitivity',
    Default = Config.Sensitivity,
    Min = 9,
    Max = 99,
    Rounding = 0,
    Callback = function(value) Config.Sensitivity = value end,
})
MovementBox:AddToggle('OA_UseOffset', {
    Text = 'Use offset',
    Default = Config.UseOffset,
    Callback = function(value) Config.UseOffset = value end,
})
MovementBox:AddDropdown('OA_OffsetType', {
    Text = 'Offset type',
    Values = { 'Static', 'Dynamic', 'Both' },
    Default = Config.OffsetType,
    Callback = function(value) Config.OffsetType = value end,
})
MovementBox:AddSlider('OA_StaticOffset', {
    Text = 'Static offset',
    Default = Config.StaticOffsetIncrement,
    Min = -50,
    Max = 50,
    Rounding = 0,
    Callback = function(value) Config.StaticOffsetIncrement = value end,
})
MovementBox:AddSlider('OA_DynamicOffset', {
    Text = 'Dynamic offset',
    Default = Config.DynamicOffsetIncrement,
    Min = -50,
    Max = 50,
    Rounding = 0,
    Callback = function(value) Config.DynamicOffsetIncrement = value end,
})
MovementBox:AddToggle('OA_Noise', {
    Text = 'Camera noise',
    Default = Config.UseNoise,
    Callback = function(value) Config.UseNoise = value end,
})
MovementBox:AddSlider('OA_NoiseFrequency', {
    Text = 'Noise amount',
    Default = Config.NoiseFrequency,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(value) Config.NoiseFrequency = value end,
})

local TriggerBox = Tabs.Aimbot:AddRightGroupbox('Triggerbot')
TriggerBox:AddToggle('OA_TriggerBot', {
    Text = 'Triggerbot',
    Default = Config.TriggerBot,
    Callback = function(value)
        Config.TriggerBot = value
        if not value then Triggering = false end
    end,
})
TriggerBox:AddToggle('OA_SmartTrigger', {
    Text = 'Only while aiming',
    Default = Config.SmartTriggerBot,
    Callback = function(value) Config.SmartTriggerBot = value end,
})
TriggerBox:AddSlider('OA_TriggerChance', {
    Text = 'Click chance',
    Default = Config.TriggerBotChance,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Callback = function(value) Config.TriggerBotChance = value end,
})
TriggerBox:AddLabel('Trigger key'):AddKeyPicker('OA_TriggerKey', {
    Default = Config.TriggerKey,
    Mode = 'Toggle',
    Text = 'Triggerbot',
    NoUI = false,
    Callback = function(value) Triggering = Config.TriggerBot and value or false end,
})

local SimpleChecks = Tabs.Checks:AddLeftGroupbox('Simple checks')
SimpleChecks:AddToggle('OA_AliveCheck', { Text = 'Alive check', Default = Config.AliveCheck, Callback = function(value) Config.AliveCheck = value end })
SimpleChecks:AddToggle('OA_GodCheck', { Text = 'God check', Default = Config.GodCheck, Callback = function(value) Config.GodCheck = value end })
SimpleChecks:AddToggle('OA_TeamCheck', { Text = 'Team check', Default = Config.TeamCheck, Callback = function(value) Config.TeamCheck = value end })
SimpleChecks:AddToggle('OA_FriendCheck', { Text = 'Friend check', Default = Config.FriendCheck, Callback = function(value) Config.FriendCheck = value end })
SimpleChecks:AddToggle('OA_WallCheck', { Text = 'Wall check', Default = Config.WallCheck, Callback = function(value) Config.WallCheck = value end })
SimpleChecks:AddToggle('OA_WaterCheck', { Text = 'Ignore water', Default = Config.WaterCheck, Callback = function(value) Config.WaterCheck = value end })

local AdvancedChecks = Tabs.Checks:AddRightGroupbox('Advanced checks')
AdvancedChecks:AddToggle('OA_FovCheck', { Text = 'FOV check', Default = Config.FoVCheck, Callback = function(value) Config.FoVCheck = value end })
AdvancedChecks:AddSlider('OA_FovRadiusCheck', {
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
AdvancedChecks:AddToggle('OA_MagnitudeCheck', { Text = 'Magnitude check', Default = Config.MagnitudeCheck, Callback = function(value) Config.MagnitudeCheck = value end })
AdvancedChecks:AddSlider('OA_MaxMagnitude', {
    Text = 'Max distance',
    Default = Config.TriggerMagnitude,
    Min = 25,
    Max = 2000,
    Rounding = 0,
    Callback = function(value) Config.TriggerMagnitude = value end,
})
AdvancedChecks:AddToggle('OA_TransparencyCheck', { Text = 'Transparency check', Default = Config.TransparencyCheck, Callback = function(value) Config.TransparencyCheck = value end })
AdvancedChecks:AddSlider('OA_TransparencyLimit', {
    Text = 'Transparency limit',
    Default = Config.IgnoredTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(value) Config.IgnoredTransparency = value end,
})

local FovBox = Tabs.Visuals:AddLeftGroupbox('FOV')
FovBox:AddToggle('OA_FovVisible', {
    Text = 'Show FOV',
    Default = Config.FoV,
    Callback = function(value)
        Config.FoV = value
        setDrawingFovVisible(value)
    end,
})
FovBox:AddToggle('OA_FovFilled', {
    Text = 'Soft fill',
    Default = Config.FoVFilled,
    Callback = function(value)
        Config.FoVFilled = value
        FovCircle:Set('Filled', value)
    end,
})
FovBox:AddToggle('OA_FovGlow', {
    Text = 'Glow',
    Default = Config.FoVGlow,
    Callback = function(value)
        Config.FoVGlow = value
        FovCircle:Set('Glow', value)
    end,
})
FovBox:AddSlider('OA_FovThickness', {
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
FovBox:AddSlider('OA_FovSmoothing', {
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
FovBox:AddLabel('Ring color'):AddColorPicker('OA_FovColor', {
    Default = Config.FoVColour,
    Title = 'FOV ring color',
    Callback = function(value)
        Config.FoVColour = value
        FovCircle:Set('Color', value)
    end,
})
FovBox:AddLabel('Accent color'):AddColorPicker('OA_FovAccent', {
    Default = Config.FoVAccent,
    Title = 'FOV accent color',
    Callback = function(value)
        Config.FoVAccent = value
        FovCircle:Set('AccentColor', value)
    end,
})

local EspBox = Tabs.Visuals:AddRightGroupbox('ESP')
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

local SettingsBox = Tabs.Settings:AddLeftGroupbox('Menu')
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
ThemeManager:SetFolder('PureOpenAimbot')
SaveManager:SetFolder('PureOpenAimbot/' .. tostring(game.GameId))
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

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

    setDrawingFovVisible(Config.FoV)
    updateEsp()

    if Config.TriggerBot and Triggering and (not Config.SmartTriggerBot or Aiming) and getfenv().mouse1click and Mouse.Target then
        local model = Mouse.Target:FindFirstAncestorOfClass('Model')
        if model and select(1, resolveTarget(model)) and chance(Config.TriggerBotChance) then
            getfenv().mouse1click()
        end
    end

    if not Config.Aimbot then
        if Aiming then resetAimbot() end
        return
    end

    if not Aiming and Options.OA_AimKey then
        Aiming = Options.OA_AimKey:GetState()
    end

    if not Aiming then
        resetAimbot()
        return
    end

    if not select(1, resolveTarget(Target)) then
        if Target and Config.OffAimbotAfterKill then
            resetAimbot()
        else
            Target = acquireTarget()
        end
    end

    local ok, _, viewportPosition, inViewport, worldPosition = resolveTarget(Target)
    if ok then
        aimAt(worldPosition, viewportPosition, inViewport)
    else
        resetAimbot(true)
    end
end))

Library:OnUnload(function()
    resetAimbot()
    FovCircle:Destroy()
    clearEsp()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
end)

notify('loaded')
