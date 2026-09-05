local addonName, UUF = ...

local enabled = true
local running = false
local sampleTicker
local eventFrame
local startedAt

local fpsTotal = 0
local fpsMin = math.huge
local fpsMax = 0
local samples = 0
local recentTotal = 0
local recentMax = 0
local lastTotal = 0
local lastMax = 0
local eventCounts = {}
local raidEventTotal = 0

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
    "UNIT_HEAL_PREDICTION",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
}

local function Print(message)
    if UUF and UUF.PrettyPrint then
        UUF:PrettyPrint("|cFFFF8C8CCombatAuto|r " .. tostring(message))
    else
        print("UUF CombatAuto: " .. tostring(message))
    end
end

local function IsRaidUnit(unit)
    return type(unit) == "string" and unit:match("^raid%d+$") ~= nil
end

local function Reset()
    fpsTotal = 0
    fpsMin = math.huge
    fpsMax = 0
    samples = 0
    recentTotal = 0
    recentMax = 0
    lastTotal = 0
    lastMax = 0
    raidEventTotal = 0
    wipe(eventCounts)
end

local function StopSamplers()
    if sampleTicker then
        sampleTicker:Cancel()
        sampleTicker = nil
    end

    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
        eventFrame = nil
    end
end

local function Finish()
    if not running then return end
    running = false
    StopSamplers()

    local duration = math.max(GetTime() - (startedAt or GetTime()), 0.001)

    if samples > 0 then
        Print(string.format(
            "RESULT %.1fs | FPS avg=%.2f min=%.2f max=%.2f | samples=%d.",
            duration,
            fpsTotal / samples,
            fpsMin,
            fpsMax,
            samples
        ))

        Print(string.format(
            "UUF CPU Recent avg=%.4f max=%.4f ms | Last avg=%.4f max=%.4f ms.",
            recentTotal / samples,
            recentMax,
            lastTotal / samples,
            lastMax
        ))
    end

    Print(string.format(
        "raid UNIT events=%d | %.2f/s.",
        raidEventTotal,
        raidEventTotal / duration
    ))

    local rows = {}
    for event, count in pairs(eventCounts) do
        if count > 0 then
            rows[#rows + 1] = { event = event, count = count }
        end
    end

    table.sort(rows, function(a, b)
        if a.count == b.count then return a.event < b.event end
        return a.count > b.count
    end)

    for index = 1, math.min(#rows, 10) do
        local row = rows[index]
        Print(string.format(
            "%s=%d | %.2f/s.",
            row.event,
            row.count,
            row.count / duration
        ))
    end
end

local function Start()
    if not enabled or running or not IsInRaid() then return end

    Reset()
    running = true
    startedAt = GetTime()

    local metricRecent = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime or 1
    local metricLast = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.LastTime or 3

    eventFrame = CreateFrame("Frame")
    for _, event in ipairs(TRACKED_EVENTS) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end

    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if IsRaidUnit(unit) then
            eventCounts[event] = (eventCounts[event] or 0) + 1
            raidEventTotal = raidEventTotal + 1
        end
    end)

    sampleTicker = C_Timer.NewTicker(0.25, function()
        local fps = GetFramerate()

        samples = samples + 1
        fpsTotal = fpsTotal + fps
        fpsMin = math.min(fpsMin, fps)
        fpsMax = math.max(fpsMax, fps)

        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
            local recent = C_AddOnProfiler.GetAddOnMetric(addonName, metricRecent) or 0
            local last = C_AddOnProfiler.GetAddOnMetric(addonName, metricLast) or 0

            recentTotal = recentTotal + recent
            recentMax = math.max(recentMax, recent)
            lastTotal = lastTotal + last
            lastMax = math.max(lastMax, last)
        end
    end)

    Print("grabando automáticamente este combate. No tienes que hacer nada.")
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Start()
    else
        Finish()
    end
end)

SLASH_UUFCOMBATAUTO1 = "/uufcombatauto"
SlashCmdList["UUFCOMBATAUTO"] = function(message)
    local command = tostring(message or ""):lower():match("^%s*(%S*)")

    if command == "on" then
        enabled = true
        Print("ON.")
    elseif command == "off" then
        enabled = false
        Finish()
        Print("OFF.")
    elseif command == "status" then
        Print(string.format("enabled=%s | running=%s.", tostring(enabled), tostring(running)))
    else
        Print("uso: /uufcombatauto on | off | status")
    end
end
