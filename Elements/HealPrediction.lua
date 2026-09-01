local _, UUF = ...

-- Midnight 12.1: addon-owned 0-100 curve for the optimized health path.
-- Without an explicit curve UnitHealthPercent returns 0-1; feeding that into
-- a 0-100 StatusBar makes a full-health frame look almost empty/colourless.
local UUFScaleTo100Curve = C_CurveUtil.CreateCurve()
UUFScaleTo100Curve:SetType(Enum.LuaCurveType.Linear)
UUFScaleTo100Curve:AddPoint(0.0, 0)
UUFScaleTo100Curve:AddPoint(1.0, 100)

local function CreateIncomingHeal(unitFrame, unit)
    local IncomingHealDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.IncomingHeal
    if not unitFrame.Health then return end

    local IncomingHealBar = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_IncomingHealBar", unitFrame.Health)
    if IncomingHealDB.UseStripedTexture then IncomingHealBar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else IncomingHealBar:SetStatusBarTexture(UUF.Media.Foreground) end
    IncomingHealBar:SetStatusBarColor(IncomingHealDB.Colour[1], IncomingHealDB.Colour[2], IncomingHealDB.Colour[3], IncomingHealDB.Colour[4])
    IncomingHealBar:ClearAllPoints()
    local position = IncomingHealDB.Position
    local height = IncomingHealDB.MatchParentHeight and unitFrame.Health:GetHeight() or IncomingHealDB.Height
    IncomingHealBar:SetHeight(height)

    if position == "ATTACH" then
        unitFrame.Health:SetClipsChildren(true)
        if unitFrame.Health:GetReverseFill() then
            IncomingHealBar:SetPoint("TOPRIGHT", unitFrame.Health:GetStatusBarTexture(), "TOPLEFT", 0, 0)
            IncomingHealBar:SetReverseFill(true)
        else
            IncomingHealBar:SetPoint("TOPLEFT", unitFrame.Health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            IncomingHealBar:SetReverseFill(false)
        end
    elseif position == "TOPLEFT" then
        IncomingHealBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        IncomingHealBar:SetReverseFill(false)
    elseif position == "TOPRIGHT" then
        IncomingHealBar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        IncomingHealBar:SetReverseFill(true)
    elseif position == "BOTTOMLEFT" then
        IncomingHealBar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        IncomingHealBar:SetReverseFill(false)
    elseif position == "BOTTOMRIGHT" then
        IncomingHealBar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        IncomingHealBar:SetReverseFill(true)
    elseif position == "LEFT" then
        IncomingHealBar:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
        IncomingHealBar:SetReverseFill(false)
    elseif position == "RIGHT" then
        IncomingHealBar:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
        IncomingHealBar:SetReverseFill(true)
    else
        IncomingHealBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        IncomingHealBar:SetReverseFill(false)
    end
    IncomingHealBar:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 1)
    IncomingHealBar:Show()

    return IncomingHealBar
end

local function CreateUnitAbsorbs(unitFrame, unit)
    local AbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    if not unitFrame.Health then return end

    local AbsorbBar = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_AbsorbBar", unitFrame.Health)
    if AbsorbDB.UseStripedTexture then AbsorbBar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else AbsorbBar:SetStatusBarTexture(UUF.Media.Foreground) end
    AbsorbBar:SetStatusBarColor(AbsorbDB.Colour[1], AbsorbDB.Colour[2], AbsorbDB.Colour[3], AbsorbDB.Colour[4])
    AbsorbBar:ClearAllPoints()
    local position = AbsorbDB.Position
    local height = AbsorbDB.MatchParentHeight and unitFrame.Health:GetHeight() or AbsorbDB.Height
    AbsorbBar:SetHeight(height)

    if position == "ATTACH" then
        unitFrame.Health:SetClipsChildren(true)
        AbsorbBar:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
        AbsorbBar:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
        if unitFrame.Health:GetReverseFill() then
            AbsorbBar:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
            AbsorbBar:SetReverseFill(true)
        else
            AbsorbBar:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
            AbsorbBar:SetReverseFill(false)
        end
    elseif position == "TOPLEFT" then
        AbsorbBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        AbsorbBar:SetReverseFill(false)
    elseif position == "TOPRIGHT" then
        AbsorbBar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        AbsorbBar:SetReverseFill(true)
    elseif position == "BOTTOMLEFT" then
        AbsorbBar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        AbsorbBar:SetReverseFill(false)
    elseif position == "BOTTOMRIGHT" then
        AbsorbBar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        AbsorbBar:SetReverseFill(true)
    elseif position == "LEFT" then
        AbsorbBar:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
        AbsorbBar:SetReverseFill(false)
    elseif position == "RIGHT" then
        AbsorbBar:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
        AbsorbBar:SetReverseFill(true)
    else
        AbsorbBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        AbsorbBar:SetReverseFill(false)
    end
    AbsorbBar:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 1)
    AbsorbBar:Show()

    return AbsorbBar
