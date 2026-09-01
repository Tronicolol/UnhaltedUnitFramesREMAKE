local addonName, UUF = ...

local state = {
    eventFrame = nil,
    eventTimer = nil,
    profileTicker = nil,
    savedRange = nil,
    aurasDisabled = false,
}

local TRACKED_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_POWER_FREQUENT",
    "UNIT_AURA",
    "UNIT_IN_RANGE_UPDATE",
    "UNIT_CONNECTION",
    "UNIT_PHASE",
    "UNIT_FLAGS",
    "PLAYER_FLAGS_CHANGED",
    "UNIT_HEAL_PREDICTION",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    "UNIT_NAME_UPDATE",
    "UNIT_TARGET",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
}

local function Print(message)
    if UUF and UUF.PrettyPrint then
        UUF:PrettyPrint("|cFF8CC8FFRealRaidIdle|r " .. tostring(message))
    else
        print("UUF RealRaidIdle: " .. tostring(message))
    end
end

local function IsRaidUnit(unit)
    return type(unit) == "string" and unit:match("^raid%d+$") ~= nil
end

local function ActiveRaidFrames()
    local frames = {}

    UUF:ForEachRaidFrame(function(frame, unit, assignedUnit)
        if frame and assignedUnit and IsRaidUnit(assignedUnit) then
            frames[#frames + 1] = {
                frame = frame,
                unit = assignedUnit,
            }
        end
    end, false, false)

    return frames
end

