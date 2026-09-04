local _, UUF = ...

local OriginalCreateUnitFrame = UUF.CreateUnitFrame
local OriginalUpdateUnitFrame = UUF.UpdateUnitFrame
local OriginalUpdateGroupIndicators = UUF.UpdateGroupIndicators
local OriginalCreateUnitTags = UUF.CreateUnitTags
local OriginalUpdateUnitTag = UUF.UpdateUnitTag
local OriginalUpdateUnitTags = UUF.UpdateUnitTags
local OriginalCreateUnitAuras = UUF.CreateUnitAuras
local OriginalUpdateUnitAuras = UUF.UpdateUnitAuras
local OriginalRefreshMidnightManagedAuras = UUF.RefreshMidnightManagedAuras
local OriginalRetargetManagedGroupAurasForUnitChange = UUF.RetargetManagedGroupAurasForUnitChange

local UnitHealthPercent = UnitHealthPercent
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitExists = UnitExists
local UnitName = UnitName
local UnitGUID = UnitGUID
local GetTime = GetTime
local C_Timer = C_Timer
local ProfileNow = debugprofilestop
local StatusBarInterpolation = Enum.StatusBarInterpolation

-- Ellesmere-style health scale: use Blizzard's own curve when available.
-- The fallback exists only for load-order safety on clients where CurveConstants
-- is not initialized yet when UUF's Core files execute.
local HealthScaleTo100 = CurveConstants and CurveConstants.ScaleTo100
if not HealthScaleTo100 then
    HealthScaleTo100 = C_CurveUtil.CreateCurve()
    HealthScaleTo100:SetType(Enum.LuaCurveType.Linear)
    HealthScaleTo100:AddPoint(0.0, 0)
    HealthScaleTo100:AddPoint(1.0, 100)
end

local unitToButton = {}
local unitTrackers = {}
local resettlePending = {}

local profiling = false
local profileStartedAt = 0
local profileStats = {}

local function ResetProfileStats()
    profileStats = {
        events = 0,
        paints = 0,
        unmapped = 0,
        handlerMs = 0,
        handlerMaxMs = 0,
        lookupMs = 0,
        paintMs = 0,
        paintMaxMs = 0,
        healthEvents = 0,
        maxHealthEvents = 0,
        modifierEvents = 0,
        connectionEvents = 0,
        nameEvents = 0,
        resettles = 0,
        resettleMs = 0,
        resettleMaxMs = 0,
    }
end
ResetProfileStats()

local function IsRaidUnit(unit)
    return type(unit) == "string" and UUF:GetNormalizedUnit(unit) == "raid"
end

local function IsRaidToken(unit)
    return type(unit) == "string" and unit:match("^raid%d+$") ~= nil
end

local function DisableAuraContainer(container)
    if not container then return end
    if container.SetEnabled then pcall(container.SetEnabled, container, false) end
    pcall(container.Hide, container)
end

local function StripMinimalRaidExtras(unitFrame)
    if not unitFrame then return end

    UUF:UnregisterRangeFrame(unitFrame)
    UUF:UnregisterTargetGlowIndicatorFrame(unitFrame)
    if unitFrame.DispelHighlightUnit then UUF:UnregisterDispelHighlightEvents(unitFrame) end

    DisableAuraContainer(unitFrame.UUFManagedTargetBuffs)
    DisableAuraContainer(unitFrame.UUFManagedTargetDebuffs)
    DisableAuraContainer(unitFrame.UUFManagedTargetDebuffsClip)
    DisableAuraContainer(unitFrame.UUFManagedPartyRaidCustomAuras)
    DisableAuraContainer(unitFrame.UUFManagedDispelHighlight)
    DisableAuraContainer(unitFrame.BuffContainer)
    DisableAuraContainer(unitFrame.DebuffContainer)
    DisableAuraContainer(unitFrame.CustomAuraContainer)
    DisableAuraContainer(unitFrame.PrivateAuraContainer)

    if unitFrame.IsElementEnabled and unitFrame.DisableElement then
        if unitFrame:IsElementEnabled("Health") then unitFrame:DisableElement("Health") end
        if unitFrame:IsElementEnabled("Auras") then unitFrame:DisableElement("Auras") end
        if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end
        if unitFrame:IsElementEnabled("Power") then unitFrame:DisableElement("Power") end
    end