end

local function ConfigureUnitOverAbsorbs(OverAbsorbBar, unitFrame, unit)
    local AbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    local OverAbsorbClip = OverAbsorbBar.Clip
    if AbsorbDB.UseStripedTexture then OverAbsorbBar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else OverAbsorbBar:SetStatusBarTexture(UUF.Media.Foreground) end
    OverAbsorbBar:SetStatusBarColor(AbsorbDB.Colour[1], AbsorbDB.Colour[2], AbsorbDB.Colour[3], AbsorbDB.Colour[4])
    OverAbsorbClip:ClearAllPoints()
    OverAbsorbBar:ClearAllPoints()
    local height = AbsorbDB.MatchParentHeight and unitFrame.Health:GetHeight() or AbsorbDB.Height
    OverAbsorbClip:SetHeight(height)
    OverAbsorbBar:SetHeight(height)

    if unitFrame.Health:GetReverseFill() then
        OverAbsorbClip:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        OverAbsorbClip:SetPoint("BOTTOMLEFT", unitFrame.Health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
        OverAbsorbBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        OverAbsorbBar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        OverAbsorbBar:SetReverseFill(false)
    else
        OverAbsorbClip:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        OverAbsorbClip:SetPoint("BOTTOMRIGHT", unitFrame.Health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        OverAbsorbBar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        OverAbsorbBar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        OverAbsorbBar:SetReverseFill(true)
    end
    OverAbsorbClip:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 2)
    OverAbsorbBar:SetFrameLevel(OverAbsorbClip:GetFrameLevel() + 1)
end

local function CreateUnitOverAbsorbs(unitFrame, unit)
    if not unitFrame.Health then return end

    local OverAbsorbClip = CreateFrame("Frame", UUF:FetchFrameName(unit) .. "_OverAbsorbClip", unitFrame.Health)
    OverAbsorbClip:SetClipsChildren(true)

    local OverAbsorbBar = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_OverAbsorbBar", OverAbsorbClip)
    OverAbsorbBar.Clip = OverAbsorbClip
    ConfigureUnitOverAbsorbs(OverAbsorbBar, unitFrame, unit)
    OverAbsorbBar:Hide()
    OverAbsorbClip:Hide()

    return OverAbsorbBar
end

local function CreateUnitHealAbsorbs(unitFrame, unit)
    local HealAbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.HealAbsorbs
    if not unitFrame.Health then return end

    local HealAbsorbBar = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_HealAbsorbBar", unitFrame.Health)
    if HealAbsorbDB.UseStripedTexture then HealAbsorbBar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else HealAbsorbBar:SetStatusBarTexture(UUF.Media.Foreground) end
    HealAbsorbBar:SetStatusBarColor(HealAbsorbDB.Colour[1], HealAbsorbDB.Colour[2], HealAbsorbDB.Colour[3], HealAbsorbDB.Colour[4])
    HealAbsorbBar:ClearAllPoints()
    local position = HealAbsorbDB.Position
    local height = HealAbsorbDB.MatchParentHeight and unitFrame.Health:GetHeight() or HealAbsorbDB.Height
    HealAbsorbBar:SetHeight(height)

    if position == "ATTACH" then
        unitFrame.Health:SetClipsChildren(true)
        HealAbsorbBar:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
        HealAbsorbBar:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
        if unitFrame.Health:GetReverseFill() then
            HealAbsorbBar:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
            HealAbsorbBar:SetReverseFill(false)
        else
            HealAbsorbBar:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
            HealAbsorbBar:SetReverseFill(true)
        end
    elseif position == "TOPLEFT" then
        HealAbsorbBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        HealAbsorbBar:SetReverseFill(false)
    elseif position == "TOPRIGHT" then
        HealAbsorbBar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        HealAbsorbBar:SetReverseFill(true)
    elseif position == "BOTTOMLEFT" then
        HealAbsorbBar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        HealAbsorbBar:SetReverseFill(false)
    elseif position == "BOTTOMRIGHT" then
        HealAbsorbBar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        HealAbsorbBar:SetReverseFill(true)
    elseif position == "LEFT" then
        HealAbsorbBar:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
        HealAbsorbBar:SetReverseFill(false)
    elseif position == "RIGHT" then
        HealAbsorbBar:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
        HealAbsorbBar:SetReverseFill(true)
    else
        HealAbsorbBar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        HealAbsorbBar:SetReverseFill(false)
    end
    HealAbsorbBar:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 3)
    HealAbsorbBar:Show()

    return HealAbsorbBar
end

