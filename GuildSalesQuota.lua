local LAM2 = LibStub("LibAddonMenu-2.0")

local GuildSalesQuota = {}
GuildSalesQuota.name            = "GuildSalesQuota"
GuildSalesQuota.version         = "3.1.1"
GuildSalesQuota.savedVarVersion = 5
GuildSalesQuota.default = {
      enable_guild  = { true, true, true, true, true }
    , mm_date_index = 4
    , user_records = {}

}
GuildSalesQuota.max_guild_ct = 5
GuildSalesQuota.fetching = { false, false, false, false, false }

GuildSalesQuota.guild_name  = {} -- guild_name [guild_index] = "My Guild"
GuildSalesQuota.guild_index = {} -- guild_index["My Guild" ] = 1
GuildSalesQuota.guild_rank  = {} -- table of tables, gr[guild_index][rank]="Veteran"

                        -- When does the saved time range begin and end.
                        -- Seconds since the epoch.
                        -- Filled in at start of MMScan()
                        -- Either or both can be nil for "no limit".
GuildSalesQuota.saved_begin_ts = 0
GuildSalesQuota.saved_end_ts   = 0

                        -- key = user_id
                        -- value = UserRecord
GuildSalesQuota.user_records = {}

                        -- retry_ct[guild_index] = how many retries after
                        -- distrusting "nah, no more history"
GuildSalesQuota.retry_ct   = { 0, 0, 0, 0, 0 }
GuildSalesQuota.max_retry_ct = 3
                        -- Filled in partially by DateRanges(), fully by FetchMMDateRanges()
GuildSalesQuota.mm_date_ranges = nil

-- UserGuildTotals -----------------------------------------------------------
-- sub-element of UserRecord
--
-- One user's membership and buy/sell totals for one guild.
--
local UserGuildTotals = {
--    is_member      = false        -- latch true during GetGuildMember loops
--  , bought         = 0            -- gold totals for this user in this guild's store
--  , sold           = 0
--  , joined_ts      = 1469247161   -- when this user joined this guild
--  , rank_index     = 1            -- player's rank within this guild, nil if not is_member

                                    -- Audit trail: what are the first and last
                                    -- MM records that counted in the "sold" total?
--  , sold_first_mm  = mm_sales_record
--  , sold_last_mm   = mm_sales_record
--  , sold_ct_mm     = 0
}

local function MMEarlier(mm_a, mm_b)
    if not mm_b then return mm_a end
    if not mm_a then return mm_b end
    if mm_a.timestamp <= mm_b.timestamp then return mm_a end
    return mm_b
end

local function MMLater(mm_a, mm_b)
    if not mm_b then return mm_a end
    if not mm_a then return mm_b end
    if mm_a.timestamp <= mm_b.timestamp then return mm_b end
    return mm_a
end

local function MaxRank(a, b)
    if not a then return b end
    if not b then return a end
    return math.max(a, b)
end

function UserGuildTotals:Add(b)
    if not b then return end
    self.is_member      = self.is_member or b.is_member
    self.bought         = self.bought         + b.bought
    self.sold           = self.sold           + b.sold
    self.rank_index     = MaxRank(self.rank_index, b.rank_index)

    self.sold_first_mm = MMEarlier(self.sold_first_mm, b.sold_first_mm)
    self.sold_last_mm  = MMLater(self.sold_last_mm,    b.sold_last_mm )
    self.sold_ct_mm    = self.sold_ct_mm             + b.sold_ct_mm
end

local function MMToString(mm)
    if not mm then return "nil nil nil" end
    return        tostring(mm.timestamp)
        .. " " .. tostring(mm.buyer)
        .. " " .. tostring(mm.price)
end

function UserGuildTotals:ToString()
    return            tostring(  self.is_member     )
            .. " " .. tostring(  self.rank_index    )
            .. " " .. tostring(  self.bought        )
            .. " " .. tostring(  self.sold          )
            .. " " .. tostring(  self.joined_ts     )
            .. " " .. tostring(  self.sold_ct_mm    )
            .. " " .. MMToString(self.sold_first_mm )
            .. " " .. MMToString(self.sold_last_mm  )
end

function UserGuildTotals:New()
    local o = { is_member      = false
              , bought         = 0
              , sold           = 0
              , joined_ts      = nil
              , sold_first_mm  = nil
              , sold_last_mm   = nil
              , sold_ct_mm     = 0
              }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- UserRecord ----------------------------------------------------------------