local function Snapshot()
    local frames = ActiveRaidFrames()

    local managedBuffs = 0
    local managedDebuffs = 0
    local managedCustom = 0
    local managedDispel = 0
    local privateEnabled = 0
    local healthEnabled = 0
    local powerEnabled = 0
    local powerShown = 0
    local onUpdateFrames = 0

    local registeredCounts = {}

    for _, event in ipairs(TRACKED_EVENTS) do
        registeredCounts[event] = 0
    end

    for _, entry in ipairs(frames) do
        local frame = entry.frame

        if frame.UUFManagedTargetBuffs and frame.UUFManagedTargetBuffs:IsShown() then managedBuffs = managedBuffs + 1 end
        if frame.UUFManagedTargetDebuffs and frame.UUFManagedTargetDebuffs:IsShown() then managedDebuffs = managedDebuffs + 1 end
        if frame.UUFManagedPartyRaidCustomAuras and frame.UUFManagedPartyRaidCustomAuras:IsShown() then managedCustom = managedCustom + 1 end
        if frame.UUFManagedDispelHighlight and frame.UUFManagedDispelHighlight:IsShown() then managedDispel = managedDispel + 1 end

        if frame.IsElementEnabled and frame:IsElementEnabled("PrivateAuras") then privateEnabled = privateEnabled + 1 end
        if frame.IsElementEnabled and frame:IsElementEnabled("Health") then healthEnabled = healthEnabled + 1 end
        if frame.IsElementEnabled and frame:IsElementEnabled("Power") then powerEnabled = powerEnabled + 1 end
        if frame.Power and frame.Power:IsShown() then powerShown = powerShown + 1 end
        if frame:GetScript("OnUpdate") then onUpdateFrames = onUpdateFrames + 1 end

        for _, event in ipairs(TRACKED_EVENTS) do
            local ok, registered = pcall(frame.IsEventRegistered, frame, event)
            if ok and registered then registeredCounts[event] = registeredCounts[event] + 1 end
        end
    end

    Print(string.format(
        "snapshot: raidFrames=%d | Health=%d | Power element=%d/shown=%d | frame OnUpdate=%d.",
        #frames, healthEnabled, powerEnabled, powerShown, onUpdateFrames
    ))

    Print(string.format(
        "auras: Buff=%d | Debuff=%d | Custom=%d | Dispel=%d | Private=%d.",
        managedBuffs, managedDebuffs, managedCustom, managedDispel, privateEnabled
    ))

    local registered = {}
    for event, count in pairs(registeredCounts) do
        if count > 0 then
            registered[#registered + 1] = { event = event, count = count }
        end
    end

    table.sort(registered, function(a, b)
        if a.count == b.count then return a.event < b.event end
        return a.count > b.count
    end)

    local parts = {}
    for index = 1, math.min(#registered, 10) do
        local item = registered[index]
        parts[#parts + 1] = item.event .. "=" .. item.count
    end

    if #parts > 0 then
        Print("oUF registrations top: " .. table.concat(parts, " | "))
    else
        Print("oUF registrations: ninguno en frames activos.")
    end
end

local function StopEventMonitor()
    if state.eventTimer then
        state.eventTimer:Cancel()
        state.eventTimer = nil
    end

    if state.eventFrame then
        state.eventFrame:UnregisterAllEvents()
        state.eventFrame:SetScript("OnEvent", nil)
        state.eventFrame = nil
    end
end

local function StartEventMonitor(seconds)
    StopEventMonitor()

    seconds = tonumber(seconds) or 10
    seconds = math.max(5, math.min(seconds, 60))

    local counts = {}
    local raidTotal = 0
    local globalTotal = 0
    local uniqueUnits = {}

    local frame = CreateFrame("Frame")
    state.eventFrame = frame

    for _, event in ipairs(TRACKED_EVENTS) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then counts[event] = -1 end
    end

    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
            counts[event] = (counts[event] or 0) + 1
            globalTotal = globalTotal + 1
            return
        end

        if IsRaidUnit(unit) then
            counts[event] = (counts[event] or 0) + 1
            raidTotal = raidTotal + 1
            uniqueUnits[unit] = true
        end
    end)

    Print(string.format("contando eventos raid reales durante %.0f s. No hagas nada especial.", seconds))

    state.eventTimer = C_Timer.NewTimer(seconds, function()
        local results = {}

        for event, count in pairs(counts) do
            if count and count > 0 then
                results[#results + 1] = { event = event, count = count }
            end
        end

        table.sort(results, function(a, b)
            if a.count == b.count then return a.event < b.event end
            return a.count > b.count
        end)

        local uniqueCount = 0
        for _ in pairs(uniqueUnits) do uniqueCount = uniqueCount + 1 end

        Print(string.format(
            "EVENTS resultado: raidUnitEvents=%d (%.1f/s) | global=%d | raidUnits=%d.",
            raidTotal, raidTotal / seconds, globalTotal, uniqueCount
        ))

        if #results == 0 then
            Print("EVENTS: ningún evento raid de la lista durante la muestra.")
        else
            for index = 1, math.min(#results, 12) do
                local item = results[index]
                Print(string.format("EVENT %s = %d (%.2f/s).", item.event, item.count, item.count / seconds))
            end
        end

        StopEventMonitor()
    end)
end

local function StopProfile()
    if state.profileTicker then
        state.profileTicker:Cancel()
        state.profileTicker = nil
    end
end

local function StartProfile(seconds)
    StopProfile()

    seconds = tonumber(seconds) or 10
    seconds = math.max(5, math.min(seconds, 60))

    if not C_AddOnProfiler or not C_AddOnProfiler.GetAddOnMetric then
        Print("C_AddOnProfiler no está disponible en este cliente.")
        return
    end

    local metricRecent = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime or 1
    local metricLast = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.LastTime or 3

    local samples = 0
    local fpsTotal = 0
    local fpsMin = math.huge
    local fpsMax = 0
    local recentTotal = 0
    local recentMax = 0
    local lastTotal = 0
    local lastMax = 0
    local started = GetTime()

    Print(string.format("PROFILE %.0f s: midiendo FPS + C_AddOnProfiler para %s.", seconds, tostring(addonName)))

    state.profileTicker = C_Timer.NewTicker(0.25, function(ticker)
        local fps = GetFramerate()
        local recent = C_AddOnProfiler.GetAddOnMetric(addonName, metricRecent) or 0
        local last = C_AddOnProfiler.GetAddOnMetric(addonName, metricLast) or 0

        samples = samples + 1
        fpsTotal = fpsTotal + fps
        fpsMin = math.min(fpsMin, fps)
        fpsMax = math.max(fpsMax, fps)
        recentTotal = recentTotal + recent
        recentMax = math.max(recentMax, recent)
        lastTotal = lastTotal + last
        lastMax = math.max(lastMax, last)

        if GetTime() - started >= seconds then
            ticker:Cancel()
            state.profileTicker = nil

            local recentNow = C_AddOnProfiler.GetAddOnMetric(addonName, metricRecent) or 0
            local overall = C_AddOnProfiler.GetOverallMetric and (C_AddOnProfiler.GetOverallMetric(metricRecent) or 0) or 0
            local application = C_AddOnProfiler.GetApplicationMetric and (C_AddOnProfiler.GetApplicationMetric(metricRecent) or 0) or 0

            Print(string.format(
                "PROFILE FPS: avg=%.2f | min=%.2f | max=%.2f | samples=%d.",
                fpsTotal / samples, fpsMin, fpsMax, samples
            ))

            Print(string.format(
                "PROFILE UUF: Recent avgSample=%.4f ms | now=%.4f | maxSample=%.4f | Last avg=%.4f | Last max=%.4f ms.",
                recentTotal / samples, recentNow, recentMax, lastTotal / samples, lastMax
            ))

            Print(string.format(
                "PROFILE contexto: allAddons Recent=%.4f ms | application Recent=%.4f ms.",
                overall, application
            ))

            if C_AddOnProfiler.GetTopKAddOnsForMetric then
                local ok, top = pcall(C_AddOnProfiler.GetTopKAddOnsForMetric, metricRecent, 5)
                if ok and type(top) == "table" then
                    local parts = {}
                    for index, result in ipairs(top) do
                        if index > 5 then break end
                        if result and result.addOnName and result.metricValue then
                            parts[#parts + 1] = string.format("%s=%.3f", result.addOnName, result.metricValue)
                        end
                    end
                    if #parts > 0 then Print("PROFILE top addons: " .. table.concat(parts, " | ")) end
                end
            end
        end
    end)
end

local function ParkManagedContainer(container)
    if not container then return end
    if container.SetEnabled then pcall(container.SetEnabled, container, false) end
    if container.SetUnit then pcall(container.SetUnit, container, "none") end
    pcall(container.Hide, container)
end

local function AurasOff()
    if InCombatLockdown() then
        Print("AurasOff solo fuera de combate.")
        return
    end

    local frames = ActiveRaidFrames()
    local containers = 0
    local private = 0

    for _, entry in ipairs(frames) do
        local frame = entry.frame
        local list = {
            frame.UUFManagedTargetBuffs,
            frame.UUFManagedTargetDebuffs,
            frame.UUFManagedPartyRaidCustomAuras,
            frame.UUFManagedDispelHighlight,
        }

        for _, container in ipairs(list) do
            if container then
                ParkManagedContainer(container)
                containers = containers + 1
            end
        end

        if frame.IsElementEnabled and frame:IsElementEnabled("PrivateAuras") then
            frame:DisableElement("PrivateAuras")
            private = private + 1
        end
        if frame.PrivateAuraContainer then frame.PrivateAuraContainer:Hide() end
    end

    state.aurasDisabled = true

    Print(string.format(
        "AURAS OFF real raid: %d frames | %d managed containers aparcados | %d PrivateAuras desregistradas.",
        #frames, containers, private
    ))
    Print("espera 5 s y ejecuta /uufrealidle profile 10.")
end

local function AurasOn()
    if InCombatLockdown() then
        Print("AurasOn solo fuera de combate.")
        return
    end

    local frames = ActiveRaidFrames()
    local restored = 0
    local errors = 0

    for _, entry in ipairs(frames) do
        local frame = entry.frame
        local unit = entry.unit

        local okAuras = pcall(UUF.UpdateUnitAuras, UUF, frame, unit)
        local okDispel = pcall(UUF.UpdateUnitDispelHighlight, UUF, frame, unit)

        if okAuras and okDispel then restored = restored + 1 else errors = errors + 1 end
    end

    state.aurasDisabled = false

    Print(string.format("AURAS ON real raid: restaurados=%d | errores=%d.", restored, errors))
    Print("espera 5 s y ejecuta /uufrealidle profile 10.")
end

local function RangeOff()
    if InCombatLockdown() then
        Print("RangeOff solo fuera de combate.")
        return
    end

    local frames = ActiveRaidFrames()
    state.savedRange = {}
    local removed = 0

    for _, entry in ipairs(frames) do
        local frame = entry.frame
        local unit = frame.UUFRangeUnit or entry.unit

        if frame.UUFRangeUnit then
            state.savedRange[frame] = unit
            UUF:UnregisterRangeFrame(frame)
            removed = removed + 1
        end

        frame:SetAlpha(1)
    end

    Print(string.format("RANGE OFF real raid: %d registrations retiradas.", removed))
    Print("espera 5 s y ejecuta /uufrealidle profile 10.")
end

local function RangeOn()
    if InCombatLockdown() then
        Print("RangeOn solo fuera de combate.")
        return
    end

    local restored = 0

    if state.savedRange then
        for frame, oldUnit in pairs(state.savedRange) do
            if frame then
                local unit = frame:GetAttribute("unit") or oldUnit
                if IsRaidUnit(unit) then
                    UUF:RegisterRangeFrame(frame, unit)
                    restored = restored + 1
                end
            end
        end
    else
        for _, entry in ipairs(ActiveRaidFrames()) do
            UUF:RegisterRangeFrame(entry.frame, entry.unit)
            restored = restored + 1
        end
    end

    state.savedRange = nil

    Print(string.format("RANGE ON real raid: %d registrations restauradas.", restored))
    Print("espera 5 s y ejecuta /uufrealidle profile 10.")
end

local function Cleanup()
    StopEventMonitor()
    StopProfile()

    if state.savedRange then RangeOn() end
    if state.aurasDisabled then AurasOn() end

    Print("cleanup hecho.")
end

SLASH_UUFREALIDLE1 = "/uufrealidle"
SlashCmdList["UUFREALIDLE"] = function(message)
    local command, value = tostring(message or ""):lower():match("^%s*(%S*)%s*(%S*)")

    if command == "snapshot" then
        Snapshot()
    elseif command == "events" then
        StartEventMonitor(value)
    elseif command == "profile" then
        StartProfile(value)
    elseif command == "aurasoff" then
        AurasOff()
    elseif command == "aurason" then
        AurasOn()
    elseif command == "rangeoff" then
        RangeOff()
    elseif command == "rangeon" then
        RangeOn()
    elseif command == "cleanup" then
        Cleanup()
    else
        Print("uso: snapshot | events [s] | profile [s] | aurasoff|aurason | rangeoff|rangeon | cleanup")
    end
end
