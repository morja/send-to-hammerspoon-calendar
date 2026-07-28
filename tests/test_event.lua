package.path = "src/?.lua;" .. package.path

local Event = require("event")
local failures = 0

local function check(name, condition)
    if condition then
        print("ok - " .. name)
    else
        failures = failures + 1
        print("not ok - " .. name)
    end
end

local timed = Event.validate({
    title = " Project review ",
    start = "2030-04-12T09:30",
    ["end"] = "2030-04-12T10:30",
    all_day = false,
    calendar = "Work",
    location = "Room 2",
    notes = "Bring notes",
})
check("valid timed event", timed and timed.title == "Project review")
check("normalizes seconds", timed and timed.start == "2030-04-12T09:30:00")

local allDay = Event.validate({
    title = "Conference",
    start = "2030-04-12",
    ["end"] = "2030-04-14",
    all_day = true,
    calendar = "",
    location = "",
    notes = "",
})
check("valid all-day event", allDay and allDay.end_parts.day == 14)

local _, reversedError = Event.validate({
    title = "Backwards",
    start = "2030-04-12T10:30",
    ["end"] = "2030-04-12T09:30",
    all_day = false,
    calendar = "",
    location = "",
    notes = "",
})
check("rejects reversed range", reversedError == "end must be after start")

local _, impossibleError = Event.validate({
    title = "Impossible",
    start = "2030-02-30",
    ["end"] = "2030-03-02",
    all_day = true,
    calendar = "",
    location = "",
    notes = "",
})
check("rejects impossible date", impossibleError == "start is not a real calendar date")

local _, missingError = Event.validate({})
check("rejects missing fields", missingError == "title must be text")

os.exit(failures == 0 and 0 or 1)
