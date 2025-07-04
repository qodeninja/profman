#!/bin/bash
# author: qodeninja (c) 2025 ARR
# version: 0.7.0

# --- Vivaldi Profile Manager ---
#
# Standard Use Cases:
#
# 1. List all available profiles:
#    ./profman.sh --list
#
# 2. Apply the base preferences to the default profile:
#    ./profman.sh --profile 0
#
# 3. Create a timestamped backup of Profile 1's settings:
#    ./profman.sh --profile 1 --snap
#
# 4. Do a "dry run" merge on Profile 2, saving the output to a test file:
#    ./profman.sh --profile 2 --auto
#
# 5. See what has changed in the Default profile since the last merge:
#    ./profman.sh --profile 0 --diff
#
# 6. Compare the current settings of Profile 1 with its 3rd snapshot:
#    ./profman.sh --profile 1 --diff 3
#
# 7. Compare snapshot 5 with snapshot 8 for the Default profile:
#    ./profman.sh --profile 0 --diff 5 8
#
# 8. Clean up all generated files for Profile 1, archiving them into a zip file:
#    ./profman.sh --profile 1 --clean
#
# 9. Programmatically create a new profile (e.g., Profile 3, if 1 and 2 exist):
#    ./profman.sh --create-profile
#
# 10. Export the configuration from Profile 0 to a new base file:
#     ./profman.sh --export-base 0
#
# 11. Restore Profile 1 to its state from snapshot 2:
#     ./profman.sh --profile 1 --restore 2
#
# 12. Permanently delete Profile 4:
#     ./profman.sh --profile 4 --delete-profile
#
# A script to merge custom Vivaldi preferences from a base file into a new profile.
#
# IMPORTANT:
# 1. PREREQUISITES: 'jq' and 'zip' must be installed.
# 2. USAGE: Ensure Vivaldi is completely closed before running any commands.
# 3. CONFIGURATION: If running outside of WSL, set the VIVALDI_USER_DATA_PATH_MANUAL
#    variable in the Configuration section below. If in WSL, ensure the
#    WIN_USER_ROOT environment variable is set.

usage() {
  echo "Usage: $(basename "$0") [command] [options]"
  echo "A comprehensive manager for Vivaldi browser profiles."
  echo
  echo "Commands:"
  echo "  (no command)         Merge base_pref.json into the specified profile."
  echo "  --list               List all available Vivaldi profiles and exit."
  echo "  --create-profile     Creates a new, numbered Vivaldi profile."
  echo "  --snap               Create a numbered, timestamped snapshot of the profile's Preferences."
  echo "                       (Filename: Preferences.snap.1.YYYYMMDD-HHMMSS)"
  echo "  --restore <snap_num> Replaces a profile's settings with a specific snapshot."
  echo "  --diff [n1] [n2]     Compare preferences. With no args, compares current vs. last"
  echo "                       backup. With one arg (n1), compares current vs. snapshot n1,"
  echo "                       and with two args (n1, n2), compares snapshot n1 vs. n2."
  echo "  --clean              Archives all generated files (.snap, .diff, .test) into a zip"
  echo "                       file and removes the originals."
  echo "  --menus              Replaces the profile's contextmenu.json file with the base"
  echo "                       'menu_patch.json'. Creates a backup of the original file."
  echo "  --bookmarks          Replaces the profile's Bookmarks file with the base 'bookmarks.json'."
  echo "                       Creates a backup of the original file before replacing."
  echo "  --export-base <id>   Exports settings from a profile that match the keys in the"
  echo "                       existing base_pref.json, creating a new base file."
  echo
  echo "Destructive Commands:"
  echo "  --delete-profile     Permanently deletes a profile directory and deregisters it."
  echo "Merge Options:"
  echo "  --profile <id|name>  Required. Profile to target. Use '0' for Default,"
  echo "                       '1' for 'Profile 1', etc., or the full name."
  echo "  --out <file>         Write merged JSON to a specific file instead of modifying"
  echo "                       the profile's Preferences file in-place."
  echo "  --auto               Automatically name and create a test output file"
  echo "                       (e.g., Preferences.test.1) in the profile directory."
  exit 1
}

# Helper function to find a snapshot file by its number
find_snapshot_file() {
    local profile_path=$1
    local profile_name=$2
    local snap_num=$3
    # Use find to get the unique file matching the pattern.
    local found_file
    found_file=$(find "${profile_path}" -maxdepth 1 -name "Preferences.snap.${snap_num}.*" 2>/dev/null)
    if [ -z "$found_file" ]; then
        echo "Error: Snapshot number '${snap_num}' not found in profile '${profile_name}'."
        exit 1
    fi
    # Check if more than one file was found (should not happen with our naming)
    if [ "$(echo "$found_file" | wc -l)" -gt 1 ]; then
        echo "Error: Multiple files found for snapshot number '${snap_num}'. Please clean up the directory."
        exit 1
    fi
    echo "$found_file"
}

