#!/bin/zsh

set -eu

script_directory=${0:A:h}
project_directory=${script_directory:h}
service_name="Termin erstellen.workflow"
source_workflow="$project_directory/service/$service_name"
services_directory=${SERVICES_DIRECTORY:-"$HOME/Library/Services"}
installed_workflow="$services_directory/$service_name"

[[ -d "$source_workflow" ]] || {
    print -u2 -- "Workflow is missing: $source_workflow"
    exit 1
}

/bin/mkdir -p "$services_directory"

# Older installer versions left duplicate Service bundles in this folder.
for legacy_backup in "$services_directory"/"Termin erstellen.workflow.backup-"*(N); do
    /bin/rm -rf -- "$legacy_backup"
    print -- "Removed duplicate Service: $legacy_backup"
done

if [[ -d "$installed_workflow" ]] && /usr/bin/diff -qr "$source_workflow" "$installed_workflow" >/dev/null 2>&1; then
    if [[ "$services_directory" == "$HOME/Library/Services" ]]; then
        /System/Library/CoreServices/pbs -update
    fi
    print -- "Calendar Service is already up to date: $installed_workflow"
    exit 0
fi

# Stage the new bundle before replacing the installed Service.
staging_directory=$(/usr/bin/mktemp -d "$services_directory/.termin-erstellen.XXXXXXXX")
trap '/bin/rm -rf -- "$staging_directory"' EXIT
/usr/bin/ditto "$source_workflow" "$staging_directory/$service_name"

if [[ -e "$installed_workflow" ]]; then
    /bin/rm -rf -- "$installed_workflow"
fi

/bin/mv "$staging_directory/$service_name" "$installed_workflow"

# Refresh macOS's Services registry for the current user.
if [[ "$services_directory" == "$HOME/Library/Services" ]]; then
    /System/Library/CoreServices/pbs -update
fi

print -- "Calendar Service installed: $installed_workflow"
