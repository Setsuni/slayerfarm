local mq = require('mq')
local ImGui = require('ImGui')
local data = require('slayerfarm.data')
local achievements = require('slayerfarm.achievements')
local hunter = require('slayerfarm.hunter')
local opener = require('slayerfarm.opener')
local farm = require('slayerfarm.farm')
local settings = require('slayerfarm.settings')

local ui = {}

ui.open = true

local stateColors = {
    idle = ImVec4(0.7, 0.7, 0.7, 1),
    travel = ImVec4(0.4, 0.7, 1, 1),
    gather = ImVec4(0.4, 0.7, 1, 1),
    hunt = ImVec4(0.4, 1, 0.4, 1),
}
local grey = ImVec4(0.55, 0.55, 0.55, 1)
local optionalColor = ImVec4(0.9, 0.6, 0.2, 1)
local manualColor = ImVec4(0.75, 0.55, 1, 1)

local function clicked(label, selected)
    local _, pressed = ImGui.Selectable(label, selected)
    return pressed
end

local function changed()
    settings.dirty = true
end

local function zoneList(entry)
    local names = {}
    for _, shortName in ipairs(entry.zones) do
        if achievements.zoneAllowed(shortName) then table.insert(names, data.zones[shortName].name) end
    end
    return table.concat(names, ", ")
end

local function learnedRaces(entry)
    local races = {}
    for race, ids in pairs(settings.learned) do
        if (ids[entry.id] or 0) >= 2 then table.insert(races, race) end
    end
    return table.concat(races, ", ")
end

local function drawExpansionCombo()
    local detected = achievements.detectedExpansion()
    local current = settings.values.maxExpansion
    local preview = current and ("Up to " .. data.expansions[current + 1]) or ("Auto: " .. data.expansions[detected + 1])
    ImGui.SetNextItemWidth(260)
    if ImGui.BeginCombo("Expansion", preview) then
        if clicked("Auto: " .. data.expansions[detected + 1], current == nil) then
            settings.values.maxExpansion = nil
            changed()
        end
        for index, name in ipairs(data.expansions) do
            if clicked("Up to " .. name, current == index - 1) then
                settings.values.maxExpansion = index - 1
                changed()
            end
        end
        ImGui.EndCombo()
    end
end