# --- Test Environment Detection ---
# This allows the test suite (test.sh) to override key paths by setting
# environment variables, ensuring tests are fully isolated and do not affect
# real user data or configuration files.
if [ -n "$PROFMAN_TEST_USER_DATA_PATH" ] && [ -n "$PROFMAN_TEST_SCRIPT_DIR" ]; then
    IS_TEST_MODE=true
fi

# --- Configuration ---

# For non-WSL environments (Linux, macOS), set this to the absolute path of
# your Vivaldi "User Data" directory. This is ignored if running in WSL.
# Examples:
# - Linux:   "/home/your_user/.config/vivaldi"
# - macOS:   "/Users/your_user/Library/Application Support/Vivaldi"
VIVALDI_USER_DATA_PATH_MANUAL="/home/CHANGE_ME/.config/vivaldi"

# --- Path Setup ---
if [ "${IS_TEST_MODE:-false}" = true ]; then
    # In test mode, use paths from environment variables
    VIVALDI_USER_DATA_PATH="$PROFMAN_TEST_USER_DATA_PATH"
    SCRIPT_DIR="$PROFMAN_TEST_SCRIPT_DIR"
else
    # In production mode, determine paths normally
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

    # Check for WSL environment. /etc/wsl.conf is a reliable indicator.
    if [ -f /etc/wsl.conf ]; then
        if [ -z "$WIN_USER_ROOT" ]; then
            echo "Error: WSL environment detected, but WIN_USER_ROOT is not set."
            echo "Please set it to your Windows user profile path (e.g., export WIN_USER_ROOT=/mnt/c/Users/YourName)."
            exit 1
        fi
        VIVALDI_USER_DATA_PATH="${WIN_USER_ROOT}/AppData/Local/Vivaldi/User Data"
    else
        VIVALDI_USER_DATA_PATH="$VIVALDI_USER_DATA_PATH_MANUAL"
    fi
fi

SKEL_DIR="${SCRIPT_DIR}/skel"
BASE_PREFS_SKEL_FILE="${SKEL_DIR}/base_pref.skel.json"
BOOKMARKS_SKEL_FILE="${SKEL_DIR}/bookmarks.skel.json"
MENU_PATCH_SKEL_FILE="${SKEL_DIR}/menu_patch.skel.json"
BASE_PREFS_FILE="${SCRIPT_DIR}/base_pref.json" # This is the user-editable file
LOCAL_BASE_PREFS_FILE="${SCRIPT_DIR}/local.base_pref.json" # User-specific override for creation
BOOKMARKS_FILE="${SCRIPT_DIR}/bookmarks.json" # This is the user-editable file
MENU_PATCH_FILE="${SCRIPT_DIR}/menu_patch.json" # This is the user-editable file
EXPORTED_FILE="${SCRIPT_DIR}/base_pref.exported.json"

# Final sanity check on the configured path
if [[ "$VIVALDI_USER_DATA_PATH" == *CHANGE_ME* ]] || [ ! -d "$VIVALDI_USER_DATA_PATH" ]; then
    echo "Error: Vivaldi User Data path is not configured correctly or does not exist."
    echo "Please edit this script to set VIVALDI_USER_DATA_PATH_MANUAL, or ensure WIN_USER_ROOT is set in WSL."
    echo "Path currently set to: '$VIVALDI_USER_DATA_PATH'"
    exit 1
fi

# --- Base File Initialization ---
# If base_pref.json does not exist, create it from a skeleton file.
# It will prioritize local.base_pref.json if it exists.
if [ ! -f "$BASE_PREFS_FILE" ]; then
    echo "Info: 'base_pref.json' not found. Looking for a source to create it..."

    # Determine the source file for the new base_pref.json
    SOURCE_PREFS_FILE=""
    if [ -f "$LOCAL_BASE_PREFS_FILE" ]; then
        SOURCE_PREFS_FILE="$LOCAL_BASE_PREFS_FILE"
        echo "Found local override: '$(basename "$LOCAL_BASE_PREFS_FILE")'. Using it as the source."
    elif [ -f "$BASE_PREFS_SKEL_FILE" ]; then
        SOURCE_PREFS_FILE="$BASE_PREFS_SKEL_FILE"
        echo "Found default skeleton: '$(basename "$BASE_PREFS_SKEL_FILE")'. Using it as the source."
    fi

    if [ -n "$SOURCE_PREFS_FILE" ]; then
        echo "Creating 'base_pref.json'..."
        if cp "$SOURCE_PREFS_FILE" "$BASE_PREFS_FILE"; then
            echo "Successfully created '$BASE_PREFS_FILE'. You can now edit this file."
        else
            echo "Error: Failed to create '$BASE_PREFS_FILE' from '$(basename "$SOURCE_PREFS_FILE")'. Please check permissions."
            exit 1
        fi
    else
        echo "Error: Cannot create 'base_pref.json'. No source file found."
        echo "       Missing: '$(basename "$LOCAL_BASE_PREFS_FILE")' (optional)"
        echo "       And also missing: '$(basename "$BASE_PREFS_SKEL_FILE")' (required fallback)"
        exit 1
    fi
