local _, UUF = ...

local OriginalCreateUnitFrame = UUF.CreateUnitFrame
local OriginalUpdateUnitFrame = UUF.UpdateUnitFrame

local function IsRaidUnit(unit)
	return UUF:GetNormalizedUnit(unit) == "raid"
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

	if not unit or not unitFrame then return end
	if unitFrame:GetParent() == UUF.AUGMENTATION_RAID_HEADER then
		unitFrame.isAugmentationRaidFrame = true
	end

	UUF:CreateUnitContainer(unitFrame, unit)
	UUF:CreateUnitHealthBar(unitFrame, unit)
	CreateMinimalRaidName(unitFrame, unit)

	unitFrame.UUFConfiguredUnit = unit
	unitFrame:HookScript("OnAttributeChanged", function(frame, attribute, value)
		if attribute ~= "unit" then return end
		if not value then
			frame.UUFGroupUnit = nil
			if frame.UUFMinimalRaidName then frame.UUFMinimalRaidName:SetText("") end
			return
		end

		frame.UUFGroupUnit = value
		UpdateMinimalRaidName(frame, value)
		if frame.Health then frame.Health:ForceUpdate() end
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

	UUF:UpdateUnitHealthBar(unitFrame, unit)
	UpdateMinimalRaidName(unitFrame, unit)
	unitFrame:SetFrameStrata(UnitDB.Frame.FrameStrata)
end
