local mq = require('mq')
local achievements = require('slayerfarm.achievements')
local settings = require('slayerfarm.settings')

local hunter = {}

hunter.active = false
hunter.paused = false
hunter.status = "Idle"
hunter.targetId = 0
hunter.kills = 0
hunter.startTime = 0
hunter.candidates = 0

local center = nil
local drawnArea = nil
local lastAreaUpdate = 0
local zoneId = 0
local bans = {}
local engaged = false
local engagedSince = 0
local targetSince = 0
local targetRace, targetBody = nil, nil
local targetNeeded = false
local lastNeededCheck = 0
local nextScan = 0
local lastNav = 0
local navPos = nil
local lastFace = 0
local lastStuckCheck = 0
local lastPos = nil
local stuckCount = 0
local lastStrangerCheck = 0
local resting = false

local function zoneShortName()
    return (mq.TLO.Zone.ShortName() or ""):lower()
end

local function banSpawn(id, seconds)
    bans[id] = mq.gettime() + seconds * 1000
end

local function isBanned(id)
    local expires = bans[id]
    if not expires then return false end
    if mq.gettime() > expires then
        bans[id] = nil
        return false
    end
    return true
end

local function pathLength(id)
    if not mq.TLO.Navigation.PathExists('id ' .. id)() then return nil end
    return mq.TLO.Navigation.PathLength('id ' .. id)() or 0
end

local function isFriend(name)
    return name == mq.TLO.Me.CleanName() or mq.TLO.Group.Member(name)() ~= nil or mq.TLO.Raid.Member(name)() ~= nil
end

local function strangerNear(spawn)
    if not settings.values.avoidPlayers then return false end
    local search = string.format('pc loc %d %d radius %d', spawn.X() or 0, spawn.Y() or 0, settings.values.playerRadius)
    for i = 1, (mq.TLO.SpawnCount(search)() or 0) do
        local name = mq.TLO.NearestSpawn(i, search).CleanName()
        if name and not isFriend(name) then return true end
    end
    return false
end

local function haters()
    local result = {}
    for i = 1, (mq.TLO.Me.XTargetSlots() or 0) do
        local xtarget = mq.TLO.Me.XTarget(i)
        local id = xtarget.ID() or 0
        if id > 0 and xtarget.TargetType() == "Auto Hater" then table.insert(result, id) end
    end
    return result
end

local function isHater(id)
    for _, haterId in ipairs(haters()) do
        if haterId == id then return true end
    end
    return false
end

local function wanted(spawn)
    if spawn.Type() ~= "NPC" or not spawn.Targetable() or spawn.Dead() then return false end
    local id = spawn.ID() or 0
    if id == 0 or isBanned(id) or settings.isIgnored(zoneShortName(), spawn.CleanName() or "") then return false end
    local dx, dy = (spawn.X() or 0) - center.x, (spawn.Y() or 0) - center.y
    if dx * dx + dy * dy > settings.values.huntRadius ^ 2 then return false end
    if math.abs((spawn.Z() or 0) - center.z) > settings.values.zRange then return false end
    if settings.values.killAnything then return true end
    return achievements.wantsRace(spawn.Race.Name(), spawn.Body.Name())
end

local function isNeeded(spawn)
    return achievements.wantsRace(spawn.Race.Name(), spawn.Body.Name())
end

local function pickTarget(neededOnly)
    local candidates = {}
    for _, spawn in ipairs(mq.getFilteredSpawns(wanted)) do
        local needed = isNeeded(spawn)
        if needed or not neededOnly then
            table.insert(candidates, { id = spawn.ID(), distance = spawn.Distance3D() or 99999, spawn = spawn, needed = needed, })
        end
    end
    if not neededOnly then hunter.candidates = #candidates end
    table.sort(candidates, function(a, b)
        if a.needed ~= b.needed then return a.needed end
        return a.distance < b.distance
    end)
    local best = { [true] = {}, [false] = {}, }
    local checked = 0
    for _, candidate in ipairs(candidates) do
        if checked >= 6 then break end
        if strangerNear(candidate.spawn) then
            banSpawn(candidate.id, 60)
        else
            checked = checked + 1
            local length = pathLength(candidate.id)
            local group = best[candidate.needed]
            if not length then
                banSpawn(candidate.id, 120)
            elseif not group.length or length < group.length then
                group.id, group.length = candidate.id, length
            end
        end
    end
    return best[true].id or best[false].id
end

local function setTarget(id)
    local spawn = mq.TLO.Spawn(id)
    hunter.targetId = id
    targetRace, targetBody = spawn.Race.Name(), spawn.Body.Name()
    targetNeeded = isNeeded(spawn)
    targetSince = mq.gettime()
    engaged = false
    stuckCount = 0
    lastPos = nil
    navPos = nil
end

local function clearTarget()
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    if mq.TLO.Stick.Active() then mq.cmd('/squelch /stick off') end
    hunter.targetId = 0
    engaged = false