fi

# If bookmarks.json does not exist, create it from the skeleton file.
if [ ! -f "$BOOKMARKS_FILE" ]; then
    echo "Info: 'bookmarks.json' not found."
    if [ -f "$BOOKMARKS_SKEL_FILE" ]; then
        echo "Creating it from the skeleton file..."
        if cp "$BOOKMARKS_SKEL_FILE" "$BOOKMARKS_FILE"; then
            echo "Successfully created '$BOOKMARKS_FILE'. You can now edit this file."
        else
            echo "Error: Failed to create '$BOOKMARKS_FILE' from skeleton. Please check permissions."
            exit 1
        fi
    else
        echo "Error: Cannot create 'bookmarks.json' because the skeleton file is missing:"
        echo "       '$BOOKMARKS_SKEL_FILE'"
        exit 1
    fi
fi

# If menu_patch.json does not exist, create it from the skeleton file.
if [ ! -f "$MENU_PATCH_FILE" ]; then
    echo "Info: 'menu_patch.json' not found."
    if [ -f "$MENU_PATCH_SKEL_FILE" ]; then
        echo "Creating it from the skeleton file..."
        if cp "$MENU_PATCH_SKEL_FILE" "$MENU_PATCH_FILE"; then
            echo "Successfully created '$MENU_PATCH_FILE'. You can now edit this file."
        else
            echo "Error: Failed to create '$MENU_PATCH_FILE' from skeleton. Please check permissions."
            exit 1
        fi
    else
        # This is not a fatal error, as patching menus is an optional feature.
        echo "Info: Cannot create 'menu_patch.json' because the skeleton file is missing:"
        echo "      '$MENU_PATCH_SKEL_FILE'"
        echo "      The --patch-menus command will be unavailable until this is resolved."
    fi
fi

# --- Prerequisite Checks ---
# Check for jq, as it's used by most features.
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install it first."
    echo "On Debian/Ubuntu: sudo apt-get install jq"
    exit 1
fi

# --- Argument Parsing ---
PROFILE_ARG=""
OUTPUT_FILE=""
LIST_PROFILES=false
AUTO_MODE=false
SNAP_MODE=false
DIFF_MODE=false
CLEAN_MODE=false
CREATE_PROFILE_MODE=false
EXPORT_BASE_MODE=false
RESTORE_MODE=false
DELETE_MODE=false
MENUS_MODE=false
BOOKMARKS_MODE=false
DIFF_ARG1=""
DIFF_ARG2=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --list)
            LIST_PROFILES=true
            ;;
        --auto)
            AUTO_MODE=true
            ;;
        --snap)
            SNAP_MODE=true
            ;;
        --clean)
            CLEAN_MODE=true
            ;;
        --create-profile)
            CREATE_PROFILE_MODE=true
            ;;
        --restore)
            RESTORE_MODE=true
            DIFF_ARG1="$2" # Re-use DIFF_ARG1 for the snapshot number
            shift # past argument
            ;;
        --delete-profile)
            DELETE_MODE=true
            ;;
        --menus)
            MENUS_MODE=true
            ;;
        --bookmarks)
            BOOKMARKS_MODE=true
            ;;
        --export-base)
            EXPORT_BASE_MODE=true
            PROFILE_ARG="$2" # The profile to export from
            shift # past argument
            ;;
        --diff)
            DIFF_MODE=true
            # Check if next arg is not a flag (it's a value for --diff)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                DIFF_ARG1="$2"
                shift # past value
                # Check if the next arg is also not a flag
                if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                    DIFF_ARG2="$2"
                    shift # past value
                fi
            fi
            ;;
        --help)
            usage
            ;;
        --profile)
            PROFILE_ARG="$2"
            shift # past argument
            ;;
        --out)
            OUTPUT_FILE="$2"
            shift # past argument
            ;;
        *)
            echo "Error: Unknown parameter passed: $1"
            usage
            ;;
    esac
    shift # past value
done

# --- Mode: List Profiles ---
if [ "$LIST_PROFILES" = true ]; then
    echo "Available Vivaldi profiles:"
    count=0
    if [ -d "${VIVALDI_USER_DATA_PATH}/Default" ]; then
        echo "  - Default (id: 0)"
        count=$((count + 1))
    fi
    # Find directories named "Profile N" and extract N
    for dir in "${VIVALDI_USER_DATA_PATH}"/Profile\ *; do
        if [ -d "$dir" ]; then
            profile_name=$(basename "$dir")
            profile_id=${profile_name/Profile /}
            echo "  - ${profile_name} (id: ${profile_id})"
            count=$((count + 1))
        fi
    done
    echo "Total profiles found: $count"
    exit 0
