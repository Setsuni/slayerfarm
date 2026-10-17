local mq = require('mq')
local data = require('slayerfarm.data')
local settings = require('slayerfarm.settings')

local achievements = {}

achievements.list = {}
achievements.groups = {}
achievements.error = nil
achievements.lastScan = 0

local subOrder = { Skill = 1, Special = 2, Conquest = 3, }
local dataByName = {}
local matchCache = {}
local pendingKills = {}
local lastRefresh = 0

local function normalize(name)
    return ((name or ""):lower():gsub("[^%w]", ""))
end

local zonesByRace = {}

local function addUnique(list, value)
    for _, existing in ipairs(list) do
        if existing == value then return end
    end
    table.insert(list, value)
end

for _, entry in ipairs(data.achievements) do
    dataByName[normalize(entry.name)] = entry
    if entry.races and #entry.races <= 4 then
        for _, race in ipairs(entry.races) do
            zonesByRace[race] = zonesByRace[race] or {}
            for _, zone in ipairs(entry.zones or {}) do addUnique(zonesByRace[race], zone) end
        end
    end
end

local function zonesFor(baseZones, parts, remaining)
    if #parts == 0 then return baseZones end
    local zones = {}
    for _, part in ipairs(remaining) do
        for _, zone in ipairs(part.zones) do addUnique(zones, zone) end
    end
    return zones
end

local function findSlayerCategory()
    local manager = mq.TLO.Achievement
    for i = 1, (manager.CategoryCount() or 0) do
        local category = manager.CategoryByIndex(i)
        if category.Name() == "Slayer" then return category end
        for j = 1, (category.CategoryCount() or 0) do
            local subCategory = category.CategoryByIndex(j)
            if subCategory.Name() == "Slayer" then return subCategory end
        end
    end
    return nil
end

local function singular(text)
    local word = text:lower()
    if word:find("ves$") then return (word:gsub("ves$", "f")) end
    if word:find("men$") then return (word:gsub("men$", "man")) end
    if word:find("ies$") then return (word:gsub("ies$", "y")) end
    return (word:gsub("s$", ""))
end

local function readProgress(achievement)
    local count, required = 0, 0
    local parts, remaining = {}, {}
    local objectiveCount = achievement.ObjectiveCount() or 0
    for i = 1, objectiveCount do
        local objective = achievement.ObjectiveByIndex(i)
        local need = math.max(objective.RequiredCount() or 0, 1)
        local have = objective.Completed() and need or math.min(objective.Count() or 0, need)
        count = count + have
        required = required + need
        if objectiveCount > 1 then
            local description = objective.Description() or "?"
            local race = singular(description)
            local part = { description = description, race = race, zones = zonesByRace[race] or {}, have = have, need = need, done = have >= need, }
            table.insert(parts, part)
            if not part.done then table.insert(remaining, part) end
        end
    end
    return count, required, remaining, parts
end

local function remainingRaces(remaining)
    local races = {}
    for _, part in ipairs(remaining) do table.insert(races, part.race) end
    return races
end

local function makeEntry(achievement, subName)
    local entry = dataByName[normalize(achievement.Name())]
    local count, required, remaining, parts = readProgress(achievement)
    return {
        parts = parts,
        remaining = remaining,
        remainingRaces = remainingRaces(remaining),
        id = achievement.ID(),
        name = achievement.Name(),
        sub = subName,
        completed = achievement.Completed() == true,
        count = count,
        required = required,
        races = entry and entry.races or {},
        bodies = entry and entry.bodies or {},
        baseZones = entry and entry.zones or {},
        zones = zonesFor(entry and entry.zones or {}, parts, remaining),
        open = entry and entry.open or nil,
        manual = entry and entry.manual or nil,
        huntable = entry ~= nil and entry.hunt ~= false,
        known = entry ~= nil,
    }
end

local firstSlayerId, lastSlayerId = 11000000, 11000400

local function inSlayerBlock(id)
    return id ~= nil and id >= firstSlayerId and id <= lastSlayerId
end

local function findSub(id, name, subCategories, subById)
    if subById[id] then return subById[id] end
    local found = nil
    for _, subCategory in ipairs(subCategories) do
        if subCategory.Achievement(id).ID() == id then
            if found then
                found = nil
                break
            end
            found = subCategory.Name()
        end
    end
    if found then return found end
    local entry = dataByName[normalize(name)]
    return entry and entry.sub or nil
end

local function collectChildren(achievement, optionalNames, parentOf, parents)
    for i = 1, (achievement.ObjectiveCount() or 0) do
        local description = achievement.ObjectiveByIndex(i).Description() or ""
        local childName = description:match('achievement%s+"(.-)"')
        if childName then
            local key = normalize((childName:gsub("^Achievement:%s*", "")))
            if description:find("^%(Optional%)") then optionalNames[key] = true end
            parentOf[key] = achievement.Name()
            parents[achievement.Name()] = { name = achievement.Name(), completed = achievement.Completed() == true, }
        end
    end
end