end

local function ApplyMinimalRaidScripts(unitFrame)
    unitFrame:RegisterForClicks("AnyUp")
    unitFrame:SetAttribute("*type1", "target")
    unitFrame:SetAttribute("*type2", "togglemenu")
    unitFrame:HookScript("OnEnter", UnitFrame_OnEnter)
    unitFrame:HookScript("OnLeave", UnitFrame_OnLeave)
end

local function UpdateMinimalRaidName(unitFrame, unit)
    if not unitFrame or not unitFrame.UUFMinimalRaidName then return end
    local liveUnit = unit or unitFrame:GetAttribute("unit")
    local name = liveUnit and UnitName(liveUnit)
    unitFrame.UUFMinimalRaidName:SetText(name or "")
end

local function CreateMinimalRaidName(unitFrame, unit)
    if unitFrame.UUFMinimalRaidName then
        UpdateMinimalRaidName(unitFrame, unit)
        return
    end

    local GeneralDB = UUF.db.profile.General
    local fontString = unitFrame.HighLevelContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetFont(UUF.Media.Font, 12, GeneralDB.Fonts.FontFlag)
    fontString:SetPoint("CENTER", unitFrame.HighLevelContainer, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    fontString:SetJustifyV("MIDDLE")
    fontString:SetTextColor(1, 1, 1, 1)
    unitFrame.UUFMinimalRaidName = fontString
    UpdateMinimalRaidName(unitFrame, unit)
end

local function CacheNormalHealthColours(unitFrame, unit)
    local UnitDB = UUF:GetUnitDB(unitFrame, unit)
    if not UnitDB then return end

    local HealthBarDB = UnitDB.HealthBar
    local r, g, b

    if HealthBarDB.ColourByClass and unit and UnitExists(unit) then
        r, g, b = UUF:GetUnitColour(unit)
    else
        r, g, b = HealthBarDB.Foreground[1], HealthBarDB.Foreground[2], HealthBarDB.Foreground[3]
    end

    unitFrame.UUFMinimalHealthR = r
    unitFrame.UUFMinimalHealthG = g
    unitFrame.UUFMinimalHealthB = b
    unitFrame.UUFMinimalHealthA = HealthBarDB.ForegroundOpacity

    if HealthBarDB.ColourBackgroundByClass and unit and UnitExists(unit) then
        r, g, b = UUF:GetUnitColour(unit)
    else
        r, g, b = HealthBarDB.Background[1], HealthBarDB.Background[2], HealthBarDB.Background[3]
    end

    unitFrame.UUFMinimalBackgroundR = r
    unitFrame.UUFMinimalBackgroundG = g
    unitFrame.UUFMinimalBackgroundB = b
    unitFrame.UUFMinimalBackgroundA = HealthBarDB.BackgroundOpacity
    unitFrame.UUFMinimalColourBackdropWhenDead = HealthBarDB.ColourBackdropWhenDead

    unitFrame.UUFMinimalHealthState = nil
end

local function ApplyHealthState(unitFrame, connected, deadOrGhost)
    local health = unitFrame.UUFMinimalRaidHealth
    local background = unitFrame.HealthBackground
    if not health or not background then return end

    local state = not connected and 2 or deadOrGhost and 1 or 0
    if unitFrame.UUFMinimalHealthState == state then return end
    unitFrame.UUFMinimalHealthState = state

    if state == 0 then
        health:SetStatusBarColor(
            unitFrame.UUFMinimalHealthR or 1,
            unitFrame.UUFMinimalHealthG or 1,
            unitFrame.UUFMinimalHealthB or 1,
            unitFrame.UUFMinimalHealthA or 1
        )
        background:SetStatusBarColor(
            unitFrame.UUFMinimalBackgroundR or 0,
            unitFrame.UUFMinimalBackgroundG or 0,
            unitFrame.UUFMinimalBackgroundB or 0,
            unitFrame.UUFMinimalBackgroundA or 1
        )
        return
    end

    if state == 2 then
        local disconnected = UUF.oUF.colors.disconnected
        if disconnected then
            local r, g, b = disconnected:GetRGB()
            health:SetStatusBarColor(r, g, b, unitFrame.UUFMinimalHealthA or 1)
            background:SetStatusBarColor(r, g, b, unitFrame.UUFMinimalBackgroundA or 1)
        end
        return
    end

    health:SetStatusBarColor(
        unitFrame.UUFMinimalHealthR or 1,
        unitFrame.UUFMinimalHealthG or 1,
        unitFrame.UUFMinimalHealthB or 1,
        unitFrame.UUFMinimalHealthA or 1
    )

    if unitFrame.UUFMinimalColourBackdropWhenDead and UUF.oUF.colors.deadBackdrop then
        local r, g, b = UUF.oUF.colors.deadBackdrop:GetRGB()
        background:SetStatusBarColor(r, g, b, unitFrame.UUFMinimalBackgroundA or 1)
    else
        background:SetStatusBarColor(
            unitFrame.UUFMinimalBackgroundR or 0,
            unitFrame.UUFMinimalBackgroundG or 0,
            unitFrame.UUFMinimalBackgroundB or 0,
            unitFrame.UUFMinimalBackgroundA or 1
        )
    end
end

local function ApplyDirectHealthAppearance(unitFrame, unit)
    local health = unitFrame and unitFrame.UUFMinimalRaidHealth
    local background = unitFrame and unitFrame.HealthBackground
    local UnitDB = unitFrame and UUF:GetUnitDB(unitFrame, unit)
    if not health or not background or not UnitDB then return end

    local FrameDB = UnitDB.Frame
    local HealthBarDB = UnitDB.HealthBar

    unitFrame:SetSize(FrameDB.Width, FrameDB.Height)
    health:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
    background:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)

    health:SetStatusBarTexture(UUF.Media.Foreground)
    background:SetStatusBarTexture(UUF.Media.Background)

    health:SetMinMaxValues(0, 100)
    background:SetMinMaxValues(0, 1)
    background:SetValue(1)
    background:SetReverseFill(false)

    health.UUFMinimalSmoothing = HealthBarDB.Smooth ~= false
        and StatusBarInterpolation.ExponentialEaseOut
        or StatusBarInterpolation.Immediate

    health:SetReverseFill(HealthBarDB.Inverse == true)

    CacheNormalHealthColours(unitFrame, unit)
