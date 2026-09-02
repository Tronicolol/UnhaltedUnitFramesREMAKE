local _, UUF = ...

local originalLayoutGroupFrames = UUF.LayoutGroupFrames
local rosterRelayoutPending = false

local function SortPartyFrames(frames, FrameDB)
	table.sort(frames, function(firstFrame, secondFrame)
		if FrameDB.SortBy == "NAME" then
			return (UnitName(firstFrame.unit) or firstFrame.unit or "") < (UnitName(secondFrame.unit) or secondFrame.unit or "")
		elseif FrameDB.SortBy == "ROLE" then
			local firstRole = UUF.PARTY_TEST_MODE and firstFrame.testRole or UnitGroupRolesAssigned(firstFrame.unit)
			local secondRole = UUF.PARTY_TEST_MODE and secondFrame.testRole or UnitGroupRolesAssigned(secondFrame.unit)
			if firstRole ~= secondRole then
				for _, orderedRole in ipairs(FrameDB.RoleOrder or {}) do
					if firstRole == orderedRole then return true end
					if secondRole == orderedRole then return false end
				end
			end
		end
		return (firstFrame.partyIndex or 0) < (secondFrame.partyIndex or 0)
	end)
end

local function GetActivePartyFrames(FrameDB)
	local activeFrames = {}
	for _, partyFrame in ipairs(UUF.PARTY_FRAMES or {}) do
		local unit = partyFrame == UUF.PARTYPLAYER and "player" or partyFrame.unit
		if UUF.PARTY_TEST_MODE or unit and UnitExists(unit) then
			activeFrames[#activeFrames + 1] = partyFrame
		end
	end
	SortPartyFrames(activeFrames, FrameDB)
	return activeFrames
end

local function CenterActivePartyFrames(FrameDB)
	if not UUF.PARTY_CONTAINER or not FrameDB then return end
	if FrameDB.GrowthDirection ~= "LEFT" and FrameDB.GrowthDirection ~= "RIGHT" then return end

	local activeFrames = GetActivePartyFrames(FrameDB)
	if #activeFrames == 0 then return end

	local spacing = FrameDB.Layout[5] or 0
	local activeWidth = math.max((FrameDB.Width + spacing) * #activeFrames - spacing, FrameDB.Width)
	UUF.PARTY_CONTAINER:SetWidth(activeWidth)

	for index, partyFrame in ipairs(activeFrames) do
		partyFrame:ClearAllPoints()
		if FrameDB.GrowthDirection == "LEFT" then
			partyFrame:SetPoint("TOPRIGHT", UUF.PARTY_CONTAINER, "TOPRIGHT", -((index - 1) * (FrameDB.Width + spacing)), 0)
		else
			partyFrame:SetPoint("TOPLEFT", UUF.PARTY_CONTAINER, "TOPLEFT", (index - 1) * (FrameDB.Width + spacing), 0)
		end
	end
end

local function GetRaidAutoGroupCount(FrameDB)
	if not FrameDB.AutoAdjustGroups then return nil end
	local _, _, difficultyID = GetInstanceInfo()
	return (difficultyID == 14 or difficultyID == 15) and 6 or difficultyID == 16 and 4 or difficultyID == 233 and 5 or 8
end

local function IsRaidGroupEnabled(FrameDB, autoGroupCount, groupIndex)
	if autoGroupCount then return groupIndex <= autoGroupCount end
	return not FrameDB.Groups or FrameDB.Groups[groupIndex]
end

local function GetActiveRaidGroups(FrameDB, autoGroupCount)
	local activeGroups = {}
	if UUF.RAID_TEST_MODE then
		for groupIndex = 1, UUF.MAX_RAID_GROUPS do
			if IsRaidGroupEnabled(FrameDB, autoGroupCount, groupIndex) then activeGroups[groupIndex] = true end
		end
		return activeGroups
	end

	for raidIndex = 1, GetNumGroupMembers() do
		local _, _, subgroup = GetRaidRosterInfo(raidIndex)
		if subgroup and IsRaidGroupEnabled(FrameDB, autoGroupCount, subgroup) then activeGroups[subgroup] = true end
	end
	return activeGroups
end

local function CenterActiveRaidGroups(FrameDB)
	if not UUF.RAID_CONTAINER or not FrameDB then return end

	local unitGrowth, groupGrowth = (FrameDB.GrowthDirection or "RIGHT_DOWN"):match("^(%a+)_(%a+)$")
	unitGrowth = unitGrowth or "RIGHT"
	groupGrowth = groupGrowth or "DOWN"
	if groupGrowth ~= "LEFT" and groupGrowth ~= "RIGHT" then return end

	local autoGroupCount = GetRaidAutoGroupCount(FrameDB)
	local activeGroups = GetActiveRaidGroups(FrameDB, autoGroupCount)
	local activeGroupCount = 0
	for groupIndex = 1, UUF.MAX_RAID_GROUPS do
		if activeGroups[groupIndex] then activeGroupCount = activeGroupCount + 1 end
	end
	if activeGroupCount == 0 then return end

	local spacing = FrameDB.Layout[5] or 0
	local headerWidth = (unitGrowth == "UP" or unitGrowth == "DOWN") and FrameDB.Width or (FrameDB.Width + spacing) * UUF.MAX_RAID_FRAMES_PER_GROUP - spacing
	local activeWidth = math.max((headerWidth + spacing) * activeGroupCount - spacing, FrameDB.Width)
	UUF.RAID_CONTAINER:SetWidth(activeWidth)

	local activePosition = 0
	local inactivePosition = 0
	local horizontalAnchor = groupGrowth == "LEFT" and "RIGHT" or "LEFT"
	local verticalAnchor = unitGrowth == "DOWN" and "BOTTOM" or "TOP"
	local anchorPoint = verticalAnchor .. horizontalAnchor

	for groupIndex, header in ipairs(UUF.RAID_HEADERS or {}) do
		if IsRaidGroupEnabled(FrameDB, autoGroupCount, groupIndex) then
			local positionIndex
			if activeGroups[groupIndex] then
				activePosition = activePosition + 1
				positionIndex = activePosition
			else
				inactivePosition = inactivePosition + 1
				positionIndex = activeGroupCount + inactivePosition
			end

			header:ClearAllPoints()
			local xOffset = groupGrowth == "RIGHT" and (positionIndex - 1) * (headerWidth + spacing) or -((positionIndex - 1) * (headerWidth + spacing))
			header:SetPoint(anchorPoint, UUF.RAID_CONTAINER, anchorPoint, xOffset, 0)
		end
	end
end

local function ApplyActiveHorizontalCentering(groupType)
	if not UUF.db or not UUF.db.profile or not UUF.db.profile.Units then return end
	if groupType == "party" then
		CenterActivePartyFrames(UUF.db.profile.Units.party.Frame)
	elseif groupType == "raid" then
		CenterActiveRaidGroups(UUF.db.profile.Units.raid.Frame)
	end
end

function UUF:LayoutGroupFrames(groupType)
	originalLayoutGroupFrames(UUF, groupType)
	ApplyActiveHorizontalCentering(groupType)
end

local function RelayoutRosterGroups()
	if not UUF.db or not UUF.db.profile or not UUF.db.profile.Units then return end
	local PartyDB = UUF.db.profile.Units.party
	local RaidDB = UUF.db.profile.Units.raid
	if PartyDB and PartyDB.Enabled and UUF.PARTY_CONTAINER then UUF:LayoutGroupFrames("party") end
	if RaidDB and RaidDB.Enabled and UUF.RAID_CONTAINER then UUF:LayoutGroupFrames("raid") end
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
rosterFrame:SetScript("OnEvent", function(_, event)
	if event == "GROUP_ROSTER_UPDATE" then
		if InCombatLockdown() then
			rosterRelayoutPending = true
			return
		end
		C_Timer.After(0, RelayoutRosterGroups)
	elseif rosterRelayoutPending then
		rosterRelayoutPending = false
		C_Timer.After(0, RelayoutRosterGroups)
	end
end)
