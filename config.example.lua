return {
    -- Must support OpenRouter structured outputs.
    openRouterModel = "openai/gpt-4o-mini",

    -- Use an exact Calendar name, or leave empty to choose the first writable calendar.
    defaultCalendar = "",

    -- Handle text sent through Hammerspoon's built-in macOS Service.
    nativeService = {
        enabled = true,
    },

    -- This global shortcut processes the current clipboard text.
    hotkey = {
        enabled = true,
        modifiers = { "cmd", "alt", "ctrl" },
        key = "E",
    },

    -- Selected or clipboard text larger than this is rejected before upload.
    maxTextBytes = 50000,
}