fi

if [ "$CREATE_PROFILE_MODE" = true ]; then # --- Mode: Create Profile ---
    LOCAL_STATE_FILE="${VIVALDI_USER_DATA_PATH}/Local State"
    if [ ! -f "$LOCAL_STATE_FILE" ]; then
        echo "Error: Local State file not found at: $LOCAL_STATE_FILE"
        exit 1
    fi

    echo "WARNING: Vivaldi MUST be completely closed before proceeding."
    read -p "Are you sure you want to create a new profile? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    # Find the next available profile number
    last_num=$(jq -r '.profile.info_cache | keys[] | select(startswith("Profile ")) | ltrimstr("Profile ") | tonumber' "$LOCAL_STATE_FILE" 2>/dev/null | sort -n | tail -n 1)
    next_num=$(( ${last_num:-0} + 1 ))
    NEW_PROFILE_DIR_NAME="Profile $next_num"
    NEW_PROFILE_PATH="${VIVALDI_USER_DATA_PATH}/${NEW_PROFILE_DIR_NAME}"

    echo "Next available profile is number: $next_num"

    if [ -d "$NEW_PROFILE_PATH" ]; then
        echo "Error: Profile directory already exists: $NEW_PROFILE_PATH"
        exit 1
    fi

    # Create a minimal entry. Vivaldi will populate the rest on first launch.
    TEMP_STATE_FILE=$(mktemp)
    # shellcheck disable=SC2064
    trap 'rm -f "$TEMP_STATE_FILE"' EXIT

    NEW_PROFILE_UI_NAME="${NEW_PROFILE_DIR_NAME} (AUTO)"

    if jq \
      --arg dirname "$NEW_PROFILE_DIR_NAME" \
      --arg uiname "$NEW_PROFILE_UI_NAME" \
      '.profile.info_cache[$dirname] = { "name": $uiname, "user_name": $uiname }' \
      "$LOCAL_STATE_FILE" > "$TEMP_STATE_FILE" && [ -s "$TEMP_STATE_FILE" ]; then
        # Create the directory, back up Local State, and then atomically replace it
        mkdir -p "$NEW_PROFILE_PATH"
        cp "$LOCAL_STATE_FILE" "${LOCAL_STATE_FILE}.bak-before-create"
        mv "$TEMP_STATE_FILE" "$LOCAL_STATE_FILE"
        echo "Successfully registered '$NEW_PROFILE_DIR_NAME'."
        echo "Next steps:"
        echo "1. Start Vivaldi and select the new profile from the profile menu to initialize it."
        echo "2. Once initialized, close Vivaldi and you can use this script to merge preferences."
    else
        echo "Error: Failed to update Local State file with jq."
        exit 1
    fi
    exit 0
fi

# All modes below this point require a profile argument
if [ -z "$PROFILE_ARG" ]; then
    echo "Error: A profile argument is required for this operation."
    usage
fi

# --- Profile Path Setup ---
# This block now runs for all profile-dependent actions.
if [ "$PROFILE_ARG" == "0" ]; then
    PROFILE_NAME="Default"
else
    # This handles both numeric arguments (e.g., 1) and full name arguments (e.g., "Profile 1")
    [[ "$PROFILE_ARG" =~ ^[0-9]+$ ]] && PROFILE_NAME="Profile $PROFILE_ARG" || PROFILE_NAME="$PROFILE_ARG"
fi
VIVALDI_PROFILE_PATH="${VIVALDI_USER_DATA_PATH}/${PROFILE_NAME}"
VIVALDI_PREFS_FILE="${VIVALDI_PROFILE_PATH}/Preferences"