end

local function PaintRaidHealth(unitFrame, unit)
    local health = unitFrame and unitFrame.UUFMinimalRaidHealth
    if not health or not unit or not UnitExists(unit) then return end

    -- Ellesmere hot path: one engine-side percent conversion and a permanently
    -- fixed 0-100 StatusBar. No prediction calculator and no second missing-HP
    -- percentage calculation on UNIT_HEALTH.
    local pct = UnitHealthPercent(unit, true, HealthScaleTo100)
    local connected = UnitIsConnected(unit)
    local deadOrGhost = UnitIsDeadOrGhost(unit)

    health:SetValue(pct, health.UUFMinimalSmoothing)
    ApplyHealthState(unitFrame, connected, deadOrGhost)
end

local function UnmapRaidFrame(unitFrame)
    if not unitFrame then return end
    local oldUnit = unitFrame.UUFMinimalMappedUnit
    if oldUnit and unitToButton[oldUnit] == unitFrame then
        unitToButton[oldUnit] = nil
    end
    unitFrame.UUFMinimalMappedUnit = nil
    unitFrame.UUFMinimalMappedGUID = nil
end

local function MapRaidFrame(unitFrame, unit)
    if not unitFrame or unitFrame.isAugmentationRaidFrame then return false end
    if not IsRaidToken(unit) then
        UnmapRaidFrame(unitFrame)
        return false
    end

    local oldUnit = unitFrame.UUFMinimalMappedUnit
    if oldUnit and oldUnit ~= unit and unitToButton[oldUnit] == unitFrame then
        unitToButton[oldUnit] = nil
    end

    unitToButton[unit] = unitFrame
    unitFrame.UUFMinimalMappedUnit = unit

    local guid = UnitGUID(unit)
    if UUF:IsSecretValue(guid) then guid = nil end

    if guid and unitFrame.UUFMinimalMappedGUID == guid then
        return false
    end

    unitFrame.UUFMinimalMappedGUID = guid
    CacheNormalHealthColours(unitFrame, unit)
    UpdateMinimalRaidName(unitFrame, unit)
    return true
