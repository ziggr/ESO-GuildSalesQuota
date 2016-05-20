-- Read the SavedVariables file that GuildSalesQuota creates  and convert
-- that to a spreadsheet-compabitle CSV (comma-separated value) file.

IN_FILE_PATH  = "../../SavedVariables/GuildSalesQuota.lua"
OUT_FILE_PATH = "../../SavedVariables/GuildSalesQuota.csv"
dofile(IN_FILE_PATH)
OUT_FILE = assert(io.open(OUT_FILE_PATH, "w"))

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

function WriteGuild(guild_name, guild_index, user_records)
    OUT_FILE:write( "# guild"
                     .. ",user_id"
                     .. ",sold"
                     .. ",bought"
                     .. ",is_member"
                     .. "\n" )

    local records = {}

                        -- Extract flat rows for this guild's records
    for _, str in ipairs(user_records) do
        local w = split(str, "\t")
        local user_id = w[1]
        local guild_str = w[1 + guild_index]
        if guild_str and guild_str ~= "" then
            ww = split(guild_str, " ")
            local is_member = ww[1] == "true"
            local bought    = tonumber(ww[2])
            local sold      = tonumber(ww[3])

            local row = { user_id = user_id
                        , is_member = is_member
                        , bought    = bought
                        , sold      = sold
                        }
            table.insert(records, row)
        end
    end

                        -- Sort by sold amount, descending.
    table.sort(records, RecordCompare)

                        -- Dump to CSV
    for _,row in ipairs(records) do
        WriteLine(guild_name, row.user_id, row.sold, row.bought, row.is_member)
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

function WriteLine(guild_name, user_id, sold, bought, is_member)
    OUT_FILE:write(          enquote(guild_name)
          .. ',' .. enquote(user_id)
          .. ',' .. sold
          .. ',' .. bought
          .. ',' .. tostring(is_member)
          .. '\n'
          )
end


-- For each account
for k, v in pairs(GuildSalesQuotaVars["Default"]) do
    if (    GuildSalesQuotaVars["Default"][k]["$AccountWide"]
        and GuildSalesQuotaVars["Default"][k]["$AccountWide"]["user_records"]) then
        enable_guild = GuildSalesQuotaVars["Default"][k]["$AccountWide"]["enable_guild"]
        guild_name   = GuildSalesQuotaVars["Default"][k]["$AccountWide"]["guild_name"  ]
        user_records = GuildSalesQuotaVars["Default"][k]["$AccountWide"]["user_records"]

        for guild_index, enabled in ipairs(enable_guild) do
            if enabled then
                WriteGuild(guild_name[guild_index], guild_index, user_records)
            end
        end
    end
end
OUT_FILE:close()