local function mobLabel(race)
    return (race:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function mobUrl(race)
    local query = race:gsub("[^%w ]", function(character) return string.format("%%%02X", character:byte()) end):gsub(" ", "+")
    return "https://everquest.allakhazam.com/search.html?q=" .. query .. "#Mobs"
end

local function sameLineIfFits(text)
    local available = ImGui.GetContentRegionAvail()
    if ImGui.CalcTextSize(text) < available then ImGui.SameLine(0, 0) end
end

local function remainingText(entry)
    if entry.completed or #(entry.remaining or {}) == 0 then return nil end
    local parts = {}
    for _, part in ipairs(entry.remaining) do
        table.insert(parts, string.format("%s %d / %d", part.description, part.have, part.need))
    end
    return "Still need: " .. table.concat(parts, ", ")
end

local function mobsFor(entry)
    if not entry.completed and entry.remainingRaces and #entry.remainingRaces > 0 then return entry.remainingRaces end
    if #entry.races > 0 then return entry.races end
    return { entry.open, }
end

local function drawMobLinks(entry)
    local mobs = mobsFor(entry)
    if #mobs == 0 then return end
    sameLineIfFits(" [")
    ImGui.TextColored(grey, " [")
    for index, race in ipairs(mobs) do
        local label = mobLabel(race)
        sameLineIfFits(label)
        ImGui.TextLinkOpenURL(label, mobUrl(race))
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Search Allakhazam for " .. label) end
        ImGui.SameLine(0, 0)
        ImGui.TextColored(grey, index < #mobs and ", " or "]")
    end
end

local function drawObjectiveRows(entry, leadColumns, showDone)
    if entry.completed then return end
    for index, part in ipairs(entry.parts or {}) do
        if showDone or not part.done then
            ImGui.TableNextRow()
            ImGui.PushID(entry.id .. ":" .. index)
            for _ = 1, leadColumns do ImGui.TableNextColumn() end
            ImGui.TableNextColumn()
            ImGui.Indent(20)
            if part.done then
                ImGui.TextColored(ImVec4(0.4, 1, 0.4, 1), part.description .. " (done)")
            else
                ImGui.TextLinkOpenURL(part.description, mobUrl(part.race))
                if ImGui.IsItemHovered() then ImGui.SetTooltip("Search Allakhazam for " .. mobLabel(part.race)) end
            end
            ImGui.Unindent(20)
            ImGui.TableNextColumn()
            ImGui.ProgressBar(part.have / part.need, -1, 0, string.format("%d / %d", part.have, part.need))
            if leadColumns > 0 and not part.done then
                ImGui.TableNextColumn()
                local zones = zoneList(part)
                if zones == "" then
                    ImGui.TextColored(grey, "No suggested zone")
                else
                    ImGui.Text(zones)
                end
            end
            ImGui.PopID()
        end
    end
end

local function drawAchievementRow(entry)
    ImGui.TableNextRow()
    ImGui.PushID(entry.id)

    ImGui.TableNextColumn()
    if entry.completed then
        ImGui.TextColored(ImVec4(0.4, 1, 0.4, 1), "Done")
    elseif not entry.huntable then
        ImGui.TextColored(grey, "-")
    else
        local farmIt, pressed = ImGui.Checkbox("##farm", achievements.isFarmed(entry))
        if pressed then achievements.setFarmed(entry, farmIt) end
    end

    ImGui.TableNextColumn()
    if entry.optional then
        ImGui.TextColored(grey, entry.name)
    else
        ImGui.Text(entry.name)
    end
    if ImGui.IsItemHovered() then
        local tip = entry.known and ("Counts: " .. table.concat(entry.races, ", ")) or "No data for this achievement yet."
        local learned = learnedRaces(entry)
        if learned ~= "" then tip = tip .. "\nLearned: " .. learned end
        if entry.open then tip = "Opens: " .. entry.open .. " (/open, no killing)" end
        if not entry.huntable and entry.known then tip = "Not a normal mob kill - farm this one by hand." end
        if entry.optional then tip = tip .. "\n\nOptional: not needed for the Slayer meta achievements. Tick it to farm it anyway." end
        if remainingText(entry) then tip = tip .. "\n\n" .. remainingText(entry) end
        ImGui.SetTooltip(tip)
    end
    if entry.optional then
        ImGui.SameLine()
        ImGui.TextColored(optionalColor, "(optional)")
    end
    drawMobLinks(entry)

    ImGui.TableNextColumn()
    local fraction = entry.required > 0 and entry.count / entry.required or 0
    if entry.optional then ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.4, 0.4, 0.4, 1) end
    ImGui.ProgressBar(fraction, -1, 0, string.format("%d / %d", entry.count, entry.required))
    if entry.optional then ImGui.PopStyleColor() end

    ImGui.TableNextColumn()
    local zones = zoneList(entry)
    if zones == "" and entry.manual then
        ImGui.TextColored(manualColor, entry.manual .. " (manual)")
        if ImGui.IsItemHovered() then ImGui.SetTooltip(entry.manual .. "\n\nInstanced or special - do this one by hand. Slayer Farm won't travel or hunt here.") end
    elseif zones == "" then
        ImGui.TextColored(grey, entry.huntable and "No suggested zone" or "")
    else
        ImGui.Text(zones)
        if ImGui.IsItemHovered() then ImGui.SetTooltip(zones) end
    end

    ImGui.PopID()
end

local function drawAchievementsTab()
    drawExpansionCombo()
    ImGui.SameLine()
    if ImGui.Button("Rescan") then achievements.scan() end
    ImGui.SameLine()
    local showCompleted, pressed = ImGui.Checkbox("Show completed", settings.values.showCompleted)
    if pressed then
        settings.values.showCompleted = showCompleted
        changed()
    end

    if achievements.error then
        ImGui.TextColored(ImVec4(1, 0.4, 0.4, 1), achievements.error)
        return
    end

    local done = 0
    for _, entry in ipairs(achievements.list) do
        if entry.completed then done = done + 1 end
    end
    ImGui.Text(string.format("Completed %d of %d.  Untick an achievement to leave it out of farming.", done, #achievements.list))

    for _, group in ipairs(achievements.groups) do
        local entries, subDone, subTotal, optionalDone, optionalTotal = {}, 0, 0, 0, 0
        for _, entry in ipairs(achievements.list) do
            if entry.group == group.name then
                if entry.optional then
                    optionalTotal = optionalTotal + 1
                    if entry.completed then optionalDone = optionalDone + 1 end
                else
                    subTotal = subTotal + 1
                    if entry.completed then subDone = subDone + 1 end
                end
                if settings.values.showCompleted or not entry.completed then table.insert(entries, entry) end
            end
        end
        local optionalText = optionalTotal > 0 and string.format(", optional %d / %d", optionalDone, optionalTotal) or ""
        local title = group.isParent and string.format("%s  [%s]", group.name, group.sub) or group.name
        local status = group.completed and "  - COMPLETE" or ""
        local header = string.format("%s  (%d / %d needed%s)%s###%s", title, subDone, subTotal, optionalText, status, group.name)
        if group.completed then ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 1, 0.4, 1) end
        local open = ImGui.CollapsingHeader(header, group.sub == "Skill" and ImGuiTreeNodeFlags.DefaultOpen or 0)
        if group.completed then ImGui.PopStyleColor() end
        if open then
            local flags = bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersInnerV, ImGuiTableFlags.Resizable)
            if ImGui.BeginTable("table" .. group.name, 4, flags) then
                ImGui.TableSetupColumn("Farm", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn("Achievement", ImGuiTableColumnFlags.WidthStretch, 3)
                ImGui.TableSetupColumn("Progress", ImGuiTableColumnFlags.WidthStretch, 2)
                ImGui.TableSetupColumn("Zones", ImGuiTableColumnFlags.WidthStretch, 4)
                ImGui.TableHeadersRow()
                for _, entry in ipairs(entries) do
                    drawAchievementRow(entry)
                    drawObjectiveRows(entry, 1, settings.values.showCompleted)
                end
                ImGui.EndTable()
            end
        end
    end
end

local ignoreInput = ""

local function drawStatus()
    ImGui.Text("State:")
    ImGui.SameLine()
    ImGui.TextColored(stateColors[farm.state] or grey, farm.status)
    if farm.state == "hunt" and farm.mode == "open" then
        ImGui.Text("Opener: " .. opener.status)
        ImGui.Text(string.format("/open attempts: %d", opener.attempts))
    elseif farm.state == "hunt" then
        ImGui.Text("Hunter: " .. hunter.status)
        if hunter.targetId > 0 then
            local target = mq.TLO.Spawn(hunter.targetId)
            ImGui.Text("Target:")
            ImGui.SameLine()
            ImGui.TextColored(ImVec4(1, 1, 0.4, 1), string.format("%s (%s)", target.CleanName() or "?", target.Race.Name() or "?"))
        end
        ImGui.Text(string.format("Slayer kills: %d   Rate: ~%d/hr   Candidates in range: %d", hunter.kills, hunter.killsPerHour(), hunter.candidates))
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Only kills that counted toward an achievement you're farming, since you pressed Start.") end
    end

    if farm.state == "idle" then
        if ImGui.Button("Start") then farm.request("start") end
    else
        if ImGui.Button("Stop") then farm.request("stop") end
        if farm.state == "hunt" then
            ImGui.SameLine()
            if farm.isPaused() then
                if ImGui.Button("Resume") then farm.request("resume") end
            elseif ImGui.Button("Pause") then
                farm.request("pause")
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Next Zone") then farm.request("next") end
    end
    if farm.state == "hunt" and farm.mode == "hunt" then
        ImGui.SameLine()
        if ImGui.Button("Ignore Target") then hunter.ignoreTarget() end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Never hunt mobs with your current target's name in this zone.") end
    end
end

local function workingZone(ranked)
    if farm.state ~= "idle" and farm.zone then return farm.zone end
    if not settings.values.autoZone then return settings.values.manualZone end
    return ranked[1] and ranked[1].shortName or nil
end

local function drawWorkingOn(ranked)
    local zone = workingZone(ranked)
    if not zone then return end
    local entries = {}
    for _, entry in ipairs(achievements.list) do
        local showIt = settings.values.farmShowCompleted or not entry.completed
        if entry.huntable and achievements.isFarmed(entry) and showIt then
            for _, shortName in ipairs(entry.zones) do
                if shortName == zone then
                    table.insert(entries, entry)
                    break
                end
            end
        end
    end
    local heading = farm.state == "idle" and "Next up in " or "Working on in "
    ImGui.Text(heading .. farm.zoneName(zone) .. ":")
    ImGui.SameLine()
    local showCompleted, pressed = ImGui.Checkbox("Show completed##farm", settings.values.farmShowCompleted)
    if pressed then
        settings.values.farmShowCompleted = showCompleted
        changed()
    end
    if #entries == 0 then
        ImGui.TextColored(grey, "No targeted achievements list this zone.")
        return
    end
    local seen, lookingFor = {}, {}
    for _, entry in ipairs(entries) do
        if not entry.completed then
            for _, race in ipairs(mobsFor(entry)) do
                if not seen[race] then
                    seen[race] = true
                    table.insert(lookingFor, race)
                end
            end
        end
    end
    if settings.values.killAnything then
        ImGui.TextColored(ImVec4(1, 0.7, 0.3, 1), "Looking for: everything in range (Kill anything is on)")
    elseif #lookingFor > 0 then
        ImGui.Text("Looking for:")
        drawMobLinks({ races = lookingFor, })
    end
    local flags = bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersInnerV)
    if ImGui.BeginTable("workingOn", 2, flags) then
        ImGui.TableSetupColumn("Achievement", ImGuiTableColumnFlags.WidthStretch, 3)
        ImGui.TableSetupColumn("Progress", ImGuiTableColumnFlags.WidthStretch, 2)
        for _, entry in ipairs(entries) do
            ImGui.TableNextRow()
            ImGui.PushID(entry.id)
            ImGui.TableNextColumn()
            if entry.completed then
                ImGui.TextColored(ImVec4(0.4, 1, 0.4, 1), entry.name .. " (done)")
            else
                ImGui.Text(entry.name)
            end
            drawMobLinks(entry)
            ImGui.TableNextColumn()
            local fraction = entry.required > 0 and entry.count / entry.required or 0
            local gain = achievements.sessionGain(entry)
            local overlay = gain > 0 and string.format("%d / %d   +%d this session", entry.count, entry.required, gain)
                or string.format("%d / %d", entry.count, entry.required)
            ImGui.ProgressBar(fraction, -1, 0, overlay)
            ImGui.PopID()
            drawObjectiveRows(entry, 0, settings.values.farmShowCompleted)
        end
        ImGui.EndTable()
    end
end

local function drawIgnores()
    local zone = (farm.state ~= "idle" and farm.zone) or (mq.TLO.Zone.ShortName() or ""):lower()
    local names = settings.ignoredIn(zone)
    ImGui.Text(string.format("Never hunt these in %s:", farm.zoneName(zone)))
    for _, name in ipairs(names) do
        ImGui.PushID(name)
        if ImGui.SmallButton("x") then settings.setIgnored(zone, name, false) end
        ImGui.SameLine()
        ImGui.Text(name)
        ImGui.PopID()
    end
    if #names == 0 then ImGui.TextColored(grey, "Nothing ignored here yet.") end
    ImGui.SetNextItemWidth(220)
    ignoreInput = ImGui.InputText("##ignoreInput", ignoreInput)
    ImGui.SameLine()
    if ImGui.Button("Add") and ignoreInput ~= "" then
        settings.setIgnored(zone, ignoreInput, true)
        ignoreInput = ""
    end
    ImGui.SameLine()
    if ImGui.Button("Add Target") then
        local name = mq.TLO.Target.CleanName()
        if name then settings.setIgnored(zone, name, true) end
    end
end

local function drawDestination(ranked)
    if ImGui.RadioButton("Auto - best overlap", settings.values.autoZone) then
        settings.values.autoZone = true
        changed()
    end
    ImGui.SameLine()
    if ImGui.RadioButton("Manual", not settings.values.autoZone) then
        settings.values.autoZone = false
        changed()
    end
    if not settings.values.autoZone then
        ImGui.SameLine()
        ImGui.SetNextItemWidth(260)
        local preview = settings.values.manualZone and farm.zoneName(settings.values.manualZone) or "Choose a zone"
        if ImGui.BeginCombo("##manualZone", preview) then
            for _, zone in ipairs(ranked) do
                if clicked(string.format("%s (%d)", zone.name, #zone.covers), settings.values.manualZone == zone.shortName) then
                    settings.values.manualZone = zone.shortName
                    changed()
                end
            end
            ImGui.EndCombo()
        end
    end

    local flags = bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersInnerV)
    if ImGui.BeginTable("zones", 3, flags) then
        ImGui.TableSetupColumn("Zone", ImGuiTableColumnFlags.WidthStretch, 2)
        ImGui.TableSetupColumn("Covers", ImGuiTableColumnFlags.WidthFixed, 50)
        ImGui.TableSetupColumn("Achievements", ImGuiTableColumnFlags.WidthStretch, 4)
        ImGui.TableHeadersRow()
        for index, zone in ipairs(ranked) do
            if index > 8 then break end
            local names = {}
            for _, entry in ipairs(zone.covers) do table.insert(names, entry.name) end
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text((zone.shortName == farm.zone and "> " or "") .. zone.name)
            ImGui.TableNextColumn()
            ImGui.Text(tostring(#zone.covers))
            ImGui.TableNextColumn()
            ImGui.Text(table.concat(names, ", "))
            if ImGui.IsItemHovered() then ImGui.SetTooltip(table.concat(names, "\n")) end
        end
        ImGui.EndTable()
    end
    if #ranked == 0 then ImGui.TextColored(grey, "No zones left for your targeted achievements and expansion.") end
end

local function slider(label, key, min, max, tip)
    ImGui.SetNextItemWidth(160)
    local value, moved = ImGui.SliderInt(label, settings.values[key], min, max)
    if moved then
        settings.values[key] = value
        changed()
    end
    if tip and ImGui.IsItemHovered() then ImGui.SetTooltip(tip) end
end

local function checkbox(label, key, tip)
    local value, pressed = ImGui.Checkbox(label, settings.values[key])
    if pressed then
        settings.values[key] = value
        changed()
    end
    if tip and ImGui.IsItemHovered() then ImGui.SetTooltip(tip) end
end

local function drawGroupSettings()
    checkbox("Bring group", "travelGroup", "Group members travel with you over DanNet (/dgge).")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(120)
    if ImGui.BeginCombo("Followers", settings.values.followMode == "chase" and "Boxr chase" or "Leave as is") then
        if clicked("Boxr chase", settings.values.followMode == "chase") then
            settings.values.followMode = "chase"
            changed()
        end
        if clicked("Leave as is", settings.values.followMode ~= "chase") then
            settings.values.followMode = "manual"
            changed()
        end
        ImGui.EndCombo()
    end
end

local function drawHuntSettings()
    slider("Hunt radius", "huntRadius", 200, 6000, "How far from where the hunt starts to look for mobs.")
    ImGui.SameLine()
    slider("Z range", "zRange", 50, 2000, "How far above or below the start point to look.")
    slider("Approach distance", "approachDistance", 5, 120, "How close to get before fighting. Raise it for casters.")
    ImGui.SameLine()
    slider("Avoid radius", "playerRadius", 30, 400, "Skip mobs with other players this close.")
    slider("Rest below HP %", "restHP", 0, 90)
    ImGui.SameLine()
    slider("Rest below mana %", "restMana", 0, 90)
    checkbox("Melee attack", "meleeAttack")
    ImGui.SameLine()
    checkbox("Send pet", "usePet")
    ImGui.SameLine()
    checkbox("Avoid other players", "avoidPlayers")
    ImGui.SameLine()
    checkbox("Kill anything", "killAnything", "Hunt every mob in range, mobs that count first.")
    ImGui.SameLine()
    checkbox("Show hunt area on map", "showArea", "Draws the hunt radius as an orange circle on the in-game map.")
end

local function drawFarmTab()
    local ranked = achievements.rankZones()
    drawStatus()
    ImGui.Separator()
    drawWorkingOn(ranked)
    ImGui.Separator()
    drawDestination(ranked)
    ImGui.Separator()
    drawGroupSettings()
    if ImGui.CollapsingHeader("Hunt settings") then drawHuntSettings() end
    if ImGui.CollapsingHeader("Ignored mobs") then drawIgnores() end
    if ImGui.CollapsingHeader("Log") then
        for _, line in ipairs(farm.log) do ImGui.TextWrapped(line) end
    end
end

function ui.render()
    if not ui.open then return end
    local show
    ui.open, show = ImGui.Begin("Slayer Farm", ui.open)
    if show then
        if ImGui.BeginTabBar("tabs") then
            if ImGui.BeginTabItem("Achievements") then
                drawAchievementsTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Farm") then
                drawFarmTab()
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end
    ImGui.End()
end

return ui
