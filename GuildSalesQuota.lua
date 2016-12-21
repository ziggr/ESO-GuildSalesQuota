local LAM2 = LibStub("LibAddonMenu-2.0")

local GuildSalesQuota = {}
GuildSalesQuota.name            = "GuildSalesQuota"
GuildSalesQuota.version         = "2.6.4"
GuildSalesQuota.savedVarVersion = 4
GuildSalesQuota.default = {
      enable_guild  = { true, true, true, true, true }
    , user_records = {}
}
GuildSalesQuota.max_guild_ct = 5
GuildSalesQuota.fetching = { false, false, false, false, false }

GuildSalesQuota.guild_name  = {} -- guild_name [guild_index] = "My Guild"
GuildSalesQuota.guild_index = {} -- guild_index["My Guild" ] = 1

                        -- timestamp of oldest event recorded in this guild
                        -- in Shissu's Guild Tools history.
                        --   nil if not yet requested/calculated
                        --   0   if requested but not found
                        --   1469247161 (seconds since epoch) once found.
                        -- Lazy-fetched in CalcTimeGuildStarted(guild_id)
GuildSalesQuota.guild_time_started = {}

                        -- When does "Last Week" begin and end. Seconds
                        -- since the epoch. Filled in at start of MMScan()
GuildSalesQuota.last_week_begin_ts = 0
GuildSalesQuota.last_week_end_ts   = 0
                        -- When does "Last Week" end for raffle deposits?
                        -- 5 hours after M.M.'s "week" because M.M. ends around
                        -- 17:00 (EST -0500) but the raffle runs at 20:00
                        -- and sometimes starts an hour or two late.
GuildSalesQuota.last_week_end_ts_raffle = 0

                        -- key = user_id
                        -- value = UserRecord
GuildSalesQuota.user_records = {}

                        -- retry_ct[guild_index] = how many retries after
                        -- distrusting "nah, no more history"
GuildSalesQuota.retry_ct   = { 0, 0, 0, 0, 0 }
GuildSalesQuota.max_retry_ct = 3


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
--  , gold_deposited = 0            -- gold deposits to guild bank

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

function UserGuildTotals:Add(b)
    if not b then return end
    self.is_member      = self.is_member or b.is_member
    self.bought         = self.bought         + b.bought
    self.sold           = self.sold           + b.sold
    self.gold_deposited = self.gold_deposited + b.gold_deposited

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
    return tostring(self.is_member)
            .. " " .. tostring(self.bought)
            .. " " .. tostring(self.sold)
            .. " " .. tostring(self.joined_ts)
            .. " " .. tostring(self.gold_deposited)
            .. " " .. tostring(self.sold_ct_mm)
            .. " " .. MMToString(self.sold_first_mm)
            .. " " .. MMToString(self.sold_last_mm)
end

