local _, UUF = ...
local oUF = UUF.oUF

local dispelTypeMap = {
    Magic = oUF.Enum.DispelType.Magic,
    Curse = oUF.Enum.DispelType.Curse,
    Disease = oUF.Enum.DispelType.Disease,
    Poison = oUF.Enum.DispelType.Poison,
    Bleed = oUF.Enum.DispelType.Bleed,
}

local DispelHighlightFrames = {}
local DispelTypes

local DispelEventFrame = CreateFrame("Frame")
DispelEventFrame:RegisterEvent("SPELLS_CHANGED")
DispelEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
DispelEventFrame:SetScript("OnEvent", function()
	DispelTypes = UUF.LD and UUF.LD:GetMyDispelTypes()
	for unitFrame in pairs(DispelHighlightFrames) do UUF:UpdateUnitDispelState(unitFrame, unitFrame.DispelHighlightUnit) end
end)

function UUF:UpdateDispelColorCurve(unitFrame)
    if not unitFrame.dispelColorCurve then return end
    unitFrame.dispelColorCurve:ClearPoints()
    for dispelType, index in pairs(dispelTypeMap) do
        local color = oUF.colors.dispel[index]
        if color then
            unitFrame.dispelColorCurve:AddPoint(index, color)
        end
    end
    unitFrame.dispelColorCurveGeneration = UUF.dispelColorGeneration
end

function UUF:CreateUnitDispelHighlight(unitFrame, unit)
	local DispelHighlightDB = UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight
	if not unitFrame.DispelHighlight then
		local DispelHighlight = unitFrame.Health:CreateTexture(UUF:FetchFrameName(unit) .. "_DispelHighlight", "OVERLAY")
		DispelHighlight:ClearAllPoints()
		if DispelHighlightDB.Style == "GRADIENT" then
			DispelHighlight:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 1, -1)
			DispelHighlight:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
			DispelHighlight:SetTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\Gradient.png")
			DispelHighlight:SetAlpha(1)
		else
			local barTexture = unitFrame.Health and unitFrame.Health:GetStatusBarTexture()
			if barTexture then
				DispelHighlight:SetAllPoints(barTexture)
			else
				DispelHighlight:SetAllPoints(unitFrame.Health)
			end
			DispelHighlight:SetTexture("Interface\\Buttons\\WHITE8X8")
			DispelHighlight:SetAlpha(0.75)
		end
		DispelHighlight:SetBlendMode("BLEND")
		DispelHighlight:Hide()

		unitFrame.DispelHighlight = DispelHighlight

		if not unitFrame.dispelColorCurve then
			unitFrame.dispelColorCurve = C_CurveUtil.CreateColorCurve()
			unitFrame.dispelColorCurve:SetType(Enum.LuaCurveType.Step)
			UUF:UpdateDispelColorCurve(unitFrame)
		end
	end

	UUF:UpdateUnitDispelHighlight(unitFrame, unit)
end

function UUF:UpdateUnitDispelHighlight(unitFrame, unit)
	if not unitFrame.DispelHighlight then return end
	local DispelHighlightDB = UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight
	if unitFrame.DispelHighlight then
		if DispelHighlightDB.Enabled then
			UUF:RegisterDispelHighlightEvents(unitFrame, unit)
			unitFrame.DispelHighlight:ClearAllPoints()
			if DispelHighlightDB.Style == "GRADIENT" then
				unitFrame.DispelHighlight:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 1, -1)
				unitFrame.DispelHighlight:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
				unitFrame.DispelHighlight:SetTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\Gradient.png")
				unitFrame.DispelHighlight:SetAlpha(1)
			else
				local barTexture = unitFrame.Health and unitFrame.Health:GetStatusBarTexture()
				if barTexture then
					unitFrame.DispelHighlight:SetAllPoints(barTexture)
				else
					unitFrame.DispelHighlight:SetAllPoints(unitFrame.Health)
				end
				unitFrame.DispelHighlight:SetTexture("Interface\\Buttons\\WHITE8X8")
				unitFrame.DispelHighlight:SetAlpha(0.75)
			end
			UUF:UpdateUnitDispelState(unitFrame, unit)
		else
			UUF:UnregisterDispelHighlightEvents(unitFrame)
			unitFrame.DispelHighlight:Hide()
		end
	end