if [ "$EXPORT_BASE_MODE" = true ]; then # --- Mode: Export Base ---
    if [ ! -f "$BASE_PREFS_FILE" ]; then
        echo "Error: Template file not found at '$BASE_PREFS_FILE'. Cannot export."
        exit 1
    fi
    if [ ! -f "$VIVALDI_PREFS_FILE" ]; then
        echo "Error: Preferences file not found for profile '${PROFILE_NAME}'."
        exit 1
    fi
    if [ -f "$EXPORTED_FILE" ]; then
        read -p "Warning: '$EXPORTED_FILE' already exists. Overwrite? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi

    echo "Exporting settings from profile '${PROFILE_NAME}' to '$EXPORTED_FILE'..."
    echo "Using '$BASE_PREFS_FILE' as a template for which keys to export."

    # This jq filter performs a "deep pick", creating a new JSON object
    # that has the same structure as the template, but with values from the source.
    JQ_FILTER='
        def pick(template):
            . as $input | # Capture the current input object (from Preferences)
            if type == "object" and (template | type) == "object" then
                reduce (template | keys_unsorted[]) as $key ({}; # Start building a new object
                    # For each key in the template, check if it exists in the input object
                    if ($input | has($key)) then
                        # If it exists, add it to our result and recurse into its value
                        . + { ($key): ( ($input[$key]) | pick(template[$key]) ) }
                    else
                        # Otherwise, keep the result object as is and continue
                        .
                    end)
            else
                $input # For non-objects (leaves), return the original value from Preferences
            end;
        pick($template)
    '

    if jq --argfile template "$BASE_PREFS_FILE" "$JQ_FILTER" "$VIVALDI_PREFS_FILE" > "$EXPORTED_FILE"; then
        echo "Successfully exported settings to '$EXPORTED_FILE'."
        echo "You can now review this file and replace base_pref.json if desired."
    else
        echo "Error: Failed to export settings."
        rm -f "$EXPORTED_FILE" 2>/dev/null
        exit 1
    fi
    exit 0
elif [ "$RESTORE_MODE" = true ]; then # --- Mode: Restore from Snapshot ---
    if [ -z "$DIFF_ARG1" ]; then
        echo "Error: --restore requires a snapshot number."
        usage
    fi

    SNAPSHOT_FILE_TO_RESTORE=$(find_snapshot_file "$VIVALDI_PROFILE_PATH" "$PROFILE_NAME" "$DIFF_ARG1")

    echo "You are about to overwrite the current settings for profile '${PROFILE_NAME}'"
    echo "with the contents of snapshot #${DIFF_ARG1}."
    read -p "This action is permanent. Are you sure? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    # Create a one-time backup before restoring
    BACKUP_BEFORE_RESTORE="${VIVALDI_PREFS_FILE}.before-restore-snap${DIFF_ARG1}"
    echo "Backing up current settings to: $(basename "$BACKUP_BEFORE_RESTORE")"
    cp "$VIVALDI_PREFS_FILE" "$BACKUP_BEFORE_RESTORE"

    echo "Restoring from $(basename "$SNAPSHOT_FILE_TO_RESTORE")..."
    if cp "$SNAPSHOT_FILE_TO_RESTORE" "$VIVALDI_PREFS_FILE"; then
        echo "Successfully restored settings for profile '${PROFILE_NAME}'."
    else
        echo "Error: Failed to restore snapshot. Your previous settings are safe in the backup file."
        exit 1
    fi
    exit 0

elif [ "$DELETE_MODE" = true ]; then # --- Mode: Delete Profile ---
    if [ "$PROFILE_NAME" == "Default" ]; then
        echo "Error: Deleting the 'Default' profile is not allowed."
        exit 1
    fi

    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!!                      DANGER ZONE                           !!!"
    echo "!!! You are about to PERMANENTLY DELETE profile '${PROFILE_NAME}'      !!!"
    echo "!!! This will remove the directory and all its contents:       !!!"
    echo "!!!   ${VIVALDI_PROFILE_PATH}"
    echo "!!! This action is IRREVERSIBLE.                             !!!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    read -p "To confirm, please type the full profile name ('${PROFILE_NAME}'): " confirmation

    if [ "$confirmation" != "$PROFILE_NAME" ]; then
        echo "Confirmation failed. Aborting."
        exit 1
    fi

    echo "Proceeding with deletion..."
    LOCAL_STATE_FILE="${VIVALDI_USER_DATA_PATH}/Local State"
    TEMP_STATE_FILE=$(mktemp)
    # shellcheck disable=SC2064
    trap 'rm -f "$TEMP_STATE_FILE"' EXIT

    # Remove profile from Local State
    if jq --arg profilename "$PROFILE_NAME" 'del(.profile.info_cache[$profilename])' "$LOCAL_STATE_FILE" > "$TEMP_STATE_FILE"; then
        echo "Updating Local State file..."
        cp "$LOCAL_STATE_FILE" "${LOCAL_STATE_FILE}.bak-before-delete-${PROFILE_NAME// /_}"
        mv "$TEMP_STATE_FILE" "$LOCAL_STATE_FILE"

        echo "Deleting profile directory..."
        if rm -rf "$VIVALDI_PROFILE_PATH"; then
            echo "Successfully deleted profile '${PROFILE_NAME}'."
        else
            echo "Error: Failed to delete the profile directory. It has been deregistered, but you may need to remove the directory manually."
            exit 1
        fi
    else
        echo "Error: Failed to update Local State file with jq. Profile not deleted."
        exit 1
    fi
    exit 0
