-- TurtleRestedXP - Draggable rested XP progress bar for Turtle WoW
-- Auto-shows when entering a resting zone, hides when leaving.

local ADDON_NAME = "TurtleRestedXP"
local userClosed = false
local optionsDialog = nil
local autoShow = true
local autoHide = true

local defaults = { autoShow = true, autoHide = true }

-- Tent/resting rate tracking (ported from RestBar)
local lastRestXP = 0
local isTrackingRest = false
local tickStartTime = 0
local accumulatedRest = 0
local knownTentCount = nil
local knownTimeToFull = nil
local rbLastUpd = 0

local function GetRestedPercent()
    local exhaustion = GetXPExhaustion()
    local maxXP = UnitXPMax("player")
    if not maxXP or maxXP <= 0 then return nil end
    if not exhaustion or exhaustion <= 0 then return 0 end
    return math.min((exhaustion / (maxXP * 1.5)) * 100, 100)
end

-- Frame
local mainFrame = CreateFrame("Frame", "TurtleRestedXPFrame", UIParent)
mainFrame:SetWidth(200)
mainFrame:SetHeight(30)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
mainFrame:SetMovable(true)
mainFrame:SetUserPlaced(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:Hide()

local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(mainFrame)
bg:SetTexture(0, 0, 0, 0.65)

mainFrame:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
mainFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

-- Label
local label = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -2)
label:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -18, -2)
label:SetJustifyH("LEFT")
label:SetTextColor(1, 1, 1, 1)
label:SetText("Rested: -")

-- Status bar
local bar = CreateFrame("StatusBar", nil, mainFrame)
bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 2, -14)
bar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetMinMaxValues(0, 100)
bar:SetValue(0)
bar:SetStatusBarColor(0.0, 0.55, 1.0, 1.0)

local barBg = bar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints(bar)
barBg:SetTexture(0.08, 0.08, 0.08, 0.9)

-- Close button
local closeBtn = CreateFrame("Button", nil, mainFrame)
closeBtn:SetWidth(14)
closeBtn:SetHeight(14)
closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -1)

local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
closeTex:SetAllPoints(closeBtn)
closeTex:SetJustifyH("CENTER")
closeTex:SetText("|cffff6060x|r")

