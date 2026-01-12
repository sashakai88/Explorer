--[[
    IronMan - Scribe Module
    Quest journal replacement that captures and displays quest text
]]

local addonName, IronMan = ...

-- Ensure namespace exists
IronMan = IronMan or {}
IronMan.Scribe = IronMan.Scribe or {}

-- Local references
local Scribe = IronMan.Scribe

-- Database for the journal (saved in SavedVariables)
IronManJournalDB = IronManJournalDB or {}

-- Constants
local UNKNOWN_ZONE = "Unknown Zone"
local SCAN_DELAY = 4 -- Seconds to wait before scanning quest log on login

--[[
    Finds the zone header for a specific quest
    @param questID - Quest ID to find zone for
    @return string - Zone name
]]
local function GetQuestZone(questID)
    if not questID then
        return UNKNOWN_ZONE
    end

    -- Method 1: Log Headers (Standard UI structure)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if logIndex then
        -- Walk backwards from the quest to find the nearest header
        for i = logIndex, 1, -1 do
            local info = C_QuestLog.GetInfo(i)
            if info and info.isHeader then
                return info.title
            end
        end
    end

    -- Method 2: Map ID (Fallback if header failed or not found)
    local mapID = C_QuestLog.GetMapIDForQuest(questID)
    if mapID and mapID > 0 then
        local mapInfo = C_Map.GetMapInfo(mapID)
        if mapInfo and mapInfo.name then
            return mapInfo.name
        end
    end

    return UNKNOWN_ZONE
end

--[[
    Captures quest data and stores it in the journal database
    @param questID - Quest ID to capture
    @param source - Source of the capture ("Accepted", "Scan", "DataLoad")
    @param optionalTitle - Optional quest title (if already known)
    @param optionalZone - Optional zone name (if already known)
    @param optionalGiver - Optional quest giver name
]]
local function CaptureQuestData(questID, source, optionalTitle, optionalZone, optionalGiver)
    if not questID then
        return
    end

    -- Get quest title
    local title = optionalTitle or C_QuestLog.GetTitleForQuestID(questID)
    if not title or title == "" then
        C_QuestLog.RequestLoadQuestByID(questID)
        return
    end

    -- Determine zone
    local zone = optionalZone
    if not zone or zone == UNKNOWN_ZONE then
        zone = GetQuestZone(questID)
    end

    -- Get quest description and objectives
    local description = ""
    local objectives = ""

    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if logIndex then
        -- Returns: description, objectives
        description, objectives = GetQuestLogQuestText(logIndex)
    end

    -- Fallback for objectives
    if (not objectives or objectives == "") and C_QuestLog.GetQuestObjectives then
        local objectivesTable = C_QuestLog.GetQuestObjectives(questID)
        if objectivesTable then
            -- Convert objectives table to string if needed
            objectives = objectivesTable
        end
    end

    -- Request data load if description is missing
    if not description or description == "" then
        description = "(Description unavailable. Retrying...)"
        C_QuestLog.RequestLoadQuestByID(questID)
    end

    -- Preserve existing data if not provided in this update (e.g. Giver Name)
    local existing = IronManJournalDB[questID]
    local giver = optionalGiver
    if not giver and existing and existing.giver then
        giver = existing.giver
    end

    -- Save quest data
    IronManJournalDB[questID] = {
        title = title,
        zone = zone,
        description = description,
        originalObjectives = objectives,
        giver = giver,
        timestamp = time()
    }

    -- Print notification for new accepts or scans
    if source == "Accepted" or source == "Scan" then
        print("IronMan: Saved [" .. title .. "] in [" .. zone .. "]")
    end

    -- Refresh UI if open
    if Scribe.journalFrame and Scribe.journalFrame:IsShown() and Scribe.journalFrame.RefreshJournal then
        Scribe.journalFrame.RefreshJournal()
    end
end

