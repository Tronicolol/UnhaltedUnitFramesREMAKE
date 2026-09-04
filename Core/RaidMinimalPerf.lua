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

function UUF:CreateUnitFrame(unitFrame, unit)
	if not IsRaidUnit(unit) then
		return OriginalCreateUnitFrame(self, unitFrame, unit)
	end

	if not unitFrame then return end
	if unitFrame:GetParent() == UUF.AUGMENTATION_RAID_HEADER then
		unitFrame.isAugmentationRaidFrame = true
	end

	-- Intentionally no Health/Power/Auras/Tags/indicators. This benchmark
	-- measures the secure raid-frame + oUF/header + name/click base cost only.
	UUF:CreateUnitContainer(unitFrame, unit)
	CreateMinimalRaidName(unitFrame, unit)
	StripMinimalRaidExtras(unitFrame)

	unitFrame.UUFConfiguredUnit = unit
	unitFrame:HookScript("OnAttributeChanged", function(frame, attribute, value)
		if attribute ~= "unit" then return end
		if not value then
			frame.UUFGroupUnit = nil
			if frame.UUFMinimalRaidName then frame.UUFMinimalRaidName:SetText("") end
			StripMinimalRaidExtras(frame)
			return
		end

		frame.UUFGroupUnit = value
		UpdateMinimalRaidName(frame, value)
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
	UpdateMinimalRaidName(unitFrame, unit)
	unitFrame:SetSize(UnitDB.Frame.Width, UnitDB.Frame.Height)
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