local function scanSlayerBlock(subCategories)
    local optionalNames, parentOf, parents = {}, {}, {}
    local subById = {}
    for _, subCategory in ipairs(subCategories) do
        for j = 1, (subCategory.AchievementCount() or 0) do
            local id = subCategory.AchievementByIndex(j).ID()
            if inSlayerBlock(id) then subById[id] = subCategory.Name() end
        end
    end
    local list = {}
    for id = firstSlayerId, lastSlayerId do
        local achievement = mq.TLO.Achievement(id)
        local name = achievement.Name()
        if name and achievement.ID() == id then
            collectChildren(achievement, optionalNames, parentOf, parents)
            if achievement.State() ~= "HIDDEN" then
                local subName = findSub(id, name, subCategories, subById)
                if subOrder[subName or ""] then table.insert(list, makeEntry(achievement, subName)) end
            end
        end
    end
    local groups, seen = {}, {}
    for _, entry in ipairs(list) do
        local key = normalize(entry.name)
        entry.optional = optionalNames[key] == true
        entry.group = parentOf[key] or entry.sub
        if not seen[entry.group] then
            seen[entry.group] = true
            local parent = parents[entry.group]
            table.insert(groups, { name = entry.group, sub = entry.sub, completed = parent and parent.completed or false, isParent = parent ~= nil, })
        end
    end
    table.sort(groups, function(a, b)
        if a.sub ~= b.sub then return subOrder[a.sub] < subOrder[b.sub] end
        return a.name < b.name
    end)
    return list, groups
end

function achievements.scan()
    achievements.error = nil
    if not mq.TLO.Achievement.Ready() then
        achievements.error = "Achievement data is not loaded yet, try again in a moment."
        return
    end
    local slayer = findSlayerCategory()
    if not slayer then
        achievements.error = "Could not find the Slayer achievement category."
        return
    end

    local subCategories = {}
    for i = 1, (slayer.CategoryCount() or 0) do
        local subCategory = slayer.CategoryByIndex(i)
        if subOrder[subCategory.Name() or ""] then table.insert(subCategories, subCategory) end
    end

    local list, groups = scanSlayerBlock(subCategories)
    achievements.groups = groups
    table.sort(list, function(a, b)
        if a.sub ~= b.sub then return subOrder[a.sub] < subOrder[b.sub] end
        if a.optional ~= b.optional then return b.optional end
        return a.name < b.name
    end)
    if #list == 0 then
        achievements.error = "Found the Slayer category but could not read any achievements in it."
    end
    achievements.list = list
    achievements.lastScan = mq.gettime()
    matchCache = {}
end

local function dumpCategory(file, category, depth)
    local indent = string.rep("    ", depth)
    file:write(string.format("%s[%s] id=%s achievements=%s children=%s\n", indent, tostring(category.Name()), tostring(category.ID()),
        tostring(category.AchievementCount()), tostring(category.CategoryCount())))
    for j = 1, (category.AchievementCount() or 0) do
        local achievement = category.AchievementByIndex(j)
        file:write(string.format("%s    %d: id=%s index=%s state=%s name=%s\n", indent, j, tostring(achievement.ID()), tostring(achievement.Index()),
            tostring(achievement.State()), tostring(achievement.Name())))
    end
    for i = 1, (category.CategoryCount() or 0) do
        dumpCategory(file, category.CategoryByIndex(i), depth + 1)
    end
end

function achievements.dump()
    local slayer = findSlayerCategory()
    if not slayer then
        print("\ag[Slayer Farm]\ax Could not find the Slayer category to dump.")
        return
    end
    local path = string.format('%s/slayerfarm_dump.txt', mq.configDir)
    local file = io.open(path, "w")
    if not file then return end
    dumpCategory(file, slayer, 0)
    local people = mq.TLO.Achievement(11000028)
    file:write(string.format("\nLookup by ID 11000028: name=%s index=%s\n", tostring(people.Name()), tostring(people.Index())))
    file:write(string.format("\nExpansionFlags=%s\n", tostring(mq.TLO.Me.ExpansionFlags())))
    for number = 0, 35 do
        file:write(string.format("HaveExpansion(%d)=%s\n", number, tostring(mq.TLO.Me.HaveExpansion(number)())))
    end
    file:close()
    printf("\ag[Slayer Farm]\ax Wrote %s", path)
end

function achievements.isFarmed(entry)
    if entry.optional then return settings.values.included[entry.id] == true end
    return not settings.values.skipped[entry.id]
end

function achievements.isTargeted(entry)
    return not entry.completed and entry.huntable and achievements.isFarmed(entry)
end

function achievements.targeted()
    local result = {}
    for _, entry in ipairs(achievements.list) do
        if achievements.isTargeted(entry) then table.insert(result, entry) end
    end
    return result
end

function achievements.setFarmed(entry, farmed)
    if entry.optional then
        settings.values.included[entry.id] = farmed or nil
    else
        settings.values.skipped[entry.id] = (not farmed) or nil
    end
    settings.save()
    matchCache = {}
end

