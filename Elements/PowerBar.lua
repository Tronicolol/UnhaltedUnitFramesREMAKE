local _, UUF = ...

local POWER_SMOOTH_INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local POWER_IMMEDIATE_INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

local function ApplyPowerUpdateMode(element, smooth)
    if not element then return end

    -- Midnight 12.0+ provides native StatusBar interpolation. Smooth is a visual
    -- option; it must not opt the element into the higher-rate UNIT_POWER_FREQUENT
    -- stream. Keep normal UNIT_POWER_UPDATE cadence and let the StatusBar animate.
    element.smoothing = smooth and POWER_SMOOTH_INTERPOLATION or POWER_IMMEDIATE_INTERPOLATION

    if element.SetFrequentUpdates then
        -- When the element is already enabled this also repairs registrations
        -- created by an older configuration/runtime state.
        element:SetFrequentUpdates(false)
    else
        -- During initial style construction oUF has not attached the method yet.
        element.frequentUpdates = false
    end
end

local function ShouldShowUnitPowerBar(unitFrame, unit, PowerBarDB)
	if not PowerBarDB.Enabled then return false end
	if not PowerBarDB.OnlyShowHealers then return true end
	local normalizedUnit = UUF:GetNormalizedUnit(unit)
	if normalizedUnit ~= "party" and normalizedUnit ~= "raid" then return true end
	local unitToken = unit == "partyplayer" and "player" or unit
	return UnitGroupRolesAssigned(unitToken) == "HEALER"
end

local function CreatePowerBarPostUpdateColor(unitFrame, unit)
    return function(element, _, color, altR, altG, altB)
        local PowerBarDB = UUF:GetUnitDB(unitFrame, unit).PowerBar
        if not element.Background then return end

        if not PowerBarDB.ColourBackgroundByType then
            if element.BackgroundDarken then element.BackgroundDarken:Hide() end
            return
        end

        local mult = PowerBarDB.BackgroundMultiplier or 0.75
        local r, g, b

        if altR and altG and altB then
            r, g, b = altR, altG, altB
        elseif color then
            r, g, b = color:GetRGB()
        else
            r, g, b = element:GetStatusBarColor()
        end

        if not r or not g or not b then return end

        local rSecret = UUF:IsSecretValue(r)
        local gSecret = UUF:IsSecretValue(g)
        local bSecret = UUF:IsSecretValue(b)

        if rSecret or gSecret or bSecret then
            -- Midnight 12.1:
            -- los RGB de un StatusBar pueden ser secret. No se puede hacer
            -- aritmética con ellos, pero sí pasarlos a APIs que aceptan secrets.
            element.Background:SetVertexColor(r, g, b, PowerBarDB.Background[4] or 1)

            -- Simulamos el BackgroundMultiplier mediante una capa negra.
            -- Aquí solo hacemos aritmética con 'mult', que viene de la DB y
            -- nunca es un valor secret.
            if element.BackgroundDarken then
                element.BackgroundDarken:SetAlpha(1 - mult)
                element.BackgroundDarken:Show()
            end
        else
            -- Camino normal: conserva exactamente el comportamiento original.
            element.Background:SetVertexColor(
                r * mult,
                g * mult,
                b * mult,
                PowerBarDB.Background[4] or 1
            )
            if element.BackgroundDarken then element.BackgroundDarken:Hide() end
        end
    end
end

local function LayoutUnitPowerBar(unitFrame, unit, width)
    local PowerBarDB = UUF:GetUnitDB(unitFrame, unit).PowerBar
    local powerBar = unitFrame.Power
    if not powerBar then return end

    width = width and width > 0 and width or UUF:GetUnitDB(unitFrame, unit).Frame.Width
	local position = UUF:GetConfiguredPowerBarPosition(unit, unitFrame)
    local isTopAnchored = position == "TOP"
    local anchorPoint = isTopAnchored and "TOPLEFT" or "BOTTOMLEFT"
    local anchorY = isTopAnchored and -1 or 1

    powerBar:ClearAllPoints()
    powerBar:SetPoint(anchorPoint, unitFrame.Container, anchorPoint, 1, anchorY)
    powerBar:SetSize(width - 2, PowerBarDB.Height)

    if powerBar.Background then
        powerBar.Background:ClearAllPoints()
        powerBar.Background:SetPoint(anchorPoint, unitFrame.Container, anchorPoint, 1, anchorY)
        powerBar.Background:SetSize(width - 2, PowerBarDB.Height)
    end

    if powerBar.PowerBarBorder then
        powerBar.PowerBarBorder:ClearAllPoints()
        if isTopAnchored then
            powerBar.PowerBarBorder:SetPoint("BOTTOMLEFT", powerBar, "BOTTOMLEFT", 0, -1)
            powerBar.PowerBarBorder:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMRIGHT", 0, -1)
        else
            powerBar.PowerBarBorder:SetPoint("TOPLEFT", powerBar, "TOPLEFT", 0, 1)
            powerBar.PowerBarBorder:SetPoint("TOPRIGHT", powerBar, "TOPRIGHT", 0, 1)
        end
    end
end

