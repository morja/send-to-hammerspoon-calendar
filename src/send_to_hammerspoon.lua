local source = debug.getinfo(1, "S").source:sub(2)
local moduleDirectory = source:match("(.*/)") or "./"
package.path = moduleDirectory .. "?.lua;" .. package.path

local Event = require("event")

local M = {}
local state = {
    config = nil,
    server = nil,
    hotkey = nil,
    preview = nil,
    controller = nil,
    busy = false,
    calendarBusy = false,
    tasks = {},
    nativeServiceCallback = nil,
    previousNativeServiceCallback = nil,
}

local defaults = {
    port = 17391,
    endpoint = "/event",
    maxTextBytes = 50000,
    openRouterModel = "openai/gpt-4o-mini",
    defaultCalendar = "",
    nativeService = {
        enabled = true,
    },
    hotkey = {
        enabled = true,
        modifiers = { "cmd", "alt", "ctrl" },
        key = "E",
    },
}

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, item in pairs(value) do
        result[key] = copyTable(item)
    end
    return result
end

local function merge(base, overrides)
    local result = copyTable(base)
    for key, value in pairs(overrides or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = merge(result[key], value)
        else
            result[key] = value
        end
    end
    return result
end

local function readFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local contents = file:read("*a")
    file:close()
    return contents
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseServiceConfig(path)
    local values = {}
    local contents = readFile(path)
    if not contents then
        return values
    end

    for line in contents:gmatch("[^\r\n]+") do
        local key, value = line:match("^([A-Z_]+)=([A-Za-z0-9._-]+)$")
        if key then
            values[key] = value
        end
    end

    return values
end

local function secureEquals(left, right)
    if type(left) ~= "string" or type(right) ~= "string" then
        return false
    end

    local different = #left == #right and 0 or 1
    local longest = math.max(#left, #right)
    for index = 1, longest do
        if left:byte(index) ~= right:byte(index) then
            different = different + 1
        end
    end

    return different == 0
end

local function headerValue(headers, wantedName)
    for name, value in pairs(headers or {}) do
        if name:lower() == wantedName:lower() then
            return value
        end
    end
    return nil
end

local function showError(message)
    hs.alert.show("Send to Hammerspoon: " .. tostring(message), 5)
end

local function jsonForScript(value)
    local valueToEncode = value
    local unwrapFirstItem = false

    -- Hammerspoon's hs.json.encode accepts tables only, even though JavaScript messages
    -- also need scalar strings. Encode scalars inside an array and unwrap them in JS.
    if type(value) ~= "table" then
        valueToEncode = { value }
        unwrapFirstItem = true
    end

    -- Prevent untrusted strings from ending the inline script element.
    local encoded = hs.json.encode(valueToEncode):gsub("<", "\\u003c")
    if unwrapFirstItem then
        return "(" .. encoded .. ")[0]"
    end

    return encoded
end

local function setPreviewError(message)
    if not state.preview then
        showError(message)
        return
    end

    local script = "window.showError(" .. jsonForScript(tostring(message)) .. ");"
    state.preview:evaluateJavaScript(script)
end

local function userFacingValidationError(message)
    return message
        :gsub("YYYY%-MM%-DDTHH:MM", "TT.MM.JJJJ HH:MM")
        :gsub("YYYY%-MM%-DD", "TT.MM.JJJJ")
end

local function closePreview()
    if state.preview then
        state.preview:delete()
        state.preview = nil
        state.controller = nil
    end
end

local function calendarArguments(event)
    local start = event.start_parts
    local finish = event.end_parts

    return {
        event.title,
        tostring(start.year),
        tostring(start.month),
        tostring(start.day),
        tostring(start.hour or 0),
        tostring(start.min or 0),
        tostring(start.sec or 0),
        tostring(finish.year),
        tostring(finish.month),
        tostring(finish.day),
        tostring(finish.hour or 0),
        tostring(finish.min or 0),
        tostring(finish.sec or 0),
        event.all_day and "true" or "false",
        event.calendar,
        event.location,
        event.notes,
    }
end

local function createCalendarEvent(rawEvent)
    if state.calendarBusy then
        setPreviewError("Calendar creation is already in progress")
        return
    end

    local event, validationError = Event.validate(rawEvent)
    if not event then
        setPreviewError(userFacingValidationError(validationError))
        return
    end

    local scriptPath = moduleDirectory .. "create_calendar_event.js"
    if not hs.fs.attributes(scriptPath) then
        setPreviewError("Calendar helper is missing: " .. scriptPath)
        return
    end

    local task
    state.calendarBusy = true
    task = hs.task.new("/usr/bin/osascript", function(exitCode, stdout, stderr)
        state.tasks[task] = nil
        state.calendarBusy = false

        stdout = stdout or ""
        stderr = stderr or ""

        if exitCode == 0 then
            closePreview()
            hs.alert.show(trim(stdout) ~= "" and trim(stdout) or "Calendar event created", 3)
        else
            setPreviewError(trim(stderr) ~= "" and trim(stderr) or "Calendar rejected the event")
        end
    end, { "-l", "JavaScript", scriptPath, table.unpack(calendarArguments(event)) })

    if not task then
        state.calendarBusy = false
        setPreviewError("Could not start the Calendar helper")
        return
    end

    state.tasks[task] = true
    if not task:start() then
        state.tasks[task] = nil
        state.calendarBusy = false
        setPreviewError("Could not start the Calendar helper")
    end
end

local previewTemplate = [=[
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
    :root { color-scheme: light dark; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
    body { margin: 0; padding: 22px; background: Canvas; color: CanvasText; }
    h1 { font-size: 21px; margin: 0 0 18px; }
    form { display: grid; gap: 13px; }
    label { display: grid; gap: 5px; font-weight: 600; }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
    .date-time-group { display: grid; gap: 9px; }
    [hidden] { display: none !important; }
    input, textarea { box-sizing: border-box; width: 100%; padding: 8px 9px; border: 1px solid GrayText; border-radius: 7px; background: Field; color: FieldText; font: inherit; }
    textarea { min-height: 90px; resize: vertical; }
    .check { display: flex; align-items: center; gap: 8px; }
    .check input { width: auto; }
    .actions { display: flex; justify-content: flex-end; gap: 9px; margin-top: 5px; }
    button { padding: 8px 15px; border-radius: 7px; border: 1px solid GrayText; font: inherit; }
    button.primary { background: #1473e6; border-color: #1473e6; color: white; font-weight: 600; }
    #error { display: none; padding: 9px; border-radius: 7px; background: rgba(220, 40, 40, .14); color: #d33; }
    .hint { color: GrayText; font-size: 12px; font-weight: 400; }
</style>
</head>
<body>
<h1>Confirm Calendar Event</h1>
<form id="event-form">
    <div id="error"></div>
    <label>Title <input id="title" required maxlength="200"></label>
    <div class="row">
        <div class="date-time-group">
            <label>Start date <input id="start-date" type="text" inputmode="numeric" pattern="[0-9]{2}[.][0-9]{2}[.][0-9]{4}" placeholder="TT.MM.JJJJ" title="Use TT.MM.JJJJ" maxlength="10" required></label>
            <label id="start-time-label">Start time (24-hour)
                <input id="start-time" type="text" inputmode="numeric" pattern="([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?" placeholder="HH:MM" title="Use 24-hour time, HH:MM or HH:MM:SS" required>
            </label>
        </div>
        <div class="date-time-group">
            <label>End date <input id="end-date" type="text" inputmode="numeric" pattern="[0-9]{2}[.][0-9]{2}[.][0-9]{4}" placeholder="TT.MM.JJJJ" title="Use TT.MM.JJJJ" maxlength="10" required></label>
            <label id="end-time-label">End time (24-hour)
                <input id="end-time" type="text" inputmode="numeric" pattern="([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?" placeholder="HH:MM" title="Use 24-hour time, HH:MM or HH:MM:SS" required>
            </label>
        </div>
    </div>
    <label class="check"><input id="all-day" type="checkbox"> All-day event</label>
    <span id="all-day-hint" class="hint" hidden>For an event through 20.09.2026, set the end date to 21.09.2026. Calendar uses an exclusive end date for all-day events.</span>
    <label>Calendar <input id="calendar" maxlength="200"><span class="hint">Leave empty to use the first writable calendar.</span></label>
    <label>Location <input id="location" maxlength="500"></label>
    <label>Notes <textarea id="notes" maxlength="10000"></textarea></label>
    <div class="actions">
        <button id="cancel" type="button">Cancel</button>
        <button class="primary" type="submit">Create Event</button>
    </div>
</form>
<script>
const initial = __EVENT_JSON__;
const initialError = __ERROR_JSON__;
const fields = {
    title: document.querySelector('#title'),
    startDate: document.querySelector('#start-date'),
    startTime: document.querySelector('#start-time'),
    endDate: document.querySelector('#end-date'),
    endTime: document.querySelector('#end-time'),
    allDay: document.querySelector('#all-day'),
    calendar: document.querySelector('#calendar'),
    location: document.querySelector('#location'),
    notes: document.querySelector('#notes')
};

function germanDate(isoDate) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate);
    return match ? `${match[3]}.${match[2]}.${match[1]}` : '';
}

function isoDate(germanDate) {
    const match = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(germanDate);
    return match ? `${match[3]}-${match[2]}-${match[1]}` : '';
}

function setDateTime(dateField, timeField, value, defaultTime) {
    const [date, time] = value.split('T');
    dateField.value = germanDate(date);

    // Hide zero seconds, but retain nonzero seconds so editing cannot silently discard them.
    timeField.value = time
        ? (time.endsWith(':00') ? time.slice(0, 5) : time)
        : defaultTime;
}

function setAllDayMode(allDay) {
    document.querySelector('#all-day-hint').hidden = !allDay;

    for (const [field, label] of [
        [fields.startTime, document.querySelector('#start-time-label')],
        [fields.endTime, document.querySelector('#end-time-label')]
    ]) {
        label.hidden = allDay;
        field.disabled = allDay;
        field.required = !allDay;
    }
}

fields.title.value = initial.title;
setDateTime(fields.startDate, fields.startTime, initial.start, '09:00');
setDateTime(fields.endDate, fields.endTime, initial.end, '10:00');
fields.allDay.checked = initial.all_day;
fields.calendar.value = initial.calendar;
fields.location.value = initial.location;
fields.notes.value = initial.notes;
setAllDayMode(initial.all_day);

fields.allDay.addEventListener('change', () => setAllDayMode(fields.allDay.checked));
document.querySelector('#cancel').addEventListener('click', () => {
    webkit.messageHandlers.sendToHammerspoon.postMessage({ action: 'cancel' });
});
document.querySelector('#event-form').addEventListener('submit', event => {
    event.preventDefault();
    document.querySelector('#error').style.display = 'none';
    webkit.messageHandlers.sendToHammerspoon.postMessage({
        action: 'approve',
        event: {
            title: fields.title.value,
            start: isoDate(fields.startDate.value) + (fields.allDay.checked ? '' : 'T' + fields.startTime.value),
            end: isoDate(fields.endDate.value) + (fields.allDay.checked ? '' : 'T' + fields.endTime.value),
            all_day: fields.allDay.checked,
            calendar: fields.calendar.value,
            location: fields.location.value,
            notes: fields.notes.value
        }
    });
});

window.showError = message => {
    const error = document.querySelector('#error');
    error.textContent = message;
    error.style.display = 'block';
};
if (initialError) {
    window.showError(initialError);
}
</script>
</body>
</html>
]=]

local function showPreview(event, initialError)
    closePreview()

    local screen = hs.screen.mainScreen():frame()
    local width, height = 620, math.min(720, screen.h - 80)
    local frame = {
        x = screen.x + (screen.w - width) / 2,
        y = screen.y + (screen.h - height) / 2,
        w = width,
        h = height,
    }

    state.controller = hs.webview.usercontent.new("sendToHammerspoon")
    state.controller:setCallback(function(message)
        local payload = message.body or message
        if type(payload) ~= "table" then
            return
        end

        if payload.action == "cancel" then
            closePreview()
        elseif payload.action == "approve" then
            createCalendarEvent(payload.event)
        end
    end)

    local html = previewTemplate:gsub("__EVENT_JSON__", function()
        return jsonForScript(event)
    end, 1)
    html = html:gsub("__ERROR_JSON__", function()
        return jsonForScript(initialError or "")
    end, 1)
    state.preview = hs.webview.new(frame, { developerExtrasEnabled = false }, state.controller)
        :windowTitle("Send to Hammerspoon")
        :allowTextEntry(true)
        :windowStyle({ "titled", "closable" })
        :deleteOnClose(true)
        :windowCallback(function(action)
            if action == "closing" then
                state.preview = nil
                state.controller = nil
            end
        end)
        :html(html)
        :show()
        :bringToFront(true)

    -- A Service is invoked from another foreground app. Explicitly focus the preview so it
    -- cannot appear behind that app and make a successful extraction look like a no-op.
    local previewWindow = state.preview:hswindow()
    if previewWindow then
        previewWindow:focus()
    end
end

local function dateForCorrection(value, allDay)
    if type(value) ~= "string" then
        return ""
    end

    if allDay then
        return value:match("^%d%d%d%d%-%d%d%-%d%d$") and value or ""
    end

    if value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d$")
        or value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d$") then
        return value
    end

    return ""
end

local function correctionPreviewEvent(extracted)
    local allDay = extracted.all_day == true
    local function stringOrEmpty(value)
        return type(value) == "string" and value or ""
    end

    -- Do not turn an invalid midnight date-time into an all-day date silently.
    -- Leave malformed fields empty so the reviewer must enter a valid date.
    return {
        title = stringOrEmpty(extracted.title),
        start = dateForCorrection(extracted.start, allDay),
        ["end"] = dateForCorrection(extracted["end"], allDay),
        all_day = allDay,
        calendar = stringOrEmpty(extracted.calendar),
        location = stringOrEmpty(extracted.location),
        notes = stringOrEmpty(extracted.notes),
    }
end

local function extractionSchema()
    return {
        type = "object",
        additionalProperties = false,
        properties = {
            title = { type = "string", description = "Short event title" },
            start = { type = "string", description = "Local start as YYYY-MM-DDTHH:MM:SS, or YYYY-MM-DD for all-day" },
            ["end"] = { type = "string", description = "Local end; all-day end is exclusive" },
            all_day = { type = "boolean" },
            calendar = { type = "string", description = "Suggested Calendar name, or empty string" },
            location = { type = "string", description = "Location, or empty string" },
            notes = { type = "string", description = "Useful source details, or empty string" },
        },
        required = { "title", "start", "end", "all_day", "calendar", "location", "notes" },
    }
end

local function extractEvent(text)
    local apiKey = readFile(state.config.openRouterKeyFile)
    if not apiKey or trim(apiKey) == "" then
        state.busy = false
        showError("OpenRouter API key is missing. See README configuration instructions.")
        return false
    end

    local systemPrompt = table.concat({
        "Extract exactly one calendar event from the supplied text.",
        "Understand German and English event descriptions, including relative dates and times.",
        "Keep the title, location, and notes in the language used by the supplied text.",
        "Current local date and time: " .. os.date("%Y-%m-%dT%H:%M:%S%z") .. ".",
        "Resolve relative dates from that value. Do not invent missing details.",
        "For timed events use local YYYY-MM-DDTHH:MM:SS values with 24-hour time, never AM/PM.",
        "For all-day events use YYYY-MM-DD dates and make end the exclusive following date.",
        "A range with dates but no times is all-day; never use midnight date-times for it.",
        "For an inclusive date range, set the exclusive end to the day after the last stated date.",
        "If the year is omitted, use the next occurrence of the stated date from the current local date.",
        "If duration is absent, use one hour for timed events and one day for all-day events.",
        "Use the configured calendar suggestion when supplied; otherwise use an empty calendar string.",
    }, " ")

    if state.config.defaultCalendar ~= "" then
        systemPrompt = systemPrompt .. " Configured calendar suggestion: " .. state.config.defaultCalendar .. "."
    end

    local payload = {
        model = state.config.openRouterModel,
        messages = {
            { role = "system", content = systemPrompt },
            { role = "user", content = text },
        },
        response_format = {
            type = "json_schema",
            json_schema = {
                name = "calendar_event",
                strict = true,
                schema = extractionSchema(),
            },
        },
        provider = { require_parameters = true },
        temperature = 0,
    }

    hs.http.asyncPost(
        "https://openrouter.ai/api/v1/chat/completions",
        hs.json.encode(payload),
        {
            ["Authorization"] = "Bearer " .. trim(apiKey),
            ["Content-Type"] = "application/json",
            ["X-Title"] = "Send to Hammerspoon Calendar",
        },
        function(status, body)
            state.busy = false

            local response = hs.json.decode(body or "")
            if status ~= 200 then
                local detail = response and response.error and response.error.message
                showError(detail or ("OpenRouter request failed with HTTP " .. tostring(status)))
                return
            end

            local content = response
                and response.choices
                and response.choices[1]
                and response.choices[1].message
                and response.choices[1].message.content
            local extracted = type(content) == "string" and hs.json.decode(content) or nil
            if not extracted then
                showError("OpenRouter returned an invalid structured response")
                return
            end

            local event, validationError = Event.validate(extracted)
            if not event then
                if validationError:match("^start ") or validationError:match("^end ") then
                    showPreview(
                        correctionPreviewEvent(extracted),
                        "OpenRouter returned an invalid date (" .. userFacingValidationError(validationError) .. "). Enter or correct the dates before creating the event."
                    )
                    return
                end

                showError("Extracted event is invalid: " .. validationError)
                return
            end

            -- Internal date parts are intentionally omitted from the editable view.
            showPreview({
                title = event.title,
                start = event.start,
                ["end"] = event["end"],
                all_day = event.all_day,
                calendar = event.calendar,
                location = event.location,
                notes = event.notes,
            })
        end
    )

    return true
end

function M.processText(text)
    if state.busy then
        showError("An extraction is already in progress")
        return false, "busy"
    end

    if type(text) ~= "string" or trim(text) == "" then
        showError("No text was supplied")
        return false, "empty text"
    end

    if #text > state.config.maxTextBytes then
        showError("Selected text exceeds the configured size limit")
        return false, "text too large"
    end

    state.busy = true
    hs.alert.show("Extracting calendar event…", 1.5)
    if not extractEvent(text) then
        return false, "configuration error"
    end
    return true
end

function M.processClipboard()
    return M.processText(hs.pasteboard.getContents())
end

local function startServer()
    state.server = hs.httpserver.new(false, false)
        :setInterface("localhost")
        :setPort(state.config.port)
        :maxBodySize(state.config.maxTextBytes)
        :setCallback(function(method, path, headers, body)
            if method ~= "POST" or path ~= state.config.endpoint then
                return "Not found\n", 404, { ["Content-Type"] = "text/plain" }
            end

            local suppliedToken = headerValue(headers, "X-Send-To-Hammerspoon-Token")
            if not secureEquals(suppliedToken, state.config.serviceToken) then
                return "Unauthorized\n", 401, { ["Content-Type"] = "text/plain" }
            end

            local accepted, reason = M.processText(body)
            if not accepted then
                return reason .. "\n", 409, { ["Content-Type"] = "text/plain" }
            end

            return "Accepted\n", 202, { ["Content-Type"] = "text/plain" }
        end)

    if not state.server:start() then
        state.server = nil
        return false
    end

    return true
end

function M.start(userConfig)
    M.stop()

    local home = os.getenv("HOME")
    state.config = merge(defaults, userConfig)
    state.config.serviceConfigFile = state.config.serviceConfigFile
        or (home .. "/.config/send-to-hammerspoon/service.conf")
    state.config.openRouterKeyFile = state.config.openRouterKeyFile
        or (home .. "/.config/send-to-hammerspoon/openrouter-api-key")

    local serviceConfig = parseServiceConfig(state.config.serviceConfigFile)
    state.config.port = tonumber(serviceConfig.PORT) or state.config.port
    state.config.serviceToken = serviceConfig.TOKEN

    if type(state.config.port) ~= "number"
        or state.config.port % 1 ~= 0
        or state.config.port < 1024
        or state.config.port > 65535 then
        showError("Service port must be an integer between 1024 and 65535")
        return false
    end

    if type(state.config.maxTextBytes) ~= "number"
        or state.config.maxTextBytes < 1
        or state.config.maxTextBytes > 1048576 then
        showError("maxTextBytes must be between 1 and 1048576")
        return false
    end

    if not state.config.serviceToken or #state.config.serviceToken < 32 then
        showError("Service token is missing or too short; run the installer")
        return false
    end

    if not startServer() then
        showError("Could not start the localhost receiver; the port may already be in use")
        return false
    end

    if state.config.nativeService.enabled then
        state.previousNativeServiceCallback = hs.textDroppedToDockIconCallback
        state.nativeServiceCallback = function(text)
            M.processText(text)
        end
        hs.textDroppedToDockIconCallback = state.nativeServiceCallback
    end

    if state.config.hotkey.enabled then
        state.hotkey = hs.hotkey.bind(
            state.config.hotkey.modifiers,
            state.config.hotkey.key,
            M.processClipboard
        )
    end

    hs.printf("Send to Hammerspoon listening on localhost:%d%s", state.config.port, state.config.endpoint)
    return true
end

function M.stop()
    if state.nativeServiceCallback
        and hs.textDroppedToDockIconCallback == state.nativeServiceCallback then
        hs.textDroppedToDockIconCallback = state.previousNativeServiceCallback
    end
    state.nativeServiceCallback = nil
    state.previousNativeServiceCallback = nil

    if state.hotkey then
        state.hotkey:delete()
        state.hotkey = nil
    end

    if state.server then
        state.server:stop()
        state.server = nil
    end

    closePreview()
    state.busy = false
end

return M
