local mq = require('mq')
local data = require('slayerfarm.data')
local achievements = require('slayerfarm.achievements')
local hunter = require('slayerfarm.hunter')
local opener = require('slayerfarm.opener')
local settings = require('slayerfarm.settings')

local farm = {}

farm.state = "idle"
farm.status = "Idle"
farm.zone = nil
farm.mode = "hunt"
farm.log = {}

local stateSince = 0
local pendingRequest = nil
local skippedZones = {}
local travelAttempts = 0
local lastMoving = 0
local lastZoneCheck = 0
local regroupSent = false

local function zoneName(shortName)
    local zone = data.zones[shortName or ""]
    return zone and zone.name or (shortName or "?")
end

local function log(text)
    table.insert(farm.log, 1, string.format("%s  %s", os.date("%H:%M:%S"), text))
    if #farm.log > 50 then table.remove(farm.log) end
    printf("\ag[Slayer Farm]\ax %s", text)
end

local function setState(state, status)
    farm.state = state
    farm.status = status
    stateSince = mq.gettime()
end

local function groupCommand(command)
    if not settings.values.travelGroup or (mq.TLO.Group.Members() or 0) == 0 then return end
    if not mq.TLO.Plugin('mq2dannet').IsLoaded() then return end
    mq.cmdf('/squelch /dgge %s', command)
end

local function groupTravel()
    return settings.values.travelGroup and (mq.TLO.Group.Members() or 0) > 0
end

local function currentZone()
    return (mq.TLO.Zone.ShortName() or ""):lower()
end

local function zoneComplete(shortName)
    for _, entry in ipairs(achievements.targeted()) do
        for _, zone in ipairs(entry.zones) do
            if zone == shortName then return false end
        end
    end
    return true
end

local function chooseZone()
    if not settings.values.autoZone then return settings.values.manualZone end
    for _, zone in ipairs(achievements.rankZones()) do
        if not skippedZones[zone.shortName] then return zone.shortName end
    end
    return nil
end

local function openTarget(shortName)
    for _, entry in ipairs(achievements.targeted()) do
        if entry.open then
            for _, zone in ipairs(entry.zones) do
                if zone == shortName then return entry end
            end
        end
    end
    return nil
end

local function startWork()
    local openEntry = openTarget(farm.zone)
    if openEntry then
        farm.mode = "open"
        opener.start(openEntry.open)
        log(string.format("Opening %s in %s for %s", openEntry.open, zoneName(farm.zone), openEntry.name))
        return setState("hunt", "Opening in " .. zoneName(farm.zone))
    end
    farm.mode = "hunt"
    hunter.start()
    log("Hunting in " .. zoneName(farm.zone))
    setState("hunt", "Hunting in " .. zoneName(farm.zone))
end

local function beginHunt()
    mq.cmd('/squelch /boxr manual')
    mq.cmd('/squelch /boxr unpause')
    if settings.values.followMode == "chase" then
        groupCommand('/boxr chase')
        groupCommand('/boxr unpause')
    end
    startWork()
end

local function beginGather()
    regroupSent = false
    setState("gather", "Waiting for group in " .. zoneName(farm.zone))
end

local function beginTravel(shortName)
    farm.zone = shortName
    if not shortName then
        log("Nothing left to farm with the current filters.")
        return setState("idle", "Nothing left to farm")
    end
    if currentZone() == shortName then return beginGather() end
    log("Traveling to " .. zoneName(shortName))
    groupCommand('/boxr manual')
    if groupTravel() then
        mq.cmdf('/travelto group %s', shortName)
    else
        mq.cmdf('/travelto %s', shortName)
    end
    travelAttempts = 1
    lastMoving = mq.gettime()
    setState("travel", "Traveling to " .. zoneName(shortName))
end

local function stopAll(reason)
    hunter.stop(reason)
    opener.stop(reason)
    if farm.state == "travel" then
        mq.cmd('/squelch /travelto stop')
        if groupTravel() then mq.cmd('/squelch /travelto group stop') end
    end
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    setState("idle", reason)
end