function UserGuildTotals:New()
    local o = { is_member      = false
              , bought         = 0
              , sold           = 0
              , gold_deposited = 0
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

function UserRecord:AddGoldDeposit(guild_index, amount)
    local ugt = self:UGT(guild_index)
    ugt.gold_deposited = ugt.gold_deposited + amount
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

-- ShissuGuildTools integration: When does Shissu think this account
-- joined the guild?
function UserRecord:CalcTimeJoinedGuild(guild_index)
                        -- Fallback to guild-wide start time if no user-
                        -- specific time.
    local r = GuildSalesQuota:CalcTimeGuildStarted(guild_index)
    local guild_name = GuildSalesQuota.guild_name[guild_index]

                        -- "shissuGT" here is Shissu's savedVariables data.
    if not shissuGT                                              then return r end
    if not shissuGT.History                                      then return r end
    if not shissuGT.History[guild_name]                          then return r end
    if not shissuGT.History[guild_name][self.user_id]            then return r end
    if not shissuGT.History[guild_name][self.user_id].timeJoined then return r end

    return shissuGT.History[guild_name][self.user_id].timeJoined
end

-- ShissuGuildTools integration: When does Shissu think this guild started?
-- (Or more common: when did Shissu first run?)
function GuildSalesQuota:CalcTimeGuildStarted(guild_index)
    if self.guild_time_started[guild_index] then
        return self.guild_time_started[guild_index]
    end
                        -- "0" means "we tried to calc it but came up empty."
    self.guild_time_started[guild_index] = 0
    local guild_name = self.guild_name[guild_index]

                        -- "shissuGT" here is Shissu's savedVariables data.
    if not shissuGT                                    then return 0 end
    if not shissuGT.History                            then return 0 end
    if not shissuGT.History[guild_name]                then return 0 end
    if not shissuGT.History[guild_name].oldestEvent    then return 0 end
    if not shissuGT.History[guild_name].oldestEvent[1] then return 0 end

    self.guild_time_started[guild_index] = shissuGT.History[guild_name].oldestEvent[1]
    return self.guild_time_started[guild_index]
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

    LAM2:RegisterOptionControls("GuildSalesQuota", optionsData)
    CALLBACK_MANAGER:RegisterCallback("LAM-PanelControlsCreated"
            , self.OnPanelControlsCreated)
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
    if exists then
        local guildId   = GetGuildId(guild_index)
        local guildName = GetGuildName(guildId)
        self.guild_name[guild_index] = guildName
        self.guild_index[guildName]  = guild_index
    else
        self.savedVariables.enable_guild[guild_index] = false
    end
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

    self:MMScan()
    self:GuildGoldDepositScan()
end

-- When the async guild bank history scan is done, print summary to chat.
function GuildSalesQuota:Done()
    self.savedVariables.user_records       = self:CompressedUserRecords()

                        -- Tell CSV which week this is.
                        -- These timestamps aren't set until MMScan, so
                        -- don't write them until after MMScan.
    self.savedVariables.last_week_begin_ts = self.last_week_begin_ts
    self.savedVariables.last_week_end_ts   = self.last_week_end_ts


                        -- Write a summary and "gotta relog!" to chat window.
    local r = self:SummaryCount()
    d(self.name .. ": saved " ..tostring(r.user_ct).. " user record(s)." )
    d(self.name .. ": " .. tostring(r.seller_ct) .. " seller(s), "
                        .. tostring(r.buyer_ct) .. " buyer(s)." )
    d(self.name .. ": Log out or Quit to write file.")
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
    local ct = GetNumGuildMembers(guildId)

                        -- Fetch complete guild member list
    self:SetStatus(guild_index, "downloading " .. ct .. " member names...")
    for i = 1, ct do
        local user_id = GetGuildMemberInfo(guildId, i)
        local ur = self:UR(user_id)
        ur:SetIsGuildMember(guild_index)
    end
    self:SetStatus(guild_index, ct .. " members")
end

-- GuildGoldDeposits / GGD ---------------------------------------------------

-- A subset of GuildGoldDeposits to accumulate total gold deposited to the
-- guild bank in the "Last Week".

function GuildSalesQuota:GuildGoldDepositScan()
    self.fetched_str_list = {}
    for guild_index = 1, self.max_guild_ct do
        if self.savedVariables.enable_guild[guild_index] then
            self:GGD_SaveGuildIndex(guild_index)
        else
            self:SkipGuildIndex(guild_index)
        end
    end
end

-- Download one guild's history
function GuildSalesQuota:GGD_SaveGuildIndex(guild_index)
    guildId = GetGuildId(guild_index)
    self.fetching[guild_index] = true
    self:SetStatus(guild_index, "downloading history...")
    RequestGuildHistoryCategoryNewest(guildId, GUILD_HISTORY_BANK)

                        -- Start an asynchronous callback chain to slowly
                        -- poll ESO servers for all history. Chain will
                        -- callback itself until done, then callback
                        -- into the actual processing of that data.
    self:GGD_ServerDataPoll(guild_index)
end

-- Async poll to fetch ALL guild bank history data from the ESO server
-- Calls GGD_ServerDataComplete() once all data is loaded.
function GuildSalesQuota:GGD_ServerDataPoll(guild_index)
    guildId = GetGuildId(guild_index)
    more = DoesGuildHistoryCategoryHaveMoreEvents(guildId, GUILD_HISTORY_BANK)
    event_ct = GetNumGuildEvents(guildId, GUILD_HISTORY_BANK)
    self:SetStatus(guild_index, "fetching events: " .. event_ct .. " ...")
    can_retry =    (not self.retry_ct[guild_index])
                or (self.retry_ct[guild_index] < self.max_retry_ct)
    if more or can_retry then
        RequestGuildHistoryCategoryOlder(guildId, GUILD_HISTORY_BANK)
        delay_ms = 0.5 * 1000
        zo_callLater(function() self:GGD_ServerDataPoll(guild_index) end, delay_ms)
        if not more then
            self.retry_ct[guild_index] = 1 + self.retry_ct[guild_index]
        end
    else
        self:GGD_ServerDataComplete(guild_index)
    end
end

-- Now that all data from the ESO server is loaded into the ESO client,
-- extract gold deposits and write to savedVars.
function GuildSalesQuota:GGD_ServerDataComplete(guild_index)
                        -- Avoid infinite noise if a Lua error in here
                        -- causes a repeated callback. Mostly useful when
                        -- debugging, shouldn't be an issue when we're
                        -- not buggy.
    if not self.fetching[guild_index] then return end

                        -- Latch false (until next time user clicks "Save Now")
                        -- so that we know not to re-complete this guild.
                        -- And so we know when all guilds are complete.
    self.fetching[guild_index] = false

    guildId = GetGuildId(guild_index)
    guild_name = self.guild_name[guild_index]
    event_ct = GetNumGuildEvents(guildId, GUILD_HISTORY_BANK)
    --self:SetStatus(guild_index, "scanning events: " .. event_ct .. " ...")
    for i = 1, event_ct do
        local t,s,u,a = GetGuildEventInfo(guildId, GUILD_HISTORY_BANK, i)
        self:AddGGD(guild_index, t, s, u, a)
    end
    self:SetStatus(guild_index, "done")

                        -- I got sick of forgetting to relog, and I _wrote_
                        -- this thing. I can only imagine how many poor
                        -- unsuspecting users will get caught by "Oh, forgot to
                        -- relog!" if I don't add a reminder.
    if not self:StillFetchingAny() then
        self:Done()
    end
end

function GuildSalesQuota:StillFetchingAny()
    for _,v in pairs(self.fetching) do
        if v then return true end
    end
    return false
end

-- Master Merchant -----------------------------------------------------------

-- Scan through every single sale recorded in Master Merchant, and if it was
-- a sale through one of our requested guild stores, AND sometime during
-- "Last Week", then credit the seller and buyer with the gold amount.
--
-- Happens nearly instantaneously.
--
function GuildSalesQuota:MMScan()
    self:CalcLastWeekTS()

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
function GuildSalesQuota:CalcLastWeekTS()
                        -- Let MM calculate start/end times for "Last Week"
    local mmg = MMGuild:new("_not_really_a_guild")
    self.last_week_begin_ts = mmg.fourStart
    self.last_week_end_ts   = mmg.fourEnd

                        -- Add five hours of slop so that tickets purchased for
                        -- the most recent raffle count as immunity against
                        -- last week's quota, even though "last week" ends
                        -- a couple hours before the raffle.
    self.last_week_end_ts_raffle = mmg.fourEnd + 5 * 3600
end

function GuildSalesQuota:AddMMSale(mm_sales_record)
    local mm = mm_sales_record  -- for less typing

                        -- Track only sales within guilds we care about.
    local guild_index = self.guild_index[mm.guild]
    if not guild_index then return 0 end
    if not self.savedVariables.enable_guild[guild_index] then return 0 end

                        -- Track only sales within "last week"
    if mm.timestamp < self.last_week_begin_ts
            or self.last_week_end_ts < mm.timestamp then
        return 0
    end

    -- d("# buyer " .. mm.buyer .. "  seller " .. mm.seller)
    self:UR(mm.buyer ):AddBought(guild_index, mm.price)
    self:UR(mm.seller):AddSold  (guild_index, mm)
    return 1
end

function GuildSalesQuota:AddGGD(guild_index, event_type, since_secs, user, amount)
    local ts = GetTimeStamp() - since_secs
    if ts < self.last_week_begin_ts or self.last_week_end_ts_raffle < ts then
        return
    end
    self:UR(user):AddGoldDeposit(guild_index, amount)
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
