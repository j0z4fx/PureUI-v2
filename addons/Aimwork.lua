-- Bundled PureUI runtime adapted from Stefanuk12/aimwork.
-- Source: https://github.com/Stefanuk12/aimwork

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local Workspace = game:GetService('Workspace')

local LocalPlayer = Players.LocalPlayer

local Aimwork = {}
Aimwork.__index = Aimwork

local defaultSelected = {
    player = LocalPlayer,
    character = nil,
    part = nil,
    position = Vector3.zero,
    distance = math.huge,
}

local function cloneMap(map)
    local copy = {}
    for key, value in pairs(map or {}) do
        copy[key] = value
    end
    return copy
end

local function merge(base, patch)
    local output = {}

    for key, value in pairs(base or {}) do
        if type(value) == 'table' then
            output[key] = merge(value, {})
        else
            output[key] = value
        end
    end

    for key, value in pairs(patch or {}) do
        if type(value) == 'table' and type(output[key]) == 'table' then
            output[key] = merge(output[key], value)
        else
            output[key] = value
        end
    end

    return output
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(connections)
end

local function bodyEffectActive(character, name)
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

Aimwork.DefaultConfiguration = {
    TargetLock = {
        Enabled = false,
        LockOnly = false,
        Mode = 'Lock',
        Bind = Enum.KeyCode.F1,
    },

    Checks = {
        ForceField = true,
        Friend = false,
        Dead = true,
        Invisible = false,
        TransparencyLimit = 1,
        Magnitude = false,
        MaxMagnitude = 500,
        Ignored = true,
        WallCheck = false,
        KO = true,
        Held = true,
    },

    PartFilter = {
        Type = 'Allowlist',
        Name = {
            HumanoidRootPart = true,
            Torso = true,
            UpperTorso = true,
            LowerTorso = true,
        },
    },

    Ignored = {
        IgnoreLocalTeam = false,
        AllowlistEnabledFor = {
            Teams = false,
            Players = false,
        },
        Teams = {},
        Players = {},
    },

    RaycastIgnore = function(playerObject, camera)
        local ignored = { camera }
        local localCharacter = LocalPlayer.Character

        if localCharacter then
            table.insert(ignored, localCharacter)
        end

        if playerObject and playerObject.character then
            table.insert(ignored, playerObject.character)
        end

        return ignored
    end,
}

local PlayerObject = {}
PlayerObject.__index = PlayerObject

function PlayerObject.new(player)
    local self = {
        instance = player,
        character = nil,
        bodyParts = {},
        health = 0,
        friend = false,
        forceField = false,
        connections = {},
    }

    setmetatable(self, PlayerObject)
    local friendOk, isFriend = pcall(function()
        return LocalPlayer:IsFriendsWith(player.UserId)
    end)
    self.friend = friendOk and isFriend == true or false
    self:bindCharacter(player.Character)

    table.insert(self.connections, player.CharacterAdded:Connect(function(character)
        self:bindCharacter(character)
    end))
    table.insert(self.connections, player.CharacterRemoving:Connect(function()
        self:clearCharacter()
    end))

    return self
end

function PlayerObject:clearCharacter()
    self.character = nil
    self.health = 0
    self.forceField = false
    table.clear(self.bodyParts)
end

function PlayerObject:bindCharacter(character)
    self:clearCharacter()
    if not character then
        return
    end

    self.character = character

    local function childAdded(child)
        if child:IsA('BasePart') then
            table.insert(self.bodyParts, child)
        elseif child:IsA('Humanoid') then
            self.health = child.Health
            table.insert(self.connections, child.HealthChanged:Connect(function(health)
                self.health = health
            end))
        elseif child:IsA('ForceField') then
            self.forceField = true
        end
    end

    local function childRemoved(child)
        if child:IsA('BasePart') then
            local index = table.find(self.bodyParts, child)
            if index then
                table.remove(self.bodyParts, index)
            end
        elseif child:IsA('Humanoid') then
            self.health = 0
        elseif child:IsA('ForceField') then
            self.forceField = false
        end
    end

    for _, child in ipairs(character:GetChildren()) do
        childAdded(child)
    end

    table.insert(self.connections, character.ChildAdded:Connect(childAdded))
    table.insert(self.connections, character.ChildRemoved:Connect(childRemoved))
