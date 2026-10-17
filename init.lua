local mq = require('mq')
local settings = require('slayerfarm.settings')
settings.load()

local achievements = require('slayerfarm.achievements')
local hunter = require('slayerfarm.hunter')
local opener = require('slayerfarm.opener')
local farm = require('slayerfarm.farm')
local ui = require('slayerfarm.ui')

local running = true
local lastSave = 0

local function help()
    print("\ag[Slayer Farm]\ax Commands:")
    print("  \ay/sf show\ax | \ay/sf hide\ax - open or close the window")
    print("  \ay/sf start\ax - start farming")
    print("  \ay/sf pause\ax | \ay/sf resume\ax - pause or resume hunting")
    print("  \ay/sf stop\ax - stop farming (Slayer Farm keeps running)")
    print("  \ay/sf next\ax - skip to the next zone")
    print("  \ay/sf ignore\ax - never hunt mobs with your target's name in this zone")
    print("  \ay/sf scan\ax - rescan achievements")
    print("  \ay/sf dump\ax - write the Slayer category to config/slayerfarm_dump.txt for troubleshooting")
    print("  \ay/sf quit\ax - stop farming and end Slayer Farm (also /sf end, /sf exit)")
end

local function command(action)
    action = (action or "show"):lower()
    if action == "show" then
        ui.open = true
    elseif action == "hide" then
        ui.open = false
    elseif action == "scan" then
        achievements.scan()
    elseif action == "dump" then
        achievements.dump()
    elseif action == "ignore" then
        hunter.ignoreTarget()
    elseif action == "quit" or action == "end" or action == "exit" then
        print("\ag[Slayer Farm]\ax Ending.")
        farm.request("stop")
        running = false
    elseif (action == "pause" or action == "resume") and farm.state ~= "hunt" then
        print("\ag[Slayer Farm]\ax Nothing to " .. action .. " - not hunting right now.")
    elseif action == "start" or action == "stop" or action == "pause" or action == "resume" or action == "next" then
        farm.request(action)
    else
        help()
    end
end

mq.bind('/sf', command)
mq.event('slayerFarmDeath', "You have been slain by#*#", function() farm.onDeath() end)
mq.imgui.init('SlayerFarm', ui.render)

achievements.scan()
print("\ag[Slayer Farm]\ax Loaded. /sf help lists commands.")

while running do
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then
        farm.request("stop")
        running = false
    end
    if achievements.error and mq.gettime() - achievements.lastScan > 5000 then
        achievements.lastScan = mq.gettime()
        achievements.scan()
    end
    farm.tick()
    hunter.tick()
    opener.tick()
    achievements.refresh()
    mq.doevents()
    if settings.dirty and mq.gettime() - lastSave > 2000 then
        settings.save()
        settings.dirty = false
        lastSave = mq.gettime()
    end
    mq.delay(100)
end

farm.tick()
settings.save()
mq.unbind('/sf')