end

local function needsRest()
    local restHP, restMana = settings.values.restHP, settings.values.restMana
    local hpGoal, manaGoal = restHP, restMana
    if resting then hpGoal, manaGoal = math.min(restHP + 40, 95), math.min(restMana + 50, 90) end
    local me = mq.TLO.Me
    if (me.PctHPs() or 100) < hpGoal then return true end
    if me.Class.CanCast() and (me.MaxMana() or 0) > 0 and (me.PctMana() or 100) < manaGoal then return true end
    for i = 1, (mq.TLO.Group.Members() or 0) do
        local member = mq.TLO.Group.Member(i)
        if (member.ID() or 0) > 0 and not member.Dead() then
            if (member.PctHPs() or 100) < hpGoal then return true end
            if member.Class.CanCast() and (member.PctMana() or 100) < manaGoal then return true end
        end
    end
    return false
end

local function checkStuck()
    local now = mq.gettime()
    if now - lastStuckCheck < 2000 then return end
    lastStuckCheck = now
    local x, y = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
    if lastPos and mq.TLO.Navigation.Active() and math.abs(x - lastPos.x) + math.abs(y - lastPos.y) < 4 then
        stuckCount = stuckCount + 1
    else
        stuckCount = 0
    end
    lastPos = { x = x, y = y, }
    if stuckCount == 2 then
        mq.cmd('/squelch /doortarget')
    elseif stuckCount == 3 then
        mq.cmd('/squelch /click left door')
    elseif stuckCount == 4 then
        mq.cmd('/keypress jump')
    elseif stuckCount >= 6 then
        printf("\ag[Slayer Farm]\ax Stuck reaching \ay%s\ax, skipping it.", mq.TLO.Spawn(hunter.targetId).CleanName() or "mob")
        banSpawn(hunter.targetId, 300)
        clearTarget()
    end
end

local function navigateTo(spawn, distance)
    if mq.TLO.Me.Casting() and mq.TLO.Me.Class.ShortName() ~= "BRD" then return end
    local x, y = spawn.X() or 0, spawn.Y() or 0
    local moved = navPos and (math.abs(x - navPos.x) + math.abs(y - navPos.y)) > 15
    if not mq.TLO.Navigation.Active() or (moved and mq.gettime() - lastNav > 3000) then
        mq.cmdf('/squelch /nav id %d distance=%d log=off', hunter.targetId, distance)
        lastNav = mq.gettime()
        navPos = { x = x, y = y, }
    end
    checkStuck()
end

local function fight(spawn)
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    if mq.TLO.Target.ID() ~= hunter.targetId then mq.cmdf('/squelch /target id %d', hunter.targetId) end
    if settings.values.meleeAttack then
        if not mq.TLO.Stick.Active() then mq.cmdf('/squelch /stick id %d 80%% moveback uw', hunter.targetId) end
        if not mq.TLO.Me.Combat() then mq.cmd('/squelch /attack on') end
    elseif mq.gettime() - lastFace > 1500 then
        mq.cmd('/squelch /face fast nolook')
        lastFace = mq.gettime()
    end
    local pet = mq.TLO.Me.Pet
    if settings.values.usePet and (pet.ID() or 0) > 0 and pet.Target.ID() ~= hunter.targetId then mq.cmd('/squelch /pet attack') end
    if mq.gettime() - engagedSince > 30000 and (spawn.PctHPs() or 100) >= 100 then
        local name = spawn.CleanName() or ""
        printf("\ag[Slayer Farm]\ax \ay%s\ax isn't taking damage, added it to this zone's ignore list.", name)
        settings.setIgnored(zoneShortName(), name, true)
        mq.cmd('/squelch /attack off')
        clearTarget()
    end
end

local function manageTarget()
    local spawn = mq.TLO.Spawn(hunter.targetId)
    if not spawn() or spawn.Dead() or (spawn.ID() or 0) == 0 then
        if engaged then
            if targetNeeded then hunter.kills = hunter.kills + 1 end
            achievements.recordKill(targetRace, targetBody)
        end
        clearTarget()
        return
    end

    local hater = isHater(hunter.targetId)
    if not hater and not engaged and mq.gettime() - lastStrangerCheck > 2000 then
        lastStrangerCheck = mq.gettime()
        targetNeeded = isNeeded(spawn)
        if not targetNeeded and not settings.values.killAnything then
            printf("\ag[Slayer Farm]\ax \ay%s\ax no longer counts for anything you're farming, dropping it.", spawn.CleanName() or "mob")
            clearTarget()
            return
        end
        if strangerNear(spawn) then
            banSpawn(hunter.targetId, 60)
            clearTarget()
            return
        end
    end
    if not engaged and not hater and mq.gettime() - targetSince > 120000 then
        banSpawn(hunter.targetId, 300)
        clearTarget()
        return
    end

    local approach = settings.values.approachDistance
    local distance = spawn.Distance3D() or 0
    local engageRange = approach + (engaged and 30 or 10)
    local inRange = distance <= engageRange and (distance <= 12 or spawn.LineOfSight())
    if inRange then
        if not engaged then
            engaged = true
            engagedSince = mq.gettime()
        end
        hunter.status = string.format("Fighting %s", spawn.CleanName() or "")
        fight(spawn)
    else
        if engaged and mq.TLO.Stick.Active() then mq.cmd('/squelch /stick off') end
        engaged = false
        if spawn.LineOfSight() and mq.TLO.Target.ID() ~= hunter.targetId then mq.cmdf('/squelch /target id %d', hunter.targetId) end
        hunter.status = string.format("Moving to %s (%d)", spawn.CleanName() or "", math.floor(distance))
        navigateTo(spawn, spawn.LineOfSight() and approach or 5)
    end