-- One row in our savedVariables history
--
-- One user's membership and buy/sell totals for each guild.
--
-- Knows how to add a sale/purchase to a specific guild by index
local UserRecord = {
--    user_id = nil     -- @account string
--
--                      -- UserGuildTotals struct, one per guild with any of
--                      -- guild membership, sale, or purchase.
--  , g       = { nil, nil, nil, nil, nil }
}

-- For summary reports
function UserRecord:Sum()
    local r = UserGuildTotals:New()
    for _, ugt in pairs(self.g) do
        r:Add(ugt)
    end
    return r
end

function UserRecord:SetIsGuildMember(guild_index, is_member)
    local ugt = self:UGT(guild_index)
    local v = true            -- default to true if left nil.
    if is_member == false then v = false end
    ugt.is_member = v
end

function UserRecord:SetGuildNote(guild_index, note)
    local ugt = self:UGT(guild_index)
    ugt.note = note
end

function UserRecord:SetRankIndex(guild_index, rank_index)
    local ugt = self:UGT(guild_index)
    ugt.rank_index = rank_index
end

-- Lazy-create list elements upon demand.
function UserRecord:UGT(guild_index)
    if not self.g[guild_index] then
        self.g[guild_index] = UserGuildTotals:New()
        self.g[guild_index].joined_ts = self:CalcTimeJoinedGuild(guild_index)
    end
    return self.g[guild_index]
end

function UserRecord:AddSold(guild_index, mm_sales_record)
    local ugt = self:UGT(guild_index)
    ugt.sold = ugt.sold + mm_sales_record.price

    ugt.sold_first_mm = MMEarlier(ugt.sold_first_mm, mm_sales_record)
    ugt.sold_last_mm  = MMLater(ugt.sold_last_mm, mm_sales_record)
    ugt.sold_ct_mm    = ugt.sold_ct_mm + 1
end

function UserRecord:AddBought(guild_index, amount)
    local ugt = self:UGT(guild_index)
    ugt.bought = ugt.bought + amount
end

function UserRecord:FromUserID(user_id)
    local o = { user_id = user_id
              , g       = { nil, nil, nil, nil, nil }
              }
    setmetatable(o, self)
    self.__index = self
    return o
end

function UserRecord:ToString()
    local s = self.user_id
    for guild_index = 1, GuildSalesQuota.max_guild_ct do
        local ugt = self.g[guild_index]
        if ugt then
            s = s .. "\t" .. ugt:ToString()
        else
            s = s .. "\t"
        end
    end
    return s
end

-- When was the first time we saw this user_id in this guild?
function UserRecord:CalcTimeJoinedGuild(guild_index)
    if not (GuildSalesQuota.savedVariables
            and GuildSalesQuota.savedVariables.roster
            and GuildSalesQuota.savedVariables.roster[guild_index]
            and GuildSalesQuota.savedVariables.roster[guild_index][self.user_id]
           ) then return 0 end
    return GuildSalesQuota.savedVariables.roster[guild_index][self.user_id].first_seen_ts
end

-- Lazy-create UserRecord instances on demand.
function GuildSalesQuota:UR(user_id)
    if not self.user_records[user_id] then
        self.user_records[user_id] = UserRecord:FromUserID(user_id)
    end
    return self.user_records[user_id]
end

-- Return a more compact list-of-strings representation
function GuildSalesQuota:CompressedUserRecords()
    local line_list = {}
    for _, ur in pairs(self.user_records) do
        table.insert(line_list, ur:ToString())
    end
    return line_list
end

function GuildSalesQuota:UserNotes()
    local u_g_note = {}
    for _, ur in pairs(self.user_records) do
        local g_note   = {}
        local have_one = false
        for guild_index,ugt in pairs(ur.g) do
            if ugt and ugt.note and ugt.note ~= "" then
                g_note[guild_index] = ugt.note
                have_one = true
            end
        end
        if have_one then
            u_g_note[ur.user_id] = g_note
        end
    end
    return u_g_note
end

-- Roster --------------------------------------------------------------------

function GuildSalesQuota.TodayTS()
                        -- Copied straight from MasterMerchant_Guild.lua
      return GetTimeStamp() - GetSecondsSinceMidnight()
end

function GuildSalesQuota.RosterList(guild_index)
    local member_names = {}
    local guildId = GetGuildId(guild_index)
    local ct      = GetNumGuildMembers(guildId)
    for i = 1, ct do
        local user_id = GetGuildMemberInfo(guildId, i)
        table.insert(member_names, user_id)
    end
    return member_names