local function UpdateUnitOverAbsorbs(unitFrame, unit)
    local AbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    if not unitFrame.HealthPrediction or not unitFrame.HealthPrediction.damageAbsorb then return end

    if not AbsorbDB.Enabled or not AbsorbDB.ShowOverAbsorb or AbsorbDB.Position ~= "ATTACH" then
        if unitFrame.HealthPrediction.overDamageAbsorb then
            unitFrame.HealthPrediction.overDamageAbsorb:Hide()
            unitFrame.HealthPrediction.overDamageAbsorb.Clip:Hide()
        end
        return
    end

    unitFrame.HealthPrediction.overDamageAbsorb = unitFrame.HealthPrediction.overDamageAbsorb or CreateUnitOverAbsorbs(unitFrame, unit)
    local OverAbsorbBar = unitFrame.HealthPrediction.overDamageAbsorb
    if not OverAbsorbBar then return end

    ConfigureUnitOverAbsorbs(OverAbsorbBar, unitFrame, unit)
    OverAbsorbBar:SetMinMaxValues(unitFrame.HealthPrediction.damageAbsorb:GetMinMaxValues())
    OverAbsorbBar:SetValue(unitFrame.HealthPrediction.damageAbsorb:GetValue())
    OverAbsorbBar:SetWidth(unitFrame.Health:GetWidth())
    OverAbsorbBar.Clip:Show()
    OverAbsorbBar:Show()
end


-- Unified prediction optimization for all UUF unit frames: use oUF's Health
-- prediction sub-widgets instead of the deprecated standalone HealthPrediction
-- element. Health already owns a prediction calculator, so this avoids a second
-- UnitGetDetailedHealPrediction pass on every health/absorb update.
local OptimizedPredictionUnits = {
    player = true,
    target = true,
    targettarget = true,
    pet = true,
    focus = true,
    focustarget = true,
    party = true,
    raid = true,
    boss = true,
}

local function IsOptimizedPredictionUnit(unit)
    if type(unit) ~= "string" then return false end
    local normalizedUnit = UUF:GetNormalizedUnit(unit)
    return OptimizedPredictionUnits[normalizedUnit] == true
end

local function ResetGroupPredictionBar(bar)
    if not bar then return end
    -- Prediction bars are persistent/reused. Clear any previous unit/value before
    -- showing/reconfiguring them so a stale heal-absorb/absorb colour cannot
    -- cover the health bar until the next prediction event arrives.
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
end

local function ConfigureGroupIncomingHealBar(bar, unitFrame, unit)
    local DB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.IncomingHeal
    ResetGroupPredictionBar(bar)
    if DB.UseStripedTexture then bar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else bar:SetStatusBarTexture(UUF.Media.Foreground) end
    bar:SetStatusBarColor(DB.Colour[1], DB.Colour[2], DB.Colour[3], DB.Colour[4])
    bar:ClearAllPoints()
    local position = DB.Position
    local height = DB.MatchParentHeight and unitFrame.Health:GetHeight() or DB.Height
    bar:SetHeight(height)

    if position == "ATTACH" then
        unitFrame.Health:SetClipsChildren(true)
        if unitFrame.Health:GetReverseFill() then
            bar:SetPoint("TOPRIGHT", unitFrame.Health:GetStatusBarTexture(), "TOPLEFT", 0, 0)
            bar:SetReverseFill(true)
        else
            bar:SetPoint("TOPLEFT", unitFrame.Health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            bar:SetReverseFill(false)
        end
    elseif position == "TOPLEFT" then
        bar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "TOPRIGHT" then
        bar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        bar:SetReverseFill(true)
    elseif position == "BOTTOMLEFT" then
        bar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "BOTTOMRIGHT" then
        bar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        bar:SetReverseFill(true)
    elseif position == "LEFT" then
        bar:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "RIGHT" then
        bar:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
        bar:SetReverseFill(true)
    else
        bar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        bar:SetReverseFill(false)
    end
    bar:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 1)
    bar:Show()
end

local function ConfigureGroupAbsorbBar(bar, unitFrame, unit)
    local DB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    ResetGroupPredictionBar(bar)
    if DB.UseStripedTexture then bar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else bar:SetStatusBarTexture(UUF.Media.Foreground) end
    bar:SetStatusBarColor(DB.Colour[1], DB.Colour[2], DB.Colour[3], DB.Colour[4])
    bar:ClearAllPoints()
    local position = DB.Position
    local height = DB.MatchParentHeight and unitFrame.Health:GetHeight() or DB.Height
    bar:SetHeight(height)

    if position == "ATTACH" then
        unitFrame.Health:SetClipsChildren(true)
        bar:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
        bar:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
        if unitFrame.Health:GetReverseFill() then
            bar:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
            bar:SetReverseFill(true)
        else
            bar:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
            bar:SetReverseFill(false)
        end
    elseif position == "TOPLEFT" then
        bar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "TOPRIGHT" then
        bar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        bar:SetReverseFill(true)
    elseif position == "BOTTOMLEFT" then
        bar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "BOTTOMRIGHT" then
        bar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        bar:SetReverseFill(true)
    elseif position == "LEFT" then
        bar:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "RIGHT" then
        bar:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
        bar:SetReverseFill(true)
    else
        bar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        bar:SetReverseFill(false)
    end
    bar:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 1)
    bar:Show()
end

