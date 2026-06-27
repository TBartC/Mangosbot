local Mangosbot_EventFrame = CreateFrame("Frame")
Mangosbot_EventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
Mangosbot_EventFrame:RegisterEvent("CHAT_MSG_WHISPER")
Mangosbot_EventFrame:RegisterEvent("CHAT_MSG_ADDON")
Mangosbot_EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
Mangosbot_EventFrame:RegisterEvent("UPDATE")
Mangosbot_EventFrame:Hide()

local ToolBars = {}
local GroupToolBars = {}

function SendBotCommand(text, chat, lang, channel)
    if (text == nil or text == "") then
        return
    end

    if (chat == "PARTY" and GetNumPartyMembers() == 0 and (GetNumRaidMembers == nil or GetNumRaidMembers() == 0)) then
        return
    end

    if (chat == "RAID" and (GetNumRaidMembers == nil or GetNumRaidMembers() == 0)) then
        chat = "PARTY"
        if (GetNumPartyMembers() == 0) then
            return
        end
    end

    if (chat == "WHISPER" and (channel == nil or channel == "")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot blocked whisper with no bot target: " .. text .. "|r")
        return
    end

    SendChatMessage(text, chat, lang, channel)
end

function SendBotAddonCommand(text, chat, lang, channel)
    SendBotCommand(text, chat, lang, channel)
end

-- Bartcraft raid fix:
-- In a raid, PARTY chat can miss bots in raid group 2+. Use RAID for group-wide
-- toolbar commands so the whole raid hears follow/stay/attack/formation commands.
function GetBotGroupChat()
    if (GetNumRaidMembers ~= nil and GetNumRaidMembers() > 0) then
        return "RAID"
    end
    return "PARTY"
end

function SendBotGroupCommand(text)
    SendBotCommand(text, GetBotGroupChat())
end

-- Bartcraft fix:
-- Some toolbar commands were written as "co +thing,?" / "nc +thing,?".
-- The trailing ,? is only a follow-up status query. It is valid bot syntax,
-- but on this server it clutters whispers and can make it look like the addon
-- sent a separate "?" command. Strip the query from action buttons, then
-- refresh the selected bot once after the action finishes.
function NormalizeBotCommand(text)
    if (text == nil) then
        return nil
    end

    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    if (text == "") then
        return nil
    end

    -- Your CMaNGOS build answers plain bot commands better than addon-prefixed commands.
    text = string.gsub(text, "^#a%s+", "")

    -- Remove only the appended status-query suffix from action commands.
    -- Pure queries like "co ?", "nc ?", "ll ?" are left alone elsewhere.
    text = string.gsub(text, ",%s*%?%s*$", "")

    return text
end



-- Bartcraft exact strategy helpers:
-- Green buttons now mean the bot really has that exact co/nc flag.
-- Clicking a green strategy button removes that same flag instead of adding/toggling it again.
function BartcraftTrimFlag(text)
    if (text == nil) then return "" end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function BartcraftAddFlag(map, family, flag)
    if (map == nil or family == nil or flag == nil or flag == "") then
        return
    end

    if (map[family] == nil) then
        map[family] = {}
    end

    for i = 1, table.getn(map[family]) do
        if (map[family][i] == flag) then
            return
        end
    end

    table.insert(map[family], flag)
end

function BartcraftHasAnyFlags(map)
    if (map == nil) then return false end
    if (map["co"] ~= nil and table.getn(map["co"]) > 0) then return true end
    if (map["nc"] ~= nil and table.getn(map["nc"]) > 0) then return true end
    return false
end

function BartcraftParseFlagCommand(command)
    local clean = NormalizeBotCommand(command)
    if (clean == nil) then
        return nil, nil, nil
    end

    local family, op, flag = string.match(clean, "^(co)%s*([%+%-%~])%s*(.+)$")
    if (family == nil) then
        family, op, flag = string.match(clean, "^(nc)%s*([%+%-%~])%s*(.+)$")
    end

    if (family == nil) then
        return nil, nil, nil
    end

    flag = BartcraftTrimFlag(flag)
    if (flag == "" or flag == "?") then
        return nil, nil, nil
    end

    return family, op, flag
end

function BartcraftGetButtonFlagMap(button)
    if (button == nil) then
        return { co = {}, nc = {} }
    end

    if (button["flagMap"] ~= nil) then
        return button["flagMap"]
    end

    local map = { co = {}, nc = {} }

    if (button["command"] ~= nil) then
        for key, command in pairs(button["command"]) do
            local family, op, flag = BartcraftParseFlagCommand(command)

            -- +flag and ~flag both mean this button represents that active strategy.
            -- -flag commands are cleanup only and should not light the button green.
            if (family ~= nil and (op == "+" or op == "~")) then
                BartcraftAddFlag(map, family, flag)
            end
        end
    end

    -- Fallback for older buttons that only define button.strategy.
    if (not BartcraftHasAnyFlags(map) and button["strategy"] ~= nil and button["strategy"] ~= "") then
        BartcraftAddFlag(map, "co", button["strategy"])
        BartcraftAddFlag(map, "nc", button["strategy"])
    end

    button["flagMap"] = map
    return map
end

function BartcraftBotHasFlag(bot, family, flag)
    if (bot == nil or bot["strategy"] == nil or bot["strategy"][family] == nil) then
        return false
    end

    for i = 1, table.getn(bot["strategy"][family]) do
        if (bot["strategy"][family][i] == flag) then
            return true
        end
    end

    return false
end

function BartcraftBotHasAllFlags(bot, family, flags)
    if (flags == nil or table.getn(flags) == 0) then
        return false
    end

    for i = 1, table.getn(flags) do
        if (not BartcraftBotHasFlag(bot, family, flags[i])) then
            return false
        end
    end

    return true
end

function BartcraftBotHasFlagAnyFamily(bot, flag)
    if (BartcraftBotHasFlag(bot, "co", flag)) then
        return true
    end

    if (BartcraftBotHasFlag(bot, "nc", flag)) then
        return true
    end

    return false
end

function BartcraftBotHasAllFlagsAnyFamily(bot, flags)
    if (flags == nil or table.getn(flags) == 0) then
        return false
    end

    for i = 1, table.getn(flags) do
        if (not BartcraftBotHasFlagAnyFamily(bot, flags[i])) then
            return false
        end
    end

    return true
end



-- Bartcraft role/spec alias helpers:
-- Playerbot can report real spec package strategies such as "protection pve"
-- or "restoration pve" instead of plain "tank"/"heal"/"dps".
-- These helpers let the panel light the pet-style role buttons from what the bot
-- actually reports.
BartcraftRoleAliases = {
    ["tank"] = {
        "tank", "tank assist", "tank aoe",
        "protection", "protection pve",
        "tank feral", "tank feral pve"
    },
    ["heal"] = {
        "heal", "healer",
        "holy", "holy pve",
        "restoration", "restoration pve",
        "discipline", "discipline pve"
    },
    ["dps"] = {
        -- Do NOT include plain "dps assist" here. Healers/tanks often keep
        -- dps assist as a support/default flag, so it would light DPS incorrectly.
        "dps",
        "shadow", "shadow pve",
        "fire", "fire pve", "frost", "frost pve", "arcane", "arcane pve",
        "elemental", "elemental pve", "enhancement", "enhancement pve",
        "retribution", "retribution pve",
        "arms", "arms pve", "fury", "fury pve",
        "combat", "combat pve", "assassination", "assassination pve", "subtlety", "subtlety pve",
        "beast mastery", "beast mastery pve", "marksmanship", "marksmanship pve", "survival", "survival pve",
        "affliction", "affliction pve", "demonology", "demonology pve", "destruction", "destruction pve",
        "balance", "balance pve", "dps feral", "dps feral pve"
    }
}

function BartcraftBotHasAnyAlias(bot, role)
    local aliases = BartcraftRoleAliases[role]
    if (aliases == nil) then
        return false
    end

    for i = 1, table.getn(aliases) do
        if (BartcraftBotHasFlagAnyFamily(bot, aliases[i])) then
            return true
        end
    end

    return false
end

function BartcraftBotMatchesRole(bot, role)
    if (bot == nil or role == nil or role == "") then
        return false
    end

    -- Do not let offheal/offdps alone define the main role.
    -- Main role comes from actual spec/package strategies or plain tank/heal/dps.
    if (role == "tank") then
        return BartcraftBotHasAnyAlias(bot, "tank")
    end

    if (role == "heal") then
        return BartcraftBotHasAnyAlias(bot, "heal")
    end

    if (role == "dps") then
        return BartcraftBotHasAnyAlias(bot, "dps")
    end

    return false
end


function ButtonIsActiveForBot(button, bot)
    if (button ~= nil and button["roleButton"] ~= nil and button["roleButton"] ~= "") then
        return BartcraftBotMatchesRole(bot, button["roleButton"])
    end

    local map = BartcraftGetButtonFlagMap(button)

    -- Buttons should reflect the exact flags the bot reported, even if this
    -- playerbot build placed a combat-looking flag in the nc list or an nc flag in co.
    -- Example: a DPS button that represents "dps" + "dps assist" lights up if those
    -- exact flags are present in either co or nc.
    if (BartcraftBotHasAllFlags(bot, "co", map["co"])) then
        return true
    end

    if (BartcraftBotHasAllFlags(bot, "nc", map["co"])) then
        return true
    end

    if (BartcraftBotHasAllFlags(bot, "nc", map["nc"])) then
        return true
    end

    if (BartcraftBotHasAllFlags(bot, "co", map["nc"])) then
        return true
    end

    if (BartcraftBotHasAllFlagsAnyFamily(bot, map["co"])) then
        return true
    end

    if (BartcraftBotHasAllFlagsAnyFamily(bot, map["nc"])) then
        return true
    end

    return false
end

function ButtonHasStrategyFlags(button)
    return BartcraftHasAnyFlags(BartcraftGetButtonFlagMap(button))
end

function ButtonHasExplicitStrategyCommands(button)
    if (button == nil or button["command"] == nil) then
        return false
    end

    for key, command in pairs(button["command"]) do
        local family, op, flag = BartcraftParseFlagCommand(command)
        if (family ~= nil and (op == "+" or op == "~")) then
            return true
        end
    end

    return false
end

function BuildButtonOnCommands(button)
    -- Some buttons intentionally send cleanup commands before adding their active flag.
    -- Example: paladin blessing buttons remove every other blessing strategy, then
    -- add only the selected blessing. Do not rebuild those into plain +flags.
    if (button ~= nil and button["rawOnActivate"]) then
        return button["command"]
    end

    local map = BartcraftGetButtonFlagMap(button)
    local commands = {}
    local seen = {}
    local delay = 0
    local step = 0.15

    local function add(family, flag)
        flag = BartcraftTrimFlag(flag)
        if (family == nil or flag == nil or flag == "" or flag == "?" or seen[family .. ":" .. flag]) then
            return
        end

        seen[family .. ":" .. flag] = true
        commands[delay] = family .. " +" .. flag
        delay = delay + step
    end

    if (map["co"] ~= nil) then
        for i = 1, table.getn(map["co"]) do
            add("co", map["co"][i])
        end
    end

    if (map["nc"] ~= nil) then
        for i = 1, table.getn(map["nc"]) do
            add("nc", map["nc"][i])
        end
    end

    if (delay == 0) then
        return button["command"]
    end

    return commands
end

function ButtonHasIntendedFlags(button, bot)
    local map = BartcraftGetButtonFlagMap(button)
    local hasAny = false

    if (map["co"] ~= nil and table.getn(map["co"]) > 0) then
        hasAny = true
        if (not BartcraftBotHasAllFlags(bot, "co", map["co"])) then
            return false
        end
    end

    if (map["nc"] ~= nil and table.getn(map["nc"]) > 0) then
        hasAny = true
        if (not BartcraftBotHasAllFlags(bot, "nc", map["nc"])) then
            return false
        end
    end

    return hasAny
end

function BuildButtonOffCommands(button)
    local map = BartcraftGetButtonFlagMap(button)
    local commands = {}
    local seen = {}
    local delay = 0
    local step = 0.15

    local function add(family, flag)
        flag = BartcraftTrimFlag(flag)
        if (family == nil or flag == nil or flag == "" or flag == "?" or seen[family .. ":" .. flag]) then
            return
        end

        seen[family .. ":" .. flag] = true
        commands[delay] = family .. " -" .. flag
        delay = delay + step
    end

    local function addBoth(flag)
        add("co", flag)
        add("nc", flag)
    end

    -- Remove this button's own flags from BOTH co and nc. This handles this
    -- playerbot build reporting combat-looking strategies under Non Combat
    -- Strategies without making every normal button become a full wipe.
    if (map["co"] ~= nil) then
        for i = 1, table.getn(map["co"]) do
            addBoth(map["co"][i])
        end
    end

    if (map["nc"] ~= nil) then
        for i = 1, table.getn(map["nc"]) do
            addBoth(map["nc"][i])
        end
    end

    return commands
end


function CreateToolBar(frame, y, name, buttons, x, spacing, register)
    if (x == nil) then x = 5 end
    if (spacing == nil) then spacing = 5 end
    if (register == nil) then register = true end

    if (frame.toolbar == nil) then
        frame.toolbar = {}
    end

    local tb = CreateFrame("Frame", "Toolbar" .. name, frame)
    tb:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    tb:SetWidth(frame:GetWidth() - x - 5)
    tb:SetHeight(22)
    tb:SetBackdropColor(0,0,0,1.0)
    tb:SetBackdrop({
        edgeFile="Interface/ChatFrame/ChatFrameBackground",
        tile = false, tileSize = 16, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    tb:SetBackdropBorderColor(0,0,0,1.0)

    tb.buttons = {}
    for key, button in pairs(buttons) do
        local btn = CreateFrame("Button", "Toolbar" .. name .. key, tb)
        btn:SetPoint("TOPLEFT", tb, "TOPLEFT", button["index"] * (22 + spacing), 0)
        btn:SetWidth(20)
        btn:SetHeight(20)
        btn:SetBackdrop({
            edgeFile="Interface/ChatFrame/ChatFrameBackground",
            tile = false, tileSize = 16, edgeSize = 2,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        btn:SetBackdropBorderColor(0, 0, 0, 0.0)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonDown")
        btn["tooltip"] = button["tooltip"]
        btn:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(frame, "ANCHOR_TOPLEFT", 0, -frame:GetHeight() - 40)
          GameTooltip:SetText(btn["tooltip"])
          GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
        end)
        btn["command"] = button["command"]
        btn["emote"] = button["emote"]
        btn["group"] = button["group"]
        btn["handler"] = button["handler"]
        btn["roleButton"] = button["roleButton"]
        btn["rawOnActivate"] = button["rawOnActivate"]
        btn["strategy"] = button["strategy"]
        btn["formation"] = button["formation"]
        btn["rti"] = button["rti"]
        btn["loot"] = button["loot"]
        btn["savemana"] = button["savemana"]
        btn["ToolBarButtonOnClick"] = ToolBarButtonOnClick;
        btn:SetScript("OnClick", function()
            btn["ToolBarButtonOnClick"](btn, true)
        end)

        local image = CreateFrame("Frame", "Toolbar" .. name .. key .. "Image", btn)
        image:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        image:SetWidth(16)
        image:SetHeight(16)
        image.texture = image:CreateTexture(nil, "BACKGROUND")
        local filename = "Interface\\Addons\\Mangosbot\\Images\\" .. button["icon"] .. ".tga"
        image.texture:SetTexture(filename)
        image.texture:SetAllPoints()
        btn.image = image

        tb.buttons[key] = btn
    end

    frame.toolbar[name] = tb
    if (register) then
        ToolBars[name] = buttons
    end
    return buttons
end

function ClickToolBarButton(toolbar, button)
    local btn = ToolBars[toolbar][button];
    ToolBarButtonOnClick(btn, false)
end

function ClickGroupToolBarButton(toolbar, button)
    local btn = GroupToolBars[toolbar][button];
    ToolBarButtonOnClick(btn, false)
end

-- Bartcraft menu pin fix:
-- Individual bot buttons should whisper the bot whose control panel is open,
-- not whatever player/NPC/mob is currently targeted. This lets you keep a bot
-- menu open while targeting enemies, dummies, loot, or another player.
function GetPinnedBotName()
    if (SelectedBotPanel ~= nil and SelectedBotPanel.botName ~= nil and SelectedBotPanel.botName ~= "") then
        return SelectedBotPanel.botName
    end

    if (CurrentBot ~= nil and CurrentBot ~= "") then
        return CurrentBot
    end

    local name = GetUnitName("target")
    local selfName = GetUnitName("player")
    if (name ~= nil and UnitExists("target") and not UnitIsEnemy("target", "player") and UnitIsPlayer("target") and name ~= selfName) then
        return name
    end

    return nil
end

function OnKeyBindingDown(button)
    if (GetPinnedBotName() == nil) then
        ClickGroupToolBarButton("group_movement", button)
    else
        ClickToolBarButton("movement", button)
    end
end

function ToolBarButtonOnClick(btn, visual)
    if (btn["handler"] ~= nil) then
        btn["handler"]()
        return
    end

    if (visual) then
      btn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1.0)
    end

    if (btn["emote"] ~= nil) then
        DoEmote(btn["emote"])
    end

    local commands = btn["command"]

    if (btn["group"]) then
        -- Group buttons are always action buttons. Do not auto-wipe or toggle off
        -- based on one bot being green; that was making normal buttons feel destructive.
        local delay = 0
        for key, command in pairs(commands) do
            local cleanCommand = NormalizeBotCommand(command)
            if (cleanCommand ~= nil and cleanCommand ~= "") then
                wait(key, function(command) SendBotGroupCommand(command) end, cleanCommand)
            end
            if (delay < key) then delay = key end
        end

        -- Do not send tooltip text as a party command.
        -- The original addon did this, which causes junk like "Mana save level: ?"
        -- to be whispered/party-spammed and can confuse bot command parsing.
    else
        local bot = GetPinnedBotName()
        if (bot == nil or bot == "") then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot blocked individual command: no bot menu is selected.|r")
            return
        end

        -- Normal strategy buttons are now true on/off toggles only for their own flags.
        -- They do NOT wipe old strategies. Full wiping only happens from the wipe button.
        -- If a button is green only because the flag is showing in the wrong family
        -- (example: dps assist listed under nc), clicking it will still send the intended
        -- add command instead of removing everything.
        if (visual and ButtonHasStrategyFlags(btn)) then
            if (btn["isActive"]) then
                commands = BuildButtonOffCommands(btn)
            elseif (ButtonHasExplicitStrategyCommands(btn)) then
                commands = BuildButtonOnCommands(btn)
            end
        end

        local delay = 0
        for key, command in pairs(commands) do
            local cleanCommand = NormalizeBotCommand(command)
            if (cleanCommand ~= nil and cleanCommand ~= "") then
                wait(key, function(command, bot) SendBotCommand(command, "WHISPER", nil, bot) end, cleanCommand, bot)
            end
            if (delay < key) then delay = key end
        end

        -- Refresh after add/remove so the green buttons always mirror the real bot flags.
        if (bot ~= nil and bot ~= "") then
            wait(delay + 0.35, function(bot)
                LastBotQueryTime[bot] = nil
                QuerySelectedBot(bot, false)
            end, bot)
        end
    end
end

function ToggleButton(frame, toolbar, button, toggle)
    local btn = frame.toolbar[toolbar].buttons[button]
    btn["isActive"] = toggle

    if (toggle) then
        btn:SetBackdropBorderColor(0.2, 1.0, 0.2, 1.0)
    else
        btn:SetBackdropBorderColor(0, 0, 0, 0.0)
    end
end

function EnablePositionSaving(frame, frameName)
    frame:SetScript("OnMouseDown", function()
        local button = arg1

        -- Only left-click should move/save the window.
        -- Right-click was starting a move and could save a bad position/off-screen.
        if (button == "LeftButton") then
            this:StartMoving()
        elseif (button == "RightButton") then
            if (frameopts ~= nil) then
                frameopts[frameName] = nil
            end
            frame:StopMovingOrSizing()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER")
            DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Mangosbot reset " .. frameName .. " window position.|r")
        end
    end)

    frame:SetScript("OnMouseUp", function()
            local button = arg1

            -- Do not save frame positions from right-click or any non-left click.
            if (button ~= "LeftButton") then
                return
            end

            local self = frame
            self:StopMovingOrSizing()

            if (frameopts == nil) then
                frameopts = {}
            end
            if (frameopts[frameName] == nil) then
                frameopts[frameName] = {}
            end

            local opts = frameopts[frameName]
            local from, _, to, x, y = self:GetPoint()

            opts.anchorFrom = from
            opts.anchorTo = to

            if self.is_expanded then
                if opts.anchorFrom == "TOPLEFT" or opts.anchorFrom == "LEFT" or opts.anchorFrom == "BOTTOMLEFT" then
                    opts.offsetx = x
                elseif opts.anchorFrom == "TOP" or opts.anchorFrom == "CENTER" or opts.anchorFrom == "BOTTOM" then
                    opts.offsetx = x - 151/2
                elseif opts.anchorFrom == "TOPRIGHT" or opts.anchorFrom == "RIGHT" or opts.anchorFrom == "BOTTOMRIGHT" then
                    opts.offsetx = x - 151
                end
            else
                opts.offsetx = x
            end
            opts.offsety = y
        end)

    do
        -------------------------------------------------------------------------------
        -- Restore the panel's position on the screen.
        -------------------------------------------------------------------------------
        local function Reset_Position()
            local self = frame
            if (frameopts == nil) then
                frameopts = {}
            end
            if (frameopts[frameName] == nil) then
                frameopts[frameName] = {}
            end
            local opts = frameopts[frameName]

            self:ClearAllPoints()

            if opts.anchorTo == nil then
                self:SetPoint("CENTER", UIParent, "CENTER")
            else
                self:SetPoint(opts.anchorFrom, UIParent, opts.anchorTo, opts.offsetx, opts.offsety)
            end
        end

        frame:SetScript("OnShow", Reset_Position)
    end -- do-block
end
function ResizeBotPanel(frame, width, height)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame.header:SetWidth(frame:GetWidth())
    frame.header.text:SetWidth(frame.header:GetWidth())
    for toolbarName,toolbar in pairs(ToolBars) do
        frame.toolbar[toolbarName]:SetWidth(frame:GetWidth() - 10)
    end
end


function AddBartcraftCloseButton(parent, ownerFrame, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -3)
    btn:SetWidth(16)
    btn:SetHeight(16)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonDown")
    btn:SetBackdrop({
        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
        tile = false, tileSize = 16, edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropBorderColor(1.0, 0.2, 0.2, 1.0)

    btn.text = btn:CreateFontString(name .. "Text")
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.text:SetWidth(16)
    btn.text:SetHeight(16)
    btn.text:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    btn.text:SetText("X")

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_TOPLEFT", 0, -25)
        GameTooltip:SetText("Close")
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if (ownerFrame == SelectedBotPanel) then
            CurrentBot = nil
            ownerFrame.botName = nil
        end

        ownerFrame:Hide()
    end)

    return btn
end

function CreateBotRoster()
    local frame = CreateFrame("Frame", "BotRoster", UIParent)
    frame:Hide()
    frame:SetWidth(170)
    frame:SetHeight(175)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdropColor(0, 0, 0, 1.0)
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        tile = true, tileSize = 16, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:RegisterForDrag("LeftButton")

    EnablePositionSaving(frame, "BotRoster")
    frame.close = AddBartcraftCloseButton(frame, frame, "BotRosterClose")

    frame.items = {}
    for i = 1,10 do
        local item = CreateFrame("Frame", "BotRoster_Item" .. i, frame)
        item:SetPoint("TOPLEFT", frame, "TOPLEFT", i * 100, 0)
        item:SetWidth(96)
        item:SetHeight(40)
        item:SetBackdropColor(0,0,0,1)
        item:SetBackdrop({
            bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
            edgeFile="Interface/ChatFrame/ChatFrameBackground",
            tile = true, tileSize = 16, edgeSize = 2,
            insets = { left = 2, right = 2, top = 2, bottom = 0 }
        })
        item:SetBackdropBorderColor(0.8,0.8,0.8,1)

        item.text = item:CreateFontString("BotRoster_ItemHeader" .. i)
        item.text:SetPoint("TOPLEFT", item, "TOPLEFT", 20, 1)
        item.text:SetWidth(item:GetWidth())
        item.text:SetHeight(22)
        item.text:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
        item.text:SetJustifyH("LEFT")
        item.text:SetText("Click!")

        local cls = CreateFrame("Button", "BotRoster_ItemHeader" .. i .. "Image", item)
        cls:SetPoint("TOPLEFT", item, "TOPLEFT", 3, -3)
        cls:SetWidth(16)
        cls:SetHeight(16)
        cls:EnableMouse(true)
        cls:RegisterForClicks("LeftButtonDown")
        cls.texture = cls:CreateTexture(nil, "BACKGROUND")
        cls.texture:SetTexture("Interface\\Addons\\Mangosbot\\Images\\role_dps.tga")
        cls.texture:SetAllPoints()
        cls:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(item, "ANCHOR_TOPLEFT", 0, -item:GetHeight() - 40)
          GameTooltip:SetText("Bot Control Panel")
          GameTooltip:Show()
        end)
        cls:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
        end)
        item.cls = cls

        CreateToolBar(item, -18, "quickbar"..i, {
            ["login"] = {
                icon = "login",
                command = {[0] = ""},
                strategy = "",
                tooltip = "Bring bot online",
                index = 0
            },
            ["logout"] = {
                icon = "logout",
                command = {[0] = ""},
                tooltip = "Logout bot",
                strategy = "",
                index = 0
            },
            ["invite"] = {
                icon = "invite",
                command = {[0] = ""},
                tooltip = "Invite to your group",
                strategy = "",
                index = 1
            },
            ["leave"] = {
                icon = "leave",
                command = {[0] = ""},
                tooltip = "Remove from group",
                strategy = "",
                index = 1
            },
            ["whisper"] = {
                icon = "whisper",
                command = {[0] = ""},
                tooltip = "Start whisper chat",
                strategy = "",
                index = 2
            },
            ["summon"] = {
                icon = "summon",
                command = {[0] = ""},
                tooltip = "Summon at meeting stone",
                strategy = "",
                index = 3
            }
        }, 20, 0, false)
        local tb = item.toolbar["quickbar"..i]
        tb:SetBackdropBorderColor(0,0,0,0.0)
        tb.buttons["login"]:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, 0)
        tb.buttons["logout"]:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, 0)
        tb.buttons["invite"]:SetPoint("TOPLEFT", tb, "TOPLEFT", 16, 0)
        tb.buttons["leave"]:SetPoint("TOPLEFT", tb, "TOPLEFT", 16, 0)
        tb.buttons["whisper"]:SetPoint("TOPLEFT", tb, "TOPLEFT", 48, 0)
        tb.buttons["summon"]:SetPoint("TOPLEFT", tb, "TOPLEFT", 32, 0)

        item:Hide()
        frame.items[i] = item
        frame.ShowRequest = false
    end

    CreateToolBar(frame, 0, "quickbar", {
        ["login_all"] = {
            icon = "login",
            command = {[0] = ""},
            strategy = "",
            tooltip = "Bring all bots online",
            index = 0
        },
        ["logout_all"] = {
            icon = "logout",
            command = {[0] = ""},
            tooltip = "Logout all bots",
            strategy = "",
            index = 1
        },
        ["invite_all"] = {
            icon = "invite",
            command = {[0] = ""},
            tooltip = "Invite all bots to your group",
            strategy = "",
            index = 2
        },
        ["leave_all"] = {
            icon = "leave",
            command = {[0] = ""},
            tooltip = "Remove all bots from group",
            strategy = "",
            index = 3
        }
    }, 5, 0, false)
    frame.toolbar["quickbar"]:SetBackdropBorderColor(0,0,0,0.0)

    GroupToolBars["group_movement"] = CreateMovementToolBar(frame, 0, "group_movement", true, 5, 0, false)
    frame.toolbar["group_movement"]:SetBackdropBorderColor(0,0,0,0.0)

    GroupToolBars["group_formation"] = CreateFormationToolBar(frame, 0, "group_formation", true, 5, 0, false)
    frame.toolbar["group_formation"]:SetBackdropBorderColor(0,0,0,0.0)

    GroupToolBars["group_savemana"] = CreateSaveManaToolBar(frame, 0, "group_savemana", true, 5, 0, false)
    frame.toolbar["group_savemana"]:SetBackdropBorderColor(0,0,0,0.0)

    return frame