end

function GuildSalesQuota:RememberMembers(guild_index)
    local today_ts = self.TodayTS()
    local prev     = {}
    local new      = {}
    if self.savedVariables.roster and self.savedVariables.roster[guild_index] then
        prev = self.savedVariables.roster[guild_index]
    end

    local curr = self.RosterList(guild_index)
    for i, user_id in ipairs(curr) do
                        -- Retain any survivors from before.
                        -- or create new record for newbies.
        new[user_id] = prev[user_id] or { first_seen_ts = today_ts }
    end

    if not self.savedVariables.roster then self.savedVariables.roster = {} end
    self.savedVariables.roster[guild_index] = new
    return #curr
end

function GuildSalesQuota:RememberMembersAllEnabledGuilds()
    self.savedVariables.guild_name = self:GuildNameList()
    local ct = 0
    for guild_index = 1, self.max_guild_ct do
        if self.savedVariables.enable_guild[guild_index] then
            ct = ct + self:RememberMembers(guild_index)
        end
    end
    return ct
end

function GuildSalesQuota:DailyRosterCheckNeeded()
    if not self.savedVariables then return true end
    if not self.savedVariables.roster then return true end
    if not self.savedVariables.roster.last_scan_ts then return true end
    if not (self.TodayTS() <= self.savedVariables.roster.last_scan_ts)  then return true end
    return false
end

function GuildSalesQuota.DailyRosterCheck()
                        -- NOP if already checked once today
    self = GuildSalesQuota
    if not self:DailyRosterCheckNeeded() then
        --d("GuildSalesQuota: guild roster already saved once today. Done.")
        return
    end

    d("GuildSalesQuota: saving guild rosters...")
    local ct = self:RememberMembersAllEnabledGuilds()
    d("GuildSalesQuota: saved "..tostring(ct).." guild members. Done.")

    if not self.savedVariables.roster then self.savedVariables.roster = {} end
    self.savedVariables.roster.last_scan_ts = self.TodayTS()
end

-- Init ----------------------------------------------------------------------

function GuildSalesQuota.OnAddOnLoaded(event, addonName)
    if addonName ~= GuildSalesQuota.name then return end
    if not GuildSalesQuota.version then return end
    if not GuildSalesQuota.default then return end
    GuildSalesQuota:Initialize()
end

function GuildSalesQuota:Initialize()
    self.savedVariables = ZO_SavedVars:NewAccountWide(
                              "GuildSalesQuotaVars"
                            , self.savedVarVersion
                            , nil
                            , self.default
                            )

                        -- While I'm having irreproducible results with
                        -- savedVariables, it's helpful to have SOME clue
                        -- to when I last loaded this from NewAccountWide().
                        --
                        -- Helps also to keep bumping the savedVarVersion.
    self.savedVariables.last_initialized = GetDateStringFromTimestamp(GetTimeStamp())
                                           .. " " .. GetTimeString()

    self:CreateSettingsWindow()
    --EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_ADD_ON_LOADED)
end

-- UI ------------------------------------------------------------------------

function GuildSalesQuota.ref_cb(guild_index)
    return "GuildSalesQuota_cbg" .. guild_index
end

function GuildSalesQuota.ref_desc(guild_index)
    return "GuildSalesQuota_desc" .. guild_index
end