local function ConfigureGroupHealAbsorbBar(bar, unitFrame, unit)
    local DB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.HealAbsorbs
    ResetGroupPredictionBar(bar)
    if DB.UseStripedTexture then bar:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else bar:SetStatusBarTexture(UUF.Media.Foreground) end
    bar:SetStatusBarColor(DB.Colour[1], DB.Colour[2], DB.Colour[3], DB.Colour[4])
    bar:ClearAllPoints()
    local position = DB.Position
    local height = DB.MatchParentHeight and unitFrame.Health:GetHeight() or DB.Height
    bar:SetHeight(height)

    if position == "ATTACH" then
        unitFrame.Health:SetClipsChildren(true)
        bar:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
        bar:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
        if unitFrame.Health:GetReverseFill() then
            bar:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
            bar:SetReverseFill(false)
        else
            bar:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
            bar:SetReverseFill(true)
        end
    elseif position == "TOPLEFT" then
        bar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "TOPRIGHT" then
        bar:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
        bar:SetReverseFill(true)
    elseif position == "BOTTOMLEFT" then
        bar:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "BOTTOMRIGHT" then
        bar:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
        bar:SetReverseFill(true)
    elseif position == "LEFT" then
        bar:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
        bar:SetReverseFill(false)
    elseif position == "RIGHT" then
        bar:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
        bar:SetReverseFill(true)
    else
        bar:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
        bar:SetReverseFill(false)
    end
    bar:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 3)
    bar:Show()
end

local function UpdateGroupOverAbsorbs(unitFrame, unit)
    local state = unitFrame.UUFGroupPredictionBars
    local damageAbsorb = unitFrame.Health and unitFrame.Health.DamageAbsorb
    local over = state and state.overDamageAbsorb
    if not state or not over or not damageAbsorb then return end

    local DB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    if not DB.Enabled or not DB.ShowOverAbsorb or DB.Position ~= "ATTACH" then
        over:Hide()
        over.Clip:Hide()
        return
    end

    over:SetMinMaxValues(damageAbsorb:GetMinMaxValues())
    over:SetValue(damageAbsorb:GetValue())
    over.Clip:Show()
    over:Show()
end

-- UUF 12.1 health fast path.
--
-- oUF's generic Health element calls UnitGetDetailedHealPrediction() for every
-- UNIT_HEALTH event because the same element also owns prediction/absorb bars.
-- Without a split path every health tick pays the prediction-calculator
-- cost even when only the health fill changed. Optimized UUF frames split those jobs:
--   * UNIT_HEALTH -> clean UnitHealthPercent() paint only.
--   * absorb/prediction events -> one coalesced calculator pass next render frame.
--
-- This keeps the event split validated on Party/Raid while
-- preserving UUF's existing absorb/heal-absorb visuals.
local GroupPredictionDirty = {}
local GroupPredictionDriver = CreateFrame("Frame")
GroupPredictionDriver:Hide()

local GroupPredictionEvents = {
    UNIT_ABSORB_AMOUNT_CHANGED = true,
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
    UNIT_HEAL_PREDICTION = true,
    UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
}

local function HasGroupPredictionWidgets(health)
    return health and (health.HealingAll or health.HealingPlayer or health.HealingOther
        or health.DamageAbsorb or health.HealAbsorb)
end

local function UpdateGroupPredictionValues(unitFrame, unit)
    if unitFrame and unitFrame.UUFTestModeActive then return end
    local health = unitFrame and unitFrame.Health
    if not health or not health.values or not unit or not HasGroupPredictionWidgets(health) then return end

    UnitGetDetailedHealPrediction(unit, "player", health.values)
    local maxHealth = health.values:GetMaximumHealth()

    if health.HealingAll or health.HealingPlayer or health.HealingOther then
        local allHeal, playerHeal, otherHeal = health.values:GetIncomingHeals()
        if health.HealingAll then
            health.HealingAll:SetMinMaxValues(0, maxHealth)
            health.HealingAll:SetValue(allHeal)
        end
        if health.HealingPlayer then
            health.HealingPlayer:SetMinMaxValues(0, maxHealth)
            health.HealingPlayer:SetValue(playerHeal)
        end
        if health.HealingOther then
            health.HealingOther:SetMinMaxValues(0, maxHealth)
            health.HealingOther:SetValue(otherHeal)
        end
    end

    if health.DamageAbsorb then
        local damageAbsorbAmount = health.values:GetDamageAbsorbs()
        health.DamageAbsorb:SetMinMaxValues(0, maxHealth)
        health.DamageAbsorb:SetValue(damageAbsorbAmount)

        -- Outside restricted states this lets health ticks repaint over-absorb
        -- only while a shield is actually present. If the amount is secret we
        -- fail open after an absorb event: correctness wins over skipping a
        -- calculator pass for that shielded unit.
        if not UUF:IsSecretValue(damageAbsorbAmount) then
            unitFrame.UUFGroupAbsorbActive = damageAbsorbAmount > 0
        end
    else
        unitFrame.UUFGroupAbsorbActive = false
    end

    if health.HealAbsorb then
        local healAbsorbAmount = health.values:GetHealAbsorbs()
        health.HealAbsorb:SetMinMaxValues(0, maxHealth)
        health.HealAbsorb:SetValue(healAbsorbAmount)
    end

    UpdateGroupOverAbsorbs(unitFrame, unit)
