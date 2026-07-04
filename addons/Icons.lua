-- PureUI adapter for Footagesus/Icons.
-- Source: https://github.com/Footagesus/Icons

local repo = getgenv().PureUIRepo or 'https://raw.githubusercontent.com/j0z4fx/PureUI-v2/main/'
if repo:sub(-1) ~= '/' then
    repo = repo .. '/'
end

local Icons = {
    IconsType = 'lucide',
    Packs = {
        lucide = loadstring(game:HttpGet(repo .. 'addons/IconsData.lua'))(),
    },
}

local function parseIcon(icon)
    if type(icon) ~= 'string' then
        return Icons.IconsType, icon
    end

    local separator = icon:find(':', 1, true)
    if separator then
        return icon:sub(1, separator - 1), icon:sub(separator + 1)
    end

    return Icons.IconsType, icon
end

function Icons.SetIconsType(iconType)
    if type(iconType) == 'string' then
        Icons.IconsType = iconType
    end
end

function Icons.AddIcons(packName, iconsData)
    if type(packName) == 'string' and type(iconsData) == 'table' then
        Icons.Packs[packName] = iconsData
    end
end

function Icons.GetIcon(icon, iconType)
    local parsedType, parsedName = parseIcon(icon)
    local pack = Icons.Packs[iconType or parsedType]

    if type(pack) ~= 'table' then
        return nil
    end

    return pack[parsedName]
end

return Icons