function GuildSalesQuota:CreateSettingsWindow()
    local panelData = {
        type                = "panel",
        name                = "Guild Sales Quota",
        displayName         = "Guild Sales Quota",
        author              = "ziggr",
        version             = self.version,
        --slashCommand        = "/gg",            -- !!! COMMENT THIS OUT BEFORE PUBLISHING
        registerForRefresh  = true,
        registerForDefaults = false,
    }
    local cntrlOptionsPanel = LAM2:RegisterAddonPanel( self.name
                                                     , panelData
                                                     )
    local optionsData = {
        { type      = "button"
        , name      = "Save Data Now"
        , tooltip   = "Save guild sales data to file now."
        , func      = function() self:SaveNow() end
        },
        { type      = "header"
        , name      = "Guilds"
        },
    }

    for guild_index = 1, self.max_guild_ct do
        table.insert(optionsData,
            { type      = "checkbox"
            , name      = "(guild " .. guild_index .. ")"
            , tooltip   = "Save data for guild " .. guild_index .. "?"
            , getFunc   = function()
                            return self.savedVariables.enable_guild[guild_index]
                          end
            , setFunc   = function(e)
                            self.savedVariables.enable_guild[guild_index] = e
                          end
            , reference = self.ref_cb(guild_index)
            })
                        -- HACK: for some reason, I cannot get "description"
                        -- items to dynamically update their text. Color and
                        -- hidden, yes, but text? Nope, it never changes. So
                        -- instead of a desc for static text, I'm going to use
                        -- a "checkbox" with the on/off field hidden. Total
                        -- hack. Sorry.
        table.insert(optionsData,
            { type      = "checkbox"
            , name      = "(desc " .. guild_index .. ")"
            , reference = self.ref_desc(guild_index)
            , getFunc   = function() return false end
            , setFunc   = function() end
            })
    end

                    -- MM date range
    table.insert(optionsData,
        { type    = "header"
        , name    = "Date Options"
        })

    local r = {
          type    = "dropdown"
        , name    = "Date range"
        , getFunc = function() return self.savedVariables.mm_date_index end
        , setFunc = function(e) self.savedVariables.mm_date_index = e end
        , tooltip = "Which Master Merchant date range to export?"
                    .." 'Last Week' is most common."
        , choices = {}
        , choicesValues = {}
        }
    for index, mmdr in ipairs(GuildSalesQuota.DateRanges()) do
        r.choices[index] = mmdr.name
        r.choicesValues[index] = index
    end
    table.insert(optionsData, r)

    LAM2:RegisterOptionControls("GuildSalesQuota", optionsData)
    CALLBACK_MANAGER:RegisterCallback("LAM-PanelControlsCreated"
            , self.OnPanelControlsCreated)
end

-- Return a partially initialized date range table.
-- Names are there, but start/end timestamps not yet: those don't get
-- filled in until SaveNow() calls FetchMMDateRanges().
function GuildSalesQuota.DateRanges()
    if GuildSalesQuota.mm_date_ranges then
        return GuildSalesQuota.mm_date_ranges
    end

    local r   = {}
    r[1] = { name = "Today"        }
    r[2] = { name = "Yesterday"    }
    r[3] = { name = "This Week"    }
    r[4] = { name = "Last Week"    }
    r[5] = { name = "Prior Week"   }
    r[6] = { name = "Last 10 Days" }
    r[7] = { name = "Last 30 Days" }
    r[8] = { name = "Last 7 Days"  }
    r[9] = { name = "All History" }
    GuildSalesQuota.mm_date_ranges = r
    return GuildSalesQuota.mm_date_ranges
end

-- Lazy fetch M.M. date ranges.
function GuildSalesQuota.FetchMMDateRanges()
    local mmg = MMGuild:new("_not_really_a_guild")
    local r   = GuildSalesQuota.DateRanges()
    r[1].start_ts = mmg.oneStart        -- Today
    r[1].end_ts   = nil
    r[2].start_ts = mmg.twoStart        -- Yesterday
    r[2].end_ts   = mmg.oneStart
    r[3].start_ts = mmg.threeStart      -- This Week
    r[3].end_ts   = nil
    r[4].start_ts = mmg.fourStart       -- Last Week
    r[4].end_ts   = mmg.fourEnd
    r[5].start_ts = mmg.fiveStart       -- Prior Week
    r[5].end_ts   = mmg.fiveEnd
    r[6].start_ts = mmg.sixStart        -- Last 10 Days
    r[6].end_ts   = nil
    r[7].start_ts = mmg.sevenStart      -- Last 30 Days
    r[7].end_ts   = nil
    r[8].start_ts = mmg.eightStart      -- Last 7 Days
    r[8].end_ts   = nil
                        -- Replace MM's "custom" date range with "All".
                        -- (Not worth the effort: I would have to dynamically
                        -- reload each time I updated UI or ran a scan)
    r[9].start_ts = nil
    r[9].end_ts   = nil
    GuildSalesQuota.mm_date_ranges = r
    return GuildSalesQuota.mm_date_ranges
end

-- Delay initialization of options panel: don't waste time fetching
-- guild names until a human actually opens our panel.
function GuildSalesQuota.OnPanelControlsCreated(panel)
    self = GuildSalesQuota
    local guild_ct = GetNumGuilds()
    for guild_index = 1,self.max_guild_ct do
        exists = guild_index <= guild_ct
        self:InitGuildSettings(guild_index, exists)
        self:InitGuildControls(guild_index, exists)
    end
