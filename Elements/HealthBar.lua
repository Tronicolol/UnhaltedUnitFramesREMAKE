local _, UUF = ...
local StatusBarInterpolation = Enum.StatusBarInterpolation
local oUF = UUF.oUF

-- Midnight 12.1: addon-owned reverse 0-100 curve for secret-safe health values.
-- We keep the optimized Party/Raid path independent from the global CurveConstants
-- load state so the StatusBar always receives values in the range it was configured for.
local UUFReverseTo100Curve = C_CurveUtil.CreateCurve()
UUFReverseTo100Curve:SetType(Enum.LuaCurveType.Linear)
UUFReverseTo100Curve:AddPoint(0.0, 100)
UUFReverseTo100Curve:AddPoint(1.0, 0)

local function SetHealthBackgroundColour(unitFrame, unit, HealthBarDB, forceUpdate)
	local backgroundUnit = unitFrame.unit or unit
	local isDead = HealthBarDB.ColourBackdropWhenDead and UnitIsDeadOrGhost(backgroundUnit)
	local backgroundClass
	local backgroundReaction
	if HealthBarDB.ColourBackgroundByClass then
		local unitToColour = backgroundUnit ~= "pet" and backgroundUnit or "player"
		local queriedClass = select(2, UnitClass(unitToColour))

		-- Midnight 12.1: no guardar ni comparar una clase secret.
		if queriedClass and not UUF:IsSecretValue(queriedClass) then
			backgroundClass = queriedClass
		else
			backgroundReaction = UnitReaction(unitToColour, "player")
		end
	end
	if not forceUpdate and unitFrame.HealthBackgroundClass == backgroundClass and unitFrame.HealthBackgroundReaction == backgroundReaction and unitFrame.HealthBackgroundIsDead == isDead then return end
	unitFrame.HealthBackgroundClass = backgroundClass
	unitFrame.HealthBackgroundReaction = backgroundReaction
	unitFrame.HealthBackgroundIsDead = isDead

    if isDead then
        local deadBackdropColour = oUF.colors.deadBackdrop
        local r, g, b = deadBackdropColour:GetRGB()
        unitFrame.HealthBackground:SetStatusBarColor(r, g, b, HealthBarDB.BackgroundOpacity)
    elseif HealthBarDB.ColourBackgroundByClass then
        local unitToColour = backgroundUnit ~= "pet" and backgroundUnit or "player"
        local r, g, b = UUF:GetUnitColour(unitToColour)
        unitFrame.HealthBackground:SetStatusBarColor(r, g, b, HealthBarDB.BackgroundOpacity)
    else
        unitFrame.HealthBackground:SetStatusBarColor(HealthBarDB.Background[1], HealthBarDB.Background[2], HealthBarDB.Background[3], HealthBarDB.BackgroundOpacity)
    end
end

function UUF:CreateUnitHealthBar(unitFrame, unit)
    local FrameDB = UUF:GetUnitDB(unitFrame, unit).Frame
    local HealthBarDB = UUF:GetUnitDB(unitFrame, unit).HealthBar
    local unitContainer = unitFrame.Container

    if not unitFrame.HealthBar then
        if not unitFrame.HealthBackground then
            unitFrame.HealthBackground = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_HealthBackground", unitContainer)
            unitFrame.HealthBackground:SetPoint("TOPLEFT", unitContainer, "TOPLEFT", 1, -1)
            unitFrame.HealthBackground:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
            unitFrame.HealthBackground:SetStatusBarTexture(UUF.Media.Background)
            unitFrame.HealthBackground:SetFrameLevel(unitContainer:GetFrameLevel() + 1)
            SetHealthBackgroundColour(unitFrame, unit, HealthBarDB, true)
        end

        local HealthBar = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_HealthBar", unitContainer)
        HealthBar:SetPoint("TOPLEFT", unitContainer, "TOPLEFT", 1, -1)
        HealthBar:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
        HealthBar:SetStatusBarTexture(UUF.Media.Foreground)
        HealthBar:SetFrameLevel(unitContainer:GetFrameLevel() + 2)
        HealthBar:SetStatusBarColor(HealthBarDB.Foreground[1], HealthBarDB.Foreground[2], HealthBarDB.Foreground[3], HealthBarDB.ForegroundOpacity)
        HealthBar.colorClass = HealthBarDB.ColourByClass
        HealthBar.colorReaction = HealthBarDB.ColourByClass
        HealthBar.colorHealth = false
        HealthBar.colorTapping = HealthBarDB.ColourWhenTapped
        HealthBar.colorDisconnected = HealthBarDB.ColourWhenDisconnected
        HealthBar.smoothing = HealthBarDB.Smooth ~= false and StatusBarInterpolation.ExponentialEaseOut or StatusBarInterpolation.Immediate
		HealthBar.PostUpdateColor = function(healthBar, unit, colour)
			if colour and colour ~= oUF.colors.health then return end
			local currentHealthBarDB = UUF:GetUnitDB(unitFrame, unit).HealthBar
			if unit == "pet" and currentHealthBarDB.ColourByClass then
				local unitColour = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
				if unitColour then healthBar:SetStatusBarColor(unitColour.r, unitColour.g, unitColour.b, currentHealthBarDB.ForegroundOpacity) return end
			end
			healthBar:SetStatusBarColor(currentHealthBarDB.Foreground[1], currentHealthBarDB.Foreground[2], currentHealthBarDB.Foreground[3], currentHealthBarDB.ForegroundOpacity)
		end

        if unit == "pet" and HealthBarDB.ColourByClass then
            HealthBar.colorClass = false
            HealthBar.colorReaction = false
            HealthBar.colorHealth = false
        end

        unitFrame.Health = HealthBar

        unitFrame.Health.PostUpdate = function(_, _, curHP, maxHP)
            local unitHP = unitFrame.HealthBackground
            local frameUnit = unitFrame.unit or unit

            -- Party/Raid lean-health path: the foreground Health bar is a 0-100
            -- percent bar, so keep the missing-health background on the same
            -- clean percentage scale. UnitHealthPercent + ScaleTo100 is safe for
            -- restricted group health values and avoids the full prediction
            -- calculator on every UNIT_HEALTH tick.
            if unitFrame.UUFGroupLeanHealth then
                -- Midnight 12.1: the health percentage can be secret on a tainted
                -- execution path, so Lua must not calculate 100 - curHP. Ask the
                -- native curve API for the reversed 0-100 value and pass that
                -- secret value directly to StatusBar:SetValue().
                local missingHealthPercent = UnitHealthPercent(frameUnit, true, UUFReverseTo100Curve)
                unitHP:SetMinMaxValues(0, 100)
                unitHP:SetValue(missingHealthPercent, unitFrame.Health.smoothing)
            else
                maxHP = maxHP or 1
                curHP = curHP or 0
                unitHP:SetMinMaxValues(0, maxHP)
                unitHP:SetValue(UnitHealthMissing(frameUnit, true), unitFrame.Health.smoothing)
            end

			SetHealthBackgroundColour(unitFrame, unit, UUF:GetUnitDB(unitFrame, unit).HealthBar)
        end

        if HealthBarDB.Inverse then
            unitFrame.Health:SetReverseFill(true)
            unitFrame.HealthBackground:SetReverseFill(false)
        else
            unitFrame.Health:SetReverseFill(false)
            unitFrame.HealthBackground:SetReverseFill(true)
        end

    end