end

local function GetManagedDispelSignature(unitFrame, unit)
	local db = UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight
	local types = DispelTypes or (UUF.LD and UUF.LD:GetMyDispelTypes()) or {}
	return table.concat({
		tostring(db.Enabled),
		tostring(db.Style),
		tostring(types.Magic == true),
		tostring(types.Curse == true),
		tostring(types.Disease == true),
		tostring(types.Poison == true),
		tostring(types.Bleed == true),
		tostring(UUF.dispelColorGeneration or 0),
	}, "|")
end

local function DisableManagedDispelContainer(unitFrame)
	local container = unitFrame.UUFManagedDispelHighlight
	if container then
		pcall(container.SetEnabled, container, false)
		container:Hide()
	end
end

local function CreateDispelSlotTexture(button, unitFrame, DispelHighlightDB, color, level)
	button:EnableMouse(false)
	button:SetFrameLevel((unitFrame.Health and unitFrame.Health:GetFrameLevel() or unitFrame:GetFrameLevel()) + level)

	local texture = button:CreateTexture(nil, "OVERLAY", nil, 3)

	if DispelHighlightDB.Style == "GRADIENT" then
		texture:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 1, -1)
		texture:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", -1, 1)
		texture:SetTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\Gradient.png")
		texture:SetVertexColor(color:GetRGB())
		texture:SetAlpha(1)
	else
		local barTexture = unitFrame.Health and unitFrame.Health:GetStatusBarTexture()
		texture:SetPoint("TOPLEFT", unitFrame.Health or unitFrame, "TOPLEFT")
		if barTexture then
			texture:SetPoint("BOTTOMRIGHT", barTexture, "BOTTOMRIGHT")
		else
			texture:SetPoint("BOTTOMRIGHT", unitFrame.Health or unitFrame, "BOTTOMRIGHT")
		end
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
		texture:SetVertexColor(color:GetRGB())
		texture:SetAlpha(0.75)
	end

	texture:SetBlendMode("BLEND")
	button.UUFDispelHighlightTexture = texture

	-- Borde blanco de 3 px, visible únicamente mientras este slot de dispel esté activo.
	local borderSize = 3

	local borderTop = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderTop:SetVertexColor(1, 1, 1, 1)
	borderTop:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", unitFrame, "TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)

	local borderBottom = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderBottom:SetVertexColor(1, 1, 1, 1)
	borderBottom:SetPoint("BOTTOMLEFT", unitFrame, "BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)

	local borderLeft = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderLeft:SetVertexColor(1, 1, 1, 1)
	borderLeft:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", unitFrame, "BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)

	local borderRight = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderRight:SetVertexColor(1, 1, 1, 1)
	borderRight:SetPoint("TOPRIGHT", unitFrame, "TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)

	button.UUFDispelHighlightBorder = {
		top = borderTop,
		bottom = borderBottom,
		left = borderLeft,
		right = borderRight,
	}
end

local function CreateManagedDispelContainer(unitFrame, unit)
	if not CreateFrame then return nil end

	local ok, container = pcall(CreateFrame, "AuraContainer", nil, unitFrame, "CustomAuraContainerTemplate")
	if not ok or not container or type(container.AddAuraSlot) ~= "function" then
		return nil
	end

	local unitToken = unit == "partyplayer" and "player" or unit
	local DispelHighlightDB = UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight
	local types = DispelTypes or (UUF.LD and UUF.LD:GetMyDispelTypes()) or {}

	container:SetAllPoints(unitFrame)
	container:SetFrameStrata(unitFrame:GetFrameStrata())

	-- En 12.1 la unidad se asigna antes de declarar slots; SetEnabled va al final.
	if container.SetUnit then container:SetUnit(unitToken) end

	local slots = {
		{ key = "Magic",   enabled = types.Magic,   index = dispelTypeMap.Magic,   level = 5 },
		{ key = "Curse",   enabled = types.Curse,   index = dispelTypeMap.Curse,   level = 4 },
		{ key = "Disease", enabled = types.Disease, index = dispelTypeMap.Disease, level = 3 },
		{ key = "Poison",  enabled = types.Poison,  index = dispelTypeMap.Poison,  level = 2 },
		{ key = "Bleed",   enabled = types.Bleed,   index = dispelTypeMap.Bleed,   level = 1 },
	}

	local addedAny = false

	for _, slot in ipairs(slots) do
		if slot.enabled then
			local color = oUF.colors.dispel[slot.index]
			if color then
				local added = pcall(container.AddAuraSlot, container,
					"UUFDispel_" .. slot.key,
					"HARMFUL",
					{
						candidateFilters = {
							includeDispelTypes = {
								[slot.key] = true,
							},
						},
						initializeFrame = function(button)
							button:SetPoint("CENTER", unitFrame.Health or unitFrame, "CENTER")
							CreateDispelSlotTexture(button, unitFrame, DispelHighlightDB, color, slot.level)
						end,
					}
				)
				if added then
					addedAny = true
				end
			end
		end
	end

	if not addedAny then
		container:Hide()
		return container
	end

	if container.SetEnabled then container:SetEnabled(true) end
	container:Show()
	if container.UpdateAllAuras then container:UpdateAllAuras() end

	return container
end

function UUF:UpdateUnitDispelState(unitFrame, unit)
	if not unitFrame.DispelHighlight then return end

	local DispelHighlightDB = UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight
	local unitToken = unit == "partyplayer" and "player" or unit

	-- El texture antiguo no debe intentar decidir nada a partir de datos secretos.
	unitFrame.DispelHighlight:Hide()

	if not DispelHighlightDB.Enabled then
		DisableManagedDispelContainer(unitFrame)
		return
	end

	if not UnitIsUnit(unitToken, "player") and not UnitIsFriend("player", unitToken) then
		DisableManagedDispelContainer(unitFrame)
		return
	end

	if unitFrame.dispelColorCurve and unitFrame.dispelColorCurveGeneration ~= UUF.dispelColorGeneration then
		UUF:UpdateDispelColorCurve(unitFrame)
	end

	DispelTypes = UUF.LD and UUF.LD:GetMyDispelTypes() or DispelTypes or {}

	local signature = GetManagedDispelSignature(unitFrame, unit)
	local container = unitFrame.UUFManagedDispelHighlight

	if container and unitFrame.UUFManagedDispelHighlightSignature ~= signature then
		if InCombatLockdown() then
			-- No reconstruimos la topología de slots en combate.
			if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
			return
		end
		DisableManagedDispelContainer(unitFrame)
		unitFrame.UUFManagedDispelHighlight = nil
		container = nil
	end

	if not container then
		if InCombatLockdown() then return end
		container = CreateManagedDispelContainer(unitFrame, unit)
		unitFrame.UUFManagedDispelHighlight = container
		unitFrame.UUFManagedDispelHighlightSignature = signature
	end

	if not container then return end

	if container.SetUnit then pcall(container.SetUnit, container, unitToken) end
	if container.SetEnabled then pcall(container.SetEnabled, container, true) end
	container:Show()
	if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
end

function UUF:RegisterDispelHighlightEvents(unitFrame, unit)
    if not unitFrame.DispelHighlight then return end
    if not UUF:GetUnitDB(unitFrame, unit).HealthBar.DispelHighlight.Enabled then return end
    local unitToken = unit == "partyplayer" and "player" or unit

    unitFrame.DispelHighlightUnit = unit
    DispelHighlightFrames[unitFrame] = true

    -- All supported UUF dispel highlights use Blizzard's managed AuraContainer.
    -- It already listens to UNIT_AURA and consumes incremental aura updates, so a
    -- second addon UNIT_AURA handler would only force redundant full rescans.
    if unitFrame.DispelHighlightHandler then
        unitFrame.DispelHighlightHandler:UnregisterAllEvents()
    end
    return
end

function UUF:UnregisterDispelHighlightEvents(unitFrame)
    if not unitFrame.DispelHighlightHandler then return end

    unitFrame.DispelHighlightHandler:UnregisterAllEvents()
	DispelHighlightFrames[unitFrame] = nil
    unitFrame.DispelHighlightUnit = nil
end
