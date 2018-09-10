-- Read the SavedVariables file that GuildSalesQuota creates  and convert
-- that to a spreadsheet-compabitle CSV (comma-separated value) file.

IN_FILE_PATH  = "../../SavedVariables/GuildSalesQuota.lua"
OUT_FILE_PATH = "../../SavedVariables/GuildSalesQuota.csv"
dofile(IN_FILE_PATH)
OUT_FILE = assert(io.open(OUT_FILE_PATH, "w"))


NEWBIE_DAYS = 10        -- How many days can you be in the guild
                        -- before sales quotas apply?
NEWBIE_TS   = os.time() - (24*3600*NEWBIE_DAYS)
ALSO_TAB    = arg[1] and arg[1] == "--tab"

-- Lua lacks a split() function. Here's a cheesy one that works
-- for our specific need.
function split(str, delim)
    local l = {}
    local delim_index = 0
    while true do
        end_index = string.find(str, delim, delim_index + 1)
        if end_index == nil then
            local word = string.sub(str, delim_index + 1)
            table.insert(l, word)
            break
        end
        local word = string.sub(str, delim_index + 1, end_index - 1)
        table.insert(l, word)
        delim_index = end_index
    end
    return l
end

-- Optional filter to reduce output.
-- Return true for rows you want written to CSV, false for
-- uninteresting rows not worth writing to CSV.
function PassesReportFilter(row)
                        -- Overload the "--tab" command line option
                        -- to also engage our output filter.
                        --
                        -- Because this is really just a big Zig-specific
                        -- hack thelp use GuildSalesQuota to help manage
                        -- Zig's trading guild, and Zig already passes
                        -- "--tab" for the guild's weekly quota check.
  if ALSO_TAB then

                        -- To reduce output for our guild, omit from report
                        -- any player who...

                        -- is not a guildie (left the guild between time of
                        -- sale and this report)
      if not row.is_member then return false end

-- ZIG COMMENTING THESE NEXT TWO TESTS
-- ALLOWS FULL 500-member export

                        -- is a recent addition to the guild (give folks a
                        -- couple weeks to learn our ways).
      -- if row.is_newbie then return false end

                        -- has sold enough that they don't need our help
      -- if 30000 <= row.sold then return false end
  end

  return true
end

-- Sort by sold, descending. If that matches, sort by bought.
function RecordCompare(a,b)
    -- Group members before outlanders.
    if b.is_member ~= a.is_member then return a.is_member end

    -- First sort by amount sold, descending
    if b.sold < a.sold then return true  end
    if b.sold > a.sold then return false end

    -- Then by amount bought, descending (big buyers are our friends!)
    if b.bought < a.bought then return true  end
    if b.bought > a.bought then return false end

    -- And finally, by user id when there's nothing else meaningful.
    return string.lower(b.user_id) > string.lower(a.user_id)
end

local function tostring_or_nil(s)
    if s == "nil" then return nil end
    return s
end

local function torank_string(guild_rank, guild_index, rank_index)
    if not rank_index or (rank_index == "nil") then return "" end
    if not guild_rank
        or (not guild_index)
        or (not guild_rank[guild_index][rank_index]) then
        return tostring(rank_index)
    end
    return tostring(rank_index).." "..tostring(guild_rank[guild_index][rank_index])
end

local function user_note(user_note, guild_index)
  if not (user_note and user_note[guild_index]) then return nil end
  return user_note[guild_index]
end

