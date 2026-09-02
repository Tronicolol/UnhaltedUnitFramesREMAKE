local _, UUF = ...

local function ReapplyCDMPosition(unit)
	if unit ~= "player" and unit ~= "target" then return end
	if not C_AddOns.IsAddOnLoaded("Ayije_CDM") then return end

	local unitFrame = UUF[unit:upper()]
	local UnitDB = UUF.db and UUF.db.profile and UUF.db.profile.Units and UUF.db.profile.Units[unit]
	if not unitFrame or not UnitDB or not UnitDB.HealthBar.AnchorToCooldownViewer then return end

	local parentFrame = _G["UUF_CDMAnchor"]
	if not parentFrame or not UUF.PositionPrimaryUnitFrame then return end

	unitFrame:ClearAllPoints()
	UUF:PositionPrimaryUnitFrame(unitFrame, unit, parentFrame, UnitDB.Frame)
end

local function ReapplyPrimaryFrames()
	ReapplyCDMPosition("player")
	ReapplyCDMPosition("target")
end

hooksecurefunc(UUF, "UpdateUnitHealthBar", function(_, _, unit)
	ReapplyCDMPosition(unit)
end)

hooksecurefunc(UUF, "SpawnUnitFrame", function(_, unit)
	ReapplyCDMPosition(unit)
end)

local Ayije = C_AddOns.IsAddOnLoaded("Ayije_CDM") and _G["Ayije_CDM"] or nil
if Ayije and Ayije.ForceReanchor then
	hooksecurefunc(Ayije, "ForceReanchor", function(_, viewer)
		if viewer and viewer.GetName and viewer:GetName() == "EssentialCooldownViewer" then
			C_Timer.After(0, ReapplyPrimaryFrames)
		end
	end)
end