function UUF:CreateUnitPowerBar(unitFrame, unit)
    local FrameDB = UUF:GetUnitDB(unitFrame, unit).Frame
    local PowerBarDB = UUF:GetUnitDB(unitFrame, unit).PowerBar
    local unitContainer = unitFrame.Container

    local PowerBar = CreateFrame("StatusBar", UUF:FetchFrameName(unit) .. "_PowerBar", unitContainer)
    PowerBar:SetPoint("BOTTOMLEFT", unitContainer, "BOTTOMLEFT", 1, 1)
    PowerBar:SetSize(FrameDB.Width - 2, PowerBarDB.Height)
    PowerBar:SetStatusBarTexture(UUF.Media.Foreground)
    PowerBar:SetStatusBarColor(PowerBarDB.Foreground[1], PowerBarDB.Foreground[2], PowerBarDB.Foreground[3], PowerBarDB.Foreground[4] or 1)
    PowerBar:SetFrameLevel(unitContainer:GetFrameLevel() + 2)
    PowerBar.colorPower = PowerBarDB.ColourByType
    PowerBar.colorClass = PowerBarDB.ColourByClass
    ApplyPowerUpdateMode(PowerBar, PowerBarDB.Smooth)
    PowerBar.PostUpdateColor = CreatePowerBarPostUpdateColor(unitFrame, unit)
	unitFrame.PowerBar = PowerBar

    if PowerBarDB.Inverse then
        PowerBar:SetReverseFill(true)
    else
        PowerBar:SetReverseFill(false)
    end

    PowerBar.Background = PowerBar:CreateTexture(UUF:FetchFrameName(unit) .. "_PowerBackground", "BACKGROUND")
    PowerBar.Background:SetPoint("BOTTOMLEFT", unitContainer, "BOTTOMLEFT", 1, 1)
    PowerBar.Background:SetSize(FrameDB.Width - 2, PowerBarDB.Height)
    PowerBar.Background:SetTexture(UUF.Media.Background)
    PowerBar.Background:SetVertexColor(PowerBarDB.Background[1], PowerBarDB.Background[2], PowerBarDB.Background[3], PowerBarDB.Background[4] or 1)

    -- Capa de oscurecimiento para colores secret de Midnight 12.1.
    -- Se crea fuera del callback para no tener que crear regiones en combate.
    PowerBar.BackgroundDarken = PowerBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    PowerBar.BackgroundDarken:SetAllPoints(PowerBar.Background)
    PowerBar.BackgroundDarken:SetTexture("Interface\\Buttons\\WHITE8X8")
    PowerBar.BackgroundDarken:SetVertexColor(0, 0, 0, 1)
    PowerBar.BackgroundDarken:Hide()

    if not PowerBar.PowerBarBorder then
        PowerBar.PowerBarBorder = PowerBar:CreateTexture(nil, "OVERLAY")
        PowerBar.PowerBarBorder:SetHeight(1)
        PowerBar.PowerBarBorder:SetTexture("Interface\\Buttons\\WHITE8x8")
        PowerBar.PowerBarBorder:SetVertexColor(0, 0, 0, 1)
        PowerBar.PowerBarBorder:SetPoint("TOPLEFT", PowerBar, "TOPLEFT", 0, 1)
        PowerBar.PowerBarBorder:SetPoint("TOPRIGHT", PowerBar, "TOPRIGHT", 0, 1)
    end

    if ShouldShowUnitPowerBar(unitFrame, unit, PowerBarDB) then
        unitFrame.Power = PowerBar
        PowerBar:Show()
        if unitFrame.PowerBackground then unitFrame.PowerBackground:Show() end
    else
        if unitFrame:IsElementEnabled("Power") then unitFrame:DisableElement("Power") end
        PowerBar:Hide()
        if unitFrame.PowerBackground then unitFrame.PowerBackground:Hide() end
    end

    if unitFrame.Power then
        LayoutUnitPowerBar(unitFrame, unit, FrameDB.Width)
    end
    UUF:UpdateHealthBarLayout(unitFrame, unit)

    return PowerBar
end

function UUF:UpdateUnitPowerBar(unitFrame, unit)
    local FrameDB = UUF:GetUnitDB(unitFrame, unit).Frame
    local PowerBarDB = UUF:GetUnitDB(unitFrame, unit).PowerBar

    if ShouldShowUnitPowerBar(unitFrame, unit, PowerBarDB) then
		unitFrame.Power = unitFrame.Power or unitFrame.PowerBar or UUF:CreateUnitPowerBar(unitFrame, unit)

        if not unitFrame:IsElementEnabled("Power") then unitFrame:EnableElement("Power") end

        if unitFrame.Power then
            LayoutUnitPowerBar(unitFrame, unit, unitFrame:GetWidth())
            unitFrame.Power:SetStatusBarColor(PowerBarDB.Foreground[1], PowerBarDB.Foreground[2], PowerBarDB.Foreground[3], PowerBarDB.Foreground[4] or 1)
            unitFrame.Power:SetStatusBarTexture(UUF.Media.Foreground)
            unitFrame.Power.colorPower = PowerBarDB.ColourByType
            unitFrame.Power.colorClass = PowerBarDB.ColourByClass
            ApplyPowerUpdateMode(unitFrame.Power, PowerBarDB.Smooth)
            if PowerBarDB.Inverse then
                unitFrame.Power:SetReverseFill(true)
            else
                unitFrame.Power:SetReverseFill(false)
            end
        end

        if unitFrame.Power.Background then
            unitFrame.Power.Background:SetVertexColor(PowerBarDB.Background[1], PowerBarDB.Background[2], PowerBarDB.Background[3], PowerBarDB.Background[4] or 1)
            unitFrame.Power.Background:SetTexture(UUF.Media.Background)
            if unitFrame.Power.BackgroundDarken and not PowerBarDB.ColourBackgroundByType then
                unitFrame.Power.BackgroundDarken:Hide()
            end
        end

        unitFrame.Power:Show()
        unitFrame.Power:ForceUpdate()
    else
        if unitFrame.Power then
            if unitFrame:IsElementEnabled("Power") then unitFrame:DisableElement("Power") end
            unitFrame.Power:Hide()
            unitFrame.Power = nil
        end
        UUF:UpdateHealthBarLayout(unitFrame, unit)
        return
    end

    UUF:UpdateHealthBarLayout(unitFrame, unit)
end