function WriteGuild(args)
    OUT_FILE:write( "# guild"
                     .. ",range_begin"
                     .. ",range_end"
                     .. ",user_id"
                     .. ",sold"
                     .. ",bought"
                     .. ",is_member"
                     .. ",is_newbie"
                     .. ",rank"
                     .. ",joined"
                     .. ",sale_ct"
                     .. ",first_sale_time"
                     .. ",first_sale_buyer"
                     .. ",first_sale_amount"
                     .. ",last_sale_time"
                     .. ",last_sale_buyer"
                     .. ",last_sale_amount"
                     .. ",note"
                     .. "\n" )
    if ALSO_TAB then
        print( "# guild"
                .. "\trange_begin"
                .. "\trange_end"
                .. "\tuser_id"
                .. "\tsold"
                .. "\tbought"
                .. "\tis_member"
                .. "\tis_newbie"
                .. "\trank"
                .. "\tjoined"
                .. "\tsale_ct"
                .. "\tfirst_sale_time"
                .. "\tfirst_sale_buyer"
                .. "\tfirst_sale_amount"
                .. "\tlast_sale_time"
                .. "\tlast_sale_buyer"
                .. "\tlast_sale_amount"
                .. "\tnote"
                 )
    end

    local records = {}

                        -- Extract flat rows for this guild's records
    for _, str in ipairs(args.user_records) do
        local w = split(str, "\t")
        local user_id = w[1]
        local guild_str = w[1 + args.guild_index]
        if guild_str and guild_str ~= "" then
            ww = split(guild_str, " ")
            local is_member         = ww[1] == "true"
            local rank_index        = tonumber       (ww[ 2])
            local bought            = tonumber       (ww[ 3])
            local sold              = tonumber       (ww[ 4])
            local joined_ts         = tonumber       (ww[ 5])
            local sale_ct           = tonumber       (ww[ 6])
            local first_sale_time   = tonumber       (ww[ 7])
            local first_sale_buyer  = tostring_or_nil(ww[ 8])
            local first_sale_amount = tonumber       (ww[ 9])
            local last_sale_time    = tonumber       (ww[10])
            local last_sale_buyer   = tostring_or_nil(ww[11])
            local last_sale_amount  = tonumber       (ww[12])
            local note              = user_note( args.user_notes[user_id]
                                               , args.guild_index )
            if joined_ts == 0
                    and args.roster
                    and args.roster[user_id]
                    and args.roster[user_id].first_seen_ts then
                joined_ts =  args.roster[user_id].first_seen_ts
            end
            local row = { user_id           = user_id
                        , is_member         = is_member
                        , is_newbie         = (NEWBIE_TS <= joined_ts) or (0 == joined_ts)
                        , rank_index        = rank_index
                        , bought            = bought
                        , sold              = sold
                        , joined_ts         = joined_ts
                        , sale_ct           = sale_ct
                        , first_sale_time   = first_sale_time
                        , first_sale_buyer  = first_sale_buyer
                        , first_sale_amount = first_sale_amount
                        , last_sale_time    = last_sale_time
                        , last_sale_buyer   = last_sale_buyer
                        , last_sale_amount  = last_sale_amount
                        , note              = note
                        }

                        -- Ignore any row that satisfies membership criteria
            if PassesReportFilter(row) then
                table.insert(records, row)
            end
        end
    end

                        -- Sort by sold amount, descending.
    table.sort(records, RecordCompare)

                        -- Dump to CSV
    for _,row in ipairs(records) do
        WriteLine({ guild_name        = args.guild_name
                  , guild_index       = args.guild_index
                  , guild_rank        = args.guild_rank
                  , saved_begin_ts    = args.saved_begin_ts
                  , saved_end_ts      = args.saved_end_ts
                  , user_id           = row.user_id
                  , is_member         = row.is_member
                  , is_newbie         = row.is_newbie
                  , rank_index        = row.rank_index
                  , bought            = row.bought
                  , sold              = row.sold
                  , joined_ts         = row.joined_ts
                  , sale_ct           = row.sale_ct
                  , first_sale_time   = row.first_sale_time
                  , first_sale_buyer  = row.first_sale_buyer
                  , first_sale_amount = row.first_sale_amount
                  , last_sale_time    = row.last_sale_time
                  , last_sale_buyer   = row.last_sale_buyer
                  , last_sale_amount  = row.last_sale_amount
                  , note              = row.note
                  })
    end
end

-- Return table keys, sorted, as an array
function sorted_keys(tabl)
    keys = {}
    for k in pairs(tabl) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

function enquote(s)
    return '"' .. s .. '"'
end

-- Convert "1456709816" to "2016-02-28T17:36:56" ISO 8601 formatted time
-- Assume "local machine time" and ignore any incorrect offsets due to
-- Daylight Saving Time transitions. Ugh.
local function iso_date(secs_since_1970)
    if not secs_since_1970 then return 0 end
    if secs_since_1970 == 0 then return 0 end
    t = os.date("*t", secs_since_1970)
    return string.format("%04d-%02d-%02dT%02d:%02d:%02d"
                        , t.year
                        , t.month
                        , t.day
                        , t.hour
                        , t.min
                        , t.sec
                        )