--[[
    Scans the entire quest log to capture all quest data
]]
local function ScanQuestLog()
    -- Track current quest IDs to clean up removed quests
    local currentLogQuestIDs = {}

    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    print("|cffaaaaaaIronMan:|r Scanning " .. numEntries .. " log entries...")

    local currentZone = UNKNOWN_ZONE
    local found = 0

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)

        if info then
            if info.isHeader then
                currentZone = info.title
            elseif not info.isHidden and not info.isTask and info.questID > 0 then
                -- Filter out "Level XX" titles (these are not real quests)
                local title = info.title
                if title and not string.match(title, "^Level %d+$") then
                    currentLogQuestIDs[info.questID] = true

                    -- Capture quest data (preserves existing giver name)
                    local status, err = pcall(CaptureQuestData, info.questID, "Scan", title, currentZone)
                    if status then
                        found = found + 1
                    end
                end
            end
        end
    end

    -- Cleanup: Remove quests that are no longer in the log
    for questID in pairs(IronManJournalDB) do
        if not currentLogQuestIDs[questID] then
            IronManJournalDB[questID] = nil
        end
    end

    print("|cffaaaaaaIronMan:|r Scan complete. Found " .. found .. " quests.")

    -- Refresh UI if open
    if Scribe.journalFrame and Scribe.journalFrame:IsShown() then
        Scribe.journalFrame.RefreshJournal()
    end
end

