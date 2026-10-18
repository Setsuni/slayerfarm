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
    for _, entry in ipairs(ui.commands) do
        printf("  \ay%s\ax - %s", entry.command, entry.about)
    end
end

local function command(action)
    action = (action or "show"):lower()
    if action == "show" then
        ui.hidden = false
    elseif action == "hide" then
        ui.hidden = true
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
    elseif action == "start" or action == "here" or action == "stop" or action == "pause" or action == "resume" or action == "next" then
        farm.request(action)
    else
        help()
    end
end

mq.bind('/slayerfarm', command)
mq.event('slayerFarmDeath', "You have been slain by#*#", function() farm.onDeath() end)
mq.imgui.init('SlayerFarm', ui.render)

achievements.scan()
print("\ag[Slayer Farm]\ax Loaded. /slayerfarm help lists commands.")

while running do
    if ui.quitRequested then
        print("\ag[Slayer Farm]\ax Ending.")
        farm.request("stop")
        running = false
    end
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
mq.unbind('/slayerfarm')
