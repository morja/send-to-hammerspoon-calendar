#!/bin/zsh

set -eu

script_directory=${0:A:h}
project_directory=${script_directory:h}
install_directory="$HOME/.hammerspoon/send-to-hammerspoon"
config_directory="$HOME/.config/send-to-hammerspoon"
init_file="$HOME/.hammerspoon/init.lua"

mkdir -p "$install_directory" "$config_directory" "$HOME/.hammerspoon"

/usr/bin/install -m 0644 "$project_directory/src/event.lua" "$install_directory/event.lua"
/usr/bin/install -m 0644 "$project_directory/src/send_to_hammerspoon.lua" "$install_directory/send_to_hammerspoon.lua"
/usr/bin/install -m 0644 "$project_directory/scripts/create_calendar_event.js" "$install_directory/create_calendar_event.js"
/usr/bin/install -m 0755 "$project_directory/scripts/send-to-hammerspoon-service" "$install_directory/send-to-hammerspoon-service"

if [[ ! -e "$install_directory/config.lua" ]]; then
    /usr/bin/install -m 0600 "$project_directory/config.example.lua" "$install_directory/config.lua"
fi

service_config="$config_directory/service.conf"
if [[ ! -e "$service_config" ]]; then
    token=$(/usr/bin/openssl rand -hex 32)
    /usr/bin/printf 'PORT=17391\nTOKEN=%s\n' "$token" > "$service_config"
fi
/bin/chmod 0600 "$service_config"

key_file="$config_directory/openrouter-api-key"
if [[ ! -e "$key_file" ]]; then
    /usr/bin/touch "$key_file"
fi
/bin/chmod 0600 "$key_file"

begin_marker="-- BEGIN send-to-hammerspoon-calendar"
end_marker="-- END send-to-hammerspoon-calendar"

if [[ ! -f "$init_file" ]] || ! /usr/bin/grep -Fq -- "$begin_marker" "$init_file"; then
    {
        /usr/bin/printf '\n%s\n' "$begin_marker"
        /usr/bin/printf 'local sendToHammerspoonHome = os.getenv("HOME") .. "/.hammerspoon/send-to-hammerspoon/"\n'
        /usr/bin/printf 'local sendToHammerspoon = dofile(sendToHammerspoonHome .. "send_to_hammerspoon.lua")\n'
        /usr/bin/printf 'local sendToHammerspoonConfig = dofile(sendToHammerspoonHome .. "config.lua")\n'
        /usr/bin/printf 'sendToHammerspoon.start(sendToHammerspoonConfig)\n'
        /usr/bin/printf '%s\n' "$end_marker"
    } >> "$init_file"
fi

print ""
print "Installation complete. Next steps:"
print "1. Put only your OpenRouter key in: $key_file"
print "2. Review local settings in: $install_directory/config.lua"
print "3. Reload Hammerspoon configuration."
print "4. Grant Automation access to Calendar when macOS asks."
print "5. Use Hammerspoon's built-in Send to Hammerspoon Service; no extra workflow is required."