--[[
    Event handler for quest-related events
]]
local function OnEvent(self, event, arg1, arg2)
    if event == "QUEST_ACCEPTED" then
        local questID = arg1
        if not questID then
            return
        end

        -- Capture giver name immediately (before it's lost)
        local giverName = UnitName("npc") or UnitName("target")

        -- Delay capture to ensure quest data is loaded
        C_Timer.After(1, function()
            C_QuestLog.RemoveQuestWatch(questID)
            if C_QuestLog.IsQuestTask(questID) then
                return
            end

            local status, err = pcall(CaptureQuestData, questID, "Accepted", nil, nil, giverName)
            if not status then
                print("|cffff0000IronMan Error:|r Failed to capture quest: " .. tostring(err))
            end
        end)

    elseif event == "QUEST_REMOVED" then
        local questID = arg1
        if questID then
            -- Remove from database
            if IronManJournalDB[questID] then
                IronManJournalDB[questID] = nil
            end

            -- Refresh UI if visible
            if Scribe.journalFrame and Scribe.journalFrame:IsShown() then
                -- Small delay to ensure UI updates properly
                C_Timer.After(0.1, function()
                    if Scribe.journalFrame and Scribe.journalFrame.RefreshJournal then
                        Scribe.journalFrame.RefreshJournal()
                    end
                end)
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Delay scan to ensure quest log is fully loaded
        C_Timer.After(SCAN_DELAY, ScanQuestLog)

    elseif event == "QUEST_DATA_LOAD_RESULT" then
        local questID, success = arg1, arg2
        if success and questID then
            pcall(CaptureQuestData, questID, "DataLoad")
        end

    elseif event == "PLAYER_LOGIN" then
        -- Override "L" key binding for journal
        if Scribe.journalFrame then
            SetOverrideBinding(Scribe.journalFrame, true, "L", "IRONMAN_TOGGLE_JOURNAL")
            print("|cffcc3333IronMan|r: 'L' key bound to Journal.")
        end

    elseif event == "QUEST_LOG_UPDATE" then
        -- Throttle refresh to avoid spam
        if Scribe.journalFrame and Scribe.journalFrame:IsShown() and Scribe.journalFrame.RefreshJournal then
            Scribe.journalFrame.RefreshJournal()
        end
    end
end


--[[
    Highlights directional words in quest text
    @param text - Text to highlight
    @return string - Text with highlighted directions
]]
local function HighlightDirections(text)
    if not text then
        return ""
    end

    local color = "|cffffcc00"
    local clear = "|r"

    -- List of terms to highlight (order matters: compounds first!)
    local directions = {
        "Northwest", "Northeast", "Southwest", "Southeast",
        "northwest", "northeast", "southwest", "southeast",
        "Northern", "Southern", "Eastern", "Western",
        "northern", "southern", "eastern", "western",
        "North", "South", "East", "West",
        "north", "south", "east", "west"
    }

    for _, dir in ipairs(directions) do
        -- Use %f[%a] frontier pattern for word boundaries
        text = text:gsub("%f[%a]" .. dir .. "%f[%A]", color .. dir .. clear)
    end

    return text
end

--[[
    Handles hyperlink clicks in the journal
]]
local function OnHyperlinkClick(self, link, text, button)
    local linkType, action, arg = strsplit(":", link)
    if linkType ~= "ironman" or action ~= "abandon" then
        return
    end

    local questID = tonumber(arg)
    if not questID then
        return
    end

    local data = IronManJournalDB[questID]
    local title = data and data.title or "Unknown Quest"

    -- Define popup dialog if not exists
    if not StaticPopupDialogs["IRONMAN_ABANDON"] then
        StaticPopupDialogs["IRONMAN_ABANDON"] = {
            text = "|cffffcc00Abandon Quest|r\n\n%s\n\nAre you sure?",
            button1 = "Abandon",
            button2 = "Cancel",
            OnAccept = function()
                local abandonQuestID = questID
                local abandonTitle = title

                -- Abandon quest in game
                -- Set the quest as selected first
                C_QuestLog.SetSelectedQuest(abandonQuestID)
                
                -- Small delay to ensure quest is selected before abandoning
                C_Timer.After(0.1, function()
                    -- Check if quest still exists before abandoning
                    if C_QuestLog.GetLogIndexForQuestID(abandonQuestID) then
                        C_QuestLog.SetAbandonQuest()
                        C_QuestLog.AbandonQuest()
                    end
                end)

                -- Remove from database immediately (will be confirmed by QUEST_REMOVED event)
                if IronManJournalDB[abandonQuestID] then
                    IronManJournalDB[abandonQuestID] = nil
                end

                print("IronMan: Abandoned " .. abandonTitle)

                -- Refresh UI after a short delay to ensure quest is removed
                C_Timer.After(0.2, function()
                    -- Double-check removal (in case quest wasn't actually abandoned)
                    if not C_QuestLog.GetLogIndexForQuestID(abandonQuestID) then
                        -- Quest is gone, ensure it's removed from DB
                        IronManJournalDB[abandonQuestID] = nil
                    end

                    -- Refresh UI
                    if Scribe.journalFrame and Scribe.journalFrame.RefreshJournal then
                        Scribe.journalFrame.RefreshJournal()
                    end
                end)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show("IRONMAN_ABANDON", title)
end

--[[
    Creates the journal UI frame
]]
local function CreateJournalFrame()
    local journalFrame = CreateFrame("Frame", "IronManJournalFrame", UIParent, "BasicFrameTemplateWithInset")
    journalFrame:SetSize(400, 500)
    journalFrame:SetPoint("CENTER")
    journalFrame:SetMovable(true)
    journalFrame:EnableMouse(true)
    journalFrame:RegisterForDrag("LeftButton")
    journalFrame:SetScript("OnDragStart", journalFrame.StartMoving)
    journalFrame:SetScript("OnDragStop", journalFrame.StopMovingOrSizing)
    journalFrame:Hide()

    -- Title
    local title = journalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("CENTER", journalFrame.TitleBg, "CENTER", 0, 0)
    title:SetText("IronMan Journal")
    journalFrame.title = title

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "IronManJournalScrollFrame", journalFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    -- Content frame (EditBox for hyperlink support)
    local content = CreateFrame("EditBox", nil, scrollFrame)
    content:SetMultiLine(true)
    content:SetFontObject(GameFontHighlight)
    content:SetWidth(scrollFrame:GetWidth() - 20)
    content:SetAutoFocus(false)
    content:EnableMouse(true)
    content:SetHyperlinksEnabled(true)
    scrollFrame:SetScrollChild(content)

    -- Prevent cursor from showing
    content:SetScript("OnCursorChanged", function(self)
        self:SetCursorPosition(0)
        self:ClearFocus()
    end)

    -- Handle hyperlink clicks
    content:SetScript("OnHyperlinkClick", OnHyperlinkClick)

    journalFrame.scrollFrame = scrollFrame
    journalFrame.content = content

    return journalFrame
end

--[[
    Refreshes the journal display with current quest data
]]
local function RefreshJournal(self)
    if not self or not self.content then
        return
    end

    local text = ""
    local zones = {}
    local zoneNames = {}
    local count = 0

    -- Organize quests by zone
    for questID, data in pairs(IronManJournalDB) do
        if questID and data then
            data.id = questID
            local zone = data.zone or UNKNOWN_ZONE

            if not zones[zone] then
                zones[zone] = {}
                table.insert(zoneNames, zone)
            end
            table.insert(zones[zone], data)
            count = count + 1
        end
    end

    -- Sort zone names alphabetically
    table.sort(zoneNames)

    if count == 0 then
        text = "\n\n   The Journal is empty.\n   Go find some adventure."
    else
        for _, zoneName in ipairs(zoneNames) do
            -- Zone header
            text = text .. "\n|cff00ccff== " .. string.upper(zoneName) .. " ==|r\n"

            local questList = zones[zoneName]
            -- Sort quests alphabetically
            table.sort(questList, function(a, b)
                return (a.title or "") < (b.title or "")
            end)

            for _, entry in ipairs(questList) do
                -- Abandon link
                local abandonLink = "|cffff3333|Hironman:abandon:" .. (entry.id or 0) .. "|h[x]|h|r"

                -- Title with abandon link
                text = text .. "   |cffffcc00" .. (entry.title or "???") .. "|r   " .. abandonLink .. "\n"

                -- Quest giver
                if entry.giver then
                    text = text .. "   |cff88ccffGiven by: " .. entry.giver .. "|r\n"
                end

                -- Description with highlighted directions
                local desc = HighlightDirections(entry.description or "No description.")
                text = text .. "   |cffffffff" .. desc .. "|r\n"

                -- Dynamic objective tracking
                if entry.id then
                    local isComplete = C_QuestLog.IsComplete(entry.id)
                    local objectives = C_QuestLog.GetQuestObjectives(entry.id)

                    if isComplete then
                        text = text .. "   |cff00ff00(Quest Complete)|r\n"
                    elseif objectives then
                        for _, obj in ipairs(objectives) do
                            local objText = obj.text
                            if obj.finished then
                                objText = "|cff00ff00" .. objText .. " (Done)|r"
                            else
                                objText = "|cffaaaaaa" .. objText .. "|r"
                            end
                            text = text .. "   - " .. objText .. "\n"
                        end
                    elseif entry.originalObjectives and entry.originalObjectives ~= "" then
                        -- Fallback to captured text
                        text = text .. "   |cffaaaaaaTask: " .. entry.originalObjectives .. "|r\n"
                    end
                end

                text = text .. "\n   |cff444444" .. string.rep("-", 20) .. "|r\n\n"
            end
        end
    end

    -- Apply text to content frame
    self.content:SetText(text)
end

--[[
    Handles slash commands for the journal
]]
local function HandleSlashCommand(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""

    if msg == "debug" then
        local count = 0
        for _ in pairs(IronManJournalDB) do
            count = count + 1
        end
        print("IronManJournalDB has " .. count .. " entries.")
        for questID, data in pairs(IronManJournalDB) do
            print(" - ID: " .. questID .. " | Title: " .. (data.title or "nil"))
        end

    elseif msg == "scan" then
        ScanQuestLog()

    elseif msg == "test" then
        -- Insert test entry
        IronManJournalDB[999999] = {
            title = "Test Quest",
            description = "This is a test entry to verify the UI.",
            originalObjectives = "Check the journal.",
            zone = "Test Zone",
            timestamp = time()
        }
        print("IronMan: Test entry added.")
        if Scribe.journalFrame and Scribe.journalFrame:IsShown() then
            Scribe.journalFrame.RefreshJournal()
        end

    elseif msg == "clear" then
        IronManJournalDB = {}
        print("IronMan Journal cleared.")
        if Scribe.journalFrame and Scribe.journalFrame:IsShown() then
            Scribe.journalFrame.RefreshJournal()
        end

    else
        -- Toggle journal
        if Scribe.journalFrame then
            if Scribe.journalFrame:IsShown() then
                Scribe.journalFrame:Hide()
            else
                Scribe.journalFrame:Show()
            end
        end
    end
end

--[[
    Initialize the Scribe module
]]
function Scribe.Initialize()
    -- Create event frame
    local eventFrame = CreateFrame("Frame", "IronManScribeFrame")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Create journal frame
    Scribe.journalFrame = CreateJournalFrame()
    Scribe.journalFrame.RefreshJournal = RefreshJournal
    Scribe.journalFrame:SetScript("OnShow", RefreshJournal)

    -- Register slash commands
    SLASH_IRONMANJOURNAL1 = "/journal"
    SLASH_IRONMANJOURNAL2 = "/imj"
    SlashCmdList["IRONMANJOURNAL"] = HandleSlashCommand
end

-- Auto-initialize on load
Scribe.Initialize()
