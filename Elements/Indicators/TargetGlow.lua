local _, UUF = ...
UUF.TargetHighlightEvtFrames = {}


local function IsBossUnit(unit)
	return type(unit) == "string" and unit:match("^boss%d+$") ~= nil
end

local FrameStrataPriority = {
	BACKGROUND = 1,
	LOW = 2,
	MEDIUM = 3,
	HIGH = 4,
	DIALOG = 5,
	FULLSCREEN = 6,
	FULLSCREEN_DIALOG = 7,
	TOOLTIP = 8,
}

local function RaiseBossTargetWhiteBorder(unitFrame)
	if not unitFrame or not unitFrame.UUFBossTargetWhiteBorder or not unitFrame.Container then return end

	local overlay = unitFrame.UUFBossTargetWhiteBorder
	local container = unitFrame.Container
	local bestStrata = container:GetFrameStrata() or "MEDIUM"
	local bestPriority = FrameStrataPriority[bestStrata] or 0
	local bestLevel = container:GetFrameLevel() + 4

	-- La CastBar tiene su propio FrameStrata. Si está por encima del UnitFrame,
	-- igualamos ese strata y colocamos el borde unos niveles por delante.
	local castBar = unitFrame.Castbar
	local castBarContainer = castBar and castBar:GetParent()

	if castBarContainer then
		local castStrata = castBarContainer:GetFrameStrata()
		local castPriority = FrameStrataPriority[castStrata] or 0

		if castPriority > bestPriority then
			bestStrata = castStrata
			bestPriority = castPriority
		end

		bestLevel = math.max(bestLevel, castBarContainer:GetFrameLevel() + 3)
	end

	if castBar then
		bestLevel = math.max(bestLevel, castBar:GetFrameLevel() + 2)
	end

	overlay:SetFrameStrata(bestStrata)
	overlay:SetFrameLevel(bestLevel)
end

local function EnsureBossTargetWhiteBorder(unitFrame, unit)
	if not unitFrame or not IsBossUnit(unit) then return end
	if unitFrame.UUFBossTargetWhiteBorder then return end
	if not unitFrame.Health or not unitFrame.Container then return end

	local health = unitFrame.Health
	local container = unitFrame.Container
	local borderSize = 3

	-- El overlay abraza por fuera el Container completo.
	-- Así el borde incluye Health + PowerBar sin invadir ninguna de las dos.
	local overlay = CreateFrame("Frame", nil, unitFrame)
	overlay:SetPoint("TOPLEFT", container, "TOPLEFT", -borderSize, borderSize)
	overlay:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", borderSize, -borderSize)
	overlay:SetFrameLevel(container:GetFrameLevel() + 4)
	overlay:EnableMouse(false)

	-- Highlight blanco suave: conserva el comportamiento anterior y sigue
	-- afectando únicamente a la barra de vida, no a la PowerBar.
	local highlight = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
	highlight:SetVertexColor(1, 1, 1, 1)
	highlight:SetBlendMode("BLEND")
	highlight:SetAlpha(0.18)
	highlight:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
	highlight:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)

	-- Borde blanco de 3 px completamente EXTERIOR al Container.
	local top = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	top:SetTexture("Interface\\Buttons\\WHITE8X8")
	top:SetVertexColor(1, 1, 1, 1)
	top:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
	top:SetHeight(borderSize)

	local bottom = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	bottom:SetTexture("Interface\\Buttons\\WHITE8X8")
	bottom:SetVertexColor(1, 1, 1, 1)
	bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(borderSize)

	local left = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	left:SetTexture("Interface\\Buttons\\WHITE8X8")
	left:SetVertexColor(1, 1, 1, 1)
	left:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
	left:SetWidth(borderSize)

	local right = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	right:SetTexture("Interface\\Buttons\\WHITE8X8")
	right:SetVertexColor(1, 1, 1, 1)
	right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(borderSize)

	overlay:SetAlpha(0)

	unitFrame.UUFBossTargetWhiteBorder = overlay
	unitFrame.UUFBossTargetHighlight = highlight
	RaiseBossTargetWhiteBorder(unitFrame)
end

local function UpdateBossTargetWhiteBorder(unitFrame, unit, enabled)
	if not unitFrame or not IsBossUnit(unit) then return end

	EnsureBossTargetWhiteBorder(unitFrame, unit)

	local border = unitFrame.UUFBossTargetWhiteBorder
	if not border then return end

	-- Mantener el borde por delante de la CastBar aunque ésta use un
	-- FrameStrata distinto al del Boss Frame.
	RaiseBossTargetWhiteBorder(unitFrame)

	if enabled then
		-- El frame completo (borde + velo 8%) se muestra solo en el boss target.
		border:SetAlphaFromBoolean(UnitIsUnit("target", unit), 1, 0)
	else
		border:SetAlpha(0)
	end