end

local function MarkGroupPredictionDirty(unitFrame, unit, absorbEvent)
    if not unitFrame or unitFrame.UUFTestModeActive or not unitFrame.Health or not HasGroupPredictionWidgets(unitFrame.Health) then return end
    if absorbEvent and unitFrame.Health.DamageAbsorb then
        -- A restricted absorb amount cannot be compared in addon Lua. Arm the
        -- health ride immediately; a later non-secret calculator result clears it.
        unitFrame.UUFGroupAbsorbActive = true
    end
    GroupPredictionDirty[unitFrame] = unit
    GroupPredictionDriver:Show()
end

GroupPredictionDriver:SetScript("OnUpdate", function(self)
    self:Hide()
    for unitFrame, unit in pairs(GroupPredictionDirty) do
        GroupPredictionDirty[unitFrame] = nil
        UpdateGroupPredictionValues(unitFrame, unit)
    end
end)

local function GroupLeanHealthOverride(owner, event, unit)
    if owner.UUFTestModeActive then return end
    if not unit or owner.unit ~= unit then return end
    local health = owner.Health
    if not health then return end

    if GroupPredictionEvents[event] then
        MarkGroupPredictionDirty(owner, unit, event == "UNIT_ABSORB_AMOUNT_CHANGED")
        return
    end

    if health.PreUpdate then health:PreUpdate(unit) end

    local healthPercent = UnitHealthPercent(unit, true, UUFScaleTo100Curve)
    if not health.UUFGroupPercentRange then
        health:SetMinMaxValues(0, 100)
        health.UUFGroupPercentRange = true
    end

    local connected = UnitIsConnected(unit)
    local displayHealth = healthPercent
    if not UUF:IsSecretValue(connected) and connected == false then
        displayHealth = 100
    end
    health:SetValue(displayHealth, health.smoothing)

    -- Deprecated oUF compatibility fields. Group frames intentionally expose a
    -- percent range here; UUF itself does not consume these fields.
    health.cur = displayHealth
    health.max = 100

    if health.PostUpdate then health:PostUpdate(unit, displayHealth, 100, 0) end

    -- Maximum-health changes alter absorb/prediction scaling. A health tick only
    -- needs a prediction repaint while over-absorb tracking is armed.
    if event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION"
        or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE"
        or event == "ForceUpdate" then
        MarkGroupPredictionDirty(owner, unit, false)
    elseif event == "UNIT_HEALTH" and owner.UUFGroupAbsorbActive then
        local DB = UUF:GetUnitDB(owner, unit).HealPrediction.Absorbs
        if DB.Enabled and DB.ShowOverAbsorb and DB.Position == "ATTACH" then
            MarkGroupPredictionDirty(owner, unit, false)
        end
    end
end

local function InstallGroupLeanHealth(unitFrame)
    local health = unitFrame and unitFrame.Health
    if not health then return end
    unitFrame.UUFGroupLeanHealth = true
    health.Override = GroupLeanHealthOverride
    health.UUFGroupForcePredictionUpdate = function()
        UpdateGroupPredictionValues(unitFrame, unitFrame.unit)
    end
    health.UUFGroupForceHealthUpdate = function()
        GroupLeanHealthOverride(unitFrame, "UNIT_HEALTH", unitFrame.unit)
    end
end