end

function CreateRtiToolBar(frame, y, name, group, x, spacing, register)
    return CreateToolBar(frame, -y, name, {
        ["rti_skull"] = {
            icon = "rti_skull",
            command = {[0] = "rti skull"},
            rti = "skull",
            tooltip = "Assign skull mark",
            index = 0,
            group = group
        },
        ["rti_cross"] = {
            icon = "rti_cross",
            command = {[0] = "rti cross"},
            rti = "cross",
            tooltip = "Assign cross mark",
            index = 1,
            group = group
        },
        ["rti_circle"] = {
            icon = "rti_circle",
            command = {[0] = "rti circle"},
            rti = "circle",
            tooltip = "Assign circle mark",
            index = 2,
            group = group
        },
        ["rti_star"] = {
            icon = "rti_star",
            command = {[0] = "rti star"},
            rti = "star",
            tooltip = "Assign star mark",
            index = 3,
            group = group
        },
        ["rti_square"] = {
            icon = "rti_square",
            command = {[0] = "rti square"},
            rti = "square",
            tooltip = "Assign square mark",
            index = 4,
            group = group
        },
        ["rti_triangle"] = {
            icon = "rti_triangle",
            command = {[0] = "rti triangle"},
            rti = "triangle",
            tooltip = "Assign triangle mark",
            index = 5,
            group = group
        },
        ["rti_diamond"] = {
            icon = "rti_diamond",
            command = {[0] = "rti diamond"},
            rti = "diamond",
            tooltip = "Assign diamond mark",
            index = 6,
            group = group
        }
    }, x, spacing, register)
