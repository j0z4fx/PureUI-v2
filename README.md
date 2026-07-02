# LinoriaLib
A Roblox UI library inspired by Splix, BBot and many others.

Used in the Linoria script hub: https://kyaru.cloud

###### Example Script: 
* [Example](Example.lua)

###### Interface Addons:
* [Theme Manager](addons/ThemeManager.lua)&nbsp;&nbsp;|&nbsp;&nbsp;[Save Manager](addons/SaveManager.lua) 

## Features
- Tabs, group boxes, and tab boxes
- Almost any UI element you would ever need (toggles, sliders, dropdowns, etc)
- Interface automatically becomes scrollable whenever there are too many UI elements
- Dependency boxes, allowing you to easily hide/show UI elements depending on the state of other UI elements
- Separate target info and player list windows for player-focused scripts

## Extra Windows

### Target Info

```lua
local TargetInfo = Library:CreateTargetInfo({
    Player = game:GetService('Players').LocalPlayer,
    shieldBar = true, -- set false to hide the armor bar
})

TargetInfo:SetPlayer(game:GetService('Players').LocalPlayer)
TargetInfo:SetHealth(75, 100)
TargetInfo:SetArmor(50)
```

### Player List

```lua
local PlayerList = Library:CreatePlayerList({
    Title = 'Players',
})

PlayerList:AddButton({
    Text = 'Teleport',
    Func = function(Player)
        print('Teleport action for', Player and Player.Name)
    end,
})

PlayerList:AddToggle('SpectatePlayer', {
    Text = 'Spectate',
    Default = false,
    Callback = function(Value, Player)
        print('Spectate:', Value, Player and Player.Name)
    end,
})

PlayerList:AddDropdown('Disposition', {
    Values = { 'Whitelist', 'Enemy', 'Sentry', 'Sentry (Passive)' },
    Default = 'Whitelist',
    Callback = function(Value, Player)
        print('Disposition:', Value, Player and Player.Name)
    end,
})
```

The player list window is separate from the main menu. The top section shows players with profile pictures, keeps the local player pinned to the top, and includes search by display name or username. Prefix the search with `@` to search usernames only. The bottom third is reserved for compact action controls. Action callbacks receive the selected player.

Player action toggles and dropdowns store values per target. If you set one player to `Enemy`, selecting another player will show that player's own saved value or the control default.

### Command Modal

```lua
local CommandModal = Library:CreateCommandModal({
    Title = 'Fruits',
    Placeholder = 'Search fruits...',
    Items = { 'Apple', 'Banana', 'Cherry', 'Mango', 'Watermelon' },
    Callback = function(Value)
        print('Selected command:', Value)
    end,
})
```

Press `Ctrl+K` to open the command modal. Type to filter suggestions, use the arrow keys to move selection, press `Enter` to select, and press `Tab` to autocomplete the top result. Arrow navigation auto-scrolls the suggestion list, and a half-typed command is restored for 20 seconds after closing the modal.

### Infinite Yield Wrapper

```lua
local CommandModal = Library:CreateInfiniteYieldCommandModal({
    Title = 'Infinite Yield',
    Placeholder = 'Run command...',
    Source = repo .. 'InfiniteYield.lua',
})
```

The wrapper loads the repo-owned `InfiniteYield.lua` fork, hides its default command menu, feeds IY commands into the Pure command modal, and executes selected or typed commands through IY's `execCmd`. IY utility windows and later external tool UIs are restyled with the Pure theme where possible.

## Interface Preview
<img src="https://i.imgur.com/qs0Hqc6.png" />

## Contributors
- Inori: Main developer.
- Wally: Cleaning up verbose code, extending library functionality.
- Stefanuk: Extending library functionality.
- matas3535: Creator of Splix.