local function ApplyGroupUnifiedPrediction(unitFrame, unit, isInitialCreate)
    if not unitFrame.Health then return end

    local IncomingHealDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.IncomingHeal
    local AbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    local HealAbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.HealAbsorbs
    local health = unitFrame.Health
    local state = unitFrame.UUFGroupPredictionBars or {}
    unitFrame.UUFGroupPredictionBars = state
    unitFrame.UUFGroupUnifiedPrediction = true

    -- These are calculator options used by the Health element itself.
    health.damageAbsorbClampMode = 2
    health.healAbsorbClampMode = 1
    health.healAbsorbMode = 1

    local hadIncoming = health.HealingPlayer ~= nil
    local hadAbsorb = health.DamageAbsorb ~= nil
    local hadHealAbsorb = health.HealAbsorb ~= nil

    if IncomingHealDB.Enabled then
        state.incomingHeal = state.incomingHeal or CreateIncomingHeal(unitFrame, unit)
        ConfigureGroupIncomingHealBar(state.incomingHeal, unitFrame, unit)
        health.HealingPlayer = state.incomingHeal
    else
        if state.incomingHeal then
            ResetGroupPredictionBar(state.incomingHeal)
            state.incomingHeal:Hide()
        end
        health.HealingPlayer = nil
    end

    if AbsorbDB.Enabled then
        state.damageAbsorb = state.damageAbsorb or CreateUnitAbsorbs(unitFrame, unit)
        ConfigureGroupAbsorbBar(state.damageAbsorb, unitFrame, unit)
        health.DamageAbsorb = state.damageAbsorb

        if AbsorbDB.ShowOverAbsorb and AbsorbDB.Position == "ATTACH" then
            state.overDamageAbsorb = state.overDamageAbsorb or CreateUnitOverAbsorbs(unitFrame, unit)
            if state.overDamageAbsorb then
                ConfigureUnitOverAbsorbs(state.overDamageAbsorb, unitFrame, unit)
                state.overDamageAbsorb:SetWidth(unitFrame.Health:GetWidth())
            end
        elseif state.overDamageAbsorb then
            state.overDamageAbsorb:Hide()
            state.overDamageAbsorb.Clip:Hide()
        end
    else
        if state.damageAbsorb then
            ResetGroupPredictionBar(state.damageAbsorb)
            state.damageAbsorb:Hide()
        end
        health.DamageAbsorb = nil
        if state.overDamageAbsorb then
            state.overDamageAbsorb:Hide()
            state.overDamageAbsorb.Clip:Hide()
        end
    end

    if HealAbsorbDB.Enabled then
        state.healAbsorb = state.healAbsorb or CreateUnitHealAbsorbs(unitFrame, unit)
        ConfigureGroupHealAbsorbBar(state.healAbsorb, unitFrame, unit)
        health.HealAbsorb = state.healAbsorb
    else
        if state.healAbsorb then
            ResetGroupPredictionBar(state.healAbsorb)
            state.healAbsorb:Hide()
        end
        health.HealAbsorb = nil
    end

    InstallGroupLeanHealth(unitFrame)

    if not isInitialCreate then
        local registrationChanged = hadIncoming ~= (health.HealingPlayer ~= nil)
            or hadAbsorb ~= (health.DamageAbsorb ~= nil)
            or hadHealAbsorb ~= (health.HealAbsorb ~= nil)

        local frameUnit = unitFrame.unit or (unit == "partyplayer" and "player" or unit)

        if registrationChanged and unitFrame.IsElementEnabled and unitFrame:IsElementEnabled("Health") then
            unitFrame:DisableElement("Health", frameUnit)
            unitFrame:EnableElement("Health", frameUnit)
            if health.HealingPlayer then health.HealingPlayer:Show() end
            if health.DamageAbsorb then health.DamageAbsorb:Show() end
            if health.HealAbsorb then health.HealAbsorb:Show() end
        end

        -- A settings change can reconfigure persistent prediction bars without
        -- changing which widgets are enabled. In that case oUF does not run its
        -- Enable() path, so the prediction calculator can retain the previous
        -- predicted state until a later game event. This was visible as a stale
        -- Heal Absorb/Absorb tint covering the health bar after changing options;
        -- toggling the checkbox fixed it because Disable/Enable resets the
        -- calculator. Do that reset explicitly for every configuration refresh,
        -- then repaint immediately from the current unit state.
        if not unitFrame.UUFTestModeActive then
            if health.ForceUpdate then health:ForceUpdate() end
            if health.values and health.values.ResetPredictedValues then
                health.values:ResetPredictedValues()
            end
            UpdateGroupPredictionValues(unitFrame, frameUnit)
            GroupPredictionDirty[unitFrame] = nil
        end
    end
end

function UUF:CreateUnitHealPrediction(unitFrame, unit)
    if IsOptimizedPredictionUnit(unit) then
        ApplyGroupUnifiedPrediction(unitFrame, unit, true)
        return
    end

    local IncomingHealDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.IncomingHeal
    local AbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    local HealAbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.HealAbsorbs

    unitFrame.HealthPrediction = {
        healingPlayer = IncomingHealDB.Enabled and CreateIncomingHeal(unitFrame, unit),
        damageAbsorb = AbsorbDB.Enabled and CreateUnitAbsorbs(unitFrame, unit),
        damageAbsorbClampMode = 2,
        overDamageAbsorb = AbsorbDB.Enabled and AbsorbDB.ShowOverAbsorb and AbsorbDB.Position == "ATTACH" and CreateUnitOverAbsorbs(unitFrame, unit),
        healAbsorb = HealAbsorbDB.Enabled and CreateUnitHealAbsorbs(unitFrame, unit),
        healAbsorbClampMode = 1,
        healAbsorbMode = 1,
        PostUpdate = function(_, updateUnit) UpdateUnitOverAbsorbs(unitFrame, updateUnit) end,
    }
end

