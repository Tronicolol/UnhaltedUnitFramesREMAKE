local _, UUF = ...

local OriginalCreateUnitFrame = UUF.CreateUnitFrame
local OriginalUpdateUnitFrame = UUF.UpdateUnitFrame

local UnitExists = UnitExists
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local GetTime = GetTime
local C_Timer = C_Timer
local ProfileNow = debugprofilestop

local unitToButton = {}
local trackers = {}
local dirty = {}
local armed = {}
local flushBudget = 20
local beltTicker
local beltPhase = 0

local wantsIncoming = false
local wantsAbsorb = false
local wantsHealAbsorb = false
local wantsAny = false

local profiling = false
local profileStartedAt = 0
local profileStats = {}

local function ResetProfileStats()
    profileStats = {
        events = 0,
        marks = 0,
        coalesced = 0,
        paints = 0,
        unmapped = 0,
        flushes = 0,
        beltMarks = 0,
        handlerMs = 0,
        handlerMaxMs = 0,
        lookupMs = 0,
        paintMs = 0,
        paintMaxMs = 0,
        predictionEvents = 0,
        absorbEvents = 0,
        healAbsorbEvents = 0,
        maxHealthEvents = 0,
        modifierEvents = 0,
        connectionEvents = 0,
        secretPaints = 0,
    }
end
ResetProfileStats()

local function IsRaidUnit(unit)
    return type(unit) == "string" and UUF:GetNormalizedUnit(unit) == "raid"
end

local function IsRaidToken(unit)
    return type(unit) == "string" and unit:match("^raid%d+$") ~= nil
end

local function GetPredictionHealth(unitFrame)
    return unitFrame and unitFrame.UUFMinimalRaidHealth
end

local function GetPredictionState(unitFrame)
    if not unitFrame then return nil end
    local state = unitFrame.UUFMinimalRaidPredictionState
    if not state then
        state = {
            mappedUnit = nil,
            lastPaint = 0,
            overEnabled = false,
        }
        unitFrame.UUFMinimalRaidPredictionState = state
    end
    return state
end

local function ResetBar(bar)
    if not bar then return end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
end

local function ResetPredictionValues(unitFrame)
    local health = GetPredictionHealth(unitFrame)
    if not health then return end

    ResetBar(health.HealingPlayer)
    ResetBar(health.DamageAbsorb)
    ResetBar(health.HealAbsorb)

    local bars = unitFrame.UUFGroupPredictionBars
    local over = bars and bars.overDamageAbsorb
    if over then
        ResetBar(over)
        over:Hide()
        if over.Clip then over.Clip:Hide() end
    end

    local state = GetPredictionState(unitFrame)
    if state then state.lastPaint = 0 end
    armed[unitFrame] = nil
end

local function EnsurePredictionCalculator(health)
    if not health then return nil end

    local values = health.values
    if not values then
        values = CreateUnitHealPredictionCalculator()
        health.values = values
    elseif values.ResetPredictedValues then
        values:ResetPredictedValues()
    end

    if health.damageAbsorbClampMode then
        values:SetDamageAbsorbClampMode(health.damageAbsorbClampMode)
    end
    if health.healAbsorbClampMode then
        values:SetHealAbsorbClampMode(health.healAbsorbClampMode)
    end
    if health.healAbsorbMode then
        values:SetHealAbsorbMode(health.healAbsorbMode)
    end
    if health.incomingHealClampMode then
        values:SetIncomingHealClampMode(health.incomingHealClampMode)
    end
    if health.incomingHealOverflow then
        values:SetIncomingHealOverflowPercent(health.incomingHealOverflow)
    end

    return values
end

local function SizePredictionBars(health)
    if not health then return end
    local width = health:GetWidth()
    if health.HealingPlayer then health.HealingPlayer:SetWidth(width) end
    if health.DamageAbsorb then health.DamageAbsorb:SetWidth(width) end
    if health.HealAbsorb then health.HealAbsorb:SetWidth(width) end
end

local function SyncTrackerEvent(tracker, event, unit, wanted)
    local registrations = tracker.UUFMinimalPredictionRegistrations
    if wanted then
        if not registrations[event] then
            tracker:RegisterUnitEvent(event, unit)
            registrations[event] = true
        end
    elseif registrations[event] then
        tracker:UnregisterEvent(event)
        registrations[event] = nil
    end
end