local function tickTravel()
    if currentZone() == farm.zone then return beginGather() end
    local now = mq.gettime()
    local easyFind = mq.TLO.EasyFind
    if (easyFind and easyFind.Active()) or mq.TLO.Navigation.Active() or mq.TLO.Me.Zoning() then lastMoving = now end
    if now - lastMoving > (travelAttempts == 1 and 10000 or 30000) then
        if travelAttempts >= 3 then
            log("Travel to " .. zoneName(farm.zone) .. " failed. Is the zone available to you?")
            return stopAll("Travel failed")
        end
        travelAttempts = travelAttempts + 1
        lastMoving = now
        mq.cmdf('/travelto %s', farm.zone)
    end
    if now - stateSince > 1200000 then
        log("Travel to " .. zoneName(farm.zone) .. " took over 20 minutes, stopping.")
        stopAll("Travel timed out")
    end
end

local function groupHere()
    for i = 1, (mq.TLO.Group.Members() or 0) do
        local member = mq.TLO.Group.Member(i)
        if (member.ID() or 0) == 0 or (member.Distance3D() or 9999) > 150 then return false end
    end
    return true
end

local function groupMissing()
    for i = 1, (mq.TLO.Group.Members() or 0) do
        if (mq.TLO.Group.Member(i).ID() or 0) == 0 then return true end
    end
    return false
end

local function tickGather()
    if not settings.values.travelGroup or groupHere() or mq.gettime() - stateSince > 120000 then return beginHunt() end
    if not regroupSent and mq.gettime() - stateSince > 60000 and groupMissing() then
        regroupSent = true
        log("Some of the group isn't here yet, sending travel again.")
        mq.cmdf('/travelto group %s', farm.zone)
    end
end

local function tickHunt()
    local worker = farm.mode == "open" and opener or hunter
    if not worker.active then
        log(worker.status)
        return setState("idle", worker.status)
    end
    local now = mq.gettime()
    if now - lastZoneCheck < 5000 then return end
    lastZoneCheck = now
    if farm.mode == "open" and not openTarget(farm.zone) then
        opener.stop("Done opening")
        log("Done opening in " .. zoneName(farm.zone) .. ".")
        if not zoneComplete(farm.zone) then return startWork() end
    end
    if zoneComplete(farm.zone) and (settings.values.autoZone or farm.mode == "open") then
        log("Everything in " .. zoneName(farm.zone) .. " is done.")
        hunter.stop("Zone complete")
        opener.stop("Zone complete")
        if settings.values.autoZone and settings.values.autoNextZone then return beginTravel(chooseZone()) end
        log("Press Start to go to the next zone.")
        setState("idle", "Zone complete - press Start for the next zone")
    end
end

local function setPaused(paused)
    hunter.setPaused(paused)
    opener.setPaused(paused)
end

local function handleRequest(request)
    if request == "start" and farm.state == "idle" then
        if #achievements.list == 0 then achievements.scan() end
        achievements.markSession()
        hunter.resetStats()
        skippedZones = {}
        beginTravel(chooseZone())
    elseif request == "stop" then
        stopAll("Stopped")
    elseif request == "pause" and farm.state == "hunt" then
        setPaused(true)
    elseif request == "resume" and farm.state == "hunt" then
        setPaused(false)
    elseif request == "next" and farm.state ~= "idle" then
        if farm.zone then skippedZones[farm.zone] = true end
        hunter.stop("Skipped zone")
        opener.stop("Skipped zone")
        beginTravel(chooseZone())
    end
end

function farm.isPaused()
    return hunter.paused or opener.paused
end

function farm.request(request)
    pendingRequest = request
end

function farm.onDeath()
    log("You died. Hunt stopped.")
    stopAll("Died")
end

function farm.zoneName(shortName)
    return zoneName(shortName)
end

function farm.tick()
    if pendingRequest then
        local request = pendingRequest
        pendingRequest = nil
        handleRequest(request)
    end
    if farm.state == "travel" then
        tickTravel()
    elseif farm.state == "gather" then
        tickGather()
    elseif farm.state == "hunt" then
        tickHunt()
    end
end

return farm
