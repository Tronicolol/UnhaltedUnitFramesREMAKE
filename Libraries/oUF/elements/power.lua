--[[
# Element: Power Bar

Handles the updating of a status bar that displays the unit's power.

## Widget

Power - A `StatusBar` used to represent the unit's power.

## Sub-Widgets

.CostPrediction - A `StatusBar` used to represent the power cost of spells on top of the Power element.

## Notes

A default texture will be applied if the widget is a StatusBar and doesn't have a texture or a color set.

## Options

.frequentUpdates                  - Indicates whether to use UNIT_POWER_FREQUENT instead UNIT_POWER_UPDATE to update the
                                    bar (boolean)
.displayAltPower                  - Use this to let the widget display alternative power, if the unit has one.
                                    By default, it does so only for raid and party units. If none, the display will fall
                                    back to the primary power (boolean)
.considerSelectionInCombatHostile - Indicates whether selection should be considered hostile while the unit is in
                                    combat with the player (boolean)
.smoothing                        - Which status bar smoothing method to use, defaults to `Enum.StatusBarInterpolation.Immediate` (number)

The following options are listed by priority. The first check that returns true decides the color of the bar.

.colorDisconnected - Use `self.colors.disconnected` to color the bar if the unit is offline (boolean)
.colorTapping      - Use `self.colors.tapping` to color the bar if the unit isn't tapped by the player (boolean)
.colorThreat       - Use `self.colors.threat[threat]` to color the bar based on the unit's threat status. `threat` is
                     defined by the first return of [UnitThreatSituation](https://warcraft.wiki.gg/wiki/API_UnitThreatSituation) (boolean)
.colorPower        - Use `self.colors.power[token]` to color the bar based on the unit's power type. This method will
                     fall-back to the alternative power colors returned by [UnitPowerType](https://warcraft.wiki.gg/wiki/API_UnitPowerType)
                     if it can't find a color matching the token. If these aren't defined, then it will attempt to color
                     the bar based upon `self.colors.power[type]`. In case of failure it'll default to `self.colors.power.MANA` (boolean)
.colorPowerAtlas   - Use atlas from `self.colors.power[token]` to replace the texture whenever it's available. The previously
                     defined texture (if any) will be restored if the color changes to one that doesn't have an atlas.
                     Requires `.colorPower` to be enabled (boolean)
.colorPowerSmooth  - Use color curve from `self.colors.power[token]` to color the bar with a smooth gradient based on the unit's
                     current power percentage. Requires `.colorPower` to be enabled (boolean)
.colorClass        - Use `self.colors.class[class]` to color the bar based on unit class. `class` is defined by the
                     second return of [UnitClass](https://warcraft.wiki.gg/wiki/API_UnitClass) (boolean)
.colorClassNPC     - Use `self.colors.class[class]` to color the bar if the unit is a NPC (boolean)
.colorClassPet     - Use `self.colors.class[class]` to color the bar if the unit is player controlled, but not a player
                     (boolean)
.colorSelection    - Use `self.colors.selection[selection]` to color the bar based on the unit's outline/highlight
                     color. `selection` is defined by the return value of Private.unitSelectionType, a wrapper function
                     for [UnitSelectionType](https://warcraft.wiki.gg/wiki/API_UnitSelectionType) (boolean)
.colorReaction     - Use `self.colors.reaction[reaction]` to color the bar based on the player's reaction towards the
                     unit. `reaction` is defined by the return value of
                     [UnitReaction](https://warcraft.wiki.gg/wiki/API_UnitReaction) (boolean)

## Examples

    -- Position and size
    local Power = CreateFrame('StatusBar', nil, self)
    Power:SetHeight(20)
    Power:SetPoint('BOTTOM')
    Power:SetPoint('LEFT')
    Power:SetPoint('RIGHT')

    -- Optionally add CostPrediction sub-widget
    local CostPrediction = CreateFrame('StatusBar', nil, Power)
    CostPrediction:SetReverseFill(true)
    CostPrediction:SetPoint('TOP')
    CostPrediction:SetPoint('BOTTOM')
    CostPrediction:SetPoint('RIGHT', Power:GetStatusBarTexture())
    Power.CostPrediction = CostPrediction

    -- Options
    Power.frequentUpdates = true
    Power.colorTapping = true
    Power.colorDisconnected = true
    Power.colorPower = true
    Power.colorClass = true
    Power.colorReaction = true

    -- Register it with oUF
    self.Power = Power
--]]

local _, ns = ...
local oUF = ns.oUF
local Private = oUF.Private

local unitIsUnit = Private.unitIsUnit
local unitSelectionType = Private.unitSelectionType

-- sourced from Blizzard_UnitFrame/UnitPowerBarAlt.lua
local ALTERNATE_POWER_INDEX = Enum.PowerType.Alternate or 10

local function IsUsableValue(value)
	return value ~= nil and not issecretvalue(value)
end

local function SafeBoolean(value)
	if(value == nil or issecretvalue(value)) then
		return nil
	end
	return value
end

--[[ Override: Power:GetDisplayPower(unit)
Used to get info on the unit's alternative power, if any.
Should return the power type index (see [Enum.PowerType.Alternate](https://warcraft.wiki.gg/wiki/Enum.PowerType))
and the minimum value for the given power type (see [info.minPower](https://warcraft.wiki.gg/wiki/API_GetUnitPowerBarInfo))
or nil if the unit has no alternative (alternate) power or it should not be
displayed. In case of a nil return, the element defaults to the primary power
type and zero for the minimum value.

* self - the Power element
* unit - the unit for which the update has been triggered (string)
--]]
local function GetDisplayPower(_, unit)
	local barInfo = GetUnitPowerBarInfo(unit)
	if(not barInfo or issecretvalue(barInfo)) then return end

	local showOnRaid = SafeBoolean(barInfo.showOnRaid)
	if(showOnRaid ~= true) then return end

	local inParty = SafeBoolean(UnitInParty(unit))
	local inRaid = SafeBoolean(UnitInRaid(unit))
	if(inParty ~= true and inRaid ~= true) then return end

	local minPower = barInfo.minPower
	if(issecretvalue(minPower)) then
		minPower = nil
	end

	return ALTERNATE_POWER_INDEX, minPower
end

local function UpdateColor(self, event, unit)
	if(self.unit ~= unit) then return end
	local element = self.Power

	local isConnected = SafeBoolean(UnitIsConnected(unit))
	local isPlayerControlled = SafeBoolean(UnitPlayerControlled(unit))
	local isTapDenied = SafeBoolean(UnitIsTapDenied(unit))
	local isPlayer = SafeBoolean(UnitIsPlayer(unit))
	local isAI = SafeBoolean(UnitInPartyIsAI(unit))

	local threat = UnitThreatSituation('player', unit)
	if(not IsUsableValue(threat)) then threat = nil end

	local selection
	if(element.colorSelection) then
		selection = unitSelectionType(unit, element.considerSelectionInCombatHostile)
		if(not IsUsableValue(selection)) then selection = nil end
	end

	local reaction
	if(element.colorReaction) then
		reaction = UnitReaction(unit, 'player')
		if(not IsUsableValue(reaction)) then reaction = nil end
	end

	local r, g, b, color, atlas
	local hasRGB = false

	if(element.colorDisconnected and isConnected == false) then
		color = self.colors.disconnected
	elseif(element.colorTapping and isPlayerControlled == false and isTapDenied == true) then
		color = self.colors.tapped
	elseif(element.colorThreat and isPlayerControlled == false and threat ~= nil) then
		color = self.colors.threat[threat]
	elseif(element.colorPower) then
		if(IsUsableValue(element.displayType)) then
			color = self.colors.power[element.displayType]
		end

		if(not color) then
			local pType, pToken, altR, altG, altB = UnitPowerType(unit)

			if(IsUsableValue(pToken)) then
				color = self.colors.power[pToken]
			end

			if(not color) then
				local altRAvailable = issecretvalue(altR) or altR ~= nil
				local altGAvailable = issecretvalue(altG) or altG ~= nil
				local altBAvailable = issecretvalue(altB) or altB ~= nil

				if(altRAvailable and altGAvailable and altBAvailable) then
					r, g, b = altR, altG, altB
					hasRGB = true

					local rgbIsSecret = issecretvalue(r) or issecretvalue(g) or issecretvalue(b)
					if(not rgbIsSecret and (r > 1 or g > 1 or b > 1)) then
						-- Legacy API may return 0-255 values.
						r, g, b = r / 255, g / 255, b / 255
					end
				else
					if(IsUsableValue(pType)) then
						color = self.colors.power[pType]
					end
					color = color or self.colors.power.MANA
				end
			end
		end

		if(element.colorPowerAtlas and color) then
			atlas = color:GetAtlas()
		end

		if(element.colorPowerSmooth and color and color:GetCurve()) then
			local smoothColor = UnitPowerPercent(unit, nil, true, color:GetCurve())
			if(not issecretvalue(smoothColor)) then
				color = smoothColor
			end
		end
	else
		local wantsClassColor = false

		if(element.colorClass and (isPlayer == true or isAI == true)) then
			wantsClassColor = true
		elseif(element.colorClassNPC and isPlayer ~= nil and isAI ~= nil and not (isPlayer or isAI)) then
			wantsClassColor = true
		elseif(element.colorClassPet and isPlayerControlled == true and isPlayer == false) then
			wantsClassColor = true
		end

		if(wantsClassColor) then
			local _, class = UnitClass(unit)
			if(IsUsableValue(class)) then
				color = self.colors.class[class]
			end
		end

		if(not color and element.colorSelection and selection ~= nil) then
			color = self.colors.selection[selection]
		end

		if(not color and element.colorReaction and reaction ~= nil) then
			color = self.colors.reaction[reaction]
		end
	end

	if(atlas) then
		element:SetStatusBarTexture(atlas)
		element:GetStatusBarTexture():SetVertexColor(1, 1, 1)
	else
		if(element.__texture) then
			element:SetStatusBarTexture(element.__texture)
		end

		-- SetStatusBarColor puede recibir RGB protegidos; lo que no puede hacer
		-- el addon es compararlos o realizar aritmética con ellos.
		if(hasRGB) then
			element:SetStatusBarColor(r, g, b)
		elseif(color) then
			element:SetStatusBarColor(color:GetRGB())
		end
	end

	--[[ Callback: Power:PostUpdateColor(unit, color, altR, altG, altB)
	Called after the element color has been updated.

	* self  - the Power element
	* unit  - the unit for which the update has been triggered (string)
	* color - the used ColorMixin-based object (table?)
	* altR  - the red component of the used alternative color (number?)[0-1]
	* altG  - the green component of the used alternative color (number?)[0-1]
	* altB  - the blue component of the used alternative color (number?)[0-1]
	--]]
	if(element.PostUpdateColor) then
		element:PostUpdateColor(unit, color, r, g, b)
	end
end

local function ColorPath(self, ...)
	--[[ Override: Power.UpdateColor(self, event, unit)
	Used to completely override the internal function for updating the widgets' colors.

	* self  - the parent object
	* event - the event triggering the update (string)
	* unit  - the unit accompanying the event (string)
	--]]
	(self.Power.UpdateColor or UpdateColor) (self, ...)
end

local function Update(self, event, unit)
	if(self.unit ~= unit) then return end
	local element = self.Power

	--[[ Callback: Power:PreUpdate(unit)
	Called before the element has been updated.

	* self - the Power element
	* unit - the unit for which the update has been triggered (string)
	--]]
	if(element.PreUpdate) then
		element:PreUpdate(unit)
	end

	local displayType, min
	if(element.displayAltPower) then
		displayType, min = element:GetDisplayPower(unit)
	end

	local cur, max = UnitPower(unit, displayType), UnitPowerMax(unit, displayType)

	-- Un minimum protegido no puede evaluarse con "min or 0".
	if(issecretvalue(min) or min == nil) then
		min = 0
	end

	element:SetMinMaxValues(min, max)

	local isConnected = SafeBoolean(UnitIsConnected(unit))
	if(isConnected == false) then
		element:SetValue(max, element.smoothing)
	else
		-- Si el estado de conexión es secret, pasar cur directamente al
		-- StatusBar sigue siendo seguro; lo que evitamos es evaluarlo en Lua.
		element:SetValue(cur, element.smoothing)
	end

	element.cur = cur
	element.min = min
	element.max = max
	element.displayType = displayType

	--[[ Callback: Power:PostUpdate(unit, cur, min, max)
	Called after the element has been updated.

	* self - the Power element
	* unit - the unit for which the update has been triggered (string)
	* cur  - the unit's current power value (number)
	* min  - the unit's minimum possible power value (number)
	* max  - the unit's maximum possible power value (number)
	--]]
	if(element.PostUpdate) then
		element:PostUpdate(unit, cur, min, max)
	end
end

local function UpdatePrediction(self, event, unit)
	if(self.unit ~= unit) then return end

	local element = self.Power

	--[[ Callback: Power:PreUpdatePrediction(unit)
	Called before the element has been updated.

	* self - the Power element
	* unit - the unit for which the update has been triggered (string)
	--]]
	if(element.PreUpdatePrediction) then
		element:PreUpdatePrediction(unit)
	end

	local _, _, _, startTime, endTime, _, _, _, spellID = UnitCastingInfo(unit)
	local cost = 0

	local powerType = UnitPowerType(unit)
	if(element.displayAltPower) then
		powerType = element:GetDisplayPower(unit)
	end

	if(event == 'UNIT_SPELLCAST_START' and startTime ~= endTime) then
		local costTable = C_Spell.GetSpellPowerCost(spellID)
		if(not costTable) then return end

		-- hasRequiredAura is always false if there's only 1 subtable
		local checkRequiredAura = #costTable > 1

		for _, costInfo in next, costTable do
			if(not checkRequiredAura or costInfo.hasRequiredAura) then
				if(costInfo.type == powerType) then
					cost = costInfo.cost
					element.cost = cost

					break
				end
			end
		end
	elseif(spellID) then
		-- if we try to cast a spell while casting another one we need to avoid
		-- resetting the element
		cost = element.cost or 0
	else
		element.cost = cost
	end

	element.CostPrediction:SetMinMaxValues(0, UnitPowerMax(unit, powerType))
	element.CostPrediction:SetValue(cost)
	element.CostPrediction:Show()

	--[[ Callback: Power:PostUpdatePrediction(unit, cost)
	Called after the element has been updated.

	* self - the Power element
	* unit - the unit for which the update has been triggered (string)
	* cost - the power type cost of the cast ability (number)
	--]]
	if(element.PostUpdatePrediction) then
		return element:PostUpdatePrediction(unit, cost)
	end
end

local function UpdatePredictionSize(self, event, unit)
	local element = self.Power
	if(element.CostPrediction and element.__size) then
		element.CostPrediction[element.__isHoriz and 'SetWidth' or 'SetHeight'](element.CostPrediction, element.__size)
	end
end

local function shouldUpdatePredictionSize(self)
	local element = self.Power

	local isHoriz = element:GetOrientation() == 'HORIZONTAL'
	local newSize = element[isHoriz and 'GetWidth' or 'GetHeight'](element)
	if(isHoriz ~= element.__isHoriz or newSize ~= element.__size) then
		element.__isHoriz = isHoriz
		element.__size = newSize

		return true
	end
end

local function Path(self, ...)
	--[[ Override: Power.Override(self, event, unit, ...)
	Used to completely override the internal update function.

	* self  - the parent object
	* event - the event triggering the update (string)
	* unit  - the unit accompanying the event (string)
	* ...   - the arguments accompanying the event
	--]]
	local event = ...
	do
		(self.Power.Override or Update) (self, ...)
	end

	-- Party/Raid power type, colour and connectivity are refreshed by their
	-- dedicated lifecycle events. UNIT_POWER_UPDATE only changes the value, so
	-- UUF can opt out of the comparatively expensive generic ColorPath here.
	if(not (event == 'UNIT_POWER_UPDATE' and self.Power.UUFSkipColorOnPowerUpdate)) then
		ColorPath(self, ...)
	end
end

local function PredictionPath(self, ...)
	--[[ Override: Power.UpdatePredictionSize(self, event, unit, ...)
	Used to completely override the internal function for updating the cost prediction sub-widget's size.

	* self  - the parent object
	* event - the event triggering the update (string)
	* unit  - the unit accompanying the event (string)
	* ...   - the arguments accompanying the event
	--]]
	if(shouldUpdatePredictionSize(self)) then
		(self.Power.UpdatePredictionSize or UpdatePredictionSize) (self, ...)
	end

	--[[ Override: Power.OverridePrediction(self, event, unit, ...)
	Used to completely override the internal update function.

	* self  - the parent object
	* event - the event triggering the update (string)
	* unit  - the unit accompanying the event (string)
	* ...   - the arguments accompanying the event
	--]]
	do
		(self.Power.OverridePrediction or UpdatePrediction) (self, ...)
	end
end

local function ForceUpdate(element)
	Path(element.__owner, 'ForceUpdate', element.__owner.unit)

	if(element.CostPrediction) then
		PredictionPath(element.__owner, 'ForceUpdate', element.__owner.unit)
	end
end

--[[ Power:SetColorDisconnected(state, isForced)
Used to toggle coloring if the unit is offline.

* self     - the Power element
* state    - the desired state (boolean)
* isForced - forces the event update even if the state wasn't changed (boolean)
--]]
local function SetColorDisconnected(element, state, isForced) -- DEPRECATED
	if(element.colorDisconnected ~= state or isForced) then
		element.colorDisconnected = state
	end
end

--[[ Power:SetColorSelection(state, isForced)
Used to toggle coloring by the unit's selection.

* self     - the Power element
* state    - the desired state (boolean)
* isForced - forces the event update even if the state wasn't changed (boolean)
--]]
local function SetColorSelection(element, state, isForced)
	if(element.colorSelection ~= state or isForced) then
		element.colorSelection = state
		if(state) then
			element.__owner:RegisterEvent('UNIT_FLAGS', ColorPath)
		else
			element.__owner:UnregisterEvent('UNIT_FLAGS', ColorPath)
		end
	end
end

--[[ Power:SetColorTapping(state, isForced)
Used to toggle coloring if the unit isn't tapped by the player.

* self     - the Power element
* state    - the desired state (boolean)
* isForced - forces the event update even if the state wasn't changed (boolean)
--]]
local function SetColorTapping(element, state, isForced)
	if(element.colorTapping ~= state or isForced) then
		element.colorTapping = state
		if(state) then
			element.__owner:RegisterEvent('UNIT_FACTION', ColorPath)
		elseif(not element.colorReaction) then
			element.__owner:UnregisterEvent('UNIT_FACTION', ColorPath)
		end
	end
end

--[[ Power:SetColorReaction(state, isForced)
Used to toggle coloring by the unit's reaction.

* self     - the Power element
* state    - the desired state (boolean)
* isForced - forces the event update even if the state wasn't changed (boolean)
--]]
local function SetColorReaction(element, state, isForced)
	if(element.colorReaction ~= state or isForced) then
		element.colorReaction = state
		if(state) then
			element.__owner:RegisterEvent('UNIT_FACTION', ColorPath)
		elseif(not element.colorTapping) then
			element.__owner:UnregisterEvent('UNIT_FACTION', ColorPath)
		end
	end
end

--[[ Power:SetColorThreat(state, isForced)
Used to toggle coloring by the unit's threat status.

* self     - the Power element
* state    - the desired state (boolean)
* isForced - forces the event update even if the state wasn't changed (boolean)
--]]
local function SetColorThreat(element, state, isForced)
	if(element.colorThreat ~= state or isForced) then
		element.colorThreat = state
		if(state) then
			element.__owner:RegisterEvent('UNIT_THREAT_LIST_UPDATE', ColorPath)
		else
			element.__owner:UnregisterEvent('UNIT_THREAT_LIST_UPDATE', ColorPath)
		end
	end
end

--[[ Power:SetFrequentUpdates(state, isForced)
Used to toggle frequent updates.

* self     - the Power element
* state    - the desired state (boolean)
* isForced - forces the event update even if the state wasn't changed (boolean)
--]]
local function SetFrequentUpdates(element, state, isForced)
	if(element.frequentUpdates ~= state or isForced) then
		element.frequentUpdates = state
		if(state) then
			element.__owner:UnregisterEvent('UNIT_POWER_UPDATE', Path)
			element.__owner:RegisterEvent('UNIT_POWER_FREQUENT', Path)
		else
			element.__owner:UnregisterEvent('UNIT_POWER_FREQUENT', Path)
			element.__owner:RegisterEvent('UNIT_POWER_UPDATE', Path)
		end
	end
end

local function Enable(self, unit)
	local element = self.Power
	if(element) then
		element.__owner = self
		element.ForceUpdate = ForceUpdate
		element.SetColorDisconnected = SetColorDisconnected
		element.SetColorSelection = SetColorSelection
		element.SetColorTapping = SetColorTapping
		element.SetColorReaction = SetColorReaction
		element.SetColorThreat = SetColorThreat
		element.SetFrequentUpdates = SetFrequentUpdates

		if(not element.smoothing) then
			element.smoothing = Enum.StatusBarInterpolation.Immediate
		end

		if(element.colorSelection) then
			self:RegisterEvent('UNIT_FLAGS', ColorPath)
		end

		if(element.colorTapping or element.colorReaction) then
			self:RegisterEvent('UNIT_FACTION', ColorPath)
		end

		if(element.colorThreat) then
			self:RegisterEvent('UNIT_THREAT_LIST_UPDATE', ColorPath)
		end

		if(element.frequentUpdates) then
			self:RegisterEvent('UNIT_POWER_FREQUENT', Path)
		else
			self:RegisterEvent('UNIT_POWER_UPDATE', Path)
		end

		self:RegisterEvent('UNIT_DISPLAYPOWER', Path)
		self:RegisterEvent('UNIT_MAXPOWER', Path)
		self:RegisterEvent('UNIT_POWER_BAR_HIDE', Path)
		self:RegisterEvent('UNIT_POWER_BAR_SHOW', Path)
		self:RegisterEvent('UNIT_CONNECTION', Path)

		if(unit == 'party' or unit == 'raid') then
			self:RegisterEvent('PARTY_MEMBER_ENABLE', Path)
			self:RegisterEvent('PARTY_MEMBER_DISABLE', Path)
		end

		if(element:IsObjectType('StatusBar') and not element:GetStatusBarTexture()) then
			element:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
		end

		if(element.colorPowerAtlas) then
			element.__texture = element.__texture or element:GetStatusBarTexture():GetTexture()
		end

		if(not element.GetDisplayPower) then
			element.GetDisplayPower = GetDisplayPower
		end

		if(element.CostPrediction) then
			element.CostPrediction:Hide()

			if(unitIsUnit(unit, 'player')) then
				if(element.CostPrediction:IsObjectType('StatusBar') and not element.CostPrediction:GetStatusBarTexture()) then
					element.CostPrediction:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
				end

				self:RegisterEvent('UNIT_SPELLCAST_START', PredictionPath)
				self:RegisterEvent('UNIT_SPELLCAST_STOP', PredictionPath)
				self:RegisterEvent('UNIT_SPELLCAST_FAILED', PredictionPath)
				self:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED', PredictionPath)
			end
		end

		element:Show()

		return true
	end
end

local function Disable(self)
	local element = self.Power
	if(element) then
		element:Hide()

		self:UnregisterEvent('UNIT_DISPLAYPOWER', Path)
		self:UnregisterEvent('UNIT_MAXPOWER', Path)
		self:UnregisterEvent('UNIT_POWER_BAR_HIDE', Path)
		self:UnregisterEvent('UNIT_POWER_BAR_SHOW', Path)
		self:UnregisterEvent('UNIT_POWER_FREQUENT', Path)
		self:UnregisterEvent('UNIT_POWER_UPDATE', Path)
		self:UnregisterEvent('UNIT_CONNECTION', Path)
		self:UnregisterEvent('PARTY_MEMBER_ENABLE', Path)
		self:UnregisterEvent('PARTY_MEMBER_DISABLE', Path)
		self:UnregisterEvent('UNIT_FACTION', ColorPath)
		self:UnregisterEvent('UNIT_FLAGS', ColorPath)
		self:UnregisterEvent('UNIT_THREAT_LIST_UPDATE', ColorPath)

		if(element.CostPrediction) then
			element.CostPrediction:Hide()

			self:UnregisterEvent('UNIT_SPELLCAST_START', PredictionPath)
			self:UnregisterEvent('UNIT_SPELLCAST_STOP', PredictionPath)
			self:UnregisterEvent('UNIT_SPELLCAST_FAILED', PredictionPath)
			self:UnregisterEvent('UNIT_SPELLCAST_SUCCEEDED', PredictionPath)
		end
	end
end

oUF:AddElement('Power', Path, Enable, Disable)
