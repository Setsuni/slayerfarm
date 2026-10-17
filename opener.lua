local mq = require('mq')

local opener = {}

opener.active = false
opener.paused = false
opener.status = "Idle"
opener.attempts = 0
opener.objectName = nil

local zoneId = 0
local lastOpen = 0
local lastNav = 0
local lastTarget = 0
local currentId = 0

local function inCombat()
    if mq.TLO.Me.Combat() then return true end
    for i = 1, (mq.TLO.Me.XTargetSlots() or 0) do
        local xtarget = mq.TLO.Me.XTarget(i)
        if (xtarget.ID() or 0) > 0 and xtarget.TargetType() == "Auto Hater" then return true end
    end
    return false
end

function opener.start(objectName)
    opener.objectName = objectName
    opener.attempts = 0
    opener.active = true
    opener.paused = false
    opener.status = "Starting"
    zoneId = mq.TLO.Zone.ID() or 0
    currentId = 0
end

function opener.stop(reason)
    if opener.active and mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    opener.active = false
    opener.paused = false
    opener.status = reason or "Stopped"
end

function opener.setPaused(paused)
    opener.paused = paused
    if paused then
        if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
        opener.status = "Paused"
    end
end

function opener.tick()
    if not opener.active or opener.paused then return end
    if mq.TLO.Me.Dead() or mq.TLO.Me.Hovering() then return opener.stop("Died - stopped opening") end
    if (mq.TLO.Zone.ID() or 0) ~= zoneId then return opener.stop("Zoned - stopped opening") end
    if inCombat() then
        opener.status = "In combat, waiting"
        return
    end

    local spawn = mq.TLO.NearestSpawn(opener.objectName)
    local id = spawn.ID() or 0
    if id == 0 then
        opener.status = string.format("Waiting for %s to spawn", opener.objectName)
        return
    end
    if id ~= currentId then
        currentId = id
        lastNav = 0
    end

    local now = mq.gettime()
    local distance = spawn.Distance3D() or 999
    if distance > 15 or not spawn.LineOfSight() then
        opener.status = string.format("Moving to %s (%d)", opener.objectName, math.floor(distance))
        if not mq.TLO.Navigation.Active() and now - lastNav > 1000 then
            mq.cmdf('/squelch /nav id %d distance=8 log=off', id)
            lastNav = now
        end
        return
    end

    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    if mq.TLO.Target.ID() ~= id and now - lastTarget > 1000 then
        mq.cmdf('/squelch /target id %d', id)
        lastTarget = now
    end
    if now - lastOpen > 1500 then
        mq.cmd('/squelch /open')
        lastOpen = now
        opener.attempts = opener.attempts + 1
    end
    opener.status = string.format("Opening %s", opener.objectName)
end

return opener