end

function CreateMovementToolBar(frame, y, name, group, x, spacing, register)
    local tb = {
        ["follow_master"] = {
            icon = "follow_master",
            command = {[0] = "#a follow", [1] = "#a nc ?", [2] = "#a co ?"},
            strategy = "follow",
            tooltip = "Follow me",
            index = 0,
            group = group,
            emote = "follow"
        },
        ["stay"] = {
            icon = "stay",
            command = {[0] = "#a stay", [1] = "#a nc ?", [2] = "#a co ?"},
            strategy = "stay",
            tooltip = "Stay in place",
            index = 1,
            group = group,
            emote = "wait"
        }
    }
    local index = 2
    if (not group) then
        tb["runaway"] = {
            icon = "flee",
            command = {[0] = "#a co ~runaway,?"},
            strategy = "runaway",
            tooltip = "Run away from mobs",
            index = index,
            group = group
        }
        index = index + 1
        tb["guard"] = {
            icon = "guard",
            command = {[0] = "#a nc +guard,?"},
            strategy = "guard",
            tooltip = "Guard pre-set place",
            index = index,
            group = group
        }
        index = index + 1
        tb["grind"] = {
            icon = "grind",
            command = {[0] = "#a nc ~grind,?"},
            strategy = "grind",
            tooltip = "Aggresive mode (grinding)",
            index = index,
            group = group
        }
        index = index + 1
    end

    tb["passive"] = {
        icon = "passive",
        command = {[0] = "#a nc +passive,?", [1] = "#a co +passive,?"},
        strategy = "passive",
        tooltip = "Passive mode",
        index = index,
        group = group
    }
    index = index + 1

    tb["flee_passive"] = {
        icon = "flee_passive",
        command = {[0] = "#a flee", [1] = "#a nc ?", [2] = "#a co ?"},
        strategy = "",
        tooltip = "Flee",
        index = index,
        group = group,
        emote = "flee"
    }
    index = index + 1

    if (group) then
        tb["loot"] = {
            icon = "loot",
            command = {[0] = "d add all loot", [1] = "d loot"},
            strategy = "",
            tooltip = "Loot everything",
            index = index,
            group = group
        }
        index = index + 1
        tb["attack"] = {
            icon = "dps",
            command = {[0] = "d attack my target"},
            strategy = "",
            tooltip = "Attack my target",
            index = index,
            group = group
        }
        index = index + 1
        tb["pull"] = {
            icon = "tank_assist",
            command = {[0] = "#a @dps flee", [1] = "#a @heal flee", [2] = "#a @tank d attack my target"},
            strategy = "",
            tooltip = "Pull",
            index = index,
            group = group
        }
        index = index + 1
        tb["summon"] = {
            icon = "summon",
            command = {[0] = "summon"},
            strategy = "",
            tooltip = "Summon at meeting stone",
            index = index,
            group = group
        }
        index = index + 1
    end

    return CreateToolBar(frame, -y, name, tb, x, spacing, register)
end

function CreateFormationToolBar(frame, y, name, group, x, spacing, register)
    return CreateToolBar(frame, -y, name, {
        ["near"] = {
            icon = "formation_near",
            command = {[0] = "formation near"},
            formation = "near",
            tooltip = "Follow me",
            index = 0,
            group = group
        },
        ["melee"] = {
            icon = "formation_melee",
            command = {[0] = "formation melee"},
            formation = "melee",
            tooltip = "Melee formation",
            index = 1,
            group = group
        },
        ["arrow"] = {
            icon = "formation_arrow",
            command = {[0] = "formation arrow"},
            formation = "arrow",
            tooltip = "Tank first, dps last",
            index = 2,
            group = group
        },
        ["chaos"] = {
            icon = "formation_chaos",
            command = {[0] = "formation chaos"},
            formation = "chaos",
            tooltip = "Move freely",
            index = 3,
            group = group
        },
        ["line"] = {
            icon = "formation_line",
            command = {[0] = "formation line"},
            formation = "line",
            tooltip = "Form a line",
            index = 4,
            group = group
        },
        ["queue"] = {
            icon = "formation_queue",
            command = {[0] = "formation queue"},
            formation = "queue",
            tooltip = "Form a queue",
            index = 5,
            group = group
        },
        ["circle"] = {
            icon = "formation_circle",
            command = {[0] = "formation circle"},
            formation = "circle",
            tooltip = "Form a big circle",
            index = 6,
            group = group
        }
    }, x, spacing, register)
end

function CreateSaveManaToolBar(frame, y, name, group, x, spacing, register)
    local buttons = {};
    for i = 1, 5 do
        buttons["savemana"..i] = {
            icon = "savemana"..i,
            command = {[0] = "save mana "..i},
            tooltip = "Save mana level: "..(i>1 and "#"..i or "disabled"),
            index = i - 1,
            group = group,
            savemana = i
        }
    end
    return CreateToolBar(frame, -y, name, buttons, x, spacing, register)
end

function StartChat()
    local name = GetPinnedBotName()
    if (name == nil or name == "") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot cannot start whisper: no bot menu is selected.|r")
        return
    end

    local editBox = getglobal("ChatFrameEditBox")
    editBox:Show()
    editBox:SetFocus()
    editBox:SetText("/w " .. name .. " ")
end


-- Bartcraft role reset helpers:
-- Role buttons must SET a role, not just ADD one.  These commands first wipe
-- the common combat roles one by one, then add only the selected role.
-- Separate whispers are more reliable on this CMaNGOS/playerbot build than one
-- long comma command like "co +heal,-dps,-tank".
BartcraftCombatRoleClearList = {
    "heal",
    "healer",
    "dps",
    "dps assist",
    "tank",
    "tank aoe",
    "bear",
    "cat",
    "caster",
    "melee",
    "shadow",
    "holy",
    "aoe",
    "aoe restoration pve",
    "threat",
    "ranged",
    "offheal",
    "offheal pve",
    "restoration",
    "restoration pve"
}

function BuildCombatRoleCommands(a, b, c, d, e, f)
    local commands = {}
    local delay = 0
    local step = 0.15
    local seen = {}

    -- Role/strategy buttons are no longer destructive.
    -- They add their own combat strategies only. If the button is already active
    -- in the intended family, ToolBarButtonOnClick turns only those exact flags off.
    -- The big wipe button is the only thing that removes every current strategy.
    local adds = {a, b, c, d, e, f}
    for i = 1, table.getn(adds) do
        if (adds[i] ~= nil and adds[i] ~= "" and not seen[adds[i]]) then
            seen[adds[i]] = true
            commands[delay] = "co +" .. adds[i]
            delay = delay + step
        end
    end

    return commands
end

function BuildStrategyCommands(coFlags, ncFlags)
    local commands = {}
    local delay = 0
    local step = 0.15
    local seen = {}

    local function add(family, flag)
        flag = BartcraftTrimFlag(flag)
        if (family == nil or flag == nil or flag == "" or flag == "?" or seen[family .. ":" .. flag]) then
            return
        end

        seen[family .. ":" .. flag] = true
        commands[delay] = family .. " +" .. flag
        delay = delay + step
    end

    if (coFlags ~= nil) then
        for i = 1, table.getn(coFlags) do
            add("co", coFlags[i])
        end
    end

    if (ncFlags ~= nil) then
        for i = 1, table.getn(ncFlags) do
            add("nc", ncFlags[i])
        end
    end

    return commands
end


-- Bartcraft paladin blessing buttons:
-- ike3 AIPlayerbot manual blessing strategies are named
-- "blessing might", "blessing wisdom", "blessing kings", etc.
-- These buttons clear the generic/auto blessing packages and every other manual
-- blessing first, then add only the blessing the player picked to BOTH
-- combat and non-combat strategy lists.
BartcraftPaladinBlessingClearList = {
    "blessing",
    "blessing might",
    "blessing wisdom",
    "blessing kings",
    "blessing sanctuary",
    "blessing light",
    "blessing salvation",
    "blessing holy pve",
    "blessing protection pve",
    "blessing retribution pve",
    "blessing holy raid",
    "blessing protection raid",
    "blessing retribution raid",
    "blessing holy pvp",
    "blessing protection pvp",
    "blessing retribution pvp",
    "blessing pve",
    "blessing raid",
    "blessing pvp",
    "greater blessing",
    "greater blessing pve",
    "greater blessing raid",
    "greater blessing pvp"
}

function BuildExclusivePaladinBlessingCommands(selectedBlessing)
    local commands = {}
    local delay = 0
    local step = 0.10
    local seen = {}

    local function remove(family, flag)
        flag = BartcraftTrimFlag(flag)
        if (family == nil or flag == nil or flag == "" or flag == "?" or seen[family .. ":-" .. flag]) then
            return
        end

        seen[family .. ":-" .. flag] = true
        commands[delay] = family .. " -" .. flag
        delay = delay + step
    end

    -- Remove from both families because role/default buttons may have added
    -- generic or automatic blessing strategies to either strategy list.
    for i = 1, table.getn(BartcraftPaladinBlessingClearList) do
        remove("co", BartcraftPaladinBlessingClearList[i])
        remove("nc", BartcraftPaladinBlessingClearList[i])
    end

    selectedBlessing = BartcraftTrimFlag(selectedBlessing)
    if (selectedBlessing ~= nil and selectedBlessing ~= "" and selectedBlessing ~= "?") then
        delay = delay + 0.10
        commands[delay] = "co +" .. selectedBlessing
        delay = delay + step
        commands[delay] = "nc +" .. selectedBlessing
    end

    return commands
end

-- Bartcraft dangerous fear/CC cleanup:
-- Priest and warlock package strategies can show up as exact flags like
-- "cc shadow" in addition to plain "cc". The normal CC toggle only knows
-- about its own represented flag, so this helper is a dungeon-safe nuke button
-- that removes every current cc* flag plus known priest/warlock cc packages
-- from BOTH co and nc strategy lists.
BartcraftDangerousFearCcClearList = {
    "cc",
    "cc pve",
    "cc pvp",
    "cc raid",
    "cc shadow",
    "cc shadow pve",
    "cc shadow pvp",
    "cc shadow raid",
    "cc holy",
    "cc holy pve",
    "cc holy pvp",
    "cc holy raid",
    "cc discipline",
    "cc discipline pve",
    "cc discipline pvp",
    "cc discipline raid",
    "cc affliction",
    "cc affliction pve",
    "cc affliction pvp",
    "cc affliction raid",
    "cc demonology",
    "cc demonology pve",
    "cc demonology pvp",
    "cc demonology raid",
    "cc destruction",
    "cc destruction pve",
    "cc destruction pvp",
    "cc destruction raid",
    "fear",
    "fear pve",
    "fear pvp",
    "fear raid",
    "howl of terror",
    "howl of terror pve",
    "howl of terror pvp",
    "howl of terror raid"
}