end

local function QueueHealthResettle(unit)
    if resettlePending[unit] then return end
    resettlePending[unit] = true

    C_Timer.After(0, function()
        resettlePending[unit] = nil
        local button = unitToButton[unit]
        if not button or not button:IsVisible() then return end

        if profiling and ProfileNow then
            local startTime = ProfileNow()
            PaintRaidHealth(button, unit)
            local elapsed = ProfileNow() - startTime
            profileStats.resettles = profileStats.resettles + 1
            profileStats.resettleMs = profileStats.resettleMs + elapsed
            if elapsed > profileStats.resettleMaxMs then profileStats.resettleMaxMs = elapsed end
        else
            PaintRaidHealth(button, unit)
        end
    end)
end

local function HandleTrackedUnitEvent(event, unit)
    local handlerStart = profiling and ProfileNow and ProfileNow()
    local lookupStart = handlerStart
    local button = unitToButton[unit]
    local lookupEnd = profiling and ProfileNow and ProfileNow()

    if profiling then
        profileStats.events = profileStats.events + 1
        if event == "UNIT_HEALTH" then
            profileStats.healthEvents = profileStats.healthEvents + 1
        elseif event == "UNIT_MAXHEALTH" then
            profileStats.maxHealthEvents = profileStats.maxHealthEvents + 1
        elseif event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
            profileStats.modifierEvents = profileStats.modifierEvents + 1
        elseif event == "UNIT_CONNECTION" then
            profileStats.connectionEvents = profileStats.connectionEvents + 1
        elseif event == "UNIT_NAME_UPDATE" then
            profileStats.nameEvents = profileStats.nameEvents + 1
        end

        profileStats.lookupMs = profileStats.lookupMs + (lookupEnd - lookupStart)
    end

    if not button then
        if profiling then
            profileStats.unmapped = profileStats.unmapped + 1
            local handlerElapsed = ProfileNow() - handlerStart
            profileStats.handlerMs = profileStats.handlerMs + handlerElapsed
            if handlerElapsed > profileStats.handlerMaxMs then profileStats.handlerMaxMs = handlerElapsed end
        end
        return
    end

    if event == "UNIT_NAME_UPDATE" or event == "UNIT_CONNECTION" then
        button.UUFMinimalMappedGUID = nil
        MapRaidFrame(button, unit)
    end

    local paintStart = profiling and ProfileNow and ProfileNow()
    PaintRaidHealth(button, unit)
    local paintEnd = profiling and ProfileNow and ProfileNow()

    if profiling then
        local paintElapsed = paintEnd - paintStart
        profileStats.paints = profileStats.paints + 1
        profileStats.paintMs = profileStats.paintMs + paintElapsed
        if paintElapsed > profileStats.paintMaxMs then profileStats.paintMaxMs = paintElapsed end
    end

    if event == "UNIT_MAXHEALTH" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        QueueHealthResettle(unit)
    end

    if profiling then
        local handlerElapsed = ProfileNow() - handlerStart
        profileStats.handlerMs = profileStats.handlerMs + handlerElapsed
        if handlerElapsed > profileStats.handlerMaxMs then profileStats.handlerMaxMs = handlerElapsed end
    end
end