local function wordMatch(text, word)
    local padded = " " .. text .. " "
    return padded:find(" " .. word .. " ", 1, true) ~= nil
        or padded:find(" " .. word .. "s ", 1, true) ~= nil
        or padded:find(" " .. word .. "es ", 1, true) ~= nil
end

local function cleanText(text)
    return ((text or ""):lower():gsub("[^%w']", " "))
end

function achievements.entryMatches(entry, raceName, bodyName)
    if #entry.remainingRaces > 0 then
        local race = cleanText(raceName)
        for _, word in ipairs(entry.remainingRaces) do
            if wordMatch(race, word) then return true end
        end
        return false
    end
    local learned = settings.learned[raceName:lower()]
    if learned and (learned[entry.id] or 0) >= 2 then return true end
    local race = cleanText(raceName)
    for _, word in ipairs(entry.races) do
        if wordMatch(race, word) then return true end
    end
    local body = cleanText(bodyName)
    for _, word in ipairs(entry.bodies) do
        if wordMatch(body, word) then return true end
    end
    return false
end

function achievements.wantsRace(raceName, bodyName)
    local key = (raceName or "") .. "|" .. (bodyName or "")
    if matchCache[key] == nil then
        matchCache[key] = false
        for _, entry in ipairs(achievements.list) do
            if achievements.isTargeted(entry) and achievements.entryMatches(entry, raceName or "", bodyName or "") then
                matchCache[key] = true
                break
            end
        end
    end
    return matchCache[key]
end

function achievements.zoneAllowed(shortName)
    local zone = data.zones[shortName]
    if not zone then return false end
    local maxExpansion = settings.values.maxExpansion or achievements.detectedExpansion()
    return zone.expansion == nil or zone.expansion <= maxExpansion
end

local detected = nil

function achievements.detectedExpansion()
    if detected then return detected end
    detected = 0
    for number = 1, #data.expansions - 1 do
        if mq.TLO.Me.HaveExpansion(number)() then detected = number end
    end
    if detected >= 16 then detected = #data.expansions - 1 end
    return detected
end

function achievements.rankZones()
    local byZone = {}
    for _, entry in ipairs(achievements.targeted()) do
        for _, shortName in ipairs(entry.zones) do
            if achievements.zoneAllowed(shortName) then
                local zone = byZone[shortName]
                if not zone then
                    zone = { shortName = shortName, name = data.zones[shortName].name, covers = {}, skillCount = 0, }
                    byZone[shortName] = zone
                end
                table.insert(zone.covers, entry)
                if entry.sub == "Skill" then zone.skillCount = zone.skillCount + 1 end
            end
        end
    end
    local ranked = {}
    for _, zone in pairs(byZone) do table.insert(ranked, zone) end
    table.sort(ranked, function(a, b)
        if #a.covers ~= #b.covers then return #a.covers > #b.covers end
        if a.skillCount ~= b.skillCount then return a.skillCount > b.skillCount end
        return a.name < b.name
    end)
    return ranked
end

function achievements.markSession()
    for _, entry in ipairs(achievements.list) do entry.sessionStart = entry.count end
end

function achievements.sessionGain(entry)
    return entry.count - (entry.sessionStart or entry.count)
end

function achievements.recordKill(raceName, bodyName)
    table.insert(pendingKills, { race = (raceName or ""):lower(), body = bodyName, time = mq.gettime(), })
end

local function learnFrom(entry)
    local now = mq.gettime()
    local races = {}
    for _, kill in ipairs(pendingKills) do
        if now - kill.time < 4000 then races[kill.race] = true end
    end
    local onlyRace = nil
    for race in pairs(races) do
        if onlyRace then return end
        onlyRace = race
    end
    if not onlyRace or onlyRace == "" then return end
    settings.learned[onlyRace] = settings.learned[onlyRace] or {}
    local confirmations = (settings.learned[onlyRace][entry.id] or 0) + 1
    settings.learned[onlyRace][entry.id] = confirmations
    settings.saveLearned()
    if confirmations == 2 then
        matchCache = {}
        printf("\ag[Slayer Farm]\ax Learned: \ay%s\ax counts toward \at%s", onlyRace, entry.name)
    end
end

function achievements.refresh()
    local now = mq.gettime()
    if now - lastRefresh < 2000 then return end
    lastRefresh = now
    for _, entry in ipairs(achievements.list) do
        if not entry.completed and entry.huntable then
            local achievement = mq.TLO.Achievement(entry.id)
            if achievement() then
                local count, required, remaining, parts = readProgress(achievement)
                if count > entry.count then
                    learnFrom(entry)
                    entry.parts, entry.remaining, entry.remainingRaces = parts, remaining, remainingRaces(remaining)
                    entry.zones = zonesFor(entry.baseZones, parts, remaining)
                    matchCache = {}
                end
                entry.count, entry.required = count, required
                if achievement.Completed() then
                    entry.completed = true
                    matchCache = {}
                    printf("\ag[Slayer Farm]\ax Completed: \at%s", entry.name)
                end
            end
        end
    end
    for i = #pendingKills, 1, -1 do
        if now - pendingKills[i].time > 15000 then table.remove(pendingKills, i) end
    end
end

return achievements
