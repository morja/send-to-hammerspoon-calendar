#!/bin/zsh

set -eu

project_directory=${0:A:h:h}
cd "$project_directory"

lua tests/test_event.lua
lua tests/test_main.lua
node tests/test_calendar_helper.js
luac -p src/event.lua
luac -p src/send_to_hammerspoon.lua
/bin/zsh -n scripts/install.sh
/bin/zsh -n scripts/send-to-hammerspoon-service
/usr/bin/plutil -lint "service/Send to Hammerspoon.workflow/Contents/document.wflow"
/usr/bin/osacompile -l JavaScript -o /tmp/send-to-hammerspoon-calendar-test.scpt scripts/create_calendar_event.js
/bin/rm -f /tmp/send-to-hammerspoon-calendar-test.scpt

print "All checks passed."