elif [ "$DIFF_MODE" = true ]; then # --- Mode: Diff ---
    if ! command -v diff &> /dev/null; then
        echo "Error: 'diff' is not installed. Please install it first."
        echo "On Debian/Ubuntu: sudo apt-get install diffutils"
        exit 1
    fi

    # Determine which diff scenario to run
    if [ -n "$DIFF_ARG2" ]; then # Scenario: two snapshots
        FILE1=$(find_snapshot_file "$VIVALDI_PROFILE_PATH" "$PROFILE_NAME" "$DIFF_ARG1")
        FILE2=$(find_snapshot_file "$VIVALDI_PROFILE_PATH" "$PROFILE_NAME" "$DIFF_ARG2")
        DIFF_OUTPUT_FILE="${VIVALDI_PROFILE_PATH}/diff.snap${DIFF_ARG1}-vs-snap${DIFF_ARG2}.diff"
        echo "Comparing snapshot ${DIFF_ARG1} with snapshot ${DIFF_ARG2}..."
    elif [ -n "$DIFF_ARG1" ]; then # Scenario: current vs snapshot
        FILE1=$(find_snapshot_file "$VIVALDI_PROFILE_PATH" "$PROFILE_NAME" "$DIFF_ARG1")
        FILE2="$VIVALDI_PREFS_FILE"
        DIFF_OUTPUT_FILE="${VIVALDI_PROFILE_PATH}/diff.current-vs-snap${DIFF_ARG1}.diff"
        echo "Comparing current preferences with snapshot ${DIFF_ARG1}..."
    else # Scenario: current vs last merge backup
        if [ "$PROFILE_NAME" == "Default" ]; then
            FILE1="${VIVALDI_PREFS_FILE}.Default"
        else
            # e.g., Preferences.1
            FILE1="${VIVALDI_PREFS_FILE}.${PROFILE_NAME/Profile /}"
        fi
        FILE2="$VIVALDI_PREFS_FILE"
        DIFF_OUTPUT_FILE="${VIVALDI_PROFILE_PATH}/last.diff"
        echo "Comparing current preferences with backup from last merge..."
    fi

    # Check that files exist before diffing
    if [ ! -f "$FILE1" ]; then echo "Error: Comparison file not found at '$FILE1'."; exit 1; fi
    if [ ! -f "$FILE2" ]; then echo "Error: Comparison file not found at '$FILE2'."; exit 1; fi

    # Create a temporary file for the diff output
    DIFF_TEMP_FILE=$(mktemp)
    # shellcheck disable=SC2064
    trap 'rm -f "$DIFF_TEMP_FILE"' EXIT

    # Use process substitution <(...) to feed sorted json to diff. Use -u for a readable format.
    if ! diff -u <(jq -S . "$FILE1") <(jq -S . "$FILE2") > "$DIFF_TEMP_FILE"; then
        diff_status=$?
        if [ $diff_status -eq 1 ]; then
            # Differences were found, which is not a script error.
            mv "$DIFF_TEMP_FILE" "$DIFF_OUTPUT_FILE"
            echo "Differences found. Output saved to: $DIFF_OUTPUT_FILE"
            read -p "Display the differences now? (y/n) " -n 1 -r
            echo # move to a new line
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "----------------------------------------"
                cat "$DIFF_OUTPUT_FILE"
                echo "----------------------------------------"
            fi
        else
            # An actual error occurred during the diff operation.
            echo "Error: An error occurred during the diff operation (code: $diff_status)."
            exit 1 # The trap will clean up the temp file
        fi
    else
        echo "No differences found."
    fi
    exit 0

elif [ "$SNAP_MODE" = true ]; then # --- Mode: Create Snapshot ---
    if [ ! -f "$VIVALDI_PREFS_FILE" ]; then
      echo "Error: Preferences file not found for profile '${PROFILE_NAME}'."
      exit 1
    fi

    # Find the highest existing snapshot number and add 1
    latest_num=0
    # Loop through all snapshot files to find the highest number
    for f in "${VIVALDI_PROFILE_PATH}"/Preferences.snap.*; do
        # If the glob doesn't match, it returns the literal string. This check handles that.
        [ -e "$f" ] || continue
        # Extract the number (part 3 of the filename, e.g., Preferences.snap.1.TIMESTAMP)
        num=$(basename "$f" | cut -d. -f3)
        # Update latest_num if this one is higher
        if [[ "$num" -gt "$latest_num" ]]; then
            latest_num=$num
        fi
    done
    snap_num=$((latest_num + 1))

    TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
    SNAPSHOT_FILE="${VIVALDI_PROFILE_PATH}/Preferences.snap.${snap_num}.${TIMESTAMP}"

    if cp "$VIVALDI_PREFS_FILE" "$SNAPSHOT_FILE"; then
        echo "Snapshot created successfully at: $SNAPSHOT_FILE"
    else
        echo "Error: Failed to create snapshot for profile '${PROFILE_NAME}'."
        exit 1
    fi
    exit 0
