function run(arguments) {
    if (arguments.length !== 17) {
        throw new Error("Expected 17 event arguments");
    }

    function numberAt(index) {
        const value = Number(arguments[index]);
        if (!Number.isInteger(value)) {
            throw new Error("Invalid numeric date component");
        }
        return value;
    }

    function localDateAt(offset) {
        return new Date(
            numberAt(offset),
            numberAt(offset + 1) - 1,
            numberAt(offset + 2),
            numberAt(offset + 3),
            numberAt(offset + 4),
            numberAt(offset + 5)
        );
    }

    const eventTitle = arguments[0];
    const startDate = localDateAt(1);
    const endDate = localDateAt(7);
    const isAllDay = arguments[13] === "true";
    const requestedCalendar = arguments[14];
    const eventLocation = arguments[15];
    const eventNotes = arguments[16];

    const Calendar = Application("Calendar");
    const calendars = requestedCalendar
        ? Calendar.calendars.whose({ name: requestedCalendar })()
        : Calendar.calendars().filter(calendar => calendar.writable());

    if (calendars.length === 0) {
        throw new Error(requestedCalendar
            ? `Calendar not found: ${requestedCalendar}`
            : "No writable Calendar is available");
    }

    const targetCalendar = calendars[0];
    if (!targetCalendar.writable()) {
        throw new Error(`Calendar is read-only: ${requestedCalendar}`);
    }

    const event = Calendar.Event({
        summary: eventTitle,
        startDate,
        endDate,
        alldayEvent: isAllDay,
        location: eventLocation,
        description: eventNotes,
    });
    targetCalendar.events.push(event);

    return "Calendar event created";
}