end

local unitIsTargetEvtFrame = CreateFrame("Frame")
unitIsTargetEvtFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
unitIsTargetEvtFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
unitIsTargetEvtFrame:RegisterEvent("UNIT_TARGET")
unitIsTargetEvtFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
unitIsTargetEvtFrame:SetScript("OnEvent", function(_, event, eventUnit)
	if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		C_Timer.After(0, function()
			for frame, unit in pairs(UUF.TargetHighlightEvtFrames) do
				if IsBossUnit(unit) and frame:IsShown() then
					UUF:UpdateTargetGlowIndicator(frame, unit)
				end
			end
		end)
		return
	end

	local changedUnit = eventUnit and eventUnit .. "target"
	for frame, unit in pairs(UUF.TargetHighlightEvtFrames) do
		local unitChanged = event == "PLAYER_TARGET_CHANGED"
			or (event == "PLAYER_FOCUS_CHANGED" and (unit == "focus" or unit == "focustarget"))
			or unit == changedUnit
		if unitChanged and UUF:GetUnitDB(frame, unit).Indicators.Target.Enabled then
			UUF:UpdateTargetGlowIndicator(frame, unit)
		end
	end
end)

function UUF:CreateUnitTargetGlowIndicator(unitFrame, unit)
    local TargetIndicatorDB = UUF:GetUnitDB(unitFrame, unit).Indicators.Target
    EnsureBossTargetWhiteBorder(unitFrame, unit)
    if TargetIndicatorDB then
        if TargetIndicatorDB.Style == "Border" then
            unitFrame.TargetIndicator = unitFrame.Container
        else
            unitFrame.TargetIndicatorFrame = CreateFrame("Frame", UUF:FetchFrameName(unit).."_TargetIndicator", unitFrame.Container, "BackdropTemplate")
            unitFrame.TargetIndicator = unitFrame.TargetIndicatorFrame
            unitFrame.TargetIndicatorFrame:SetFrameLevel(unitFrame.Container:GetFrameLevel() + 3)
            unitFrame.TargetIndicatorFrame:SetBackdropColor(0, 0, 0, 0)
            unitFrame.TargetIndicator:SetBackdrop({ edgeFile = "Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\Glow.tga", edgeSize = 3, insets = {left = -3, right = -3, top = -3, bottom = -3} })
            unitFrame.TargetIndicator:SetPoint("TOPLEFT", unitFrame.Container, "TOPLEFT", -3, 3)
            unitFrame.TargetIndicator:SetPoint("BOTTOMRIGHT", unitFrame.Container, "BOTTOMRIGHT", 3, -3)
            unitFrame.TargetIndicator:SetBackdropBorderColor(TargetIndicatorDB.Colour[1], TargetIndicatorDB.Colour[2], TargetIndicatorDB.Colour[3], TargetIndicatorDB.Colour[4])
            unitFrame.TargetIndicator:SetAlpha(0)
        end
    end
end

function UUF:UpdateUnitTargetGlowIndicator(unitFrame, unit)
    local TargetIndicatorDB = UUF:GetUnitDB(unitFrame, unit).Indicators.Target
    if unitFrame and TargetIndicatorDB then
        if unitFrame.TargetIndicator and unitFrame.TargetIndicator ~= unitFrame.Container then unitFrame.TargetIndicator:SetAlpha(0) end
        if TargetIndicatorDB.Style == "Border" then
            unitFrame.TargetIndicator = unitFrame.Container
            unitFrame.Container:SetBackdropBorderColor(0, 0, 0, 1)
            UUF:UpdateTargetGlowIndicator(unitFrame, unit)
            return
        end

        if not unitFrame.TargetIndicatorFrame then
            unitFrame.TargetIndicatorFrame = CreateFrame("Frame", UUF:FetchFrameName(unit).."_TargetIndicator", unitFrame.Container, "BackdropTemplate")
            unitFrame.TargetIndicatorFrame:SetFrameLevel(unitFrame.Container:GetFrameLevel() + 3)
        end
        unitFrame.TargetIndicator = unitFrame.TargetIndicatorFrame
        unitFrame.TargetIndicator:ClearAllPoints()
        unitFrame.TargetIndicator:SetBackdropColor(0, 0, 0, 0)
        unitFrame.TargetIndicator:SetBackdrop({ edgeFile = "Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\Glow.tga", edgeSize = 3, insets = {left = -3, right = -3, top = -3, bottom = -3} })
        unitFrame.TargetIndicator:SetPoint("TOPLEFT", unitFrame.Container, "TOPLEFT", -3, 3)
        unitFrame.TargetIndicator:SetPoint("BOTTOMRIGHT", unitFrame.Container, "BOTTOMRIGHT", 3, -3)
        unitFrame.TargetIndicator:SetBackdropBorderColor(TargetIndicatorDB.Colour[1], TargetIndicatorDB.Colour[2], TargetIndicatorDB.Colour[3], TargetIndicatorDB.Colour[4])
        UUF:UpdateTargetGlowIndicator(unitFrame, unit)
    end