function BartcraftStrategyLooksLikeCc(flag)
    flag = BartcraftTrimFlag(flag)
    if (flag == nil or flag == "") then
        return false
    end

    local lower = string.lower(flag)

    -- Exact cc or any package that begins with cc, such as "cc shadow".
    if (lower == "cc" or string.find(lower, "^cc%s") ~= nil) then
        return true
    end

    -- Extra safety for fear-named package strategies, if a build reports them.
    if (lower == "fear" or string.find(lower, "^fear%s") ~= nil) then
        return true
    end

    if (lower == "howl of terror" or string.find(lower, "^howl of terror%s") ~= nil) then
        return true
    end

    return false
end

function BartcraftAddDangerousCcFlag(flags, seen, flag)
    flag = BartcraftTrimFlag(flag)
    if (flag == nil or flag == "" or flag == "?") then
        return
    end

    local key = string.lower(flag)
    if (seen[key]) then
        return
    end

    seen[key] = true
    table.insert(flags, flag)
end

function BartcraftBuildDangerousFearCcOffCommands(bot)
    local flags = {}
    local seen = {}

    if (bot ~= nil and bot["strategy"] ~= nil) then
        if (bot["strategy"]["co"] ~= nil) then
            for i = 1, table.getn(bot["strategy"]["co"]) do
                if (BartcraftStrategyLooksLikeCc(bot["strategy"]["co"][i])) then
                    BartcraftAddDangerousCcFlag(flags, seen, bot["strategy"]["co"][i])
                end
            end
        end

        if (bot["strategy"]["nc"] ~= nil) then
            for i = 1, table.getn(bot["strategy"]["nc"]) do
                if (BartcraftStrategyLooksLikeCc(bot["strategy"]["nc"][i])) then
                    BartcraftAddDangerousCcFlag(flags, seen, bot["strategy"]["nc"][i])
                end
            end
        end
    end

    for i = 1, table.getn(BartcraftDangerousFearCcClearList) do
        BartcraftAddDangerousCcFlag(flags, seen, BartcraftDangerousFearCcClearList[i])
    end

    local commands = {}
    local delay = 0
    local step = 0.10

    for i = 1, table.getn(flags) do
        commands[delay] = "co -" .. flags[i]
        delay = delay + step
        commands[delay] = "nc -" .. flags[i]
        delay = delay + step
    end

    return commands, delay
end

function BartcraftRunDangerousFearCcOff(botName)
    if (botName == nil or botName == "") then
        return
    end

    local bot = botTable[botName]
    local commands, finalDelay = BartcraftBuildDangerousFearCcOffCommands(bot)
    local count = 0

    for delay, command in pairs(commands) do
        count = count + 1
        wait(delay, function(command, botName)
            SendBotCommand(command, "WHISPER", nil, botName)
        end, command, botName)
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Mangosbot removing dangerous fear/CC strategies from " .. botName .. ".|r")

    wait(finalDelay + 0.75, function(botName)
        LastBotQueryTime[botName] = nil
        QuerySelectedBot(botName, false)
    end, botName)
end

function DisableSelectedBotDangerousFearCc()
    local botName = GetPinnedBotName()

    if (botName == nil or botName == "") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot cannot remove fear/CC: no bot menu is selected.|r")
        return
    end

    -- Query first so exact package strategies like "cc shadow" are captured.
    LastBotQueryTime[botName] = nil
    SendBotAddonCommand("co ?", "WHISPER", nil, botName)
    wait(0.20, function(botName) SendBotAddonCommand("nc ?", "WHISPER", nil, botName) end, botName)
    wait(0.90, function(botName) BartcraftRunDangerousFearCcOff(botName) end, botName)
end



-- Strategies that commonly appear as default/playerbot package behavior.
-- The wipe button also removes every exact strategy currently reported by co ? / nc ?,
-- so this list is only a safety net for stale panels or server-side oddities.
BartcraftKnownStrategyClearList = {
    "default",
    "passive",
    "avoid mobs",
    "flee",
    "flee combat",
    "follow",
    "stay",
    "guard",
    "grind",
    "loot",
    "food",
    "chat",
    "custom::say",
    "ai chat",
    "boost",
    "buff",
    "buff elemental pve",
    "buff restoration pve",
    "bhealth",
    "bmana",
    "barmor",
    "bdps",
    "bspeed",
    "bthreat",
    "cure",
    "cure elemental pve",
    "cure restoration pve",
    "cc",
    "cc pve",
    "cc pvp",
    "cc raid",
    "cc shadow",
    "cc shadow pve",
    "cc holy",
    "cc holy pve",
    "cc discipline",
    "cc discipline pve",
    "cc affliction",
    "cc affliction pve",
    "cc demonology",
    "cc demonology pve",
    "cc destruction",
    "cc destruction pve",
    "cc restoration pve",
    "chase jump",
    "duel",
    "elemental",
    "elemental pve",
    "mount",
    "potions",
    "pvp",
    "racials",
    "roll",
    "totems",
    "quest",
    "rpg",
    "rpg bank",
    "rpg bg",
    "rpg explore",
    "rpg guild",
    "rpg maintenance",
    "rpg quest",
    "rpg vendor",
    "fish",
    "group",
    "guild"
}

function BartcraftAddUniqueStrategyFlag(list, seen, flag)
    flag = BartcraftTrimFlag(flag)
    if (flag == nil or flag == "" or flag == "?" or flag == "co" or flag == "nc") then
        return
    end

    if (seen[flag]) then
        return
    end

    seen[flag] = true
    table.insert(list, flag)
end

function BartcraftBuildCurrentStrategyWipeCommands(bot)
    local flags = {}
    local seen = {}

    if (bot ~= nil and bot["strategy"] ~= nil) then
        if (bot["strategy"]["co"] ~= nil) then
            for i = 1, table.getn(bot["strategy"]["co"]) do
                BartcraftAddUniqueStrategyFlag(flags, seen, bot["strategy"]["co"][i])
            end
        end

        if (bot["strategy"]["nc"] ~= nil) then
            for i = 1, table.getn(bot["strategy"]["nc"]) do
                BartcraftAddUniqueStrategyFlag(flags, seen, bot["strategy"]["nc"][i])
            end
        end
    end

    for i = 1, table.getn(BartcraftCombatRoleClearList) do
        BartcraftAddUniqueStrategyFlag(flags, seen, BartcraftCombatRoleClearList[i])
    end

    for i = 1, table.getn(BartcraftKnownStrategyClearList) do
        BartcraftAddUniqueStrategyFlag(flags, seen, BartcraftKnownStrategyClearList[i])
    end

    local commands = {}
    local delay = 0
    local step = 0.10

    for i = 1, table.getn(flags) do
        commands[delay] = "co -" .. flags[i]
        delay = delay + step
        commands[delay] = "nc -" .. flags[i]
        delay = delay + step
    end

    return commands, delay
end

function BartcraftRunFullStrategyWipe(botName)
    if (botName == nil or botName == "") then
        return
    end

    local bot = botTable[botName]
    local commands, finalDelay = BartcraftBuildCurrentStrategyWipeCommands(bot)
    local count = 0

    for delay, command in pairs(commands) do
        count = count + 1
        wait(delay, function(command, botName)
            SendBotCommand(command, "WHISPER", nil, botName)
        end, command, botName)
    end

    if (count == 0) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Mangosbot had no current strategies cached. Press refresh, then wipe again.|r")
        return
    end

    if (botTable[botName] ~= nil) then
        botTable[botName]["strategy"] = {co = {}, nc = {}}
        botTable[botName]["role"] = "dps"
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Mangosbot wiping " .. count .. " strategy removals from " .. botName .. ".|r")

    wait(finalDelay + 0.75, function(botName)
        LastBotQueryTime[botName] = nil
        QuerySelectedBot(botName, true)
    end, botName)
end

function WipeSelectedBotStrategies()
    local botName = GetPinnedBotName()

    if (botName == nil or botName == "") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot cannot wipe strategies: no bot menu is selected.|r")
        return
    end

    -- Pull the latest exact strategy list first, then wipe what the bot really reports.
    LastBotQueryTime[botName] = nil
    SendBotAddonCommand("co ?", "WHISPER", nil, botName)
    wait(0.20, function(botName) SendBotAddonCommand("nc ?", "WHISPER", nil, botName) end, botName)
    wait(0.90, function(botName) BartcraftRunFullStrategyWipe(botName) end, botName)
end

function BartcraftGuessRoleFromStrategies(bot)
    if (bot == nil or bot["strategy"] == nil) then
        return "dps"
    end

    -- Protection/feral tank packages should win over generic dps/aoe flags.
    if (BartcraftBotMatchesRole(bot, "tank")) then
        return "tank"
    end

    if (BartcraftBotMatchesRole(bot, "heal")) then
        return "heal"
    end

    return "dps"
end



-- Class/spec role requests.
-- This CMaNGOS/playerbot build changes real role from TALENTS first, then
-- rebuilds the default strategies from that spec with reset strats.
-- Correct command is: talents <premade spec name>
BartcraftSpecCommandTemplate = "talents %s"

BartcraftRoleProfiles = {
    ["WARRIOR"] = {
        dps = { spec = "pve fury", co = {"fury", "dps assist", "behind", "close", "aoe", "buff", "boost"}, nc = {"fury", "dps assist", "buff", "boost"} },
        tank = { spec = "pve prot", co = {"protection", "tank assist", "pull", "pull back", "close", "aoe", "buff", "boost"}, nc = {"protection", "tank assist", "buff", "boost"} }
    },
    ["PALADIN"] = {
        dps = { spec = "pve dps ret", co = {"retribution", "dps assist", "close", "cure", "aoe", "cc", "buff", "boost", "aura"}, nc = {"retribution", "dps assist", "cure", "buff", "boost", "aura"} },
        tank = { spec = "pve prot", co = {"protection", "tank assist", "pull", "pull back", "close", "cure", "aoe", "cc", "buff", "boost", "aura"}, nc = {"protection", "tank assist", "cure", "buff", "boost", "aura"} },
        heal = { spec = "pve holy", co = {"holy", "dps assist", "flee", "ranged", "cure", "buff", "boost", "aura"}, nc = {"holy", "dps assist", "cure", "buff", "boost", "aura"} }
    },
    ["HUNTER"] = {
        dps = { spec = "pve dps bm", co = {"beast mastery", "dps assist", "ranged", "pet", "aspect", "sting", "cc", "aoe", "buff", "boost"}, nc = {"beast mastery", "dps assist", "pet", "aspect", "buff", "boost"} }
    },
    ["ROGUE"] = {
        dps = { spec = "pve dps combat", co = {"combat", "dps assist", "close", "behind", "stealth", "poisons", "aoe", "cc", "buff", "boost"}, nc = {"combat", "dps assist", "stealth", "poisons", "buff", "boost"} }
    },
    ["PRIEST"] = {
        dps = { spec = "pve dps shadow", co = {"shadow", "dps assist", "flee", "ranged", "cure", "buff", "aoe", "boost"}, nc = {"shadow", "dps assist", "cure", "buff", "boost"} },
        heal = { spec = "pve heal holy", co = {"holy", "dps assist", "flee", "ranged", "cure", "buff", "aoe", "boost"}, nc = {"holy", "dps assist", "cure", "buff", "boost"} }
    },
    ["SHAMAN"] = {
        dps = { spec = "pve dps elem", co = {"elemental", "dps assist", "ranged", "aoe", "cc", "cure", "totems", "buff", "boost"}, nc = {"elemental", "dps assist", "aoe", "cc", "cure", "totems", "buff", "boost"} },
        melee = { spec = "pve dps enh", co = {"enhancement", "dps assist", "close", "aoe", "cc", "cure", "totems", "buff", "boost"}, nc = {"enhancement", "dps assist", "aoe", "cc", "cure", "totems", "buff", "boost"} },
        heal = { spec = "pve resto", co = {"restoration", "flee", "ranged", "dps assist", "cure", "totems", "buff", "boost"}, nc = {"restoration", "dps assist", "cure", "totems", "buff", "boost"} }
    },
    ["MAGE"] = {
        dps = { spec = "pve dps fire", co = {"fire", "dps assist", "flee", "ranged", "cc", "cure", "buff", "aoe", "boost"}, nc = {"fire", "dps assist", "cure", "buff", "boost"} }
    },
    ["WARLOCK"] = {
        dps = { spec = "pve dps destro", co = {"destruction", "dps assist", "flee", "ranged", "pet", "aoe", "buff", "boost", "curse"}, nc = {"destruction", "dps assist", "pet", "buff", "boost"} }
    },
    ["DRUID"] = {
        dps = { spec = "pve dps feral cat", co = {"dps feral", "dps assist", "close", "behind", "cure", "aoe", "cc", "buff", "boost"}, nc = {"dps feral", "dps assist", "cure", "buff", "boost"} },
        caster = { spec = "pve dps balance", co = {"balance", "dps assist", "flee", "ranged", "cure", "aoe", "cc", "buff", "boost"}, nc = {"balance", "dps assist", "cure", "buff", "boost"} },
        tank = { spec = "pve dps feral tank", co = {"tank feral", "tank assist", "pull", "pull back", "close", "cure", "aoe", "cc", "buff", "boost"}, nc = {"tank feral", "tank assist", "cure", "buff", "boost"} },
        heal = { spec = "pve resto", co = {"restoration", "dps assist", "flee", "ranged", "cure", "aoe", "cc", "buff", "boost"}, nc = {"restoration", "dps assist", "cure", "buff", "boost"} }
    }
}