end

function UUF:UpdateUnitHealthBar(unitFrame, unit)
    local FrameDB = UUF:GetUnitDB(unitFrame, unit).Frame
    local HealthBarDB = UUF:GetUnitDB(unitFrame, unit).HealthBar
    local DispelHighlightDB = UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight

    if unitFrame then
        unitFrame:ClearAllPoints()
        unitFrame:SetSize(FrameDB.Width, FrameDB.Height)
        if unit == "player" or unit == "target" then
            local parentFrame = UUF:GetUnitDB(unitFrame, unit).HealthBar.AnchorToCooldownViewer and _G["UUF_CDMAnchor"] or UIParent
            UUF[unit:upper()]:SetPoint(FrameDB.Layout[1], parentFrame, FrameDB.Layout[2], FrameDB.Layout[3], FrameDB.Layout[4])
            UUF[unit:upper()]:SetSize(FrameDB.Width, FrameDB.Height)
        elseif unit == "targettarget" or unit == "focus" or unit == "focustarget" or unit == "pet" then
            local parentFrame = _G[UUF:GetUnitDB(unitFrame, unit).Frame.AnchorParent] or UIParent
            UUF[unit:upper()]:SetPoint(FrameDB.Layout[1], parentFrame, FrameDB.Layout[2], FrameDB.Layout[3], FrameDB.Layout[4])
            UUF[unit:upper()]:SetSize(FrameDB.Width, FrameDB.Height)
        end
    end

    if unitFrame.Health then
        unitFrame.Health:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
        unitFrame.Health:SetStatusBarColor(HealthBarDB.Foreground[1], HealthBarDB.Foreground[2], HealthBarDB.Foreground[3], HealthBarDB.ForegroundOpacity)
        unitFrame.Health.colorClass = HealthBarDB.ColourByClass
        unitFrame.Health.colorReaction = HealthBarDB.ColourByClass
        unitFrame.Health.colorHealth = false
        unitFrame.Health.colorTapping = HealthBarDB.ColourWhenTapped
        unitFrame.Health.colorDisconnected = HealthBarDB.ColourWhenDisconnected
        unitFrame.Health.smoothing = HealthBarDB.Smooth ~= false and StatusBarInterpolation.ExponentialEaseOut or StatusBarInterpolation.Immediate
        unitFrame.Health:SetStatusBarTexture(UUF.Media.Foreground)
        if unit == "pet" and HealthBarDB.ColourByClass then
            unitFrame.Health.colorClass = false
            unitFrame.Health.colorReaction = false
            unitFrame.Health.colorHealth = false
        end
    end

    if unitFrame.HealthBackground then
        unitFrame.HealthBackground:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
        SetHealthBackgroundColour(unitFrame, unit, HealthBarDB, true)
        unitFrame.HealthBackground:SetStatusBarTexture(UUF.Media.Background)
    end

    if HealthBarDB.Inverse then
        unitFrame.Health:SetReverseFill(true)
        unitFrame.HealthBackground:SetReverseFill(false)
    else
        unitFrame.Health:SetReverseFill(false)
        unitFrame.HealthBackground:SetReverseFill(true)
    end

    if unitFrame.DispelHighlight then
        UUF:UpdateUnitDispelHighlight(unitFrame, unit)
    end

    unitFrame.Health:ForceUpdate()
end
