local _, UUF = ...

local function RaiseManagedAuraContainer(unitFrame, container)
    if not unitFrame or not container then return end

    local baseLevel = unitFrame:GetFrameLevel()
    if unitFrame.Container and unitFrame.Container.GetFrameLevel then
        baseLevel = math.max(baseLevel, unitFrame.Container:GetFrameLevel())
    end
    if unitFrame.Health and unitFrame.Health.GetFrameLevel then
        baseLevel = math.max(baseLevel, unitFrame.Health:GetFrameLevel())
    end

    local wantedLevel = baseLevel + 2
    if container:GetFrameLevel() ~= wantedLevel then
        container:SetFrameLevel(wantedLevel)
    end
end

local function RaiseManagedAuras(unitFrame)
    if not unitFrame then return end

    RaiseManagedAuraContainer(unitFrame, unitFrame.UUFManagedTargetBuffs)
    RaiseManagedAuraContainer(unitFrame, unitFrame.UUFManagedTargetDebuffs)
    RaiseManagedAuraContainer(unitFrame, unitFrame.UUFManagedPartyRaidCustomAuras)
    RaiseManagedAuraContainer(unitFrame, unitFrame.UUFManagedDispelHighlight)
end

local originalUpdateUnitAuras = UUF.UpdateUnitAuras
if type(originalUpdateUnitAuras) == "function" then
    UUF.UpdateUnitAuras = function(self, unitFrame, unit, ...)
        local result = originalUpdateUnitAuras(self, unitFrame, unit, ...)
        RaiseManagedAuras(unitFrame)
        return result
    end
end

local function GetActivePlayerSpecRole()
    if not GetSpecialization or not GetSpecializationRole then return nil end

    local specialization = GetSpecialization()
    if not specialization then return nil end

    local role = GetSpecializationRole(specialization)
    if role == "HEALER" or role == "TANK" or role == "DAMAGER" then
        return role
    end
end

local function LayoutSoloPartyPower(unitFrame, PowerBarDB)
    local powerBar = unitFrame and unitFrame.Power
    if not powerBar or not unitFrame.Container then return end

    local width = unitFrame:GetWidth()
    if not width or width <= 0 then
        width = UUF.db.profile.Units.party.Frame.Width
    end

    local position = UUF:GetConfiguredPowerBarPosition("partyplayer", unitFrame)
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

local function ApplySoloPartyPowerRoleFallback(unitFrame)
    if not unitFrame or unitFrame ~= UUF.PARTY_SOLO_PLAYER then return end

    local PartyDB = UUF.db and UUF.db.profile and UUF.db.profile.Units and UUF.db.profile.Units.party
    local PowerBarDB = PartyDB and PartyDB.PowerBar
    if not PowerBarDB then return end

    local shouldShow = PowerBarDB.Enabled == true
    if shouldShow and PowerBarDB.OnlyShowHealers then
        shouldShow = GetActivePlayerSpecRole() == "HEALER"
    end

    if shouldShow then
        local powerBar = unitFrame.Power or unitFrame.PowerBar
        if not powerBar then
            powerBar = UUF:CreateUnitPowerBar(unitFrame, "partyplayer")
        end
        if not powerBar then return end

        unitFrame.Power = powerBar
        if not unitFrame:IsElementEnabled("Power") then
            unitFrame:EnableElement("Power")
        end

        LayoutSoloPartyPower(unitFrame, PowerBarDB)
        powerBar:Show()
        powerBar:ForceUpdate()
    else
        if unitFrame.Power then
            if unitFrame:IsElementEnabled("Power") then
                unitFrame:DisableElement("Power")
            end
            unitFrame.Power:Hide()
            unitFrame.Power = nil
        elseif unitFrame.PowerBar then
            unitFrame.PowerBar:Hide()
        end
    end

    if UUF.UpdateHealthBarLayout then
        UUF:UpdateHealthBarLayout(unitFrame, "partyplayer")
    end
end

local originalUpdateUnitPowerBar = UUF.UpdateUnitPowerBar
if type(originalUpdateUnitPowerBar) == "function" then
    UUF.UpdateUnitPowerBar = function(self, unitFrame, unit, ...)
        local result = originalUpdateUnitPowerBar(self, unitFrame, unit, ...)
        if unit == "partyplayer" and unitFrame == self.PARTY_SOLO_PLAYER then
            ApplySoloPartyPowerRoleFallback(unitFrame)
        end
        return result
    end
end

local function RefreshGroupLifecycleVisuals()
    for _, unitFrame in ipairs(UUF.PARTY_FRAMES or {}) do
        RaiseManagedAuras(unitFrame)
    end
    for _, unitFrame in ipairs(UUF.RAID_FRAMES or {}) do
        RaiseManagedAuras(unitFrame)
    end

    if UUF.PARTY_SOLO_PLAYER then
        ApplySoloPartyPowerRoleFallback(UUF.PARTY_SOLO_PLAYER)
    end
end

local lifecycleFrame = CreateFrame("Frame")
lifecycleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
lifecycleFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
lifecycleFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
lifecycleFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
lifecycleFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end

    C_Timer.After(0, RefreshGroupLifecycleVisuals)
    C_Timer.After(0.5, RefreshGroupLifecycleVisuals)
end)
