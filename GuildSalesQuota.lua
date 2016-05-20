local LAM2 = LibStub("LibAddonMenu-2.0")

local GuildSalesQuota = {}
GuildSalesQuota.name            = "GuildSalesQuota"
GuildSalesQuota.version         = "2.3.7.2"
GuildSalesQuota.savedVarVersion = 2
GuildSalesQuota.default = {
      enable_guild  = { true, true, true, true, true }
    , user_records = {}
}
GuildSalesQuota.max_guild_ct = 5
GuildSalesQuota.fetching = { false, false, false, false, false }

GuildSalesQuota.guild_name  = {} -- guild_name [guild_index] = "My Guild"
GuildSalesQuota.guild_index = {} -- guild_index["My Guild" ] = 1

                        -- When does "Last Week" begin and end. Seconds
                        -- since the epoch. Filled in at start of MMScan()
GuildSalesQuota.last_week_begin_ts = 0
GuildSalesQuota.last_week_end_ts   = 0

                        -- key = user_id
                        -- value = UserRecord
GuildSalesQuota.user_records = {}

-- UserRecord ----------------------------------------------------------------
-- One row in our savedVariables history
--
-- Knows how to add a sale/purchase to a specific guild by index
local UserRecord = {
--    user_id = nil     -- @account string
--
--                      -- UserGuildTotals struct, one per guild with any of
--                      -- guild membership, sale, or purchase.
--  , g       = { nil, nil, nil, nil, nil }
}

local UserGuildTotals = {
--    is_member = false   -- latch true during GetGuildMember loops
--  , bought    = 0       -- gold totals for this user in this guild's store
--  , sold      = 0
}

function UserRecord:FromUserID(user_id)
    o = { user_id = user_id
        , g       = { nil, nil, nil, nil, nil }
        }
    setmetatable(o, self)
    self.__index = self
    return o
end

function UserGuildTotals:New()
    o = { is_member = false
        , bought    = 0
        , sold      = 0
        }
    setmetatable(o, self)
    self.__index = self
    return o
end

function UserRecord:SetIsGuildMember(guild_index, is_member)
    ugt = self:UGT(guild_index)
    v = true            -- default to true if left nil.
    if is_member == false then v = false end
    ugt.is_member = v
end

-- Lazy-create list elements upon demand.
function UserRecord:UGT(guild_index)
    if not self.g[guild_index] then
        self.g[guild_index] = UserGuildTotals:New()
    end
    return self.g[guild_index]
end

function UserRecord:AddSold(guild_index, amount)
    ugt = self.UGT(guild_index)
    ugt.sold = ugt.sold + amount
end

function UserRecord.AddBought(guild_index, amount)
    ugt = self.UGT(guild_index)
    ugt.bought = ugt.bought + amount
end

-- Lazy-create UserRecord instances on demand.
function GuildSalesQuota:UR(user_id)
    if not self.user_records[user_id] then
        self.user_records[user_id] = UserRecord:FromUserID(user_id)
    end
    return self.user_records[user_id]
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
        slashCommand        = "/gg",            -- !!! COMMENT THIS OUT BEFORE PUBLISHING
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
    guild_ct = GetNumGuilds()
    for guild_index = 1,self.max_guild_ct do
        exists = guild_index <= guild_ct
        self:InitGuildSettings(guild_index, exists)
        self:InitGuildControls(guild_index, exists)
    end
end

-- Data portion of init UI
function GuildSalesQuota:InitGuildSettings(guild_index, exists)
    if exists then
        guildId   = GetGuildId(guild_index)
        guildName = GetGuildName(guildId)
        self.guild_name[guild_index] = guildName
        self.guild_index[guildName]  = guild_index
    else
        self.savedVariables.enable_guild[guild_index] = false
    end
end

-- UI portion of init UI
function GuildSalesQuota:InitGuildControls(guild_index, exists)
    cb = _G[self.ref_cb(guild_index)]
    if exists and cb and cb.label then
        cb.label:SetText(self.guild_name[guild_index])
    end
    if cb then
        cb:SetHidden(not exists)
    end

    desc = _G[self.ref_desc(guild_index)]
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
    --d("status " .. tostring(guild_index) .. ":" .. tostring(msg))
    x = _G[self.ref_desc(guild_index)]
    if not x then return end
    desc = x.label
    desc:SetText("  " .. msg)
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
    -- self.savedVariables.user_records = self.user_records

end

-- User doesn't want this guild. Respond with "okay, skipping"
function GuildSalesQuota:SkipGuildIndex(guild_index)
    self:SetStatus(guild_index, "skipped")
end

-- Download one guild's history
function GuildSalesQuota:SaveGuildIndex(guild_index)
    guildId = GetGuildId(guild_index)
    self.fetching[guild_index] = true
    ct = GetNumGuildMembers(guildId)

                        -- Fetch complete guild member list
    self:SetStatus(guild_index, "downloading " .. ct .. " member names...")
    for i = 1, ct do
        user_id = GetGuildMemberInfo(guildId, i)
        ur = self:UR(user_id)
        ur:SetIsGuildMember(guild_index)
    end
    self:SetStatus(guild_index, ct .. " members")
end

-- Master Merchant -----------------------------------------------------------

-- Scan through every single sale recorded in Master Merchant, and if it was
-- a sale through one of our requested guild stores, AND sometime during
-- "Last Week", then credit the seller and buyer with the gold amount.

function GuildSalesQuota:MMScan()
    self.CalcLastWeekTS()

    d("MMScan start")
                        -- O(n) table scan of all MM data.
                        --- This will take a while...
    salesData = MasterMerchant.salesData
    itemID_ct = 0
    sale_ct = 0
    for itemID,t in pairs(salesData) do
        itemID_ct = itemID_ct + 1
        for itemIndex,tt in pairs(t) do
            sales = tt["sales"]
            if sales then
                for i, mm_sales_record in ipairs(sales) do
                    s = self:AddMMSale(mm_sales_record)
                    if s then
                        sale_ct = sale_ct + 1
                    end
                end
            end
        end
    end

    d("MMScan done  itemID_ct=" .. itemID_ct .. " sale_ct=" .. sale_ct)

end

-- Fill in begin/end timestamps for "Last Week"
function GuildSalesQuota:CalcLastWeekTS()
                        -- Let MM calculate start/end times for "Last Week"
    mmg = MMGuild:new("_not_really_a_guild")
    last_week_begin_ts = mmg.fourStart
    last_week_end_ts   = mmg.fourEnd
end


function GuildSalesQuota:AddMMSale(mm_sales_record)
    mm = mm_sales_record  -- for less typing

                        -- Track only sales within guilds we care about.
    guild_index = self.guild_index[mm.guild]
    if not guild_index then return 0 end
    if not self.savedVariables.enable_guild[guild_index] then return 0 end

                        -- Track only sales within "last week"
    if mm.timestamp < self.last_week_begin_ts
            or self.last_week_end_ts < mm.timestamp then
        return 0
    end

    self.UR(mm.buyer ):AddBought(guild_index, mm.price)
    self.UR(mm.seller):AddSold  (guild_index, mm.price)
    return 1
end

-- Postamble -----------------------------------------------------------------

EVENT_MANAGER:RegisterForEvent( GuildSalesQuota.name
                              , EVENT_ADD_ON_LOADED
                              , GuildSalesQuota.OnAddOnLoaded
                              )