end

local function enquote_or_nil(s)
    if s == nil then return "" end
    return enquote(s)
end

local function nil_blank(s)
    if s == nil then
        return ""
    else
        return s
    end
end

function tsv_strip(text)
  if not text then return "" end
  local t = text:gsub("\t"," ")
  t = t:gsub("\r"," ")
  t = t:gsub("\n"," ")
  return t
end

function WriteLine(args)
    OUT_FILE:write( enquote(        args.guild_name         )
          .. ',' .. iso_date(       args.saved_begin_ts     )
          .. ',' .. iso_date(       args.saved_end_ts       )
          .. ',' .. enquote(        args.user_id            )
          .. ',' ..                 args.sold
          .. ',' ..                 args.bought
          .. ',' .. tostring(       args.is_member          )
          .. ',' .. tostring(       args.is_newbie          )
          .. ',' .. enquote(torank_string( args.guild_rank
                                         , args.guild_index
                                         , args.rank_index
                                         ))
          .. ',' .. iso_date(       args.joined_ts          )
          .. ',' .. nil_blank(      args.sale_ct       )
          .. ',' .. iso_date(       args.first_sale_time    )
          .. ',' .. enquote_or_nil( args.first_sale_buyer   )
          .. ',' .. nil_blank(      args.first_sale_amount  )
          .. ',' .. iso_date(       args.last_sale_time     )
          .. ',' .. enquote_or_nil( args.last_sale_buyer    )
          .. ',' .. nil_blank(      args.last_sale_amount   )
          .. ',' .. enquote_or_nil( args.note               )
          .. '\n'
          )

    if ALSO_TAB then
        print(                      args.guild_name
              .. '\t' .. iso_date(  args.saved_begin_ts    )
              .. '\t' .. iso_date(  args.saved_end_ts      )
              .. '\t' ..            args.user_id
              .. '\t' ..            args.sold
              .. '\t' ..            args.bought
              .. '\t' .. tostring(  args.is_member         )
              .. '\t' .. tostring(  args.is_newbie         )
              .. '\t' .. torank_string( args.guild_rank
                                      , args.guild_index
                                      , args.rank_index
                                      )
              .. '\t' .. iso_date(  args.joined_ts         )
              .. '\t' .. nil_blank( args.sale_ct           )
              .. '\t' .. iso_date(  args.first_sale_time   )
              .. '\t' .. nil_blank( args.first_sale_buyer  )
              .. '\t' .. nil_blank( args.first_sale_amount )
              .. '\t' .. iso_date(  args.last_sale_time    )
              .. '\t' .. nil_blank( args.last_sale_buyer   )
              .. '\t' .. nil_blank( args.last_sale_amount  )
              .. '\t' .. tsv_strip( args.note              )
              )
      end
end



-- For each account
for k, v in pairs(GuildSalesQuotaVars["Default"]) do
    if k == "@ziggr" or k == "@UlfricStormcloak" then
        if (    GuildSalesQuotaVars["Default"][k]["$AccountWide"]
            and GuildSalesQuotaVars["Default"][k]["$AccountWide"]["user_records"]) then
            local acc_w = GuildSalesQuotaVars["Default"][k]["$AccountWide"]
            enable_guild   = acc_w["enable_guild"]
            guild_name     = acc_w["guild_name"  ]
            guild_rank     = acc_w["guild_rank"  ]
            user_records   = acc_w["user_records"]
            user_notes     = acc_w["user_notes"  ]
            saved_begin_ts = acc_w["saved_begin_ts"]
            saved_end_ts   = acc_w["saved_end_ts"]
            for guild_index, enabled in ipairs(enable_guild) do
                roster         = acc_w["roster"][guild_index]
                if enabled and guild_name and guild_name[guild_index] then
                    WriteGuild({ guild_name     = guild_name[guild_index]
                               , guild_rank     = guild_rank
                               , saved_begin_ts = saved_begin_ts
                               , saved_end_ts   = saved_end_ts
                               , guild_index    = guild_index
                               , user_records   = user_records
                               , user_notes     = user_notes
                               , roster         = roster
                               })
                elseif enabled then
                    print("Enabled guild_index:"..tostring(guild_index)
                        .." but guild_name missing an entry" )
                end
            end
        end
    end
end
OUT_FILE:close()