elif [ "$CLEAN_MODE" = true ]; then # --- Mode: Clean Profile Directory ---
    if ! command -v zip &> /dev/null; then
        echo "Error: 'zip' is not installed. Please install it first."
        echo "On Debian/Ubuntu: sudo apt-get install zip"
        exit 1
    fi

    echo "Scanning profile '${PROFILE_NAME}' for generated files..."
    # Use an array to store the list of files to clean up
    readarray -t files_to_clean < <(find "$VIVALDI_PROFILE_PATH" -maxdepth 1 \( \
        -name "Preferences.snap.*" -o \
        -name "Preferences.test.*" -o \
        -name "diff.*.diff" -o \
        -name "last.diff" \
        -o -name "contextmenu.json.bak-before-patch" \
        -o -name "Bookmarks.*" \
    \) -print)

    if [ ${#files_to_clean[@]} -eq 0 ]; then
        echo "No generated files found to clean up."
        exit 0
    fi

    echo "Found ${#files_to_clean[@]} file(s) to archive:"
    for f in "${files_to_clean[@]}"; do
        echo "  - $(basename "$f")"
    done

    # Determine profile ID for the zip filename
    if [ "$PROFILE_NAME" == "Default" ]; then
        PROFILE_ID="0"
    else
        PROFILE_ID=${PROFILE_NAME/Profile /}
    fi
    ZIP_FILE_NAME="Preferences.${PROFILE_ID}.bak.zip"
    ZIP_FILE_PATH="${VIVALDI_PROFILE_PATH}/${ZIP_FILE_NAME}"

    if [ -f "$ZIP_FILE_PATH" ]; then
        echo "Error: Backup zip file '$ZIP_FILE_PATH' already exists. Please remove it first."
        exit 1
    fi

    # Get just the basenames for zipping, as we'll cd into the directory
    basenames=()
    for f in "${files_to_clean[@]}"; do
        basenames+=("$(basename "$f")")
    done

    # Create the zip archive from within the profile directory for clean paths
    if (cd "$VIVALDI_PROFILE_PATH" && zip "$ZIP_FILE_NAME" "${basenames[@]}"); then
        echo "Successfully created archive: $ZIP_FILE_PATH"
        # Now remove the original files
        if rm "${files_to_clean[@]}"; then
            echo "Successfully removed original files."
        else
            echo "Warning: Failed to remove all original files. Please check the directory."
        fi
    else
        echo "Error: Failed to create zip archive."
        exit 1
    fi
    exit 0
elif [ "$MENUS_MODE" = true ]; then # --- Mode: Replace Context Menus ---
    CONTEXT_MENU_FILE="${VIVALDI_PROFILE_PATH}/contextmenu.json"

    # --- Sanity Checks ---
    if [ ! -f "$MENU_PATCH_FILE" ]; then
        echo "Error: Base menu file not found at: $MENU_PATCH_FILE"
        exit 1
    fi
    if [ ! -f "$CONTEXT_MENU_FILE" ]; then
        echo "Error: Context menu file not found for profile '${PROFILE_NAME}'."
        echo "This usually means the profile hasn't been fully initialized by Vivaldi."
        exit 1
    fi

    echo "You are about to overwrite the context menus for profile '${PROFILE_NAME}'."
    read -p "This action is permanent. Are you sure? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    # Create a backup
    BACKUP_FILE="${CONTEXT_MENU_FILE}.bak-before-patch"
    echo "Backing up current context menu to: $(basename "$BACKUP_FILE")"
    cp "$CONTEXT_MENU_FILE" "$BACKUP_FILE"

    echo "Replacing context menus with contents from '$MENU_PATCH_FILE'..."
    if cp "$MENU_PATCH_FILE" "$CONTEXT_MENU_FILE"; then
        echo "Successfully replaced context menus for profile '${PROFILE_NAME}'."
    else
        echo "Error: Failed to replace context menus. Your previous menus are safe in the backup file."
        exit 1
    fi
    exit 0
elif [ "$BOOKMARKS_MODE" = true ]; then # --- Mode: Replace Bookmarks ---
    VIVALDI_BOOKMARKS_FILE="${VIVALDI_PROFILE_PATH}/Bookmarks"

    # --- Sanity Checks ---
    if [ ! -f "$BOOKMARKS_FILE" ]; then
        echo "Error: Base bookmarks file not found at: $BOOKMARKS_FILE"
        exit 1
    fi
    if [ ! -f "$VIVALDI_BOOKMARKS_FILE" ]; then
        echo "Error: Vivaldi Bookmarks file not found at: $VIVALDI_BOOKMARKS_FILE"
        echo "Please check the path and ensure the profile '${PROFILE_NAME}' has been created."
        exit 1
    fi

    echo "You are about to overwrite the bookmarks for profile '${PROFILE_NAME}'."
    read -p "This action is permanent. Are you sure? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    # Determine backup file name (e.g., Bookmarks.Default, Bookmarks.1)
    if [ "$PROFILE_NAME" == "Default" ]; then
        BACKUP_FILE="${VIVALDI_BOOKMARKS_FILE}.Default"
    else
        # e.g., Bookmarks.1
        BACKUP_FILE="${VIVALDI_BOOKMARKS_FILE}.${PROFILE_NAME/Profile /}"
    fi

    # Create a backup
    echo "Backing up current bookmarks to: $(basename "$BACKUP_FILE")"
    cp "$VIVALDI_BOOKMARKS_FILE" "$BACKUP_FILE"

    echo "Replacing bookmarks with contents from '$BOOKMARKS_FILE'..."
    if cp "$BOOKMARKS_FILE" "$VIVALDI_BOOKMARKS_FILE"; then
        echo "Successfully replaced bookmarks for profile '${PROFILE_NAME}'."
    else
        echo "Error: Failed to replace bookmarks. Your previous bookmarks are safe in the backup file."
        exit 1
    fi
    exit 0
else # --- Main Operation: Merge ---
    # --- Sanity Checks ---
    # Check if the base preferences file exists
    if [ ! -f "$BASE_PREFS_FILE" ]; then
        echo "Error: Base preferences file not found at: $BASE_PREFS_FILE"
        exit 1
    fi

    # Check if the target Vivaldi preferences file exists
    if [ ! -f "$VIVALDI_PREFS_FILE" ]; then
        echo "Error: Vivaldi Preferences file not found at: $VIVALDI_PREFS_FILE"
        echo "Please check the path and ensure the profile '${PROFILE_NAME}' has been created."
        exit 1
    fi

    TEMP_FILE=$(mktemp)
    # Ensure the temporary file is cleaned up on script exit
    # shellcheck disable=SC2064
    trap 'rm -f "$TEMP_FILE"' EXIT

    # --- Auto Mode: Determine output file name ---
    if [ "$AUTO_MODE" = true ]; then
        if [ -n "$OUTPUT_FILE" ]; then
            echo "Error: --auto and --out cannot be used together."
            exit 1
        fi
        i=1
        while true; do
            auto_output_file="${VIVALDI_PROFILE_PATH}/Preferences.test.${i}"
            if [ ! -e "$auto_output_file" ]; then
                OUTPUT_FILE="$auto_output_file"
                echo "Auto-mode enabled. Output will be saved to: $OUTPUT_FILE"
                break
            fi
            ((i++))
        done
    fi

    if [ -n "$OUTPUT_FILE" ]; then
        # --- Output to File Mode (--out) ---
        echo "Merging to output file: $OUTPUT_FILE"
        # Prevent user from accidentally naming the output file like a backup file
        if [[ "$OUTPUT_FILE" == "Preferences."* ]]; then
            echo "Error: --out file name cannot start with 'Preferences.'"
            exit 1
        fi
        # Perform a deep merge of the base preferences into the profile's preferences.
        if jq -s '.[0] * .[1]' "$VIVALDI_PREFS_FILE" "$BASE_PREFS_FILE" > "$OUTPUT_FILE"; then
            echo "Successfully created '$OUTPUT_FILE'."
        else
            echo "Error: Merging to file failed."
        fi
    else
        # --- In-Place Modify Mode ---
        echo "Merging '$BASE_PREFS_FILE' into '$VIVALDI_PREFS_FILE'..."

        # Determine backup file name (e.g., Preferences.Default, Preferences.1)
        if [ "$PROFILE_NAME" == "Default" ]; then
            BACKUP_FILE="${VIVALDI_PREFS_FILE}.Default"
        else
            # e.g., Preferences.1
            BACKUP_FILE="${VIVALDI_PREFS_FILE}.${PROFILE_NAME/Profile /}"
        fi

        # Create a backup if it doesn't already exist
        if [ ! -f "$BACKUP_FILE" ]; then
            cp "$VIVALDI_PREFS_FILE" "$BACKUP_FILE"
            echo "Backup of original created at $BACKUP_FILE"
        else
            echo "Backup file already exists at $BACKUP_FILE. Skipping backup."
        fi

        # Perform a deep merge and check if jq succeeded and the temp file is not empty.
        if jq -s '.[0] * .[1]' "$VIVALDI_PREFS_FILE" "$BASE_PREFS_FILE" > "$TEMP_FILE" && [ -s "$TEMP_FILE" ]; then
            # Replace the original file with the new merged version
            mv "$TEMP_FILE" "$VIVALDI_PREFS_FILE"
            echo "Successfully updated Vivaldi preferences."
        else
            echo "Error: Merging failed. The original Preferences file was not modified."
            exit 1
        fi
    fi
fi
