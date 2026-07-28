# Send to Hammerspoon Calendar

A small, open-source macOS integration that turns arbitrary text into a reviewed Calendar event.

Select webpage text and invoke the **Send to Hammerspoon** Service, or copy text from any app and press a configurable global shortcut. Hammerspoon sends the text to OpenRouter for structured extraction, presents an editable local preview, and creates an event only after explicit approval.

The software is free under the MIT License. OpenRouter models may charge for API usage; choose a model and account limits appropriate for you.

## How it works

```text
Selected text → macOS Service ─┐
                              ├→ Hammerspoon → OpenRouter → editable preview → Calendar
Clipboard text → global key ──┘
```

- The Service posts plain text to an HTTP server bound only to `localhost`.
- A random 256-bit token authenticates Service requests.
- The global shortcut reads the current clipboard directly inside Hammerspoon.
- Both entry points use the same size checks, structured extraction, validation, preview, and Calendar creation path.
- Calendar values are passed to a fixed JavaScript for Automation (JXA) helper as separate arguments, not interpolated into shell or script source.
- The API key and Service token live outside both this repository and the installed public scripts.

## Requirements

- macOS with Calendar and Automator/Quick Actions support
- [Hammerspoon](https://www.hammerspoon.org/) installed
- An [OpenRouter](https://openrouter.ai/) API key
- An OpenRouter model that supports structured outputs

## Install

From this repository, run:

```sh
./scripts/install.sh
```

The installer:

1. copies the Lua and JXA files to `~/.hammerspoon/send-to-hammerspoon/`;
2. creates a private Service token in `~/.config/send-to-hammerspoon/service.conf`;
3. creates a private, empty key file at `~/.config/send-to-hammerspoon/openrouter-api-key`;
4. installs the included **Send to Hammerspoon** Quick Action if no Service with that name exists; and
5. adds a small, marked loader block to `~/.hammerspoon/init.lua` if it is not already present.

An existing Service is deliberately left unchanged. To make an existing **Send to Hammerspoon** Service compatible, open it in Automator and configure its **Run Shell Script** action as follows:

- Workflow receives current: `text` in `any application`
- Shell: `/bin/zsh`
- Pass input: `to stdin`
- Script:

```sh
exec "$HOME/.hammerspoon/send-to-hammerspoon/send-to-hammerspoon-service"
```

### Configure the API key

Put only the key value in the private key file. Avoid placing it in `init.lua`, this repository, shell history, or the Service workflow.

An interactive command that does not echo the key is:

```sh
read -s "OPENROUTER_KEY?OpenRouter API key: "
printf '%s\n' "$OPENROUTER_KEY" > "$HOME/.config/send-to-hammerspoon/openrouter-api-key"
unset OPENROUTER_KEY
chmod 600 "$HOME/.config/send-to-hammerspoon/openrouter-api-key"
```

Edit local settings in `~/.hammerspoon/send-to-hammerspoon/config.lua`. For example:

```lua
return {
    openRouterModel = "openai/gpt-4o-mini",
    defaultCalendar = "Work",
    hotkey = {
        enabled = true,
        modifiers = { "cmd", "alt", "ctrl" },
        key = "E",
    },
    maxTextBytes = 50000,
}
```

The default shortcut is <kbd>Control</kbd>+<kbd>Option</kbd>+<kbd>Command</kbd>+<kbd>E</kbd>. Reload the Hammerspoon configuration after editing.

## macOS permissions

macOS asks for permissions when each capability is first used. Review the exact prompts rather than granting broad access in advance.

- **Accessibility:** enable Hammerspoon under **System Settings → Privacy & Security → Accessibility** so its global shortcut works reliably.
- **Automation / Calendar:** allow Hammerspoon (or `osascript` launched by it) to control Calendar under **Privacy & Security → Automation**. The first approved event should trigger this prompt.
- **Service shortcut:** the Service should appear under **System Settings → Keyboard → Keyboard Shortcuts → Services**. Enable it there and optionally assign a separate keyboard shortcut.

Hammerspoon must be running and its configuration loaded for either entry point.

## Usage

### Selected webpage or app text

1. Select text that describes one event.
2. Open the app's context menu or **Services** menu and choose **Send to Hammerspoon**.
3. Review every field in the preview.
4. Choose **Create Event** or cancel.

The Service is app-independent: any macOS app that exposes selected text to Services can use it, not only browsers.

### Clipboard from any app

1. Copy text describing one event.
2. Press the configured global Hammerspoon shortcut.
3. Review and approve or cancel the preview.

The shortcut processes the current clipboard. It does not synthesize a copy keystroke, so it never silently replaces or reads a selection that you did not first copy.

## Privacy and security

Selected or clipboard text is sent to OpenRouter and then to the provider serving the configured model. It may contain names, addresses, meeting links, or other sensitive information. Read the applicable OpenRouter and model-provider data policies before use; do not submit material you are not permitted to share.

The extracted result remains local after the API response and is not written to a project log. Hammerspoon and macOS may still expose diagnostics in their consoles. This project does not implement telemetry.

The local receiver:

- binds to `localhost`, not a LAN interface;
- disables Bonjour advertising;
- accepts only `POST /event`;
- requires the private token; and
- enforces a configurable request-size limit.

Keep `~/.config/send-to-hammerspoon/` readable only by your user. Rotate the token by stopping Hammerspoon, replacing `TOKEN` in `service.conf` with `openssl rand -hex 32`, and reloading Hammerspoon.

## Limitations

- AI extraction can be wrong. The confirmation preview is a required safety boundary, not a guarantee of correctness.
- One invocation creates at most one event. Recurrence, attendees, alerts, attachments, and travel time are not supported initially.
- Times are interpreted in the Mac's current local timezone. Named or remote timezones may need manual correction.
- When no Calendar name is configured or approved, the first writable Calendar returned by macOS is used; configure an exact name for predictable placement.
- Only one OpenRouter extraction runs at a time, and the default input limit is 50 KB.
- A model without structured-output support will fail rather than falling back to unvalidated prose.
- The Service depends on applications correctly exposing selected text to macOS Services.

## Development and validation

Run the local checks on macOS with Lua installed:

```sh
./tests/run.sh
```

The suite exercises event validation and syntax-checks Lua, zsh, the Automator plist, and JXA. End-to-end OpenRouter and Calendar actions are intentionally not automated because they require a private key, network access, explicit macOS consent, and a real Calendar database.

## Uninstall

Quit or stop the integration in Hammerspoon, then remove:

- `~/.hammerspoon/send-to-hammerspoon/`
- `~/Library/Services/Send to Hammerspoon.workflow` if it is the workflow installed by this project
- `~/.config/send-to-hammerspoon/`
- the marked block between `BEGIN send-to-hammerspoon-calendar` and `END send-to-hammerspoon-calendar` in `~/.hammerspoon/init.lua`

Removing `~/.config/send-to-hammerspoon/` deletes the local API key and token permanently.

## License

[MIT](LICENSE)