-- Ellesmere architecture: fixed tracker per raid token, created once and never
-- re-registered as secure headers reorder occupants. WoW filters UNIT_* delivery
-- C-side before Lua sees it.
for index = 1, UUF.MAX_RAID_FRAMES do
    local unit = "raid" .. index
    local tracker = CreateFrame("Frame")
    tracker:RegisterUnitEvent("UNIT_HEALTH", unit)
    tracker:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    tracker:RegisterUnitEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", unit)
    tracker:RegisterUnitEvent("UNIT_CONNECTION", unit)
    tracker:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    tracker:SetScript("OnEvent", function(_, event, eventUnit)
        HandleTrackedUnitEvent(event, eventUnit or unit)
    end)
    unitTrackers[unit] = tracker
end

local function PrintRaidPathResult(duration)
    local stats = profileStats
    local paintAvgUs = stats.paints > 0 and (stats.paintMs * 1000 / stats.paints) or 0
    local handlerAvgUs = stats.events > 0 and (stats.handlerMs * 1000 / stats.events) or 0
    local lookupAvgUs = stats.events > 0 and (stats.lookupMs * 1000 / stats.events) or 0
    local resettleAvgUs = stats.resettles > 0 and (stats.resettleMs * 1000 / stats.resettles) or 0

    UUF:PrettyPrint(string.format(
        "|cFF78DCE8RaidPath|r RESULT %.1fs | events=%d paints=%d unmapped=%d | handler avg=%.3fus max=%.3fus | paint avg=%.3fus max=%.3fus | lookup avg=%.3fus.",
        duration,
        stats.events,
        stats.paints,
        stats.unmapped,
        handlerAvgUs,
        stats.handlerMaxMs * 1000,
        paintAvgUs,
        stats.paintMaxMs * 1000,
        lookupAvgUs
    ))

    UUF:PrettyPrint(string.format(
        "|cFF78DCE8RaidPath|r UNIT_HEALTH=%d | MAX=%d | MAX_MOD=%d | CONNECTION=%d | NAME=%d | resettle=%d avg=%.3fus max=%.3fus | paint total=%.3fms.",
        stats.healthEvents,
        stats.maxHealthEvents,
        stats.modifierEvents,
        stats.connectionEvents,
        stats.nameEvents,
        stats.resettles,
        resettleAvgUs,
        stats.resettleMaxMs * 1000,
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
        C_Timer.After(0, function() PrintRaidPathResult(duration) end)
    end
end)

local function CreateEllesmereStyleRaidHealth(unitFrame, unit)
    UUF:CreateUnitHealthBar(unitFrame, unit)

    -- Keep UUF's StatusBar/texture/layout, but remove the oUF Health element
    -- BEFORE oUF's auto-enable pass. The bar is then owned only by the fixed
    -- raid-token trackers above.
    unitFrame.UUFMinimalRaidHealth = unitFrame.Health
    unitFrame.Health = nil

    ApplyDirectHealthAppearance(unitFrame, unit)
end

function UUF:CreateUnitFrame(unitFrame, unit)
    if not IsRaidUnit(unit) then
        return OriginalCreateUnitFrame(self, unitFrame, unit)
    end

    if not unitFrame then return end
    if unitFrame:GetParent() == UUF.AUGMENTATION_RAID_HEADER then
        unitFrame.isAugmentationRaidFrame = true
    end

    UUF:CreateUnitContainer(unitFrame, unit)
    CreateEllesmereStyleRaidHealth(unitFrame, unit)
    CreateMinimalRaidName(unitFrame, unit)
    StripMinimalRaidExtras(unitFrame)

    unitFrame.UUFConfiguredUnit = unit
    unitFrame:HookScript("OnAttributeChanged", function(frame, attribute, value)
        if attribute ~= "unit" then return end

        if not value then
            frame.UUFGroupUnit = nil
            UnmapRaidFrame(frame)
            if frame.UUFMinimalRaidName then frame.UUFMinimalRaidName:SetText("") end
            StripMinimalRaidExtras(frame)
            return
        end

        frame.UUFGroupUnit = value
        local identityChanged = MapRaidFrame(frame, value)
        if identityChanged then
            ApplyDirectHealthAppearance(frame, value)
        end
        PaintRaidHealth(frame, value)
        StripMinimalRaidExtras(frame)
    end)

    local liveUnit = unitFrame:GetAttribute("unit")
    if liveUnit then
        MapRaidFrame(unitFrame, liveUnit)
        ApplyDirectHealthAppearance(unitFrame, liveUnit)
        PaintRaidHealth(unitFrame, liveUnit)
    end

    ApplyMinimalRaidScripts(unitFrame)
    UUF:RegisterRaidFrame(unitFrame)
    return unitFrame
end

function UUF:UpdateUnitFrame(unitFrame, unit)
    if not IsRaidUnit(unit) then
        return OriginalUpdateUnitFrame(self, unitFrame, unit)
    end

    if not unitFrame then return end
    local UnitDB = UUF:GetUnitDB(unitFrame, unit)
    if not UnitDB then return end

    StripMinimalRaidExtras(unitFrame)

    local liveUnit = unitFrame:GetAttribute("unit") or unitFrame.UUFMinimalMappedUnit
    if liveUnit then
        MapRaidFrame(unitFrame, liveUnit)
        ApplyDirectHealthAppearance(unitFrame, liveUnit)
        UpdateMinimalRaidName(unitFrame, liveUnit)
        PaintRaidHealth(unitFrame, liveUnit)
    else
        unitFrame:SetSize(UnitDB.Frame.Width, UnitDB.Frame.Height)
    end

    unitFrame:SetFrameStrata(UnitDB.Frame.FrameStrata)
end

function UUF:UpdateGroupIndicators(groupType, onlyUpdateRoles)
    if groupType ~= "raid" then
        return OriginalUpdateGroupIndicators(self, groupType, onlyUpdateRoles)
    end

    UUF:ForEachRaidFrame(function(raidFrame)
        StripMinimalRaidExtras(raidFrame)
        raidFrame.UUFGroupUnit = raidFrame.unit
    end, true, UUF.RAID_TEST_MODE)
end

function UUF:CreateUnitTags(unitFrame, unit)
    if IsRaidUnit(unit) then return end
    return OriginalCreateUnitTags(self, unitFrame, unit)
end

function UUF:UpdateUnitTag(unitFrame, unit, tagDB)
    if IsRaidUnit(unit) then return end
    return OriginalUpdateUnitTag(self, unitFrame, unit, tagDB)
end

function UUF:UpdateUnitTags(unit, tagName)
    if IsRaidUnit(unit) then return end
    return OriginalUpdateUnitTags(self, unit, tagName)
end

function UUF:CreateUnitAuras(unitFrame, unit)
    if IsRaidUnit(unit) then
        StripMinimalRaidExtras(unitFrame)
        return
    end
    return OriginalCreateUnitAuras(self, unitFrame, unit)
end

function UUF:UpdateUnitAuras(unitFrame, unit)
    if IsRaidUnit(unit) then
        StripMinimalRaidExtras(unitFrame)
        return
    end
    return OriginalUpdateUnitAuras(self, unitFrame, unit)
end

if type(OriginalRefreshMidnightManagedAuras) == "function" then
    function UUF:RefreshMidnightManagedAuras(unitFrame, unit, ...)
        if IsRaidUnit(unit) then
            StripMinimalRaidExtras(unitFrame)
            return
        end
        return OriginalRefreshMidnightManagedAuras(self, unitFrame, unit, ...)
    end
end

if type(OriginalRetargetManagedGroupAurasForUnitChange) == "function" then
    function UUF:RetargetManagedGroupAurasForUnitChange(unitFrame, unit, ...)
        if IsRaidUnit(unit) then
            StripMinimalRaidExtras(unitFrame)
            return
        end
        return OriginalRetargetManagedGroupAurasForUnitChange(self, unitFrame, unit, ...)
    end
end
