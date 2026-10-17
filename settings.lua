local mq = require('mq')

local settings = {}

local server = (mq.TLO.EverQuest.Server() or "unknown"):gsub("%s", "")
local characterFile = string.format('%s/slayerfarm_%s_%s.lua', mq.configDir, server, mq.TLO.Me.CleanName() or "unknown")
local learnedFile = string.format('%s/slayerfarm_learned.lua', mq.configDir)
local ignoresFile = string.format('%s/slayerfarm_ignores.lua', mq.configDir)

local defaults = {
    maxExpansion = nil,
    showCompleted = false,
    farmShowCompleted = true,
    skipped = {},
    included = {},
    autoZone = true,
    manualZone = nil,
    travelGroup = true,
    followMode = "chase",
    huntRadius = 2000,
    zRange = 500,
    approachDistance = 15,
    meleeAttack = true,
    usePet = true,
    restHP = 50,
    restMana = 20,
    avoidPlayers = true,
    playerRadius = 120,
    killAnything = false,
    showArea = true,
    finishTargetFirst = false,
    autoNextZone = false,
    restForGroup = false,
}

local function loadFile(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    local ok, result = pcall(chunk)
    if ok and type(result) == 'table' then return result end
    return nil
end

function settings.load()
    local saved = loadFile(characterFile) or {}
    for key, value in pairs(defaults) do
        if saved[key] == nil then saved[key] = value end
    end
    settings.values = saved
    settings.learned = loadFile(learnedFile) or {}
    settings.ignores = loadFile(ignoresFile) or {}
end

function settings.isIgnored(zone, name)
    local zoneIgnores = settings.ignores[zone]
    return zoneIgnores ~= nil and zoneIgnores[name] == true
end

function settings.setIgnored(zone, name, ignored)
    settings.ignores[zone] = settings.ignores[zone] or {}
    settings.ignores[zone][name] = ignored or nil
    mq.pickle(ignoresFile, settings.ignores)
end

function settings.ignoredIn(zone)
    local names = {}
    for name in pairs(settings.ignores[zone] or {}) do table.insert(names, name) end
    table.sort(names)
    return names
end

function settings.save()
    mq.pickle(characterFile, settings.values)
end

function settings.saveLearned()
    mq.pickle(learnedFile, settings.learned)
end

return settings
