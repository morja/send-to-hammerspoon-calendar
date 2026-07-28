const fs = require("node:fs");
const vm = require("node:vm");

let createdEvent = null;
const writableCalendar = {
    writable: () => true,
    events: {
        push: event => {
            createdEvent = event;
        },
    },
};

const calendars = () => [writableCalendar];
calendars.whose = () => () => [writableCalendar];

global.Application = name => {
    if (name !== "Calendar") {
        throw new Error("Unexpected application: " + name);
    }

    return {
        calendars,
        Event: properties => properties,
    };
};

const helperSource = fs.readFileSync("scripts/create_calendar_event.js", "utf8");
vm.runInThisContext(helperSource, { filename: "create_calendar_event.js" });

const result = run([
    "Argument parsing test",
    "2030", "4", "12", "9", "30", "0",
    "2030", "4", "12", "10", "30", "0",
    "false", "", "", "",
]);

if (result !== "Calendar event created") {
    throw new Error("Unexpected helper result: " + result);
}

if (!createdEvent || createdEvent.summary !== "Argument parsing test") {
    throw new Error("Calendar event was not constructed")
}

if (createdEvent.startDate.getFullYear() !== 2030 || createdEvent.startDate.getMinutes() !== 30) {
    throw new Error("Start date arguments were parsed incorrectly")
}

if (createdEvent.endDate.getHours() !== 10 || createdEvent.endDate.getMinutes() !== 30) {
    throw new Error("End date arguments were parsed incorrectly")
}

console.log("ok - Calendar helper parses osascript arguments");
