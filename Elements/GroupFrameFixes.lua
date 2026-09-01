local _, UUF = ...

local function RaiseManagedAuraContainer(frame, container)
    if not frame or not container then return end

    local baseLevel = frame:GetFrameLevel()
    if frame.Container and frame.Container.GetFrameLevel then
        baseLevel = math.max(baseLevel, frame.Container:GetFrameLevel())
    end
    if frame.Health and frame.Health.GetFrameLevel then
        baseLevel = math.max(baseLevel, frame.Health:GetFrameLevel())
    end

    container:SetFrameLevel(baseLevel + 2)
end

local function RaiseManagedGroupAuras(frame)
    if not frame then return end

    RaiseManagedAuraContainer(frame, frame.UUFManagedTargetBuffs)
    RaiseManagedAuraContainer(frame, frame.UUFManagedTargetDebuffs)
    RaiseManagedAuraContainer(frame, frame.UUFManagedPartyRaidCustomAuras)
    RaiseManagedAuraContainer(frame, frame.UUFManagedDispelHighlight)
end

local originalUpdateUnitAuras = UUF.UpdateUnitAuras
if type(originalUpdateUnitAuras) == "function" then
    UUF.UpdateUnitAuras = function(self, frame, unit, ...)
        local result = originalUpdateUnitAuras(self, frame, unit, ...)
        RaiseManagedGroupAuras(frame)
        return result
    end
end

local function GetActivePlayerSpecRole()
    if not GetSpecialization or not GetSpecializationRole then return nil end

    local specIndex = GetSpecialization()
    if not specIndex then return nil end

    local role = GetSpecializationRole(specIndex)
    if role == "HEALER" or role == "TANK" or role == "DAMAGER" then
        return role
    end
end

local function LayoutSoloPartyPower(frame, bar, PartyDB)
    if not frame or not bar or not frame.Container then return end

    local width = frame:GetWidth()
    if not width or width <= 0 then
        width = PartyDB.Frame.Width
    end

    local position = UUF:GetConfiguredPowerBarPosition("partyplayer", frame)
    local isTop = position == "TOP"
    local point = isTop and "TOPLEFT" or "BOTTOMLEFT"
    local yOffset = isTop and -1 or 1

    bar:ClearAllPoints()
    bar:SetPoint(point, frame.Container, point, 1, yOffset)
    bar:SetSize(width - 2, PartyDB.PowerBar.Height)

    if bar.Background then
        bar.Background:ClearAllPoints()
        bar.Background:SetPoint(point, frame.Container, point, 1, yOffset)
        bar.Background:SetSize(width - 2, PartyDB.PowerBar.Height)
    end

    if bar.PowerBarBorder then
        bar.PowerBarBorder:ClearAllPoints()
        if isTop then
            bar.PowerBarBorder:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, -1)
            bar.PowerBarBorder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -1)
        else
            bar.PowerBarBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 1)
            bar.PowerBarBorder:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 1)
        end
    end
end

local function UpdateSoloPartyPowerRole()
    local frame = UUF.PARTY_SOLO_PLAYER
    local PartyDB = UUF.db and UUF.db.profile and UUF.db.profile.Units and UUF.db.profile.Units.party
    if not frame or not PartyDB or not PartyDB.PowerBar then return end

    local shouldShow = PartyDB.PowerBar.Enabled == true
    if shouldShow and PartyDB.PowerBar.OnlyShowHealers == true then
        shouldShow = GetActivePlayerSpecRole() == "HEALER"
    end

    if shouldShow then
        local bar = frame.Power or frame.PowerBar
        if not bar then
            bar = UUF:CreateUnitPowerBar(frame, "partyplayer")
        end
        if not bar then return end

        frame.Power = bar
        if frame.IsElementEnabled and not frame:IsElementEnabled("Power") then
            frame:EnableElement("Power")
        end

        LayoutSoloPartyPower(frame, bar, PartyDB)
        bar:SetStatusBarTexture(UUF.Media.Foreground)
        bar:SetStatusBarColor(
            PartyDB.PowerBar.Foreground[1],
            PartyDB.PowerBar.Foreground[2],
            PartyDB.PowerBar.Foreground[3],
            PartyDB.PowerBar.Foreground[4] or 1
        )

        if bar.Background then
            bar.Background:SetTexture(UUF.Media.Background)
            bar.Background:SetVertexColor(
                PartyDB.PowerBar.Background[1],
                PartyDB.PowerBar.Background[2],
                PartyDB.PowerBar.Background[3],
                PartyDB.PowerBar.Background[4] or 1
            )
        end

        bar:Show()
        if bar.ForceUpdate then bar:ForceUpdate() end
    else
        if frame.Power then
            if frame.IsElementEnabled and frame:IsElementEnabled("Power") then
                frame:DisableElement("Power")
            end
            frame.Power:Hide()
            frame.Power = nil
        elseif frame.PowerBar then
            frame.PowerBar:Hide()
        end
    end

    if UUF.UpdateHealthBarLayout then
        UUF:UpdateHealthBarLayout(frame, "partyplayer")
    end
end

local originalUpdateSoloPartyFrame = UUF.UpdateSoloPartyFrame
if type(originalUpdateSoloPartyFrame) == "function" then
    UUF.UpdateSoloPartyFrame = function(self, ...)
        local result = originalUpdateSoloPartyFrame(self, ...)
        UpdateSoloPartyPowerRole()
        return result
    end
end

local lifecycle = CreateFrame("Frame")
lifecycle:RegisterEvent("PLAYER_ENTERING_WORLD")
lifecycle:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
lifecycle:RegisterEvent("PLAYER_ROLES_ASSIGNED")
lifecycle:RegisterEvent("GROUP_ROSTER_UPDATE")
lifecycle:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end

    C_Timer.After(0, function()
        UpdateSoloPartyPowerRole()

        for _, frame in ipairs(UUF.PARTY_FRAMES or {}) do
            RaiseManagedGroupAuras(frame)
        end
        for _, frame in ipairs(UUF.RAID_FRAMES or {}) do
            RaiseManagedGroupAuras(frame)
        end
    end)

    C_Timer.After(0.5, function()
        UpdateSoloPartyPowerRole()

        for _, frame in ipairs(UUF.PARTY_FRAMES or {}) do
            RaiseManagedGroupAuras(frame)
        end
        for _, frame in ipairs(UUF.RAID_FRAMES or {}) do
            RaiseManagedGroupAuras(frame)
        end
    end)
end)