end

-- Data portion of init UI
function GuildSalesQuota:InitGuildSettings(guild_index, exists)
    if not exists then
        self.savedVariables.enable_guild[guild_index] = false
        return
    end

    local guildId   = GetGuildId(guild_index)
    local guildName = GetGuildName(guildId)
    self.guild_name[guild_index] = guildName
    self.guild_index[guildName]  = guild_index
end

-- UI portion of init UI
function GuildSalesQuota:InitGuildControls(guild_index, exists)
    local cb = _G[self.ref_cb(guild_index)]
    if exists and cb and cb.label then
        cb.label:SetText(self.guild_name[guild_index])
    end
    if cb then
        cb:SetHidden(not exists)
    end

    local desc = _G[self.ref_desc(guild_index)]
    self.ConvertCheckboxToText(desc)
end

-- Coerce a checkbox to act like a text label.
--
-- I cannot get LibAddonMenu-2.0 "description" items to dynamically update
-- their text. SetText() has no effect. But SetText() works on "checkbox"
-- items, so beat those into a text-like UI element.
function GuildSalesQuota.ConvertCheckboxToText(desc)
    if not desc then return end
    desc:SetHandler("OnMouseEnter", nil)
    desc:SetHandler("OnMouseExit",  nil)
    desc:SetHandler("OnMouseUp",    nil)
    desc.label:SetFont("ZoFontGame")
    desc.label:SetText("-")
    desc.checkbox:SetHidden(true)
end

-- Display Status ------------------------------------------------------------

-- Update the per-guild text label with what's going on with that guild data.
function GuildSalesQuota:SetStatus(guild_index, msg)
    local x = _G[self.ref_desc(guild_index)]
    if not x then return end
    local desc = x.label
    desc:SetText("  " .. msg)
end

-- numbered list of guild names, suitable for savedVariables.guild_name
function GuildSalesQuota:GuildNameList()
    local r = {}
    for guild_index = 1, self.max_guild_ct do
        r[guild_index] = self.guild_name[guild_index]
    end
    return r
end

-- Fetch Guild Data from the server and Master Merchant ----------------------
--
-- Fetch _all_ events for each guild. Server holds no more than 10 days, no
-- more than 500 events.
--
-- Defer per-event iteration until fetch is complete. This might help reduce
-- the clock skew caused by the items using relative time, but relative
-- to _what_?

function GuildSalesQuota:SaveNow()
    self.fetched_str_list = {}
    self.savedVariables.guild_name = self:GuildNameList()

    for guild_index = 1, self.max_guild_ct do
        if self.savedVariables.enable_guild[guild_index] then
            self:SaveGuildIndex(guild_index)
        else
            self:SkipGuildIndex(guild_index)
        end
    end
    if not self.user_records then
        d("No guild members to report. Nothing to do.")
        return
    end

    self.savedVariables.guild_rank = self.guild_rank

    self:MMScan()
    self:Done()
end

-- When the async guild bank history scan is done, print summary to chat.
function GuildSalesQuota:Done()
    self.savedVariables.user_records       = self:CompressedUserRecords()
    self.savedVariables.user_notes         = self:UserNotes()

                        -- Tell CSV what time range we saved.
                        -- These timestamps aren't set until MMScan, so
                        -- don't write them until after MMScan.
    self.savedVariables.saved_begin_ts = self.saved_begin_ts
    self.savedVariables.saved_end_ts   = self.saved_end_ts

                        -- Write a summary and "gotta relog!" to chat window.
    local r = self:SummaryCount()
    d(self.name .. ": saved " ..tostring(r.user_ct).. " user record(s)." )
    d(self.name .. ": " .. tostring(r.seller_ct) .. " seller(s), "
                        .. tostring(r.buyer_ct) .. " buyer(s)." )
    d(self.name .. ": Reload UI, log out, or quit to write file.")
end

-- User doesn't want this guild. Respond with "okay, skipping"
function GuildSalesQuota:SkipGuildIndex(guild_index)
    self:SetStatus(guild_index, "skipped")
end