end

local function clearArea()
    if not drawnArea then return end
    mq.cmdf('/squelch /maploc remove %d %d', drawnArea.y, drawnArea.x)
    drawnArea = nil
end

local function drawArea()
    clearArea()
    if not settings.values.showArea or not center then return end
    local y, x = math.floor(center.y), math.floor(center.x)
    mq.cmdf('/squelch /maploc size 10 width 1 radius %d rcolor 255 140 0 %d %d', settings.values.huntRadius, y, x)
    drawnArea = { y = y, x = x, radius = settings.values.huntRadius, }
end

local function updateArea()
    if mq.gettime() - lastAreaUpdate < 1000 then return end
    lastAreaUpdate = mq.gettime()
    if not settings.values.showArea then return clearArea() end
    if not drawnArea or drawnArea.radius ~= settings.values.huntRadius then drawArea() end
end

function hunter.start()
    center = { x = mq.TLO.Me.X() or 0, y = mq.TLO.Me.Y() or 0, z = mq.TLO.Me.Z() or 0, }
    drawArea()
    zoneId = mq.TLO.Zone.ID() or 0
    bans = {}
    resting = false
    hunter.targetId = 0
    hunter.active = true
    hunter.paused = false
    hunter.status = "Starting"
    nextScan = 0
end

function hunter.stop(reason)
    if hunter.active then clearTarget() end
    clearArea()
    hunter.active = false
    hunter.paused = false
    hunter.status = reason or "Stopped"
end

function hunter.setPaused(paused)
    hunter.paused = paused
    if paused then
        clearTarget()
        hunter.status = "Paused"
    end
end

function hunter.ignoreTarget()
    local name = mq.TLO.Target.CleanName()
    if not name then return end
    settings.setIgnored(zoneShortName(), name, true)
    if mq.TLO.Target.ID() == hunter.targetId then clearTarget() end
    printf("\ag[Slayer Farm]\ax Ignoring \ay%s\ax in this zone. Remove it on the Farm tab.", name)
end

function hunter.resetStats()
    hunter.kills = 0
    hunter.startTime = mq.gettime()
end

function hunter.killsPerHour()
    local hours = (mq.gettime() - hunter.startTime) / 3600000
    if hours < 0.02 then return 0 end
    return math.floor(hunter.kills / hours)
end

function hunter.tick()
    if not hunter.active or hunter.paused then return end
    if mq.TLO.Me.Dead() or mq.TLO.Me.Hovering() then return hunter.stop("Died - hunt stopped") end
    if (mq.TLO.Zone.ID() or 0) ~= zoneId then return hunter.stop("Zoned - hunt stopped") end
    updateArea()

    if hunter.targetId > 0 then
        local hateList = haters()
        if not engaged and #hateList > 0 and not isHater(hunter.targetId) then
            clearTarget()
        elseif not engaged and not targetNeeded and #hateList == 0 and mq.gettime() - lastNeededCheck > 3000 then
            lastNeededCheck = mq.gettime()
            local neededId = pickTarget(true)
            if neededId then
                clearTarget()
                setTarget(neededId)
            end
            return manageTarget()
        else
            return manageTarget()
        end
    end

    local hateList = haters()
    if #hateList > 0 then
        table.sort(hateList, function(a, b) return (mq.TLO.Spawn(a).Distance3D() or 0) < (mq.TLO.Spawn(b).Distance3D() or 0) end)
        setTarget(hateList[1])
        resting = false
        return manageTarget()
    end

    if needsRest() then
        if not resting and mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
        resting = true
        hunter.status = string.format("Resting (HP %d%%)", mq.TLO.Me.PctHPs() or 0)
        return
    end
    resting = false

    if mq.gettime() < nextScan then return end
    local id = pickTarget()
    if id then
        setTarget(id)
        nextScan = mq.gettime() + 1000
        return manageTarget()
    end
    hunter.status = hunter.candidates > 0 and "No reachable mobs right now, waiting" or "No needed mobs in range, waiting"
    nextScan = mq.gettime() + 3000
end

return hunter