function UUF:UpdateUnitHealPrediction(unitFrame, unit)
    if IsOptimizedPredictionUnit(unit) then
        ApplyGroupUnifiedPrediction(unitFrame, unit, false)
        return
    end

    local IncomingHealDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.IncomingHeal
    local AbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.Absorbs
    local HealAbsorbDB = UUF:GetUnitDB(unitFrame, unit).HealPrediction.HealAbsorbs

    if unitFrame.HealthPrediction then
        if IncomingHealDB.Enabled then
            unitFrame.HealthPrediction.healingPlayer = unitFrame.HealthPrediction.healingPlayer or CreateIncomingHeal(unitFrame, unit)
            unitFrame.HealthPrediction.healingPlayerClampMode = 2
            unitFrame.HealthPrediction.healingPlayer:Show()
            if IncomingHealDB.UseStripedTexture then unitFrame.HealthPrediction.healingPlayer:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else unitFrame.HealthPrediction.healingPlayer:SetStatusBarTexture(UUF.Media.Foreground) end
            unitFrame.HealthPrediction.healingPlayer:SetStatusBarColor(IncomingHealDB.Colour[1], IncomingHealDB.Colour[2], IncomingHealDB.Colour[3], IncomingHealDB.Colour[4])
            unitFrame.HealthPrediction.healingPlayer:ClearAllPoints()
            local position = IncomingHealDB.Position
            local height = IncomingHealDB.MatchParentHeight and unitFrame.Health:GetHeight() or IncomingHealDB.Height
            unitFrame.HealthPrediction.healingPlayer:SetHeight(height)

            if position == "ATTACH" then
                unitFrame.Health:SetClipsChildren(true)
                unitFrame.HealthPrediction.healingPlayer:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
                if unitFrame.Health:GetReverseFill() then
                    unitFrame.HealthPrediction.healingPlayer:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
                    unitFrame.HealthPrediction.healingPlayer:SetReverseFill(true)
                else
                    unitFrame.HealthPrediction.healingPlayer:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
                    unitFrame.HealthPrediction.healingPlayer:SetReverseFill(false)
                end
            elseif position == "TOPLEFT" then
                unitFrame.HealthPrediction.healingPlayer:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(false)
            elseif position == "TOPRIGHT" then
                unitFrame.HealthPrediction.healingPlayer:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(true)
            elseif position == "BOTTOMLEFT" then
                unitFrame.HealthPrediction.healingPlayer:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(false)
            elseif position == "BOTTOMRIGHT" then
                unitFrame.HealthPrediction.healingPlayer:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(true)
            elseif position == "LEFT" then
                unitFrame.HealthPrediction.healingPlayer:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(false)
            elseif position == "RIGHT" then
                unitFrame.HealthPrediction.healingPlayer:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(true)
            else
                unitFrame.HealthPrediction.healingPlayer:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
                unitFrame.HealthPrediction.healingPlayer:SetReverseFill(false)
            end
            unitFrame.HealthPrediction:ForceUpdate()
        else
            if unitFrame.HealthPrediction.healingPlayer then
                unitFrame.HealthPrediction.healingPlayer:Hide()
            end
        end
        if AbsorbDB.Enabled then
            unitFrame.HealthPrediction.damageAbsorb = unitFrame.HealthPrediction.damageAbsorb or CreateUnitAbsorbs(unitFrame, unit)
            unitFrame.HealthPrediction.damageAbsorbClampMode = 2
            unitFrame.HealthPrediction.PostUpdate = function(_, updateUnit) UpdateUnitOverAbsorbs(unitFrame, updateUnit) end
            unitFrame.HealthPrediction.damageAbsorb:Show()
            if AbsorbDB.UseStripedTexture then unitFrame.HealthPrediction.damageAbsorb:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else unitFrame.HealthPrediction.damageAbsorb:SetStatusBarTexture(UUF.Media.Foreground) end
            unitFrame.HealthPrediction.damageAbsorb:SetStatusBarColor(AbsorbDB.Colour[1], AbsorbDB.Colour[2], AbsorbDB.Colour[3], AbsorbDB.Colour[4])
            unitFrame.HealthPrediction.damageAbsorb:ClearAllPoints()
            local position = AbsorbDB.Position
            local height = AbsorbDB.MatchParentHeight and unitFrame.Health:GetHeight() or AbsorbDB.Height
            unitFrame.HealthPrediction.damageAbsorb:SetHeight(height)

            if position == "ATTACH" then
                unitFrame.Health:SetClipsChildren(true)
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
                if unitFrame.Health:GetReverseFill() then
                    unitFrame.HealthPrediction.damageAbsorb:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
                    unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(true)
                else
                    unitFrame.HealthPrediction.damageAbsorb:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
                    unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(false)
                end
            elseif position == "TOPLEFT" then
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(false)
            elseif position == "TOPRIGHT" then
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(true)
            elseif position == "BOTTOMLEFT" then
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(false)
            elseif position == "BOTTOMRIGHT" then
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(true)
            elseif position == "LEFT" then
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(false)
            elseif position == "RIGHT" then
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(true)
            else
                unitFrame.HealthPrediction.damageAbsorb:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
                unitFrame.HealthPrediction.damageAbsorb:SetReverseFill(false)
            end

            if AbsorbDB.ShowOverAbsorb and position == "ATTACH" then
                unitFrame.HealthPrediction.overDamageAbsorb = unitFrame.HealthPrediction.overDamageAbsorb or CreateUnitOverAbsorbs(unitFrame, unit)
                if unitFrame.HealthPrediction.overDamageAbsorb then ConfigureUnitOverAbsorbs(unitFrame.HealthPrediction.overDamageAbsorb, unitFrame, unit) end
            elseif unitFrame.HealthPrediction.overDamageAbsorb then
                unitFrame.HealthPrediction.overDamageAbsorb:Hide()
                unitFrame.HealthPrediction.overDamageAbsorb.Clip:Hide()
            end
            unitFrame.HealthPrediction:ForceUpdate()
        else
            if unitFrame.HealthPrediction.damageAbsorb then
                unitFrame.HealthPrediction.damageAbsorb:Hide()
            end
            if unitFrame.HealthPrediction.overDamageAbsorb then
                unitFrame.HealthPrediction.overDamageAbsorb:Hide()
                unitFrame.HealthPrediction.overDamageAbsorb.Clip:Hide()
            end
        end
        if HealAbsorbDB.Enabled then
            unitFrame.HealthPrediction.healAbsorb = unitFrame.HealthPrediction.healAbsorb or CreateUnitHealAbsorbs(unitFrame, unit)
            unitFrame.HealthPrediction.healAbsorbClampMode = 1
            unitFrame.HealthPrediction.healAbsorb:Show()
            if HealAbsorbDB.UseStripedTexture then unitFrame.HealthPrediction.healAbsorb:SetStatusBarTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\ThinStripes.png") else unitFrame.HealthPrediction.healAbsorb:SetStatusBarTexture(UUF.Media.Foreground) end
            unitFrame.HealthPrediction.healAbsorb:SetStatusBarColor(HealAbsorbDB.Colour[1], HealAbsorbDB.Colour[2], HealAbsorbDB.Colour[3], HealAbsorbDB.Colour[4])
            unitFrame.HealthPrediction.healAbsorb:ClearAllPoints()
            local position = HealAbsorbDB.Position
            local height = HealAbsorbDB.MatchParentHeight and unitFrame.Health:GetHeight() or HealAbsorbDB.Height
            unitFrame.HealthPrediction.healAbsorb:SetHeight(height)

            if position == "ATTACH" then
                unitFrame.Health:SetClipsChildren(true)
                unitFrame.HealthPrediction.healAbsorb:SetPoint("TOP", unitFrame.Health, "TOP", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetPoint("BOTTOM", unitFrame.Health, "BOTTOM", 0, 0)
                if unitFrame.Health:GetReverseFill() then
                    unitFrame.HealthPrediction.healAbsorb:SetPoint("LEFT", unitFrame.Health:GetStatusBarTexture(), "LEFT", 0, 0)
                    unitFrame.HealthPrediction.healAbsorb:SetReverseFill(false)
                else
                    unitFrame.HealthPrediction.healAbsorb:SetPoint("RIGHT", unitFrame.Health:GetStatusBarTexture(), "RIGHT", 0, 0)
                    unitFrame.HealthPrediction.healAbsorb:SetReverseFill(true)
                end
            elseif position == "TOPLEFT" then
                unitFrame.HealthPrediction.healAbsorb:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(false)
            elseif position == "TOPRIGHT" then
                unitFrame.HealthPrediction.healAbsorb:SetPoint("TOPRIGHT", unitFrame.Health, "TOPRIGHT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(true)
            elseif position == "BOTTOMLEFT" then
                unitFrame.HealthPrediction.healAbsorb:SetPoint("BOTTOMLEFT", unitFrame.Health, "BOTTOMLEFT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(false)
            elseif position == "BOTTOMRIGHT" then
                unitFrame.HealthPrediction.healAbsorb:SetPoint("BOTTOMRIGHT", unitFrame.Health, "BOTTOMRIGHT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(true)
            elseif position == "LEFT" then
                unitFrame.HealthPrediction.healAbsorb:SetPoint("LEFT", unitFrame.Health, "LEFT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(false)
            elseif position == "RIGHT" then
                unitFrame.HealthPrediction.healAbsorb:SetPoint("RIGHT", unitFrame.Health, "RIGHT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(true)
            else
                unitFrame.HealthPrediction.healAbsorb:SetPoint("TOPLEFT", unitFrame.Health, "TOPLEFT", 0, 0)
                unitFrame.HealthPrediction.healAbsorb:SetReverseFill(false)
            end
            unitFrame.HealthPrediction.healAbsorb:SetFrameLevel(unitFrame.Health:GetFrameLevel() + 3)
            unitFrame.HealthPrediction:ForceUpdate()
        else
            if unitFrame.HealthPrediction.healAbsorb then
                unitFrame.HealthPrediction.healAbsorb:Hide()
            end
        end
    else
        UUF:CreateUnitHealPrediction(unitFrame, unit)
    end
end
