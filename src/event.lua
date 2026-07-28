local M = {}

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cleanString(value, fieldName, maxBytes)
    if type(value) ~= "string" then
        return nil, fieldName .. " must be text"
    end

    local cleaned = trim(value)
    if #cleaned > maxBytes then
        return nil, fieldName .. " is too long"
    end

    return cleaned
end

local function parseDate(value)
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then
        return nil, "must use YYYY-MM-DD"
    end

    local parts = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
        min = 0,
        sec = 0,
    }
    -- Some Lua implementations mutate the table passed to os.time while normalizing it.
    local timestamp = os.time({
        year = parts.year,
        month = parts.month,
        day = parts.day,
        hour = parts.hour,
        min = parts.min,
        sec = parts.sec,
    })
    local roundTrip = os.date("*t", timestamp)

    if roundTrip.year ~= parts.year or roundTrip.month ~= parts.month or roundTrip.day ~= parts.day then
        return nil, "is not a real calendar date"
    end

    return parts, string.format("%04d-%02d-%02d", parts.year, parts.month, parts.day), timestamp
end

local function parseDateTime(value)
    local year, month, day, hour, minute, second =
        value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)$")

    if not year then
        year, month, day, hour, minute =
            value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)$")
        second = "00"
    end

    if not year then
        return nil, "must use YYYY-MM-DDTHH:MM"
    end

    local parts = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second),
    }
    local timestamp = os.time({
        year = parts.year,
        month = parts.month,
        day = parts.day,
        hour = parts.hour,
        min = parts.min,
        sec = parts.sec,
    })
    local roundTrip = os.date("*t", timestamp)

    for _, key in ipairs({ "year", "month", "day", "hour", "min", "sec" }) do
        if roundTrip[key] ~= parts[key] then
            return nil, "is not a real local date and time"
        end
    end

    local normalized = string.format(
        "%04d-%02d-%02dT%02d:%02d:%02d",
        parts.year,
        parts.month,
        parts.day,
        parts.hour,
        parts.min,
        parts.sec
    )

    return parts, normalized, timestamp
end

function M.validate(event)
    if type(event) ~= "table" then
        return nil, "event must be an object"
    end

    local normalized = {}
    local err

    normalized.title, err = cleanString(event.title, "title", 200)
    if not normalized.title or normalized.title == "" then
        return nil, err or "title must not be empty"
    end

    if type(event.all_day) ~= "boolean" then
        return nil, "all_day must be true or false"
    end
    normalized.all_day = event.all_day

    local parser = normalized.all_day and parseDate or parseDateTime
    local startParts, startValue, startTimestamp = parser(event.start)
    if not startParts then
        return nil, "start " .. startValue
    end

    local endParts, endValue, endTimestamp = parser(event["end"])
    if not endParts then
        return nil, "end " .. endValue
    end

    if endTimestamp <= startTimestamp then
        return nil, "end must be after start"
    end

    normalized.start = startValue
    normalized["end"] = endValue
    normalized.start_parts = startParts
    normalized.end_parts = endParts

    normalized.location, err = cleanString(event.location, "location", 500)
    if not normalized.location then
        return nil, err
    end

    normalized.notes, err = cleanString(event.notes, "notes", 10000)
    if not normalized.notes then
        return nil, err
    end

    normalized.calendar, err = cleanString(event.calendar, "calendar", 200)
    if not normalized.calendar then
        return nil, err
    end

    return normalized
end

return M