function BartcraftGetRoleProfile(class, role)
    if (class == nil or role == nil) then
        return nil
    end

    local classProfiles = BartcraftRoleProfiles[class]
    if (classProfiles == nil) then
        return nil
    end

    return classProfiles[role]
end

function BartcraftGetSelectedBotClass(botName)
    if (botName ~= nil and botTable[botName] ~= nil and botTable[botName]["class"] ~= nil) then
        return string.upper(botTable[botName]["class"])
    end

    local unitClass = nil
    if (GetUnitName("target") == botName) then
        local tmp
        tmp, unitClass = UnitClass("target")
    end

    if (unitClass ~= nil) then
        return string.upper(unitClass)
    end

    return "UNKNOWN"
end

function BartcraftGetPreferredSpecForRole(class, role)
    local profile = BartcraftGetRoleProfile(class, role)
    if (profile == nil) then
        return nil
    end

    return profile["spec"]
end

function BartcraftAddRoleCommand(commands, delay, command)
    if (command == nil or command == "") then
        return delay
    end

    commands[delay] = command
    return delay + 0.18
end

function BartcraftBuildRoleModeCommands(role, class)
    local profile = BartcraftGetRoleProfile(class, role)
    if (profile == nil) then
        return nil, 0
    end

    local commands = {}
    local delay = 0

    if (profile["spec"] ~= nil and profile["spec"] ~= "") then
        delay = BartcraftAddRoleCommand(commands, delay, string.format(BartcraftSpecCommandTemplate, profile["spec"]))
        -- Rebuild the core's default strategies from the new talent tree.
        delay = BartcraftAddRoleCommand(commands, delay + 0.35, "reset strats")
    end

    if (profile["co"] ~= nil) then
        for i = 1, table.getn(profile["co"]) do
            delay = BartcraftAddRoleCommand(commands, delay, "co +" .. profile["co"][i])
        end
    end

    if (profile["nc"] ~= nil) then
        for i = 1, table.getn(profile["nc"]) do
            delay = BartcraftAddRoleCommand(commands, delay, "nc +" .. profile["nc"][i])
        end
    end

    delay = BartcraftAddRoleCommand(commands, delay + 0.25, "co ?")
    delay = BartcraftAddRoleCommand(commands, delay, "nc ?")

    return commands, delay
end

function BartcraftSetRoleMode(role)
    local botName = GetPinnedBotName()
    if (botName == nil or botName == "") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot cannot set role: no bot menu is selected.|r")
        return
    end

    local class = BartcraftGetSelectedBotClass(botName)
    local commands, finalDelay = BartcraftBuildRoleModeCommands(role, class)
    if (commands == nil) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot has no " .. role .. " role profile for " .. class .. ".|r")
        return
    end

    for key, command in pairs(commands) do
        wait(key, function(command, botName) SendBotCommand(command, "WHISPER", nil, botName) end, command, botName)
    end

    wait(finalDelay + 0.35, function(botName)
        LastBotQueryTime[botName] = nil
        QuerySelectedBot(botName, false)
    end, botName)

    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Mangosbot requested " .. role .. " mode for " .. botName .. " (" .. class .. ").|r")
end

function BartcraftSetDpsMode()
    BartcraftSetRoleMode("dps")
end

function BartcraftSetTankMode()
    BartcraftSetRoleMode("tank")
end

function BartcraftSetHealMode()
    BartcraftSetRoleMode("heal")
end


