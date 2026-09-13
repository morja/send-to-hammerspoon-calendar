#!/bin/zsh

set -eu

project_directory=${0:A:h:h}
test_directory=$(/usr/bin/mktemp -d /tmp/calendar-service-install.XXXXXXXX)
trap '/bin/rm -rf -- "$test_directory"' EXIT

services_directory="$test_directory/Services"
source_workflow="$project_directory/service/Termin erstellen.workflow"
installed_workflow="$services_directory/Termin erstellen.workflow"

/bin/mkdir -p "$services_directory"
/usr/bin/ditto "$source_workflow" "$installed_workflow"
print 'previous version' > "$installed_workflow/previous-version.txt"
/usr/bin/ditto "$source_workflow" "$services_directory/Termin erstellen.workflow.backup-legacy"

# Replacing a workflow must leave exactly one active Service bundle.
SERVICES_DIRECTORY="$services_directory" "$project_directory/scripts/install-calendar-service.sh"

[[ -d "$installed_workflow" ]]
[[ ! -e "$installed_workflow/previous-version.txt" ]]
[[ $(/usr/bin/find "$services_directory" -maxdepth 1 -name 'Termin erstellen.workflow*' | /usr/bin/wc -l | /usr/bin/tr -d ' ') == 1 ]]
[[ ! -e "$services_directory/Termin erstellen.workflow.backup-legacy" ]]

# A second install should leave the one installed Service unchanged.
SERVICES_DIRECTORY="$services_directory" "$project_directory/scripts/install-calendar-service.sh"

[[ $(/usr/bin/find "$services_directory" -maxdepth 1 -name 'Termin erstellen.workflow*' | /usr/bin/wc -l | /usr/bin/tr -d ' ') == 1 ]]
/usr/bin/diff -qr "$source_workflow" "$installed_workflow" >/dev/null

print 'ok - Service installer leaves one active workflow and no backup'