closeBtn:SetScript("OnEnter", function()
    closeTex:SetText("|cffff2020x|r")
    GameTooltip:SetOwner(closeBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Close rested bar", 1, 0.4, 0.4)
    GameTooltip:Show()
end)
closeBtn:SetScript("OnLeave", function()
    closeTex:SetText("|cffff6060x|r")
    GameTooltip:Hide()
end)
closeBtn:SetScript("OnClick", function()
    mainFrame:Hide()
    if IsResting() then
        userClosed = true
    end
end)

local function GetRestSuffix()
    if knownTentCount and knownTentCount > 0 and knownTimeToFull and knownTimeToFull > 0 then
        local mins = math.floor(knownTimeToFull / 60)
        local timeStr
        if mins >= 60 then
            timeStr = string.format("%dh%dm", math.floor(mins / 60), mins - math.floor(mins / 60) * 60)
        elseif mins > 0 then
            timeStr = string.format("%dm", mins)
        else
            timeStr = "<1m"
        end
        local tentWord = knownTentCount == 1 and "tent" or "tents"
        return string.format(" - %d %s - %s", knownTentCount, tentWord, timeStr)
    end
    return ""
end

-- Update bar values and color
local function UpdateBar()
    local pct = GetRestedPercent()
    if pct == nil then
        bar:SetValue(0)
        bar:SetStatusBarColor(0.45, 0.45, 0.45, 1.0)
        label:SetText("Rested: N/A")
    elseif pct <= 0 then
        bar:SetValue(0)
        bar:SetStatusBarColor(0.45, 0.45, 0.45, 1.0)
        label:SetText("Rested: 0%")
    else
        bar:SetValue(pct)
        bar:SetStatusBarColor(0.0, 0.4 + (pct / 100) * 0.4, 1.0 - (pct / 100) * 0.5, 1.0)
        label:SetText(string.format("Rested: %.1f%%", pct) .. GetRestSuffix())
    end
end

-- Options Dialog
local function ShowOptionsDialog()
    if optionsDialog then
        optionsDialog:Show()
        return
    end
    optionsDialog = CreateFrame("Frame", "TurtleRestedXPOptionsDialog", UIParent)
    optionsDialog:SetWidth(200)
    optionsDialog:SetHeight(100)
    optionsDialog:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    optionsDialog:SetMovable(true)
    optionsDialog:EnableMouse(true)
    optionsDialog:RegisterForDrag("LeftButton")
    optionsDialog:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    optionsDialog:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    local bg = optionsDialog:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(optionsDialog)
    bg:SetTexture(0, 0, 0, 0.65)

    -- Title
    local title = optionsDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", optionsDialog, "TOPLEFT", 8, -6)
    title:SetText("Turtle Rested XP")

    -- Auto Show Checkbox
    local showCB = CreateFrame("CheckButton", nil, optionsDialog, "UICheckButtonTemplate")
    showCB:SetPoint("TOPLEFT", optionsDialog, "TOPLEFT", 10, -26)
    showCB.text = optionsDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showCB.text:SetPoint("LEFT", showCB, "RIGHT", 2, 0)
    showCB.text:SetText("Auto show in city/inn/tent")
    showCB:SetChecked(autoShow)
    showCB:SetScript("OnClick", function()
        autoShow = this:GetChecked() and true or false
        if TurtleRestedXPDB then TurtleRestedXPDB.autoShow = autoShow end
    end)

    -- Auto Hide Checkbox
    local hideCB = CreateFrame("CheckButton", nil, optionsDialog, "UICheckButtonTemplate")
    hideCB:SetPoint("TOPLEFT", showCB, "BOTTOMLEFT", 0, -4)
    hideCB.text = optionsDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideCB.text:SetPoint("LEFT", hideCB, "RIGHT", 2, 0)
    hideCB.text:SetText("Auto hide when leaving")
    hideCB:SetChecked(autoHide)
    hideCB:SetScript("OnClick", function()
        autoHide = this:GetChecked() and true or false
        if TurtleRestedXPDB then TurtleRestedXPDB.autoHide = autoHide end
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, optionsDialog)
    closeBtn:SetWidth(14)
    closeBtn:SetHeight(14)
    closeBtn:SetPoint("TOPRIGHT", optionsDialog, "TOPRIGHT", -2, -1)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeTex:SetAllPoints(closeBtn)
    closeTex:SetJustifyH("CENTER")
    closeTex:SetText("|cffff6060x|r")
    closeBtn:SetScript("OnEnter", function()
        closeTex:SetText("|cffff2020x|r")
        GameTooltip:SetOwner(closeBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Close options", 1, 0.4, 0.4)
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetText("|cffff6060x|r")
        GameTooltip:Hide()
    end)
    closeBtn:SetScript("OnClick", function()
        optionsDialog:Hide()
    end)

    optionsDialog:SetScript("OnDragStart", function()
        optionsDialog:StartMoving()
    end)
    optionsDialog:SetScript("OnDragStop", function()
        optionsDialog:StopMovingOrSizing()
    end)
end

-- Slash command

SLASH_RESTEDXP1 = "/restedxp"
SlashCmdList["RESTEDXP"] = function(msg)
    msg = msg or ""
    msg = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    msg = string.lower(msg)
    if msg == "show" or msg == "toggle" then
        if mainFrame:IsShown() then
            mainFrame:Hide()
            userClosed = true
        else
            mainFrame:Show()
            userClosed = false
        end
    elseif msg == "reset" then
        mainFrame:StopMovingOrSizing()
        mainFrame:SetUserPlaced(false)
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        mainFrame:SetUserPlaced(true)
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473Turtle Rested XP:|r position reset to center.")
    else
        ShowOptionsDialog()
    end
end

-- Dragging
mainFrame:SetScript("OnDragStart", function()
    mainFrame:StartMoving()
end)
mainFrame:SetScript("OnDragStop", function()
    mainFrame:StopMovingOrSizing()
    mainFrame:SetUserPlaced(true)
end)

-- Tooltip
mainFrame:SetScript("OnEnter", function()
    GameTooltip:SetOwner(mainFrame, "ANCHOR_TOP")
    GameTooltip:SetText("Rested XP", 0.0, 0.75, 1.0)
    local pct = GetRestedPercent()
    if pct and pct > 0 then
        local pool = GetXPExhaustion()
        GameTooltip:AddLine(string.format("%.1f%% rested", pct), 1, 1, 1)
        if pool then
            GameTooltip:AddLine(string.format("%d XP in pool", pool), 0.75, 0.75, 0.75)
        end
    else
        GameTooltip:AddLine("No rested XP", 0.75, 0.75, 0.75)
    end
    GameTooltip:AddLine("|cffaaaaaa(Drag to move)|r")
    GameTooltip:Show()
end)
mainFrame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Events
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    UpdateBar()
    if event == "PLAYER_UPDATE_RESTING" or event == "PLAYER_ENTERING_WORLD" then
        if IsResting() and not userClosed then
            if autoShow then mainFrame:Show() end
        elseif not IsResting() then
            if autoHide then mainFrame:Hide() end
            userClosed = false
        end
    end
end)

-- Resting rate ticker: measures tent count and time to full rested (logic from RestBar)
local rbTicker = CreateFrame("Frame")
rbTicker:SetScript("OnUpdate", function()
    if GetTime() - rbLastUpd < 0.1 then return end
    rbLastUpd = GetTime()
    if UnitLevel("player") == 60 then return end

    local r = GetXPExhaustion() or 0
    local maxRest = UnitXPMax("player") * 1.5
    if lastRestXP == 0 then lastRestXP = r end
    local diff = r - lastRestXP
    lastRestXP = r

    if IsResting() then
        if not isTrackingRest then
            isTrackingRest = true
            tickStartTime = GetTime()
            accumulatedRest = 0
        end
        accumulatedRest = accumulatedRest + diff

        if GetTime() - tickStartTime >= 3 then
            tickStartTime = GetTime()
            if accumulatedRest > 0 then
                local ratePerSec = accumulatedRest / 3
                local tents = math.floor(ratePerSec / (maxRest * 0.001) + 0.5)
                if tents > 0 then
                    knownTentCount = tents
                    knownTimeToFull = (maxRest - r) / (tents * (maxRest * 0.001))
                else
                    knownTentCount = nil
                    knownTimeToFull = nil
                end
            else
                knownTentCount = nil
                knownTimeToFull = nil
            end
            accumulatedRest = 0
            UpdateBar()
        end
    else
        if isTrackingRest then
            isTrackingRest = false
            knownTentCount = nil
            knownTimeToFull = nil
            UpdateBar()
        end
    end
end)

-- Saved variables: restore options on load
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function()
    if arg1 ~= ADDON_NAME then return end
    if not TurtleRestedXPDB then TurtleRestedXPDB = {} end
    for k, v in pairs(defaults) do
        if TurtleRestedXPDB[k] == nil then TurtleRestedXPDB[k] = v end
    end
    autoShow = TurtleRestedXPDB.autoShow
    autoHide = TurtleRestedXPDB.autoHide
end)
