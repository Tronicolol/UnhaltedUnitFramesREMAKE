local _, UUF = ...

local CDM_ANCHOR_WIDTH = 300
local CDM_ANCHOR_HEIGHT = 48

local function GetPixelSnappedAnchorGeometry(anchor, referenceFrame)
    if not PixelUtil or not PixelUtil.GetPixelToUIUnitFactor then
        return 0, 0, CDM_ANCHOR_WIDTH, CDM_ANCHOR_HEIGHT
    end

    local centerX, centerY = referenceFrame:GetCenter()
    if not centerX or not centerY then
        return 0, 0, CDM_ANCHOR_WIDTH, CDM_ANCHOR_HEIGHT
    end

    local scale = anchor:GetEffectiveScale()
    if not scale or scale <= 0 then
        return 0, 0, CDM_ANCHOR_WIDTH, CDM_ANCHOR_HEIGHT
    end

    local pixelToUI = PixelUtil.GetPixelToUIUnitFactor()
    local widthPixels = math.max(1, math.floor(((CDM_ANCHOR_WIDTH * scale) / pixelToUI) + 0.5))
    local heightPixels = math.max(1, math.floor(((CDM_ANCHOR_HEIGHT * scale) / pixelToUI) + 0.5))

    local centerXPixels = (centerX * scale) / pixelToUI
    local centerYPixels = (centerY * scale) / pixelToUI

    local snappedCenterXPixels
    if widthPixels % 2 == 0 then
        snappedCenterXPixels = math.floor(centerXPixels + 0.5)
    else
        snappedCenterXPixels = math.floor(centerXPixels) + 0.5
    end

    local snappedCenterYPixels
    if heightPixels % 2 == 0 then
        snappedCenterYPixels = math.floor(centerYPixels + 0.5)
    else
        snappedCenterYPixels = math.floor(centerYPixels) + 0.5
    end

    local offsetX = (snappedCenterXPixels - centerXPixels) * pixelToUI / scale
    local offsetY = (snappedCenterYPixels - centerYPixels) * pixelToUI / scale
    local width = widthPixels * pixelToUI / scale
    local height = heightPixels * pixelToUI / scale

    return offsetX, offsetY, width, height
end

function UUF:CreatePositionController()
    local ECDM = ""

    if C_AddOns.IsAddOnLoaded("SkironCooldownManager") then
        ECDM = _G["SCM_GroupAnchor_1"]
    elseif C_AddOns.IsAddOnLoaded("Coolinator") then
        ECDM = _G["CoolinatorPrimaryGroupAnchor"]
    else
        ECDM = _G["EssentialCooldownViewer"]
    end

    if ECDM and ECDM:IsShown() then
        local CDMAnchor = _G["UUF_CDMAnchor"] or CreateFrame("Frame", "UUF_CDMAnchor", UIParent)
        local offsetX, offsetY, width, height = GetPixelSnappedAnchorGeometry(CDMAnchor, ECDM)

        -- EssentialCooldownViewer changes width with the active specialization.
        -- Keep a stable virtual box centered on it, but snap both the box size and
        -- its center to the physical pixel grid so LEFT/RIGHT margins are symmetric.
        CDMAnchor:ClearAllPoints()
        CDMAnchor:SetPoint("CENTER", ECDM, "CENTER", offsetX, offsetY)
        CDMAnchor:SetSize(width, height)
    else
        UUF:PrettyPrint("|cFF8080FFAnchor Point|r was not found.")
    end
end