end

function PlayerObject:Destroy()
    disconnectAll(self.connections)
    self:clearCharacter()
end

local function playerMatchesIgnoredEntry(player, entry)
    local entryType = typeof(entry)
    return (entryType == 'Instance' and player == entry)
        or (entryType == 'number' and player.UserId == entry)
        or (entryType == 'string' and (player.Name == entry or player.DisplayName == entry))
end

function Aimwork.new(settings)
    local self = {
        settings = merge(Aimwork.DefaultConfiguration, settings or {}),
        selected = merge(defaultSelected, {}),
        players = {},
        fovs = {},
        connections = {},
        _lockTarget = nil,
    }

    setmetatable(self, Aimwork)

    for _, player in ipairs(Players:GetPlayers()) do
        self:AddPlayer(player)
    end

    table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
        self:AddPlayer(player)
    end))
    table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
        self:RemovePlayer(player)
    end))
    table.insert(self.connections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        local lock = self.settings.TargetLock
        local bind = lock.Bind
        local pressed = typeof(bind) == 'EnumItem'
            and ((bind:IsA('KeyCode') and input.KeyCode == bind) or (bind:IsA('UserInputType') and input.UserInputType == bind))

        if lock.Enabled and pressed then
            if lock.Mode == 'Unlock' then
                self._lockTarget = nil
            else
                self:LockTarget()
            end
        end
    end))

    return self
end

function Aimwork:AddPlayer(player)
    if player == LocalPlayer or self:GetPlayerObject(player) then
        return
    end

    table.insert(self.players, PlayerObject.new(player))
end

function Aimwork:RemovePlayer(player)
    for index, playerObject in ipairs(self.players) do
        if playerObject.instance == player then
            playerObject:Destroy()
            table.remove(self.players, index)
            break
        end
    end
end

function Aimwork:GetPlayerObject(player)
    for index, playerObject in ipairs(self.players) do
        if playerObject.instance == player then
            return index, playerObject
        end
    end

    return nil, nil
end

function Aimwork:RegisterCustomFov(object, data)
    self.fovs[object] = data or {
        update = true,
        check = true,
    }

    return object
end

function Aimwork:ClearFovs()
    table.clear(self.fovs)
end

function Aimwork:SetPartFilter(names, filterType)
    self.settings.PartFilter.Type = filterType or 'Allowlist'
    self.settings.PartFilter.Name = cloneMap(names)
end

function Aimwork:LockTarget()
    local lockSettings = self.settings.TargetLock
    local wasLockOnly = lockSettings.LockOnly
    local isLockMode = lockSettings.Mode == 'Lock'

    if wasLockOnly or isLockMode then
        if wasLockOnly then
            lockSettings.LockOnly = false
        end

        if isLockMode then
            self._lockTarget = nil
        end

        self:Iterate()

        if wasLockOnly then
            lockSettings.LockOnly = true
        end
    else
        self:Iterate()
    end

    if self._lockTarget then
        return
    end

    if self.selected.player ~= LocalPlayer then
        local _, playerObject = self:GetPlayerObject(self.selected.player)
        self._lockTarget = playerObject
    end
end

function Aimwork:ResetSelected()
    for key, value in pairs(defaultSelected) do
        self.selected[key] = value
    end
end

function Aimwork:IgnoredPlayer(playerObject)
    local ignored = self.settings.Ignored
    local allowlist = ignored.AllowlistEnabledFor
    local player = playerObject.instance

    for _, entry in ipairs(ignored.Players or {}) do
        if playerMatchesIgnoredEntry(player, entry) then
            return not allowlist.Players
        end
    end

    return allowlist.Players == true
end

function Aimwork:IgnoredTeam(playerObject)
    local ignored = self.settings.Ignored
    local allowlist = ignored.AllowlistEnabledFor
    local team = playerObject.instance.Team

    if ignored.IgnoreLocalTeam and team ~= nil and team == LocalPlayer.Team then
        return true
    end

    for _, ignoredTeam in ipairs(ignored.Teams or {}) do
        if ignoredTeam == team then
            return not allowlist.Teams
        end
    end

    return false
end