function CreateSelectedBotPanel()
    local frame = CreateFrame("Frame", "SelectedBotPanel", UIParent)
    frame:Hide()
    frame.botName = nil
    frame:SetWidth(170)
    frame:SetHeight(155)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdropColor(0, 0, 0, 1.0)
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/ChatFrame/ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropBorderColor(0.5,0.1,0.7,1)
    frame:RegisterForDrag("LeftButton")

    frame.header = CreateFrame("Frame", "SelectedBotPanelHeader", frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetWidth(frame:GetWidth())
    frame.header:SetHeight(22)
    frame.header:SetBackdropColor(0.5,0.1,0.7,1)
    frame.header:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/ChatFrame/ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 0,
        insets = { left = 2, right = 2, top = 2, bottom = 0 }
    })
    frame.header:SetBackdropBorderColor(0.5,0.1,0.7,1)

    frame.header.text = frame.header:CreateFontString("SelectedBotPanelHeaderText")
    frame.header.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, 0)
    frame.header.text:SetWidth(frame.header:GetWidth())
    frame.header.text:SetHeight(22)
    frame.header.text:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    frame.header.text:SetJustifyH("LEFT")
    frame.header.text:SetText("Click!")

    frame.header.role = CreateFrame("Frame", "SelectedBotPanelHeaderRole", frame.header)
    frame.header.role:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    frame.header.role:SetWidth(16)
    frame.header.role:SetHeight(16)
    frame.header.role.texture = frame.header.role:CreateTexture(nil, "BACKGROUND")
    frame.header.role.texture:SetTexture("Interface/Addons/Mangosbot/Images/role_dps.tga")
    frame.header.role.texture:SetAllPoints()
    frame.close = AddBartcraftCloseButton(frame.header, frame, "SelectedBotPanelClose")

    EnablePositionSaving(frame, "SelectedBotPanel")

    local y = 25
    CreateMovementToolBar(frame, y, "movement", false, 5, 5, true)

    y = y + 25
    CreateToolBar(frame, -y, "actions", {
        ["stats"] = {
            icon = "stats",
            command = {[0] = "stats"},
            strategy = "",
            tooltip = "Tell stats (XP, money, etc.)",
            index = 0
        },
        ["whisper"] = {
            icon = "whisper",
            command = {[0] = ""},
            tooltip = "Start whisper chat",
            strategy = "",
            handler = StartChat,
            index = 1
        },
        ["loot"] = {
            icon = "loot",
            command = {[0] = "d add all loot", [1] = "d loot"},
            strategy = "",
            tooltip = "Loot everything",
            index = 2
        },
        ["set_guard"] = {
            icon = "set_guard",
            command = {[0] = "position guard set"},
            strategy = "",
            tooltip = "Set guard position",
            index = 3
        },
        ["release"] = {
            icon = "release",
            command = {[0] = "release"},
            strategy = "",
            tooltip = "Release spirit",
            index = 4
        },
        ["revive"] = {
            icon = "revive",
            command = {[0] = "revive"},
            strategy = "",
            tooltip = "Revive at Spirit Healer",
            index = 5
        }
    })

    y = y + 25
    CreateToolBar(frame, -y, "inventory", {
        ["los"] = {
            icon = "los",
            command = {[0] = "los gos"},
            strategy = "",
            tooltip = "Show nearby game objects",
            index = 0
        },
        ["count"] = {
            icon = "count",
            command = {[0] = "c"},
            strategy = "",
            tooltip = "Show inventory",
            index = 1
        },
        ["bank"] = {
            icon = "bank",
            command = {[0] = "bank"},
            strategy = "",
            tooltip = "Show bank",
            index = 2
        },
        ["spells"] = {
            icon = "spells",
            command = {[0] = "spells"},
            strategy = "",
            tooltip = "Show tradeskill",
            index = 3
        },
        ["mail"] = {
            icon = "mail",
            command = {[0] = "mail ?"},
            strategy = "",
            tooltip = "Show mail",
            index = 4
        }
    })

    y = y + 25
    CreateFormationToolBar(frame, y, "formation", false, 5, 5, true)

    y = y + 25
    CreateSaveManaToolBar(frame, y, "savemana", false, 5, 5, true)

    y = y + 25
    CreateToolBar(frame, -y, "loot", {
        ["ll_normal"] = {
            icon = "ll_normal",
            command = {[0] = "ll normal"},
            loot = "normal",
            tooltip = "Loot tradeskill items only",
            index = 0
        },
        ["ll_gray"] = {
            icon = "ll_gray",
            command = {[0] = "ll gray"},
            loot = "gray",
            tooltip = "Loot gray items",
            index = 1
        },
        ["ll_disenchant"] = {
            icon = "ll_disenchant",
            command = {[0] = "ll disenchant"},
            loot = "disenchant",
            tooltip = "Loot BoE items for disenchanting",
            index = 2
        },
        ["ll_all"] = {
            icon = "ll_all",
            command = {[0] = "ll all"},
            loot = "all",
            tooltip = "Loot everything",
            index = 3
        }
    })

    y = y + 25
    CreateToolBar(frame, -y, "role_set", {
        ["wipe_roles"] = {
            icon = "passive",
            command = {[0] = ""},
            strategy = "",
            tooltip = "Wipe ALL current co/nc strategies",
            handler = WipeSelectedBotStrategies,
            index = 0
        },
        ["set_heal"] = {
            icon = "heal",
            command = {[0] = ""},
            strategy = "heal",
            roleButton = "heal",
            tooltip = "Request healer mode / healer premade spec",
            handler = BartcraftSetHealMode,
            index = 1
        },
        ["set_dps"] = {
            icon = "dps",
            command = {[0] = ""},
            strategy = "dps",
            roleButton = "dps",
            tooltip = "Request DPS mode / DPS premade spec",
            handler = BartcraftSetDpsMode,
            index = 2
        },
        ["set_tank"] = {
            icon = "tank",
            command = {[0] = ""},
            strategy = "tank",
            roleButton = "tank",
            tooltip = "Request tank mode / tank premade spec",
            handler = BartcraftSetTankMode,
            index = 3
        },
        ["set_tank_aoe"] = {
            icon = "tank_assist",
            command = BuildStrategyCommands({"tank assist", "aoe"}, {"tank assist"}),
            strategy = "tank assist",
            tooltip = "Toggle tank assist / AOE tank strategy",
            index = 4
        }
    })

    y = y + 25
    CreateToolBar(frame, -y, "attack_type", {
        ["tank_aoe"] = {
            icon = "tank_assist",
            command = BuildStrategyCommands({"tank assist", "aoe"}, {"tank assist"}),
            strategy = "tank assist",
            tooltip = "Grab aggro / tank assist",
            index = 0
        },
        ["dps_assist"] = {
            icon = "dps_assist",
            command = BuildStrategyCommands({"dps assist"}, {"dps assist"}),
            strategy = "dps assist",
            tooltip = "Assist the group target",
            index = 1
        },
        ["threat"] = {
            icon = "threat",
            command = {[0] = "co ~threat,?"},
            strategy = "threat",
            tooltip = "Keep threat level low",
            index = 2
        }
    })

    y = y + 25
    CreateRtiToolBar(frame, y, "rti", false, 5, 5, true)

    y = y + 25
    CreateToolBar(frame, -y, "generic", {
        ["potions"] = {
            icon = "potions",
            command = {[0] = "co ~potions,?"},
            strategy = "potions",
            tooltip = "Use health and mana potions",
            index = 0
        },
        ["food"] = {
            icon = "food",
            command = {[0] = "nc ~food,?"},
            strategy = "food",
            tooltip = "Use food and drinks",
            index = 1
        },
        ["cast_time"] = {
            icon = "cast_time",
            command = {[0] = "co ~cast time,?"},
            strategy = "cast time",
            tooltip = "Cast long spells cautiously",
            index = 2
        }
    })

    y = y + 25
    CreateToolBar(frame, -y, "CLASS_DRUID", {
        ["bear"] = {
            icon = "bear",
            command = BuildStrategyCommands({"tank feral", "tank assist", "pull", "pull back", "close"}, {"tank feral", "tank assist"}),
            strategy = "tank feral",
            tooltip = "Feral tank / bear strategy",
            index = 0
        },
        ["cat"] = {
            icon = "cat",
            command = BuildStrategyCommands({"dps feral", "dps assist", "close", "behind"}, {"dps feral", "dps assist"}),
            strategy = "dps feral",
            tooltip = "Feral cat DPS strategy",
            index = 1
        },
        ["caster"] = {
            icon = "caster",
            command = BuildStrategyCommands({"balance", "dps assist", "ranged"}, {"balance", "dps assist"}),
            strategy = "balance",
            tooltip = "Balance caster DPS strategy",
            index = 2
        },
        ["heal"] = {
            icon = "heal",
            command = BuildStrategyCommands({"restoration", "ranged", "cure"}, {"restoration", "cure"}),
            strategy = "restoration",
            tooltip = "Restoration healer strategy",
            index = 3
        },
        ["cure"] = {
            icon = "cure",
            command = BuildStrategyCommands({"cure"}, {"cure"}),
            strategy = "cure",
            tooltip = "Cure poisons/curses",
            index = 4
        }
    })
    CreateToolBar(frame, -y, "CLASS_HUNTER", {
        ["dps"] = {
            icon = "dps",
            command = BuildStrategyCommands({"dps assist", "ranged", "pet", "aspect", "sting"}, {"dps assist", "pet", "aspect"}),
            strategy = "dps assist",
            tooltip = "Hunter DPS assist strategy",
            index = 0
        },
        ["aspect"] = {
            icon = "bspeed",
            command = BuildStrategyCommands({"aspect"}, {"aspect"}),
            strategy = "aspect",
            tooltip = "Use hunter aspects",
            index = 1
        },
        ["pet"] = {
            icon = "bmana",
            command = BuildStrategyCommands({"pet"}, {"pet"}),
            strategy = "pet",
            tooltip = "Use hunter pet",
            index = 2
        },
        ["sting"] = {
            icon = "bdps",
            command = BuildStrategyCommands({"sting"}, nil),
            strategy = "sting",
            tooltip = "Use hunter stings",
            index = 3
        }
    })
    CreateToolBar(frame, -y, "CLASS_MAGE", {
        ["arcane"] = {
            icon = "arcane",
            command = BuildStrategyCommands({"arcane", "dps assist", "ranged"}, {"arcane", "dps assist"}),
            strategy = "arcane",
            tooltip = "Arcane mage strategy",
            index = 0
        },
        ["fire"] = {
            icon = "fire",
            command = BuildStrategyCommands({"fire", "dps assist", "ranged"}, {"fire", "dps assist"}),
            strategy = "fire",
            tooltip = "Fire mage strategy",
            index = 1
        },
        ["aoe"] = {
            icon = "fire_aoe",
            command = BuildStrategyCommands({"aoe"}, nil),
            strategy = "aoe",
            tooltip = "Use AOE spells",
            index = 2
        },
        ["frost"] = {
            icon = "frost",
            command = BuildStrategyCommands({"frost", "dps assist", "ranged"}, {"frost", "dps assist"}),
            strategy = "frost",
            tooltip = "Frost mage strategy",
            index = 3
        },
        ["cc"] = {
            icon = "frost_aoe",
            command = BuildStrategyCommands({"cc"}, nil),
            strategy = "cc",
            tooltip = "Use crowd control",
            index = 4
        },
        ["buff"] = {
            icon = "bmana",
            command = BuildStrategyCommands({"buff"}, {"buff"}),
            strategy = "buff",
            tooltip = "Buff party",
            index = 5
        },
        ["boost"] = {
            icon = "bdps",
            command = BuildStrategyCommands({"boost"}, {"boost"}),
            strategy = "boost",
            tooltip = "Use burst/boost abilities",
            index = 6
        },
        ["cure"] = {
            icon = "cure",
            command = BuildStrategyCommands({"cure"}, {"cure"}),
            strategy = "cure",
            tooltip = "Remove curses",
            index = 7
        }
    })
    CreateToolBar(frame, -y, "CLASS_PALADIN", {
        ["dps"] = {
            icon = "dps",
            command = BuildStrategyCommands({"retribution", "dps assist", "close"}, {"retribution", "dps assist"}),
            strategy = "retribution",
            tooltip = "Retribution DPS strategy",
            index = 0
        },
        ["tank"] = {
            icon = "tank",
            command = BuildStrategyCommands({"protection", "tank assist", "pull", "pull back", "close"}, {"protection", "tank assist"}),
            strategy = "protection",
            tooltip = "Protection tank strategy",
            index = 1
        },
        ["heal"] = {
            icon = "heal",
            command = BuildStrategyCommands({"holy", "ranged", "cure"}, {"holy", "cure"}),
            strategy = "holy",
            tooltip = "Holy healer strategy",
            index = 2
        },
        ["aura"] = {
            icon = "bmana",
            command = BuildStrategyCommands({"aura"}, {"aura"}),
            strategy = "aura",
            tooltip = "Use auras",
            index = 3
        },
        ["buff"] = {
            icon = "bdps",
            command = BuildStrategyCommands({"buff"}, {"buff"}),
            strategy = "buff",
            tooltip = "Buff party",
            index = 4
        },
        ["boost"] = {
            icon = "barmor",
            command = BuildStrategyCommands({"boost"}, {"boost"}),
            strategy = "boost",
            tooltip = "Use boost abilities",
            index = 5
        },
        ["cc"] = {
            icon = "bspeed",
            command = BuildStrategyCommands({"cc"}, nil),
            strategy = "cc",
            tooltip = "Use control/interrupt tools",
            index = 6
        },
        ["threat"] = {
            icon = "bthreat",
            command = BuildStrategyCommands({"threat"}, nil),
            strategy = "threat",
            tooltip = "Threat management",
            index = 7
        },
        ["cure"] = {
            icon = "cure",
            command = BuildStrategyCommands({"cure"}, {"cure"}),
            strategy = "cure",
            tooltip = "Cleanse party",
            index = 8
        }
    })

    CreateToolBar(frame, -(y + 25), "CLASS_PALADIN_BLESSINGS", {
        ["blessing_might"] = {
            icon = "bdps",
            command = BuildExclusivePaladinBlessingCommands("blessing might"),
            rawOnActivate = true,
            strategy = "blessing might",
            tooltip = "Blessing of Might: removes other blessing strategies, then adds this one to co and nc",
            index = 0
        },
        ["blessing_wisdom"] = {
            icon = "bmana",
            command = BuildExclusivePaladinBlessingCommands("blessing wisdom"),
            rawOnActivate = true,
            strategy = "blessing wisdom",
            tooltip = "Blessing of Wisdom: removes other blessing strategies, then adds this one to co and nc",
            index = 1
        },
        ["blessing_kings"] = {
            icon = "bhealth",
            command = BuildExclusivePaladinBlessingCommands("blessing kings"),
            rawOnActivate = true,
            strategy = "blessing kings",
            tooltip = "Blessing of Kings: removes other blessing strategies, then adds this one to co and nc",
            index = 2
        },
        ["blessing_sanctuary"] = {
            icon = "barmor",
            command = BuildExclusivePaladinBlessingCommands("blessing sanctuary"),
            rawOnActivate = true,
            strategy = "blessing sanctuary",
            tooltip = "Blessing of Sanctuary: removes other blessing strategies, then adds this one to co and nc",
            index = 3
        },
        ["blessing_light"] = {
            icon = "heal",
            command = BuildExclusivePaladinBlessingCommands("blessing light"),
            rawOnActivate = true,
            strategy = "blessing light",
            tooltip = "Blessing of Light: removes other blessing strategies, then adds this one to co and nc",
            index = 4
        },
        ["blessing_salvation"] = {
            icon = "bthreat",
            command = BuildExclusivePaladinBlessingCommands("blessing salvation"),
            rawOnActivate = true,
            strategy = "blessing salvation",
            tooltip = "Blessing of Salvation: removes other blessing strategies, then adds this one to co and nc",
            index = 5
        }
    })
    CreateToolBar(frame, -y, "CLASS_PRIEST", {
        ["heal"] = {
            icon = "heal",
            command = BuildStrategyCommands({"holy", "ranged", "cure"}, {"holy", "cure"}),
            strategy = "holy",
            tooltip = "Holy healer strategy",
            index = 0
        },
        ["discipline"] = {
            icon = "holy",
            command = BuildStrategyCommands({"discipline", "ranged", "cure"}, {"discipline", "cure"}),
            strategy = "discipline",
            tooltip = "Discipline healer strategy",
            index = 1
        },
        ["shadow"] = {
            icon = "shadow",
            command = BuildStrategyCommands({"shadow", "dps assist", "ranged"}, {"shadow", "dps assist"}),
            strategy = "shadow",
            tooltip = "Shadow DPS strategy",
            index = 2
        },
        ["aoe"] = {
            icon = "shadow_aoe",
            command = BuildStrategyCommands({"aoe"}, nil),
            strategy = "aoe",
            tooltip = "Use AOE",
            index = 3
        },
        ["cc"] = {
            icon = "shadow_debuff",
            command = BuildStrategyCommands({"cc"}, nil),
            strategy = "cc",
            tooltip = "Toggle basic priest CC. Use CC OFF to remove cc shadow and other fear CC packages too.",
            index = 4
        },
        ["cc_off"] = {
            icon = "bthreat",
            command = {},
            handler = DisableSelectedBotDangerousFearCc,
            strategy = "",
            tooltip = "CC OFF dungeon-safe: removes cc, cc shadow, and other fear CC packages from co and nc.",
            index = 5
        },
        ["cure"] = {
            icon = "cure",
            command = BuildStrategyCommands({"cure"}, {"cure"}),
            strategy = "cure",
            tooltip = "Cure diseases/magic",
            index = 6
        }
    })
    CreateToolBar(frame, -y, "CLASS_ROGUE", {
        ["dps"] = {
            icon = "dps",
            command = BuildStrategyCommands({"combat", "dps assist", "close", "behind"}, {"combat", "dps assist"}),
            strategy = "combat",
            tooltip = "Combat rogue DPS strategy",
            index = 0
        },
        ["stealth"] = {
            icon = "shadow",
            command = BuildStrategyCommands({"stealth"}, {"stealth"}),
            strategy = "stealth",
            tooltip = "Use stealth",
            index = 1
        },
        ["poisons"] = {
            icon = "cure",
            command = BuildStrategyCommands({"poisons"}, {"poisons"}),
            strategy = "poisons",
            tooltip = "Use poisons",
            index = 2
        }
    })
    CreateToolBar(frame, -y, "CLASS_SHAMAN", {
        ["caster"] = {
            icon = "caster",
            command = BuildStrategyCommands({"elemental", "dps assist", "ranged", "aoe", "cc"}, {"elemental", "dps assist", "aoe", "cc"}),
            strategy = "elemental",
            tooltip = "Elemental caster DPS strategy",
            index = 0
        },
        ["aoe"] = {
            icon = "caster_aoe",
            command = BuildStrategyCommands({"aoe"}, {"aoe"}),
            strategy = "aoe",
            tooltip = "Use AOE abilities",
            index = 1
        },
        ["heal"] = {
            icon = "heal",
            command = BuildStrategyCommands({"restoration", "ranged", "cure"}, {"restoration", "cure"}),
            strategy = "restoration",
            tooltip = "Restoration healer strategy",
            index = 2
        },
        ["melee"] = {
            icon = "dps",
            command = BuildStrategyCommands({"enhancement", "dps assist", "close", "aoe", "cc"}, {"enhancement", "dps assist", "aoe", "cc"}),
            strategy = "enhancement",
            tooltip = "Enhancement melee DPS strategy",
            index = 3
        },
        ["cc"] = {
            icon = "aoe",
            command = BuildStrategyCommands({"cc"}, {"cc"}),
            strategy = "cc",
            tooltip = "Use CC/interrupt tools",
            index = 4
        },
        ["totems"] = {
            icon = "totems",
            command = BuildStrategyCommands({"totems"}, {"totems"}),
            strategy = "totems",
            tooltip = "Use totems",
            index = 5
        },
        ["buff"] = {
            icon = "bmana",
            command = BuildStrategyCommands({"buff"}, {"buff"}),
            strategy = "buff",
            tooltip = "Buff party",
            index = 6
        },
        ["boost"] = {
            icon = "bdps",
            command = BuildStrategyCommands({"boost"}, {"boost"}),
            strategy = "boost",
            tooltip = "Use boost abilities",
            index = 7
        },
        ["cure"] = {
            icon = "cure",
            command = BuildStrategyCommands({"cure"}, {"cure"}),
            strategy = "cure",
            tooltip = "Cure poisons/diseases",
            index = 8
        }
    })
    CreateToolBar(frame, -y, "CLASS_WARLOCK", {
        ["dps"] = {
            icon = "dps",
            command = BuildStrategyCommands({"destruction", "dps assist", "ranged", "pet", "curse"}, {"destruction", "dps assist", "pet"}),
            strategy = "destruction",
            tooltip = "Destruction DPS strategy",
            index = 0
        },
        ["curse"] = {
            icon = "dps_debuff",
            command = BuildStrategyCommands({"curse"}, nil),
            strategy = "curse",
            tooltip = "Use curses",
            index = 1
        },
        ["aoe"] = {
            icon = "caster_aoe",
            command = BuildStrategyCommands({"aoe"}, nil),
            strategy = "aoe",
            tooltip = "Use AOE abilities",
            index = 2
        },
        ["cc"] = {
            icon = "shadow_debuff",
            command = BuildStrategyCommands({"cc"}, nil),
            strategy = "cc",
            tooltip = "Toggle basic warlock CC. Use CC OFF to remove fear/howl cc packages too.",
            index = 3
        },
        ["cc_off"] = {
            icon = "bthreat",
            command = {},
            handler = DisableSelectedBotDangerousFearCc,
            strategy = "",
            tooltip = "CC OFF dungeon-safe: removes cc, cc destruction/affliction/demonology, fear, and howl packages from co and nc.",
            index = 4
        },
        ["voidwalker"] = {
            icon = "tank",
            command = BuildStrategyCommands({"pet", "pet voidwalker"}, {"pet", "pet voidwalker"}),
            strategy = "pet voidwalker",
            tooltip = "Use Voidwalker pet",
            index = 5
        }
    })
    CreateToolBar(frame, -y, "CLASS_WARRIOR", {
        ["dps"] = {
            icon = "dps",
            command = BuildStrategyCommands({"fury", "dps assist", "close", "behind"}, {"fury", "dps assist"}),
            strategy = "fury",
            tooltip = "Fury DPS strategy",
            index = 0
        },
        ["warrior_aoe"] = {
            icon = "warrior_aoe",
            command = BuildStrategyCommands({"aoe"}, nil),
            strategy = "aoe",
            tooltip = "Use AOE abilities",
            index = 1
        },
        ["tank"] = {
            icon = "tank",
            command = BuildStrategyCommands({"protection", "tank assist", "pull", "pull back", "close"}, {"protection", "tank assist"}),
            strategy = "protection",
            tooltip = "Protection tank strategy",
            index = 2
        }
    })

    frame:SetHeight(y + 25)
    return frame
end

function SetFrameColor(frame, class)
    local color = RAID_CLASS_COLORS[class]
    if (color == nil) then
        color = {r = 0.5, g = 0.1, b = 0.7};
    end
    frame:SetBackdropBorderColor(color.r, color.g, color.b, 1.0)
    frame.header:SetBackdropColor(color.r, color.g, color.b, 1.0)
    frame.header:SetBackdropBorderColor(color.r, color.g, color.b, 1.0)
end

