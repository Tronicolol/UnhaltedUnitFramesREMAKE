local _, UUF = ...

local ayijeReanchorHooked = false
local protectedReanchorPending = false

local function GetAyije()
	if not C_AddOns.IsAddOnLoaded("Ayije_CDM") then return nil end
	return _G["Ayije_CDM"]
end

local function GetAyijeEssentialAnchor()
	local CDM = GetAyije()
	if not CDM then return nil end

	if CDM.anchorContainers and CDM.anchorContainers["EssentialCooldownViewer"] then
		return CDM.anchorContainers["EssentialCooldownViewer"]
	end

	return nil
end

local function GetPhysicalPixelSize()
	local CDM = GetAyije()
	if CDM and CDM.Pixel and CDM.Pixel.GetSize then
		if CDM.Pixel.Update then CDM.Pixel.Update() end
		local pixel = CDM.Pixel.GetSize()
		if pixel and pixel > 0 then return pixel end
	end

	local _, physicalHeight = GetPhysicalScreenSize()
	local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if physicalHeight and physicalHeight > 0 and scale and scale > 0 then
		return 768 / (physicalHeight * scale)
	end

	return 1
end

local function HasHorizontalEdge(point)
	return point and (point:find("LEFT", 1, true) or point:find("RIGHT", 1, true))
end

local function HasVerticalEdge(point)
	return point and (point:find("TOP", 1, true) or point:find("BOTTOM", 1, true))
end

local function GetRequiredAnchorPhase(point, dimension, pixel, horizontal)
	local isEdge = horizontal and HasHorizontalEdge(point) or (not horizontal and HasVerticalEdge(point))
	if isEdge then return 0 end

	local dimensionPixels = math.floor((dimension or 0) / pixel + 0.5 + 0.001)
	return dimensionPixels % 2 == 1 and pixel * 0.5 or 0
end

local function GetRelativeAnchorCoordinate(frame, point, horizontal)
	if not frame then return nil end

	if horizontal then
		local left = frame:GetLeft()
		local right = frame:GetRight()
		if not left or not right then return nil end
		if point and point:find("LEFT", 1, true) then return left end
		if point and point:find("RIGHT", 1, true) then return right end
		return (left + right) * 0.5
	end

	local top = frame:GetTop()
	local bottom = frame:GetBottom()
	if not top or not bottom then return nil end
	if point and point:find("TOP", 1, true) then return top end
	if point and point:find("BOTTOM", 1, true) then return bottom end
	return (top + bottom) * 0.5
end

local function SnapAbsoluteToPhase(value, phase, pixel, direction)
	local scaled = (value - phase) / pixel
	local lower = math.floor(scaled)
	local fraction = scaled - lower
	local epsilon = 0.001
	local snapped

	if fraction < 0.5 - epsilon then
		snapped = lower
	elseif fraction > 0.5 + epsilon then
		snapped = lower + 1
	elseif direction and direction < 0 then
		snapped = lower
	else
		snapped = lower + 1
	end

	return phase + snapped * pixel
end

local function SnapCDMOffset(parentFrame, point, relativePoint, offset, dimension, horizontal)
	local pixel = GetPhysicalPixelSize()
	if not pixel or pixel <= 0 then return offset end

	local reference = GetRelativeAnchorCoordinate(parentFrame, relativePoint, horizontal)
	if not reference then return offset end

	local phase = GetRequiredAnchorPhase(point, dimension, pixel, horizontal)
	local desired = reference + (offset or 0)
	local direction = offset and offset ~= 0 and (offset > 0 and 1 or -1) or nil
	local snapped = SnapAbsoluteToPhase(desired, phase, pixel, direction)

	return snapped - reference
end

