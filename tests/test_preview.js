const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const luaSource = fs.readFileSync("src/send_to_hammerspoon.lua", "utf8");
const template = luaSource.match(/local previewTemplate = \[=\[([\s\S]*?)\]=\]/)?.[1];
assert.ok(template, "preview HTML template exists");

assert.ok(!template.includes("datetime-local"), "preview does not use a locale-dependent time picker");
assert.ok(!template.includes('type="date"'), "preview does not use locale-dependent date pickers");

for (const id of ["start-date", "end-date"]) {
    const pattern = template.match(new RegExp(`id="${id}"[^>]*pattern="([^"]+)"`))?.[1];
    assert.ok(pattern, `${id} has a German date input pattern`);

    const validDate = new RegExp(`^(?:${pattern})$`);
    assert.ok(validDate.test("26.09.2026"));
    assert.ok(!validDate.test("09/26/2026"));
}

for (const id of ["start-time", "end-time"]) {
    const pattern = template.match(new RegExp(`id="${id}"[^>]*pattern="([^"]+)"`))?.[1];
    assert.ok(pattern, `${id} has an explicit 24-hour input pattern`);

    const validTime = new RegExp(`^(?:${pattern})$`);
    assert.ok(validTime.test("00:00"));
    assert.ok(validTime.test("23:59:59"));
    assert.ok(!validTime.test("24:00"));
    assert.ok(!validTime.test("9:30 PM"));
}

function loadPreview(initial, initialError = "") {
    const elements = new Map();
    const messages = [];

    function element(selector) {
        if (!elements.has(selector)) {
            elements.set(selector, {
                value: "",
                checked: false,
                hidden: false,
                disabled: false,
                required: false,
                style: {},
                listeners: {},
                addEventListener(name, listener) {
                    this.listeners[name] = listener;
                },
            });
        }
        return elements.get(selector);
    }

    const html = template
        .replace("__EVENT_JSON__", JSON.stringify(initial))
        .replace("__ERROR_JSON__", JSON.stringify(initialError));
    const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
    assert.ok(script, "preview script exists");

    vm.runInNewContext(script, {
        document: { querySelector: element },
        window: {},
        webkit: {
            messageHandlers: {
                sendToHammerspoon: { postMessage: message => messages.push(message) },
            },
        },
    });

    function submit() {
        element("#event-form").listeners.submit({ preventDefault() {} });
        return messages.at(-1).event;
    }

    return { element, submit };
}

const timed = loadPreview({
    title: "Late call",
    start: "2030-04-12T09:30:00",
    end: "2030-04-12T23:15:45",
    all_day: false,
    calendar: "Work",
    location: "",
    notes: "",
});

assert.equal(timed.element("#start-time").value, "09:30");
assert.equal(timed.element("#end-time").value, "23:15:45");
assert.equal(timed.element("#start-date").value, "12.04.2030");
assert.equal(timed.element("#end-date").value, "12.04.2030");
assert.equal(timed.element("#start-time-label").hidden, false);
assert.equal(timed.element("#all-day-hint").hidden, true);
const timedEvent = timed.submit();
assert.equal(timedEvent.start, "2030-04-12T09:30");
assert.equal(timedEvent.end, "2030-04-12T23:15:45");
assert.equal(timedEvent.title, "Late call");
assert.equal(timedEvent.calendar, "Work");
assert.equal(timedEvent.all_day, false);

timed.element("#start-time").value = "00:15";
assert.equal(timed.submit().start, "2030-04-12T00:15");
timed.element("#start-date").value = "26.09.2026";
assert.equal(timed.submit().start, "2026-09-26T00:15");

const allDay = loadPreview({
    title: "Conference",
    start: "2030-04-12",
    end: "2030-04-14",
    all_day: true,
    calendar: "",
    location: "",
    notes: "",
});

assert.equal(allDay.element("#start-time-label").hidden, true);
assert.equal(allDay.element("#start-date").value, "12.04.2030");
assert.equal(allDay.element("#end-date").value, "14.04.2030");
assert.equal(allDay.element("#all-day-hint").hidden, false);
assert.equal(allDay.element("#start-time").disabled, true);
assert.equal(allDay.element("#start-time").required, false);
assert.equal(allDay.submit().start, "2030-04-12");
assert.equal(allDay.submit().end, "2030-04-14");

allDay.element("#all-day").checked = false;
allDay.element("#all-day").listeners.change();
assert.equal(allDay.element("#start-time").value, "09:00");
assert.equal(allDay.element("#end-time").value, "10:00");
assert.equal(allDay.element("#start-time").required, true);
assert.equal(allDay.element("#all-day-hint").hidden, true);
assert.equal(allDay.submit().start, "2030-04-12T09:00");

const correction = loadPreview({
    title: "Jahrestreffen",
    start: "",
    end: "",
    all_day: true,
    calendar: "",
    location: "",
    notes: "",
}, "start must use YYYY-MM-DD");
assert.equal(correction.element("#start-date").value, "");
assert.equal(correction.element("#error").style.display, "block");
assert.equal(correction.element("#error").textContent, "start must use YYYY-MM-DD");

console.log("ok - preview uses German dates and 24-hour time");