local total = 0
function BotDebugTimer(self, elapsed)
    local elapsed = arg1
    if (elapsed) then
        total = total + elapsed
        if total >= 1 then
            local name = GetUnitName("target")
            if (name) then
                SendBotAddonCommand("debug action", "WHISPER", nil, name)
            end
            total = 0
        end
    end
end

local actionHistory = {}
local MaxDebugLines = 60
function CreateBotDebugPanel()
    local frame = CreateFrame("Frame", "BotDebugPanel", UIParent)
    frame:Hide()
    frame:SetWidth(300)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdropColor(0, 0, 0, 1.0)
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/ChatFrame/ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropBorderColor(0.5,0.1,0.7,1)
    frame:RegisterForDrag("LeftButton")

    frame.header = CreateFrame("Frame", "SelectedBotPanelHeader", frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetWidth(frame:GetWidth())
    frame.header:SetHeight(22)
    frame.header:SetBackdropColor(0.5,0.1,0.7,1)
    frame.header:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/ChatFrame/ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 0,
        insets = { left = 2, right = 2, top = 2, bottom = 0 }
    })
    frame.header:SetBackdropBorderColor(0.5,0.1,0.7,1)

    frame.header.text = frame.header:CreateFontString("SelectedBotPanelHeaderText")
    frame.header.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, 0)
    frame.header.text:SetWidth(frame.header:GetWidth())
    frame.header.text:SetHeight(22)
    frame.header.text:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    frame.header.text:SetJustifyH("LEFT")
    frame.header.text:SetText("Debug Info")

    local lineSize = 12
    for i = 1,MaxDebugLines do
        local text = frame.header:CreateFontString("SelectedBotPanelHeaderText")
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5 -i * lineSize)
        text:SetWidth(frame:GetWidth())
        text:SetHeight(18)
        text:SetFont("Fonts/FRIZQT__.TTF", 9, "OUTLINE")
        text:SetJustifyH("LEFT")
        text:SetText("Line"..i)
        frame["text"..i] = text

        actionHistory[i] = ""
    end
    frame:SetHeight(MaxDebugLines * lineSize + 30)

    EnablePositionSaving(frame, "BotDebugPanel")

    frame:SetScript("OnUpdate", BotDebugTimer)

    return frame
end

function UpdateBotDebugPanel(message, sender)
    local splitted = splitString2(message, "|")
    local length = tablelength(splitted)
    BotDebugPanel.header.text:SetText("Debug Info "..length)

    if (length > MaxDebugLines) then length = MaxDebugLines end

    local first = MaxDebugLines - length + 1

    for i = 1, first-1 do
        local line = BotDebugPanel["text"..i]
        local source = BotDebugPanel["text"..(length + i)]
        line:SetText(source:GetText())
    end

    for i = first, MaxDebugLines do
        local idx = i - first + 1
        local name = trim2(splitted[idx])
        local line = BotDebugPanel["text"..i]
        line:SetText(name)
    end
end

botTable = {}
SelectedBotPanel = CreateSelectedBotPanel();
BotRoster = CreateBotRoster();
BotDebugPanel = CreateBotDebugPanel();
CurrentBot = nil

local function fmod(a,b)
    return a - math.floor(a/b)*b
end

LastBotQueryTime = {}

function QuerySelectedBot(name, full)
    if (name == nil or name == "") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot cannot query bot: no bot selected.|r")
        return
    end

    -- Prevent a wall of duplicate whispers if the frame/target refreshes several times.
    local now = GetTime()
    if (LastBotQueryTime[name] ~= nil and now - LastBotQueryTime[name] < 1) then
        return
    end
    LastBotQueryTime[name] = now

    -- Normal panel refresh only needs nc/co so role buttons stay highlighted.
    -- Use /bot refresh for the slower full status pull.
    wait(0.1, function() SendBotAddonCommand("nc ?", "WHISPER", nil, name) end)
    wait(0.2, function() SendBotAddonCommand("co ?", "WHISPER", nil, name) end)

    if (full) then
        wait(0.3, function() SendBotAddonCommand("formation ?", "WHISPER", nil, name) end)
        wait(0.4, function() SendBotAddonCommand("rti ?", "WHISPER", nil, name) end)
        wait(0.5, function() SendBotAddonCommand("ll ?", "WHISPER", nil, name) end)
        wait(0.6, function() SendBotAddonCommand("save mana ?", "WHISPER", nil, name) end)
    end
