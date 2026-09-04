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

local StatusBarInterpolation = Enum.StatusBarInterpolation

local HealthTo100Curve = C_CurveUtil.CreateCurve()
HealthTo100Curve:SetType(Enum.LuaCurveType.Linear)
HealthTo100Curve:AddPoint(0.0, 0)
HealthTo100Curve:AddPoint(1.0, 100)

local MissingTo100Curve = C_CurveUtil.CreateCurve()
MissingTo100Curve:SetType(Enum.LuaCurveType.Linear)
MissingTo100Curve:AddPoint(0.0, 100)
MissingTo100Curve:AddPoint(1.0, 0)

local function IsRaidUnit(unit)
	return type(unit) == "string" and UUF:GetNormalizedUnit(unit) == "raid"
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
	local liveUnit = unitFrame:GetAttribute("unit") or unit
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

local function ApplyDirectHealthAppearance(unitFrame, unit)
	local health = unitFrame and unitFrame.UUFMinimalRaidHealth
	local background = unitFrame and unitFrame.HealthBackground
	local UnitDB = UUF:GetUnitDB(unitFrame, unit)
	if not health or not background or not UnitDB then return end

	local FrameDB = UnitDB.Frame
	local HealthBarDB = UnitDB.HealthBar

	unitFrame:SetSize(FrameDB.Width, FrameDB.Height)
	health:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
	background:SetSize(FrameDB.Width - 2, FrameDB.Height - 2)
	health:SetStatusBarTexture(UUF.Media.Foreground)
	background:SetStatusBarTexture(UUF.Media.Background)
	health.smoothing = HealthBarDB.Smooth ~= false and StatusBarInterpolation.ExponentialEaseOut or StatusBarInterpolation.Immediate

	if HealthBarDB.Inverse then
		health:SetReverseFill(true)
		background:SetReverseFill(false)
	else
		health:SetReverseFill(false)
		background:SetReverseFill(true)
	end

	local liveUnit = unitFrame:GetAttribute("unit") or unit
	if HealthBarDB.ColourByClass and liveUnit then
		local r, g, b = UUF:GetUnitColour(liveUnit)
		health:SetStatusBarColor(r, g, b, HealthBarDB.ForegroundOpacity)
	else
		health:SetStatusBarColor(HealthBarDB.Foreground[1], HealthBarDB.Foreground[2], HealthBarDB.Foreground[3], HealthBarDB.ForegroundOpacity)
	end

	if HealthBarDB.ColourBackgroundByClass and liveUnit then
		local r, g, b = UUF:GetUnitColour(liveUnit)
		background:SetStatusBarColor(r, g, b, HealthBarDB.BackgroundOpacity)
	else
		background:SetStatusBarColor(HealthBarDB.Background[1], HealthBarDB.Background[2], HealthBarDB.Background[3], HealthBarDB.BackgroundOpacity)
	end
end

local function PaintDirectHealth(unitFrame, unit)
	local health = unitFrame and unitFrame.UUFMinimalRaidHealth
	local background = unitFrame and unitFrame.HealthBackground
	if not health or not background or not unit or not UnitExists(unit) then return end

	if not health.UUFDirectPercentRange then
		health:SetMinMaxValues(0, 100)
		background:SetMinMaxValues(0, 100)
		health.UUFDirectPercentRange = true
	end

	local healthPercent = UnitHealthPercent(unit, true, HealthTo100Curve)
	local missingPercent = UnitHealthPercent(unit, true, MissingTo100Curve)
	local connected = UnitIsConnected(unit)

	if not UUF:IsSecretValue(connected) and connected == false then
		health:SetValue(100, health.smoothing)
		background:SetValue(0, health.smoothing)
	else
		health:SetValue(healthPercent, health.smoothing)
		background:SetValue(missingPercent, health.smoothing)
	end
end

local function UnbindDirectHealthTracker(unitFrame)
	local tracker = unitFrame and unitFrame.UUFMinimalRaidHealthTracker
	if not tracker then return end
	tracker:UnregisterAllEvents()
	tracker.UUFUnit = nil
end

local function BindDirectHealthTracker(unitFrame, unit)
	if not unitFrame then return end

	local tracker = unitFrame.UUFMinimalRaidHealthTracker
	if not tracker then
		tracker = CreateFrame("Frame")
		unitFrame.UUFMinimalRaidHealthTracker = tracker
		tracker.UUFFrame = unitFrame
		tracker:SetScript("OnEvent", function(self, _, eventUnit)
			local liveUnit = self.UUFUnit
			if not liveUnit or (eventUnit and eventUnit ~= liveUnit) then return end
			PaintDirectHealth(self.UUFFrame, liveUnit)
		end)
	end

	tracker:UnregisterAllEvents()
	tracker.UUFUnit = unit
	if not unit then return end

	tracker:RegisterUnitEvent("UNIT_HEALTH", unit)
	tracker:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
	tracker:RegisterUnitEvent("UNIT_CONNECTION", unit)
	PaintDirectHealth(unitFrame, unit)
end

local function CreateDirectRaidHealth(unitFrame, unit)
	UUF:CreateUnitHealthBar(unitFrame, unit)

	-- Keep the StatusBar UUF already creates, but remove the `Health` field
	-- before oUF enables elements. This prevents oUF's Health element from
	-- registering any health/prediction events for this benchmark.
	unitFrame.UUFMinimalRaidHealth = unitFrame.Health
	unitFrame.Health = nil

	ApplyDirectHealthAppearance(unitFrame, unit)
	BindDirectHealthTracker(unitFrame, unitFrame:GetAttribute("unit") or unit)
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
	CreateDirectRaidHealth(unitFrame, unit)
	CreateMinimalRaidName(unitFrame, unit)
	StripMinimalRaidExtras(unitFrame)

	unitFrame.UUFConfiguredUnit = unit
	unitFrame:HookScript("OnAttributeChanged", function(frame, attribute, value)
		if attribute ~= "unit" then return end
		if not value then
			frame.UUFGroupUnit = nil
			if frame.UUFMinimalRaidName then frame.UUFMinimalRaidName:SetText("") end
			UnbindDirectHealthTracker(frame)
			StripMinimalRaidExtras(frame)
			return
		end

		frame.UUFGroupUnit = value
		UpdateMinimalRaidName(frame, value)
		ApplyDirectHealthAppearance(frame, value)
		BindDirectHealthTracker(frame, value)
		StripMinimalRaidExtras(frame)
	end)

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
	ApplyDirectHealthAppearance(unitFrame, unit)
	local liveUnit = unitFrame:GetAttribute("unit") or unit
	BindDirectHealthTracker(unitFrame, liveUnit)
	UpdateMinimalRaidName(unitFrame, liveUnit)
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
