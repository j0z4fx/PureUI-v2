-- Bundle generator. Run with Lua to produce Bundled.lua, a single self-
-- contained script: the library + addons + example inlined, no loadstring/HTTP.
--
-- Usage: lua bundle.lua
-- Output: Bundled.lua

local function read(path)
    local f = io.open(path, 'r')
    if not f then error('cannot read ' .. path) end
    local content = f:read('*a')
    f:close()
    return content
end

-- Escape backslash and backtick so each source can live inside a [[ ... ]] long
-- bracket without breaking out. (Sources use [=[ ]=]-style brackets internally,
-- so a level-0 [[ ]] is safe as long as we neutralise literal backticks, which
-- don't appear in Lua source anyway -- belt and braces.)
local function blob(src)
    return '[====[\n' .. src .. '\n]====]'
end

local library_src    = read('Library.lua')
local theme_src      = read('addons/ThemeManager.lua')
local save_src       = read('addons/SaveManager.lua')
local example_src    = read('Example.lua')

-- Strip the example's HTTP/loadstring loader (lines 1-9) since we provide the
-- locals ourselves. We grab everything from `local Window = Library:CreateWindow`
-- onward.
local _, start = example_src:find('local Window = Library:CreateWindow')
local example_body = start and example_src:sub(start) or example_src

local out = {}
table.insert(out, '-- Auto-generated bundle of Library.lua + addons + Example.lua')
table.insert(out, '-- Paste this whole script into your executor. No loadstring/HTTP needed.')
table.insert(out, '-- Regenerate with: lua bundle.lua')
table.insert(out, '')
table.insert(out, '-- Each module source is kept verbatim and run through loadstring so its')
table.insert(out, '-- returned local (Library / ThemeManager / SaveManager) is captured,')
table.insert(out, '-- exactly mirroring how the example expects to receive them.')
table.insert(out, '')
table.insert(out, 'local Library = loadstring(' .. blob(library_src) .. ')()')
table.insert(out, 'local ThemeManager = loadstring(' .. blob(theme_src) .. ')()')
table.insert(out, 'local SaveManager = loadstring(' .. blob(save_src) .. ')()')
table.insert(out, '')
table.insert(out, '-- Example script body (loader stripped, locals provided above):')
table.insert(out, example_body)

local f = io.open('Bundled.lua', 'w')
f:write(table.concat(out, '\n'))
f:close()
print('Wrote Bundled.lua (' .. #table.concat(out, '\n') .. ' bytes)')
