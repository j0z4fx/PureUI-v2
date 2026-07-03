-- PureUI Open Aimbot adapter
-- Based on ttwizz/Open-Aimbot (MIT): https://github.com/ttwizz/Open-Aimbot
-- This keeps the core target/check/visual behavior and replaces the original Fluent UI with PureUI.

local repo = 'https://raw.githubusercontent.com/j0z4fx/PureUI-v2/0561766618d8aa4842f824200df59f64b1c601fb/'
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
    OffAimbotAfterKill = false,
    AimPart = 'HumanoidRootPart',
    AimParts = { Torso = true },

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
    WallCheck = false,
    ForceFieldCheck = true,
    KOCheck = true,
    HeldCheck = true,
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

local function getAimCandidates(character)
    local candidates = {}
    normalizeAimParts(Config.AimParts)

    for _, key in ipairs(AimPartOrder) do
        if Config.AimParts[key] then
            for _, partName in ipairs(AimPartMap[key] or { key }) do
                local part = getPart(character, partName)
                if part and part:IsA('BasePart') then
                    table.insert(candidates, part)
                    break
                end
            end
        end
    end

    if #candidates == 0 then
        local fallback = getOriginPart(character)
        if fallback then
            table.insert(candidates, fallback)
        end
    end

    return candidates
end

local function chooseAimPart(character)
    local candidates = getAimCandidates(character)
    local mousePosition = UserInputService:GetMouseLocation()
    local bestPart
    local bestDistance = math.huge

    for _, part in ipairs(candidates) do
        local viewportPosition, inViewport = Camera:WorldToViewportPoint(part.Position)
        local screenDistance = inViewport and (Vector2.new(viewportPosition.X, viewportPosition.Y) - mousePosition).Magnitude or math.huge

        if screenDistance < bestDistance then
            bestDistance = screenDistance
            bestPart = part
        end
    end

    return bestPart or candidates[1]
end

local function getBodyEffectActive(character, name)
    local effects = character and character:FindFirstChild('BodyEffects')
    local value = effects and effects:FindFirstChild(name)

    if not value then
        return false
    elseif value:IsA('BoolValue') then
        return value.Value == true
    elseif value:IsA('ObjectValue') then
        return value.Value ~= nil
    elseif value:IsA('StringValue') then
        return value.Value ~= ''
    elseif value:IsA('NumberValue') or value:IsA('IntValue') then
        return value.Value ~= 0
    end

    return false
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

    if Config.ForceFieldCheck and character:FindFirstChildOfClass('ForceField') then
        return false
    end

    if Config.KOCheck and getBodyEffectActive(character, 'K.O') then
        return false
    end

    if Config.HeldCheck and getBodyEffectActive(character, 'Grabbed') then
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
        local nativePart = getOriginPart(localCharacter())
        if nativePart and (targetPart.Position - nativePart.Position).Magnitude > Config.TriggerMagnitude then
            return false
        end
    end

    if Config.WallCheck then
        local nativePart = getOriginPart(localCharacter())
        if nativePart then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { localCharacter() }
            params.IgnoreWater = true

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
    local nativePart = getOriginPart(localChar)
    local targetPart = chooseAimPart(character)
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
                local ready = not Config.SmartESP or select(1, resolveTarget(character))
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