-- Download one guild's roster
-- Happens nearly instantaneously.
function GuildSalesQuota:SaveGuildIndex(guild_index)
    local guildId = GetGuildId(guild_index)
    self.fetching[guild_index] = true

                        -- Fetch guild rank index/name list
    local rank_ct = GetNumGuildRanks(guildId)
    self.guild_rank[guild_index] = {}
    for rank_index = 1,rank_ct do
        local rank_name = GetGuildRankCustomName(guildId, rank_index)
                        -- Kudos to Ayantir's GMen for pointing me to
                        -- GetFinalGuildRankName()
        if rank_name == "" then
            rank_name = GetFinalGuildRankName(guildId, rank_index)
        end
        self.guild_rank[guild_index][rank_index] = rank_name
    end

                        -- Fetch complete guild member list
    local ct = GetNumGuildMembers(guildId)
    self:SetStatus(guild_index, "downloading " .. ct .. " member names...")
    for i = 1, ct do
        local user_id, note, rank_index = GetGuildMemberInfo(guildId, i)
        local ur = self:UR(user_id)
        ur:SetIsGuildMember(guild_index)
        ur:SetRankIndex(guild_index, rank_index)
        ur:SetGuildNote(guild_index, note)
    end
    self:SetStatus(guild_index, ct .. " members")
end

-- Master Merchant -----------------------------------------------------------

-- Scan through every single sale recorded in Master Merchant, and if it was
-- a sale through one of our requested guild stores, AND sometime during
-- "Last Week", then credit the seller and buyer with the gold amount.
--
-- Happens nearly instantaneously.
--
function GuildSalesQuota:MMScan()
    self:CalcSavedTS()

    -- d("MMScan start")
                        -- O(n) table scan of all MM data.
                        --- This will take a while...
    local salesData = MasterMerchant.salesData
    local itemID_ct = 0
    local sale_ct = 0
    for itemID,t in pairs(salesData) do
        itemID_ct = itemID_ct + 1
        for itemIndex,tt in pairs(t) do
            local sales = tt["sales"]
            if sales then
                for i, mm_sales_record in ipairs(sales) do
                    local s = self:AddMMSale(mm_sales_record)
                    if s then
                        sale_ct = sale_ct + 1
                    end
                end
            end
        end
    end

    -- d("MMScan done  itemID_ct=" .. itemID_ct .. " sale_ct=" .. sale_ct)

end

-- Fill in begin/end timestamps for "Last Week"
function GuildSalesQuota:CalcSavedTS()
                        -- Use the start/end timestamps chosen from
                        -- the UI dropdown.
    local r = GuildSalesQuota.FetchMMDateRanges()
    self.saved_begin_ts = r[self.savedVariables.mm_date_index].start_ts
    self.saved_end_ts   = r[self.savedVariables.mm_date_index].end_ts
end

function GuildSalesQuota:AddMMSale(mm_sales_record)
    local mm = mm_sales_record  -- for less typing

                        -- Track only sales within guilds we care about.
    local guild_index = self.guild_index[mm.guild]
    if not guild_index then return 0 end
    if not self.savedVariables.enable_guild[guild_index] then return 0 end

                        -- Track only sales within time range we care about.
    if self.saved_begin_ts and mm.timestamp < self.saved_begin_ts
        or self.saved_end_ts and self.saved_end_ts < mm.timestamp then
        return 0
    end

    -- d("# buyer " .. mm.buyer .. "  seller " .. mm.seller)
    self:UR(mm.buyer ):AddBought(guild_index, mm.price)
    self:UR(mm.seller):AddSold  (guild_index, mm)
    return 1
end

function GuildSalesQuota:SummaryCount()
    local r = { user_ct   = 0
              , buyer_ct  = 0
              , seller_ct = 0
              , member_ct = 0
              , bought    = 0
              , sold      = 0
              }
    for _, ur in pairs(self.user_records) do
        r.user_ct = r.user_ct + 1
        ugt_sum = ur:Sum()
        if ugt_sum.is_member   then r.member_ct = r.member_ct + 1 end
        if ugt_sum.bought > 0  then r.buyer_ct  = r.buyer_ct  + 1 end
        if ugt_sum.sold   > 0  then r.seller_ct = r.seller_ct + 1 end
        r.bought = r.bought + ugt_sum.bought
        r.sold   = r.sold   + ugt_sum.sold
    end
    return r
end

-- Postamble -----------------------------------------------------------------

EVENT_MANAGER:RegisterForEvent( GuildSalesQuota.name
                              , EVENT_ADD_ON_LOADED
                              , GuildSalesQuota.OnAddOnLoaded
                              )
EVENT_MANAGER:RegisterForEvent( GuildSalesQuota.name
                              , EVENT_PLAYER_ACTIVATED
                              , GuildSalesQuota.DailyRosterCheck
                              )