end
Mangosbot_EventFrame:SetScript("OnEvent", function(self)
    if (event == "PLAYER_TARGET_CHANGED") then
        local name = GetUnitName("target")
        local selfName = GetUnitName("player")
        local validBotTarget = (name ~= nil and UnitExists("target") and not UnitIsEnemy("target", "player") and UnitIsPlayer("target") and name ~= selfName)

        -- If a bot was chosen from the roster, keep that menu pinned even while
        -- the player changes target. Do not let target changes hijack buttons.
        if (CurrentBot ~= nil and CurrentBot ~= "") then
            SelectedBotPanel.botName = CurrentBot
            return
        end

        if (validBotTarget) then
            SelectedBotPanel.botName = name
            QuerySelectedBot(name, false)
        else
            -- Keep the existing menu open while targeting enemies/dummies/loot.
            -- Only hide when there is no pinned bot menu at all.
            if (SelectedBotPanel.botName == nil or SelectedBotPanel.botName == "") then
                SelectedBotPanel:Hide()
            end
        end
    end

    if (event == "CHAT_MSG_SYSTEM") then
        local message = arg1
        if (OnSystemMessage(message)) then
            if (BotRoster.ShowRequest) then
                BotRoster:Show()
                BotRoster.ShowRequest = false
            end
            for i = 1,10 do
                BotRoster.items[i]:Hide()
            end
            local index = 1
            local x = 5
            local width = 0
            local height = 0
            local y = 5
            local colCount = 2
            local allBots = ""
            local first = true
            local allBotsLoggedIn = true
            local allBotsLoggedOut = true
            local allBotsInParty = true
            local atLeastOneBotInParty = false
            for key,bot in pairs(botTable) do
                local item = BotRoster.items[index]
                if (first) then first = false
                else allBots = allBots .. "," end
                allBots = allBots .. key

                item.text:SetText(key)
                item.cls["key"] = key
                item.cls:SetScript("OnClick", function()
                    if (CurrentBot == item.cls["key"]) then
                        CurrentBot = nil
                        SelectedBotPanel.botName = nil
                        SelectedBotPanel:Hide()
                    else
                        CurrentBot = item.cls["key"]
                        SelectedBotPanel.botName = CurrentBot
                        SelectedBotPanel.header.text:SetText(CurrentBot)
                        QuerySelectedBot(CurrentBot, false)
                    end
                end)

                local filename = "Interface\\Addons\\Mangosbot\\Images\\cls_" .. string.lower(bot["class"]) ..".tga"
                item.cls.texture:SetTexture(filename)

                local color = RAID_CLASS_COLORS[string.upper(bot["class"])]
                item.text:SetTextColor(color.r, color.g, color.b, 1.0)

                item:SetPoint("TOPLEFT", BotRoster, "TOPLEFT", x, -y)

                local loginBtn = item.toolbar["quickbar"..index].buttons["login"]
                loginBtn:Hide()
                local logoutBtn = item.toolbar["quickbar"..index].buttons["logout"]
                logoutBtn:Hide()
                local inviteBtn = item.toolbar["quickbar"..index].buttons["invite"]
                inviteBtn:Show()
                local leaveBtn = item.toolbar["quickbar"..index].buttons["leave"]
                leaveBtn:Hide()
                local whisperBtn = item.toolbar["quickbar"..index].buttons["whisper"]
                whisperBtn:Hide()
                local summonBtn = item.toolbar["quickbar"..index].buttons["summon"]
                summonBtn:Hide()
                if (bot["online"]) then
                    item:SetBackdropBorderColor(0.6, 0.6, 0.2, 1.0)
                    logoutBtn:Show()
                    whisperBtn:Show()
                    summonBtn:Show()
                    local inParty = false
                    for i = 1,5 do
                        if (UnitName("party"..i) == key) then
                            inviteBtn:Hide()
                            leaveBtn:Show()
                            atLeastOneBotInParty = true
                            inParty = true
                            item:SetBackdropBorderColor(0.2, 0.8, 0.8, 1.0)
                        end
                    end
                    if (not inParty) then allBotsInParty = false end
                    allBotsLoggedOut = false
                else
                    item:SetBackdropBorderColor(0.2,0.2,0.2,1)
                    loginBtn:Show()
                    inviteBtn:Hide()
                    allBotsLoggedIn = false
                end
                loginBtn["key"] = key
                loginBtn:SetScript("OnClick", function()
                    SendBotCommand(".bot add " .. loginBtn["key"], "SAY")
                end)
                logoutBtn["key"] = key
                logoutBtn:SetScript("OnClick", function()
                    SendBotCommand(".bot rm " .. logoutBtn["key"], "SAY")
                end)
                inviteBtn["key"] = key
                inviteBtn:SetScript("OnClick", function()
                    InviteUnit(inviteBtn["key"])
                    -- InviteByName(inviteBtn["key"])
                end)
                leaveBtn["key"] = key
                leaveBtn:SetScript("OnClick", function()
                    SendBotCommand("leave", "WHISPER", nil, leaveBtn["key"])
                end)
                whisperBtn["key"] = key
                whisperBtn:SetScript("OnClick", function()
                    local editBox = getglobal("ChatFrameEditBox")
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:SetText("/w " .. whisperBtn["key"] .. " ")
                end)
                summonBtn["key"] = key
                summonBtn:SetScript("OnClick", function()
                    SendBotCommand("summon", "WHISPER", nil, summonBtn["key"])
                end)


                item:Show()

                index = index + 1
                x = x + (5 + item:GetWidth())
                height = item:GetHeight()
                if (width < x) then width = x end
                if (fmod((index - 1), colCount) == 0) then
                    y = y + (5 + height)
                    x = 5
                end
            end
            if (fmod((index - 1), colCount) ~= 0) then
                y = y + (5 + height)
            end

            local tb = BotRoster.toolbar["quickbar"]
            tb:SetPoint("TOPLEFT", BotRoster, "TOPLEFT", 5, -y)
            local loginAllBtn = tb.buttons["login_all"]
            x = 0
            loginAllBtn:SetPoint("TOPLEFT", tb, "TOPLEFT", x, 0)
            if (not allBotsLoggedIn) then
                loginAllBtn:Show()
                x = x + 16
            else
                loginAllBtn:Hide()
            end
            loginAllBtn["allBots"] = allBots
            loginAllBtn:SetScript("OnClick", function()
                SendBotCommand(".bot add " .. loginAllBtn["allBots"], "SAY")
            end)

            local logoutAllBtn = tb.buttons["logout_all"]
            logoutAllBtn:SetPoint("TOPLEFT", tb, "TOPLEFT", x, 0)
            if (not allBotsLoggedOut) then
                logoutAllBtn:Show()
                x = x + 16
            else
                logoutAllBtn:Hide()
            end
            logoutAllBtn["allBots"] = allBots
            logoutAllBtn:SetScript("OnClick", function()
                SendBotCommand(".bot rm " .. logoutAllBtn["allBots"], "SAY")
            end)

            local inviteAllBtn = tb.buttons["invite_all"]
            inviteAllBtn:SetPoint("TOPLEFT", tb, "TOPLEFT", x, 0)
            if (not allBotsInParty) then
                inviteAllBtn:Show()
                x = x + 16
            else
                inviteAllBtn:Hide()
            end
            inviteAllBtn["key"] = key
            inviteAllBtn:SetScript("OnClick", function()
                local timeout = 0.1
                for key,bot in pairs(botTable) do
                    wait(timeout, function(key)
                        InviteByName(key)
                    end, key)
                    timeout = timeout + 0.1
                end
                wait(1, function() SendBotCommand(".bot list", "SAY") end)
            end)

            local leaveAllBtn = tb.buttons["leave_all"]
            leaveAllBtn:SetPoint("TOPLEFT", tb, "TOPLEFT", x, 0)
            if (atLeastOneBotInParty) then
                leaveAllBtn:Show()
                x = x + 16
            else
                leaveAllBtn:Hide()
            end
            leaveAllBtn["key"] = key
            leaveAllBtn:SetScript("OnClick", function()
                local timeout = 0.1
                for key,bot in pairs(botTable) do
                    wait(timeout, function(key) SendBotCommand("leave", "WHISPER", nil, key) end, key)
                    timeout = timeout + 0.1
                end
            end)

            local formationToolBar = BotRoster.toolbar["group_formation"]
            if (atLeastOneBotInParty) then
                formationToolBar:Show()
                y = y + 22
                formationToolBar:SetPoint("TOPLEFT", BotRoster, "TOPLEFT", 5, -y)
            else
                formationToolBar:Hide()
            end

            local movementToolBar = BotRoster.toolbar["group_movement"]
            if (atLeastOneBotInParty) then
                movementToolBar:Show()
                y = y + 22
                movementToolBar:SetPoint("TOPLEFT", BotRoster, "TOPLEFT", 5, -y)
            else
                movementToolBar:Hide()
            end

            local savemanaToolBar = BotRoster.toolbar["group_savemana"]
            if (atLeastOneBotInParty) then
                savemanaToolBar:Show()
                y = y + 22
                savemanaToolBar:SetPoint("TOPLEFT", BotRoster, "TOPLEFT", 5, -y)
            else
                savemanaToolBar:Hide()
            end

            UpdateGroupToolBar()
            BotRoster:SetWidth(width)
            BotRoster:SetHeight(y + 22)
        end
    end

    if (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_ADDON") then
        --print(event.." 1 "..arg1.." 2 "..arg2.." 3 "..arg3.." 4 "..arg4)
        local message = arg1
        local sender = arg2
        if (event == "CHAT_MSG_ADDON") then sender = arg4 end

        OnWhisper(message, sender)

        if (BotDebugPanel:IsVisible()) then
            UpdateBotDebugPanel(message, sender)
        end

        if (string.find(message, "Hello") == 1 or string.find(message, "Goodbye") == 1) then
            SendBotCommand(".bot list", "SAY")
            -- Bartcraft: do not mass-query the whole group/raid here.
            -- It creates a wall of whispers and is not needed for the roster.
        end
        if (string.find(message, "Following") == 1 or string.find(message, "Staying") == 1 or string.find(message, "Fleeing") == 1) then
            wait(0.1, function() SendBotAddonCommand("nc ?", "WHISPER", nil, sender) end)
        end
        if (string.find(message, "Formation set to") == 1) then
            wait(0.1, function() SendBotAddonCommand("formation ?", "WHISPER", nil, sender) end)
        end
        if (string.find(message, "Loot strategy set to ") == 1) then
            wait(0.1, function() SendBotAddonCommand("ll ?", "WHISPER", nil, sender) end)
        end
        if (string.find(message, "RTI set to") == 1) then
            wait(0.1, function() SendBotAddonCommand("rti ?", "WHISPER", nil, sender) end)
        end
        if (string.find(message, "save mana") == 1) then
            wait(0.1, function() SendBotAddonCommand("save mana ?", "WHISPER", nil, sender) end)
        end
        UpdateGroupToolBar()

        -- Only the currently selected bot should control the selected bot panel.
        -- Other bot/player whispers can arrive while this panel is open; the old addon
        -- treated those as missing bot data and hid the panel.
        local selected = GetPinnedBotName()
        if (sender ~= selected) then
            return
        end

        local bot = botTable[sender]
        if (bot == nil or bot["strategy"] == nil or bot["role"] == nil) then
            -- Wait for nc/co replies instead of hiding a panel that just opened.
            return
        end

        if (sender == selected) then
            SelectedBotPanel.botName = sender
            SelectedBotPanel:Show()

            local tmp, class = nil, nil
            if (GetUnitName("target") ~= nil and GetUnitName("target") == sender) then
                tmp, class = UnitClass("target")
            end
            if (class == nil and bot["class"] ~= nil) then
                class = string.upper(bot["class"])
            end
            if (class == nil) then
                class = "UNKNOWN"
            end
            SetFrameColor(SelectedBotPanel, class)

            local filename = "Interface\\Addons\\Mangosbot\\Images\\role_" .. bot["role"] .. ".tga"
            SelectedBotPanel.header.role.texture:SetTexture(filename)
            SelectedBotPanel.header.text:SetText(sender)

            local width = 0
            local height = 0
            for toolbarName,toolbar in pairs(ToolBars) do
                local panelVisible = true
                if (string.find(toolbarName, "CLASS_") == 1) then
                    local classToolbarName = string.sub(toolbarName, 7)
                    local classMatch = false

                    if (classToolbarName == class) then
                        classMatch = true
                    elseif (string.sub(classToolbarName, 1, string.len(class) + 1) == class .. "_") then
                        classMatch = true
                    end

                    if (classMatch) then
                        SelectedBotPanel.toolbar[toolbarName]:Show()
                    else
                        SelectedBotPanel.toolbar[toolbarName]:Hide()
                        panelVisible = false
                    end
                end
                local numButtons = 0
                for buttonName,button in pairs(toolbar) do
                    local toggle = ButtonIsActiveForBot(button, bot)
                    if (button["formation"] ~= nil and bot["formation"] ~= nil and string.find(bot["formation"], button["formation"]) ~= nil) then
                        toggle = true
                    end
                    if (button["rti"] ~= nil and bot["rti"] ~= nil and string.find(bot["rti"], button["rti"]) ~= nil) then
                        toggle = true
                    end
                    if (button["loot"] ~= nil and bot["loot"] ~= nil and string.find(bot["loot"], button["loot"]) ~= nil) then
                        toggle = true
                    end
                    if (button["savemana"] ~= nil and bot["savemana"] ~= nil and string.find(bot["savemana"], button["savemana"]) ~= nil) then
                        toggle = true
                    end
                    ToggleButton(SelectedBotPanel, toolbarName, buttonName, toggle)
                    numButtons = numButtons + 1
                end
                if (panelVisible) then
                    height = height + 1
                    if (width < numButtons) then width = numButtons end
                end
            end
            ResizeBotPanel(SelectedBotPanel, width * 25 + 20, height * 25 + 25)
        end
    end
end)

function UpdateGroupToolBar()
    for toolbarName,toolbar in pairs(GroupToolBars) do
        for buttonName,button in pairs(toolbar) do
            local toggle = false
            for key,bot in pairs(botTable) do
                if (ButtonIsActiveForBot(button, bot)) then
                    toggle = true
                end
                if (button["formation"] ~= nil and bot["formation"] ~= nil and string.find(bot["formation"], button["formation"]) ~= nil) then
                    toggle = true
                end
                if (button["rti"] ~= nil and bot["rti"] ~= nil and string.find(bot["rti"], button["rti"]) ~= nil) then
                    toggle = true
                end
                if (button["loot"] ~= nil and bot["loot"] ~= nil and string.find(bot["loot"], button["loot"]) ~= nil) then
                    toggle = true
                end
                if (button["savemana"] ~= nil and bot["savemana"] ~= nil and string.find(bot["savemana"], button["savemana"]) ~= nil) then
                    toggle = true
                end
            end
            ToggleButton(BotRoster, toolbarName, buttonName, toggle)
        end
    end
end

function trim2(s)

    local find = string.find
    local sub = string.sub
    function trim8(s)
      local i1,i2 = find(s,'^%s*')
      if i2 >= i1 then s = sub(s,i2+1) end
      local i1,i2 = find(s,'%s*$')
      if i2 >= i1 then s = sub(s,1,i1-1) end
      return s
    end
    return trim8(s)
end

function splitString2( self, inSplitPattern, outResults )
  if not inSplitPattern then
    return
  end
  if not outResults then
    outResults = { }
  end
  local theStart = 1
  local theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
  while theSplitStart do
    table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
    theStart = theSplitEnd + 1
    theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
  end
  table.insert( outResults, string.sub( self, theStart ) )
  return outResults
end

function OnWhisper(message, sender)
    if (sender == nil or sender == "") then
        return
    end

    if (botTable[sender] == nil) then
        botTable[sender] = {}
    end

    local bot = botTable[sender]

    -- Older addon builds expected "Strategies: ...".
    -- This server build answers with "Combat Strategies: ..." and "Non Combat Strategies: ...".
    -- Support all three so the selected bot control panel can unlock.
    local strategyText = nil
    local strategyType = nil

    if (string.find(message, 'Combat Strategies: ') == 1) then
        strategyText = string.sub(message, 20)
        strategyType = "co"
    elseif (string.find(message, 'Non Combat Strategies: ') == 1) then
        strategyText = string.sub(message, 23)
        strategyType = "nc"
    elseif (string.find(message, 'Strategies: ') == 1) then
        strategyText = string.sub(message, 13)
        strategyType = "co"
    end

    if (strategyText ~= nil) then
        local list = {}
        local seen = {}
        local splitted = splitString2(strategyText, ",")

        for i = 1, tablelength(splitted) do
            local name = trim2(splitted[i] or "")

            if (name ~= "" and seen[name] == nil) then
                seen[name] = true
                table.insert(list, name)

                -- Old "Strategies:" replies could include nc in the list.
                if (name == "nc") then
                    strategyType = "nc"
                end
            end
        end

        if (bot['strategy'] == nil) then
            bot['strategy'] = {nc = {}, co = {}}
        end

        bot['strategy'][strategyType] = list

        -- Re-guess the role from both co and nc because this playerbot build can
        -- report role-looking combat flags inside Non Combat Strategies.
        bot["role"] = BartcraftGuessRoleFromStrategies(bot)
    end

    if (string.find(message, 'Formation: ') == 1) then
        bot['formation'] = string.sub(message, 11)
    end
    if (string.find(message, 'Formation set to: ') == 1) then
        bot['formation'] = string.sub(message, 19)
    end
    if (string.find(message, 'Mana save level set: ') == 1) then
        bot['savemana'] = string.sub(message, 21)
    end
    if (string.find(message, 'Mana save level: ') == 1) then
        bot['savemana'] = string.sub(message, 17)
    end
    if (string.find(message, 'Loot strategy: ') == 1) then
        bot['loot'] = string.sub(message, 15)
    end
    if (string.find(message, 'RTI: ') == 1) then
        bot['rti'] = string.sub(message, 5)
    end
end

function OnSystemMessage(message)
    if (string.find(message, 'Bot roster: ') == 1) then
        -- Preserve existing selected-bot data such as strategy/role/formation.
        -- The roster can refresh after the panel opens; wiping botTable here makes
        -- the next whisper look incomplete and the old addon hides the menu.
        local oldBotTable = botTable or {}
        local newBotTable = {}

        local text = string.sub(message, 13)
        local splitted = splitString2(text, ", ")

        for i = 1, tablelength(splitted) do
            local line = trim2(splitted[i] or "")

            if (line ~= "") then
                local on = string.sub(line, 1, 1)
                local pos = string.find(line, " ")

                if (pos ~= nil and pos > 2) then
                    local name = string.sub(line, 2, pos - 1)
                    local cls = trim2(string.sub(line, pos + 1) or "")

                    if (name ~= nil and name ~= "") then
                        if (oldBotTable[name] ~= nil) then
                            newBotTable[name] = oldBotTable[name]
                        else
                            newBotTable[name] = {}
                        end

                        newBotTable[name]["class"] = cls
                        newBotTable[name]["online"] = (on == "+")
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Mangosbot skipped bad roster entry: " .. line .. "|r")
                end
            end
        end

        botTable = newBotTable
        return true
    end

    return false
end

function MangosbotResetWindows()
    frameopts = {}

    if (BotRoster ~= nil) then
        BotRoster:StopMovingOrSizing()
        BotRoster:ClearAllPoints()
        BotRoster:SetPoint("CENTER", UIParent, "CENTER")
        BotRoster:Show()
    end

    if (SelectedBotPanel ~= nil) then
        SelectedBotPanel:StopMovingOrSizing()
        SelectedBotPanel:ClearAllPoints()
        SelectedBotPanel:SetPoint("CENTER", UIParent, "CENTER")
        SelectedBotPanel.botName = nil
        SelectedBotPanel:Hide()
    end

    if (BotDebugPanel ~= nil) then
        BotDebugPanel:StopMovingOrSizing()
        BotDebugPanel:ClearAllPoints()
        BotDebugPanel:SetPoint("CENTER", UIParent, "CENTER")
        BotDebugPanel:Hide()
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Mangosbot windows reset. Use /bot to reopen the roster.|r")
end

SLASH_MANGOSBOT1 = '/bot'
function SlashCmdList.MANGOSBOT(msg, editbox) -- 4.
    msg = string.lower(msg or "")

    if (msg == "reset" or msg == "resetpos" or msg == "resetposition") then
        MangosbotResetWindows()
        return
    end

    if (msg == "refresh") then
        if (CurrentBot ~= nil and CurrentBot ~= "") then
            LastBotQueryTime[CurrentBot] = nil
            QuerySelectedBot(CurrentBot, true)
            DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Mangosbot full refresh sent to " .. CurrentBot .. ".|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Select a bot first, then use /bot refresh.|r")
        end
        return
    end

    if (msg == "wipe" or msg == "wipestrats" or msg == "wipe strategies") then
        WipeSelectedBotStrategies()
        return
    end

    if (msg == "dps" or msg == "role dps") then
        BartcraftSetDpsMode()
        return
    end

    if (msg == "tank" or msg == "role tank") then
        BartcraftSetTankMode()
        return
    end

    if (msg == "heal" or msg == "healer" or msg == "role heal") then
        BartcraftSetHealMode()
        return
    end

    if (msg == "" or msg == "roster") then
        if (BotRoster:IsVisible()) then
            BotRoster:Hide()
        else
            BotRoster.ShowRequest = true
            SendBotCommand(".bot list", "SAY")
            -- Bartcraft: opening /bot only asks for the roster now.
            -- Select a bot to query nc/co, or use /bot refresh for full selected-bot status.
        end
    end
    if (msg == "debug") then
        if (BotDebugPanel:IsVisible()) then
            BotDebugPanel:Hide()
        else
            BotDebugPanel:Show()
        end
    end
end
local waitTable = {};
local waitFrame = nil;

function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function wait(delay, func, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
  if(type(delay)~="number" or type(func)~="function") then
    return false;
  end
  if(waitFrame == nil) then
    waitFrame = CreateFrame("Frame","WaitFrame", UIParent);
    waitFrame:SetScript("OnUpdate",function ()
      local elapse = 0.1
      local count = tablelength(waitTable);
      local i = 1;
      while(i<=count) do
        local waitRecord = tremove(waitTable,i);
        local d = tremove(waitRecord,1);
        local f = tremove(waitRecord,1);
        local p = tremove(waitRecord,1);
        if(d>elapse) then
          tinsert(waitTable,i,{d-elapse,f,p});
          i = i + 1;
        else
          count = count - 1;
          f(unpack(p));
        end
      end
    end);
  end
  tinsert(waitTable,{delay,func,{arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}});
  return true;
end

function print(s)
    if (s ~= nil) then DEFAULT_CHAT_FRAME:AddMessage(s); else DEFAULT_CHAT_FRAME:AddMessage("nil"); end
end

print("MangosBOT Addon is loaded");