local Window = Library:CreateWindow({
    Title = 'Pure Open Aimbot',
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

local AimbotTabbox = Tabs.Aimbot:AddLeftTabbox('Open Aimbot')
local AimBox = AimbotTabbox:AddTab('Aim')
local MovementBox = AimbotTabbox:AddTab('Motion')
local ChecksBox = AimbotTabbox:AddTab('Checks')
local FovBox = AimbotTabbox:AddTab('FOV')
local TriggerBox = Tabs.Aimbot:AddRightGroupbox('Triggerbot')

local AimbotToggle = AimBox:AddToggle('OA_Aimbot', {
    Text = 'Aimbot',
    Default = Config.Aimbot,
    Callback = function(value)
        Config.Aimbot = value
        if not value then resetAimbot() end
    end,
})
AimbotToggle:AddKeyPicker('OA_AimKey', {
    Default = Config.AimKey,
    Mode = 'Hold',
    Text = 'Aimbot',
    NoUI = false,
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
AimBox:AddBodySelector('OA_AimParts', {
    Default = Config.AimParts,
    Height = 186,
    Callback = function(value)
        normalizeAimParts(value)
    end,
})

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

local TriggerToggle = TriggerBox:AddToggle('OA_TriggerBot', {
    Text = 'Triggerbot',
    Default = Config.TriggerBot,
    Callback = function(value)
        Config.TriggerBot = value
        if not value then Triggering = false end
        setTriggerFovVisible(Config.TriggerFoV)
    end,
})
TriggerToggle:AddKeyPicker('OA_TriggerKey', {
    Default = Config.TriggerKey,
    Mode = 'Toggle',
    Text = 'Triggerbot',
    NoUI = false,
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
TriggerBox:AddToggle('OA_TriggerFovCheck', {
    Text = 'FOV check',
    Default = Config.TriggerFoVCheck,
    Callback = function(value) Config.TriggerFoVCheck = value end,
})
TriggerBox:AddToggle('OA_TriggerFovVisible', {
    Text = 'Show FOV',
    Default = Config.TriggerFoV,
    Callback = function(value)
        Config.TriggerFoV = value
        setTriggerFovVisible(value)
    end,
})
TriggerBox:AddSlider('OA_TriggerFovRadius', {
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
TriggerBox:AddSlider('OA_TriggerFovThickness', {
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
TriggerBox:AddLabel('FOV color'):AddColorPicker('OA_TriggerFovColor', {
    Default = Config.TriggerFoVColour,
    Title = 'Trigger FOV color',
    Callback = function(value)
        Config.TriggerFoVColour = value
        TriggerFovCircle:Set('Color', value)
    end,
})
TriggerBox:AddLabel('FOV accent'):AddColorPicker('OA_TriggerFovAccent', {
    Default = Config.TriggerFoVAccent,
    Title = 'Trigger FOV accent',
    Callback = function(value)
        Config.TriggerFoVAccent = value
        TriggerFovCircle:Set('AccentColor', value)
    end,
})

ChecksBox:AddToggle('OA_AliveCheck', { Text = 'Alive check', Default = Config.AliveCheck, Callback = function(value) Config.AliveCheck = value end })
ChecksBox:AddToggle('OA_TeamCheck', { Text = 'Team check', Default = Config.TeamCheck, Callback = function(value) Config.TeamCheck = value end })
ChecksBox:AddToggle('OA_FriendCheck', { Text = 'Friend check', Default = Config.FriendCheck, Callback = function(value) Config.FriendCheck = value end })
ChecksBox:AddToggle('OA_WallCheck', { Text = 'Wall check', Default = Config.WallCheck, Callback = function(value) Config.WallCheck = value end })
ChecksBox:AddToggle('OA_ForceFieldCheck', { Text = 'ForceField check', Default = Config.ForceFieldCheck, Callback = function(value) Config.ForceFieldCheck = value end })
ChecksBox:AddToggle('OA_KOCheck', { Text = 'K.O. check', Default = Config.KOCheck, Callback = function(value) Config.KOCheck = value end })
ChecksBox:AddToggle('OA_HeldCheck', { Text = 'Held check', Default = Config.HeldCheck, Callback = function(value) Config.HeldCheck = value end })
ChecksBox:AddToggle('OA_FovCheck', { Text = 'FOV check', Default = Config.FoVCheck, Callback = function(value) Config.FoVCheck = value end })
ChecksBox:AddSlider('OA_FovRadiusCheck', {
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
ChecksBox:AddToggle('OA_MagnitudeCheck', { Text = 'Magnitude check', Default = Config.MagnitudeCheck, Callback = function(value) Config.MagnitudeCheck = value end })
ChecksBox:AddSlider('OA_MaxMagnitude', {
    Text = 'Max distance',
    Default = Config.TriggerMagnitude,
    Min = 25,
    Max = 2000,
    Rounding = 0,
    Callback = function(value) Config.TriggerMagnitude = value end,
})
ChecksBox:AddToggle('OA_TransparencyCheck', { Text = 'Transparency check', Default = Config.TransparencyCheck, Callback = function(value) Config.TransparencyCheck = value end })
ChecksBox:AddSlider('OA_TransparencyLimit', {
    Text = 'Transparency limit',
    Default = Config.IgnoredTransparency,
    Min = 0,
    Max = 1,
    Rounding = 2,
    Callback = function(value) Config.IgnoredTransparency = value end,
})

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
ThemeManager:SetFolder('PureOpenAimbot')
SaveManager:SetFolder('PureOpenAimbot/' .. tostring(game.GameId))
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

    setDrawingFovVisible(Config.FoV)
    setTriggerFovVisible(Config.TriggerFoV)
    updateEsp()

    local nextAiming = Config.Aimbot and Options.OA_AimKey and Options.OA_AimKey:GetState() or false
    if Aiming and not nextAiming then
        resetAimbot()
    end

    Aiming = nextAiming
    Triggering = Config.TriggerBot and Options.OA_TriggerKey and Options.OA_TriggerKey:GetState() or false

    if Config.TriggerBot and Triggering and (not Config.SmartTriggerBot or Aiming) and getfenv().mouse1click and Mouse.Target then
        local model = Mouse.Target:FindFirstAncestorOfClass('Model')
        local ok, _, viewportPosition = resolveTarget(model)
        if model and ok and targetInsideTriggerFov(viewportPosition) and chance(Config.TriggerBotChance) then
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

    updateTargetInfo()
end))

Library:OnUnload(function()
    resetAimbot()
    FovCircle:Destroy()
    TriggerFovCircle:Destroy()
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