end

function UUF:UpdateTargetGlowIndicator(unitFrame, unit)
    if not unitFrame then return end

    local TargetIndicatorDB = UUF:GetUnitDB(unitFrame, unit).Indicators.Target
    if not TargetIndicatorDB then return end

    -- Boss frames: sin glow original de UUF.
    -- Borde blanco exterior de 3 px + highlight blanco BLEND al 18% sobre Health.
    if IsBossUnit(unit) then
        if unitFrame.TargetIndicator and unitFrame.TargetIndicator ~= unitFrame.Container then
            unitFrame.TargetIndicator:SetAlpha(0)
        end
        if unitFrame.Container then
            unitFrame.Container:SetBackdropBorderColor(0, 0, 0, 1)
        end
        UpdateBossTargetWhiteBorder(unitFrame, unit, TargetIndicatorDB.Enabled)
        return
    end

    -- Resto de unit frames: comportamiento original de UUF.
    if unitFrame.TargetIndicator then
        if TargetIndicatorDB.Style == "Border" then
            if TargetIndicatorDB.Enabled then
                local targetUnit = unit == "partyplayer" and "player" or unit
                unitFrame.Container:SetBackdropBorderColor(0, 0, 0, 1)
                if UnitIsUnit("target", targetUnit) then
                    unitFrame.Container:SetBackdropBorderColor(
                        TargetIndicatorDB.Colour[1],
                        TargetIndicatorDB.Colour[2],
                        TargetIndicatorDB.Colour[3],
                        TargetIndicatorDB.Colour[4] or 1
                    )
                end
            else
                unitFrame.Container:SetBackdropBorderColor(0, 0, 0, 1)
            end
        else
            unitFrame.Container:SetBackdropBorderColor(0, 0, 0, 1)
            if TargetIndicatorDB.Enabled then
                unitFrame.TargetIndicator:SetAlphaFromBoolean(
                    UnitIsUnit("target", unit == "partyplayer" and "player" or unit),
                    1,
                    0
                )
            else
                unitFrame.TargetIndicator:SetAlpha(0)
            end
        end
    end
end

function UUF:RegisterTargetGlowIndicatorFrame(frameName, unit)
	if not unit or not frameName then return end
	local unitFrame = type(frameName) == "table" and frameName or _G[frameName]
	local DB = UUF:GetUnitDB(unitFrame, unit)
	if not unitFrame or not DB or not DB.Indicators.Target then return end

	-- Los boss frames aparecen dinámicamente. Guardamos el token en el propio
	-- frame para no depender de cierres/closures del bucle de creación.
	if IsBossUnit(unit) then
		unitFrame.UUFTargetGlowBossUnit = unit
		if not unitFrame.UUFTargetGlowOnShowHooked then
			unitFrame.UUFTargetGlowOnShowHooked = true
			unitFrame:HookScript("OnShow", function(frame)
				C_Timer.After(0, function()
					local bossUnit = frame.UUFTargetGlowBossUnit
					if bossUnit and frame:IsShown() then
						UUF:UpdateTargetGlowIndicator(frame, bossUnit)
					end
				end)
			end)
		end
	end
	if DB.Indicators.Target.Enabled then
		UUF.TargetHighlightEvtFrames[unitFrame] = unit
		UUF:UpdateTargetGlowIndicator(unitFrame, unit)
	else
		UUF.TargetHighlightEvtFrames[unitFrame] = nil
		if unitFrame.TargetIndicator == unitFrame.Container then unitFrame.Container:SetBackdropBorderColor(0, 0, 0, 1) elseif unitFrame.TargetIndicator then unitFrame.TargetIndicator:SetAlpha(0) end
		UpdateBossTargetWhiteBorder(unitFrame, unit, false)
	end
end

function UUF:UnregisterTargetGlowIndicatorFrame(unitFrame)
	if unitFrame then
		UUF.TargetHighlightEvtFrames[unitFrame] = nil
		if unitFrame.UUFBossTargetWhiteBorder then
			unitFrame.UUFBossTargetWhiteBorder:SetAlpha(0)
		end
	end
end