function Aimwork:PlayerCheck(playerObject)
    local checks = self.settings.Checks
    local character = playerObject.character

    return not (
        (checks.ForceField and playerObject.forceField)
        or (checks.Friend and playerObject.friend)
        or (checks.Dead and playerObject.health <= 0)
        or (checks.Ignored and (self:IgnoredTeam(playerObject) or self:IgnoredPlayer(playerObject)))
        or (checks.KO and bodyEffectActive(character, 'K.O'))
        or (checks.Held and bodyEffectActive(character, 'Grabbed'))
    )
end

function Aimwork:PartAllowed(part)
    local partFilter = self.settings.PartFilter
    local listed = partFilter.Name[part.Name] == true

    if partFilter.Type == 'Allowlist' then
        return listed
    end

    return not listed
end

function Aimwork:WallHit(playerObject, part, camera)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    raycastParams.FilterDescendantsInstances = self.settings.RaycastIgnore(playerObject, camera)

    local origin = camera.CFrame.Position
    local direction = part.Position - origin
    local result = Workspace:Raycast(origin, direction, raycastParams)

    if not result then
        return false
    end

    return result.Instance ~= part and not playerObject.character:IsAncestorOf(result.Instance)
end

function Aimwork:PartCheck(playerObject, part)
    local checks = self.settings.Checks
    local camera = Workspace.CurrentCamera

    if not camera or not part:IsDescendantOf(Workspace) then
        return
    end

    if checks.Invisible and part.Transparency >= (checks.TransparencyLimit or 1) then
        return
    end

    if checks.Magnitude then
        local localCharacter = LocalPlayer.Character
        local localRoot = localCharacter and (localCharacter:FindFirstChild('HumanoidRootPart') or localCharacter:FindFirstChild('Torso') or localCharacter:FindFirstChild('Head'))

        if localRoot and (part.Position - localRoot.Position).Magnitude > (checks.MaxMagnitude or 500) then
            return
        end
    end

    local screenPosition, onScreen = camera:WorldToViewportPoint(part.Position)
    if checks.WallCheck and not onScreen then
        return
    end

    if checks.WallCheck == 'Full' and self:WallHit(playerObject, part, camera) then
        return
    end

    local screen2D = Vector2.new(screenPosition.X, screenPosition.Y)
    local bestDistance = math.huge

    if not next(self.fovs) then
        bestDistance = (UserInputService:GetMouseLocation() - screen2D).Magnitude
    else
        for fovObject, data in pairs(self.fovs) do
            if data.check ~= false then
                local inside, distance = fovObject:InsideFOV(screen2D)
                if inside and distance and distance < bestDistance then
                    bestDistance = distance
                end
            end
        end
    end

    if bestDistance < self.selected.distance then
        self.selected.player = playerObject.instance
        self.selected.character = playerObject.character
        self.selected.part = part
        self.selected.position = screenPosition
        self.selected.distance = bestDistance
    end
end

function Aimwork:IteratePlayer(playerObject)
    if not playerObject.character or not self:PlayerCheck(playerObject) then
        return
    end

    for _, part in ipairs(playerObject.bodyParts) do
        if self:PartAllowed(part) then
            self:PartCheck(playerObject, part)
        end
    end
end

function Aimwork:Iterate()
    self:ResetSelected()

    for fovObject, data in pairs(self.fovs) do
        if data.update ~= false and type(fovObject.Update) == 'function' then
            fovObject:Update(self.selected)
        end
    end

    if self.settings.TargetLock.Enabled and self._lockTarget then
        self:IteratePlayer(self._lockTarget)
        return self.selected
    elseif self.settings.TargetLock.LockOnly then
        return self.selected
    end

    for _, playerObject in ipairs(self.players) do
        self:IteratePlayer(playerObject)
    end

    return self.selected
end

function Aimwork:Destroy()
    disconnectAll(self.connections)

    for _, playerObject in ipairs(self.players) do
        playerObject:Destroy()
    end

    for fovObject in pairs(self.fovs) do
        if type(fovObject.Destroy) == 'function' then
            pcall(function()
                fovObject:Destroy()
            end)
        end
    end

    table.clear(self.players)
    table.clear(self.fovs)
end

return Aimwork