local function SyncTrackerEvents()
    for unit, tracker in pairs(trackers) do
        SyncTrackerEvent(tracker, "UNIT_HEAL_PREDICTION", unit, wantsIncoming)
        SyncTrackerEvent(tracker, "UNIT_ABSORB_AMOUNT_CHANGED", unit, wantsAbsorb)
        SyncTrackerEvent(tracker, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit, wantsHealAbsorb)
        SyncTrackerEvent(tracker, "UNIT_MAXHEALTH", unit, wantsAny)
        SyncTrackerEvent(tracker, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", unit, wantsAny)
        SyncTrackerEvent(tracker, "UNIT_CONNECTION", unit, wantsAny)
    end
end

local flushDriver = CreateFrame("Frame")
flushDriver:Hide()

local function MarkDirty(unitFrame)
    if not unitFrame or not wantsAny then return false end
    if dirty[unitFrame] then
        if profiling then profileStats.coalesced = profileStats.coalesced + 1 end
        return false
    end

    dirty[unitFrame] = true
    if profiling then profileStats.marks = profileStats.marks + 1 end
    flushDriver:Show()
    return true
end

local function SetArmed(unitFrame, state)
    if state then
        armed[unitFrame] = true
    else
        armed[unitFrame] = nil
    end
end

local function PlainPositive(value)
    if value == nil then return false, false end
    if UUF:IsSecretValue(value) then return false, true end
    return value > 0, false
end

local function PaintPrediction(unitFrame, unit)
    local state = GetPredictionState(unitFrame)
    local health = GetPredictionHealth(unitFrame)
    if not state or not health or not unit or not UnitExists(unit) then
        ResetPredictionValues(unitFrame)
        return
    end

    local values = health.values or EnsurePredictionCalculator(health)
    if not values then return end

    UnitGetDetailedHealPrediction(unit, "player", values)
    local maxHealth = values:GetMaximumHealth()

    local playerHeal
    local damageAbsorb
    local healAbsorb

    if health.HealingPlayer then
        local _, currentPlayerHeal = values:GetIncomingHeals()
        playerHeal = currentPlayerHeal
        health.HealingPlayer:SetMinMaxValues(0, maxHealth)
        health.HealingPlayer:SetValue(playerHeal)
    end

    if health.DamageAbsorb then
        damageAbsorb = values:GetDamageAbsorbs()
        health.DamageAbsorb:SetMinMaxValues(0, maxHealth)
        health.DamageAbsorb:SetValue(damageAbsorb)
    end

    if health.HealAbsorb then
        healAbsorb = values:GetHealAbsorbs()
        health.HealAbsorb:SetMinMaxValues(0, maxHealth)
        health.HealAbsorb:SetValue(healAbsorb)
    end

    local bars = unitFrame.UUFGroupPredictionBars
    local over = bars and bars.overDamageAbsorb
    if over then
        if state.overEnabled and health.DamageAbsorb then
            over:SetMinMaxValues(0, maxHealth)
            over:SetValue(damageAbsorb)
            if over.Clip then over.Clip:Show() end
            over:Show()
        else
            over:Hide()
            if over.Clip then over.Clip:Hide() end
        end
    end

    local incomingActive, incomingSecret = PlainPositive(playerHeal)
    local absorbActive, absorbSecret = PlainPositive(damageAbsorb)
    local healAbsorbActive, healAbsorbSecret = PlainPositive(healAbsorb)
    local hasSecret = incomingSecret or absorbSecret or healAbsorbSecret
    local isActive = incomingActive or absorbActive or healAbsorbActive or hasSecret

    if hasSecret and profiling then
        profileStats.secretPaints = profileStats.secretPaints + 1
    end

    state.lastPaint = GetTime()
    SetArmed(unitFrame, isActive)
end

local function EnsureBeltTicker()
    if beltTicker or not next(armed) then return end

    beltTicker = C_Timer.NewTicker(0.1, function()
        if not next(armed) then
            beltTicker:Cancel()
            beltTicker = nil
            beltPhase = 0
            return
        end

        beltPhase = (beltPhase + 1) % 5
        local now = GetTime()
        local index = 0

        for unitFrame in pairs(armed) do
            index = index + 1
            if index % 5 == beltPhase then
                local state = GetPredictionState(unitFrame)
                if state and state.lastPaint > 0 and now - state.lastPaint >= 0.45 then
                    if MarkDirty(unitFrame) and profiling then
                        profileStats.beltMarks = profileStats.beltMarks + 1
                    end
                end
            end
        end
    end)
end

flushDriver:SetScript("OnUpdate", function(self)
    if profiling then profileStats.flushes = profileStats.flushes + 1 end

    local processed = 0
    for unitFrame in pairs(dirty) do
        dirty[unitFrame] = nil
        processed = processed + 1

        local unit = unitFrame:GetAttribute("unit")
        if not IsRaidToken(unit) then
            unit = nil
        end

        local paintStart = profiling and ProfileNow and ProfileNow()
        if unit and unitFrame:IsVisible() then
            PaintPrediction(unitFrame, unit)
        else
            ResetPredictionValues(unitFrame)
        end
        local paintEnd = profiling and ProfileNow and ProfileNow()

        if profiling then
            local elapsed = paintEnd - paintStart
            profileStats.paints = profileStats.paints + 1
            profileStats.paintMs = profileStats.paintMs + elapsed
            if elapsed > profileStats.paintMaxMs then profileStats.paintMaxMs = elapsed end
        end

        if processed >= flushBudget then break end
    end

    if not next(dirty) then self:Hide() end
    EnsureBeltTicker()
end)

local function UnmapFrame(unitFrame)
    if not unitFrame then return end
    local state = GetPredictionState(unitFrame)
    local oldUnit = state and state.mappedUnit
    if oldUnit and unitToButton[oldUnit] == unitFrame then
        unitToButton[oldUnit] = nil
    end
    if state then state.mappedUnit = nil end
    dirty[unitFrame] = nil
    ResetPredictionValues(unitFrame)
end

local function MapFrame(unitFrame, unit)
    if not unitFrame or unitFrame.isAugmentationRaidFrame or not IsRaidToken(unit) then
        UnmapFrame(unitFrame)
        return false
    end

    local state = GetPredictionState(unitFrame)
    local oldUnit = state.mappedUnit
    if oldUnit and oldUnit ~= unit and unitToButton[oldUnit] == unitFrame then
        unitToButton[oldUnit] = nil
    end

    if oldUnit ~= unit then
        ResetPredictionValues(unitFrame)
    end

    unitToButton[unit] = unitFrame
    state.mappedUnit = unit
    MarkDirty(unitFrame)
    return oldUnit ~= unit
end

local function ConfigurePredictionFrame(unitFrame, unit, isUpdate)
    if not unitFrame or unitFrame.isAugmentationRaidFrame then return end
    local health = GetPredictionHealth(unitFrame)
    local UnitDB = UUF:GetUnitDB(unitFrame, unit)
    if not health or not UnitDB or not UnitDB.HealPrediction then return end

    -- Reuse UUF's own prediction creation/configuration so appearance and healer
    -- semantics stay identical. Expose the validated direct Health bar only for
    -- this configuration call; detach it again before oUF can auto-enable Health.
    unitFrame.Health = health
    if isUpdate then
        UUF:UpdateUnitHealPrediction(unitFrame, unit)
    else
        UUF:CreateUnitHealPrediction(unitFrame, unit)
    end
    unitFrame.Health = nil

    EnsurePredictionCalculator(health)
    SizePredictionBars(health)

    local state = GetPredictionState(unitFrame)
    local AbsorbDB = UnitDB.HealPrediction.Absorbs
    state.overEnabled = AbsorbDB and AbsorbDB.Enabled and AbsorbDB.ShowOverAbsorb and AbsorbDB.Position == "ATTACH" or false

    wantsIncoming = health.HealingPlayer ~= nil
    wantsAbsorb = health.DamageAbsorb ~= nil
    wantsHealAbsorb = health.HealAbsorb ~= nil
    wantsAny = wantsIncoming or wantsAbsorb or wantsHealAbsorb
    SyncTrackerEvents()

    if not wantsAny then
        UnmapFrame(unitFrame)
        return
    end

    local liveUnit = unitFrame:GetAttribute("unit")
    if IsRaidToken(liveUnit) then
        MapFrame(unitFrame, liveUnit)
    end
end

local function HandleTrackedEvent(event, unit)
    local handlerStart = profiling and ProfileNow and ProfileNow()
    local lookupStart = handlerStart
    local unitFrame = unitToButton[unit]
    local lookupEnd = profiling and ProfileNow and ProfileNow()

    if profiling then
        profileStats.events = profileStats.events + 1
        profileStats.lookupMs = profileStats.lookupMs + (lookupEnd - lookupStart)

        if event == "UNIT_HEAL_PREDICTION" then
            profileStats.predictionEvents = profileStats.predictionEvents + 1
        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            profileStats.absorbEvents = profileStats.absorbEvents + 1
        elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            profileStats.healAbsorbEvents = profileStats.healAbsorbEvents + 1
        elseif event == "UNIT_MAXHEALTH" then
            profileStats.maxHealthEvents = profileStats.maxHealthEvents + 1
        elseif event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
            profileStats.modifierEvents = profileStats.modifierEvents + 1
        elseif event == "UNIT_CONNECTION" then
            profileStats.connectionEvents = profileStats.connectionEvents + 1
        end
    end

    if not unitFrame then
        if profiling then
            profileStats.unmapped = profileStats.unmapped + 1
            local elapsed = ProfileNow() - handlerStart
            profileStats.handlerMs = profileStats.handlerMs + elapsed
            if elapsed > profileStats.handlerMaxMs then profileStats.handlerMaxMs = elapsed end
        end
        return
    end

    MarkDirty(unitFrame)

    if profiling then
        local elapsed = ProfileNow() - handlerStart
        profileStats.handlerMs = profileStats.handlerMs + elapsed
        if elapsed > profileStats.handlerMaxMs then profileStats.handlerMaxMs = elapsed end
    end
end

for index = 1, UUF.MAX_RAID_FRAMES do
    local unit = "raid" .. index
    local tracker = CreateFrame("Frame")
    tracker.UUFMinimalPredictionRegistrations = {}
    tracker:SetScript("OnEvent", function(_, event, eventUnit)
        HandleTrackedEvent(event, eventUnit or unit)
    end)
    trackers[unit] = tracker
end

local function PrintProfile(duration)
    local stats = profileStats
    local handlerAvgUs = stats.events > 0 and (stats.handlerMs * 1000 / stats.events) or 0
    local lookupAvgUs = stats.events > 0 and (stats.lookupMs * 1000 / stats.events) or 0
    local paintAvgUs = stats.paints > 0 and (stats.paintMs * 1000 / stats.paints) or 0

    UUF:PrettyPrint(string.format(
        "|cFFFFC857RaidPredict|r RESULT %.1fs | events=%d marks=%d coalesced=%d paints=%d unmapped=%d | handler avg=%.3fus max=%.3fus | paint avg=%.3fus max=%.3fus | lookup avg=%.3fus.",
        duration,
        stats.events,
        stats.marks,
        stats.coalesced,
        stats.paints,
        stats.unmapped,
        handlerAvgUs,
        stats.handlerMaxMs * 1000,
        paintAvgUs,
        stats.paintMaxMs * 1000,
        lookupAvgUs
    ))

    UUF:PrettyPrint(string.format(
        "|cFFFFC857RaidPredict|r HEAL_PRED=%d | ABSORB=%d | HEAL_ABSORB=%d | MAX=%d | MAX_MOD=%d | CONNECTION=%d | flushes=%d belt=%d secret=%d | paint total=%.3fms.",
        stats.predictionEvents,
        stats.absorbEvents,
        stats.healAbsorbEvents,
        stats.maxHealthEvents,
        stats.modifierEvents,
        stats.connectionEvents,
        stats.flushes,
        stats.beltMarks,
        stats.secretPaints,
        stats.paintMs
    ))
end

local profileDriver = CreateFrame("Frame")
profileDriver:RegisterEvent("PLAYER_REGEN_DISABLED")
profileDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
profileDriver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if not IsInRaid() then return end
        ResetProfileStats()
        profileStartedAt = GetTime()
        profiling = true
    elseif profiling then
        local duration = math.max(GetTime() - profileStartedAt, 0)
        profiling = false
        C_Timer.After(0, function() PrintProfile(duration) end)
    end
end)

function UUF:CreateUnitFrame(unitFrame, unit)
    local result = OriginalCreateUnitFrame(self, unitFrame, unit)
    if not IsRaidUnit(unit) or not unitFrame or unitFrame.isAugmentationRaidFrame then
        return result
    end

    ConfigurePredictionFrame(unitFrame, unit, false)

    if not unitFrame.UUFMinimalRaidPredictionHooked then
        unitFrame.UUFMinimalRaidPredictionHooked = true
        unitFrame:HookScript("OnAttributeChanged", function(frame, attribute, value)
            if attribute ~= "unit" then return end
            if IsRaidToken(value) then
                MapFrame(frame, value)
            else
                UnmapFrame(frame)
            end
        end)
        unitFrame:HookScript("OnShow", function(frame)
            local state = GetPredictionState(frame)
            if state and state.mappedUnit then MarkDirty(frame) end
        end)
    end

    return result
end

function UUF:UpdateUnitFrame(unitFrame, unit)
    local result = OriginalUpdateUnitFrame(self, unitFrame, unit)
    if not IsRaidUnit(unit) or not unitFrame or unitFrame.isAugmentationRaidFrame then
        return result
    end

    ConfigurePredictionFrame(unitFrame, unit, true)
    return result
end