function UUF:PositionPrimaryUnitFrame(unitFrame, parentFrame, FrameDB)
	if not unitFrame or not FrameDB or not parentFrame then return end

	local xOffset = FrameDB.Layout[3]
	local yOffset = FrameDB.Layout[4]

	if GetAyije() and parentFrame == _G["UUF_CDMAnchor"] then
		xOffset = SnapCDMOffset(parentFrame, FrameDB.Layout[1], FrameDB.Layout[2], xOffset, FrameDB.Width, true)
		yOffset = SnapCDMOffset(parentFrame, FrameDB.Layout[1], FrameDB.Layout[2], yOffset, FrameDB.Height, false)
	end

	unitFrame:SetPoint(FrameDB.Layout[1], parentFrame, FrameDB.Layout[2], xOffset, yOffset)
end

local function ReapplyCDMPosition(unit)
	if unit ~= "player" and unit ~= "target" then return end

	local unitFrame = UUF[unit:upper()]
	local UnitDB = UUF.db and UUF.db.profile and UUF.db.profile.Units and UUF.db.profile.Units[unit]
	if not unitFrame or not UnitDB or not UnitDB.HealthBar.AnchorToCooldownViewer then return end

	local parentFrame = _G["UUF_CDMAnchor"]
	if not parentFrame then return end

	if InCombatLockdown() then
		protectedReanchorPending = true
		return
	end

	unitFrame:ClearAllPoints()
	UUF:PositionPrimaryUnitFrame(unitFrame, parentFrame, UnitDB.Frame)
end

local function ReapplyPrimaryFrames()
	if InCombatLockdown() then
		protectedReanchorPending = true
		return
	end

	protectedReanchorPending = false
	ReapplyCDMPosition("player")
	ReapplyCDMPosition("target")
end

local function RefreshAyijeAnchorTarget()
	local CDMAnchor = _G["UUF_CDMAnchor"]
	local AyijeAnchor = GetAyijeEssentialAnchor()
	if not CDMAnchor or not AyijeAnchor then return end

	CDMAnchor:ClearAllPoints()
	CDMAnchor:SetAllPoints(AyijeAnchor)
end

local function HookAyijeReanchor()
	if ayijeReanchorHooked then return end

	local CDM = GetAyije()
	if not CDM or not CDM.ForceReanchor then return end

	ayijeReanchorHooked = true
	hooksecurefunc(CDM, "ForceReanchor", function(_, viewer)
		if not viewer or not viewer.GetName or viewer:GetName() ~= "EssentialCooldownViewer" then return end
		C_Timer.After(0, function()
			RefreshAyijeAnchorTarget()
			ReapplyPrimaryFrames()
		end)
	end)
end

local PositionRecoveryFrame = CreateFrame("Frame")
PositionRecoveryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
PositionRecoveryFrame:SetScript("OnEvent", function()
	if not protectedReanchorPending then return end
	C_Timer.After(0, ReapplyPrimaryFrames)
end)

hooksecurefunc(UUF, "UpdateUnitHealthBar", function(_, _, unit)
	ReapplyCDMPosition(unit)
end)

function UUF:CreatePositionController()
	local ECDM = ""

	if C_AddOns.IsAddOnLoaded("SkironCooldownManager") then
		ECDM = _G["SCM_GroupAnchor_1"]
	elseif C_AddOns.IsAddOnLoaded("Coolinator") then
		ECDM = _G["CoolinatorPrimaryGroupAnchor"]
	elseif GetAyije() then
		ECDM = GetAyijeEssentialAnchor() or _G["EssentialCooldownViewer"]
	else
		ECDM = _G["EssentialCooldownViewer"]
	end

	if ECDM and ECDM:IsShown() then
		local CDMAnchor = CreateFrame("Frame", "UUF_CDMAnchor", UIParent)
		CDMAnchor:SetAllPoints(ECDM)
		HookAyijeReanchor()
		C_Timer.After(0, ReapplyPrimaryFrames)
	else
		UUF:PrettyPrint("|cFF8080FFAnchor Point|r was not found.")
	end
end