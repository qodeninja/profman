#!/bin/bash

# author: qodeninja (c) 2025 ARR
# version: 0.3.2

# --- Profile Manager Test Suite ---
#
# This script runs a series of tests against profman.sh to ensure its
# core functionality is working correctly. It creates a temporary, isolated
# environment and does NOT affect your actual Vivaldi data.

# Get the directory where this test script is located
TEST_SUITE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROFMAN_SCRIPT="${TEST_SUITE_DIR}/profman.sh"

# --- Test Framework ---

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

setup_test_env() {
    # Create a temporary root directory for all test artifacts
    TEST_ROOT=$(mktemp -d)

    # These env vars will be picked up by profman.sh to redirect its operations
    export PROFMAN_TEST_SCRIPT_DIR="$TEST_ROOT/script_home"
    export PROFMAN_TEST_USER_DATA_PATH="$TEST_ROOT/user_data"

    # Create the directory structure that profman.sh expects
    mkdir -p "$PROFMAN_TEST_SCRIPT_DIR/skel"
    mkdir -p "$PROFMAN_TEST_USER_DATA_PATH/Default"

    # Create dummy skeleton files with hardcoded content for predictable tests
    echo '{"vivaldi":{"some_setting":true}}' > "$PROFMAN_TEST_SCRIPT_DIR/skel/base_pref.skel.json"
    echo '{"roots":{"bookmark_bar":{"children":[{"name":"Skel"}]}}}' > "$PROFMAN_TEST_SCRIPT_DIR/skel/bookmarks.skel.json"
    # This is now a full menu file, not a patch file.
    echo '[{"action":"page","children":[{"action":"Skel.Action"}]}]' > "$PROFMAN_TEST_SCRIPT_DIR/skel/menu_patch.skel.json"

    # Create a dummy profile Bookmarks file to be backed up and replaced
    echo '{"roots":{"bookmark_bar":{"children":[{"name":"Original"}]}}}' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Bookmarks"
    # Create a dummy profile contextmenu file to be backed up and replaced
    echo '[{"action":"page","children":[{"action":"Original.Action"}]}]' > "$PROFMAN_TEST_USER_DATA_PATH/Default/contextmenu.json"
}

test_deploy_all() {
    # Setup:
    # Manually create the user-editable config files with the expected content for this test.
    # This ensures the test is isolated and not affected by state from previous tests.
    echo '{"vivaldi":{"some_setting":true}}' > "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json"
    echo '{"roots":{"bookmark_bar":{"children":[{"name":"Skel"}]}}}' > "$PROFMAN_TEST_SCRIPT_DIR/bookmarks.json"
    echo '[{"action":"page","children":[{"action":"Skel.Action"}]}]' > "$PROFMAN_TEST_SCRIPT_DIR/menu_patch.json"
    # Create a dummy target Preferences file for the merge to happen.
    echo '{"vivaldi":{"some_setting":false}}' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    # Note: The dummy Bookmarks and contextmenu.json files are already created by setup_test_env.
    # Action: Run with 'yes' to auto-confirm the prompt
    "$PROFMAN_SCRIPT" --profile 0 --deploy-all < <(yes) > /dev/null 2>&1

    # Verification 1: Preferences were merged
    local pref_content
    pref_content=$(jq -r '.vivaldi.some_setting' "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences")
    [ "$pref_content" == "true" ] || { echo " -> FAIL: Preferences were not merged. Value was '$pref_content'."; return 1; }
    [ -f "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences.Default" ] || { echo " -> FAIL: Preferences backup not created."; return 1; }

    # Verification 2: Bookmarks were replaced
    local bookmark_content
    bookmark_content=$(jq -r '.roots.bookmark_bar.children[0].name' "$PROFMAN_TEST_USER_DATA_PATH/Default/Bookmarks")
    [ "$bookmark_content" == "Skel" ] || { echo " -> FAIL: Bookmarks were not replaced. Content was '$bookmark_content'."; return 1; }
    [ -f "$PROFMAN_TEST_USER_DATA_PATH/Default/Bookmarks.Default" ] || { echo " -> FAIL: Bookmarks backup not created."; return 1; }

    # Verification 3: Menus were replaced
    local menu_content
    menu_content=$(jq -r '.[0].children[0].action' "$PROFMAN_TEST_USER_DATA_PATH/Default/contextmenu.json")
    [ "$menu_content" == "Skel.Action" ] || { echo " -> FAIL: Menus were not replaced. Content was '$menu_content'."; return 1; }
    [ -f "$PROFMAN_TEST_USER_DATA_PATH/Default/contextmenu.json.bak-before-patch" ] || { echo " -> FAIL: Menu backup not created."; return 1; }

    return 0
}

teardown_test_env() {
    if [ -n "$TEST_ROOT" ] && [ -d "$TEST_ROOT" ]; then
        rm -rf "$TEST_ROOT"
    fi
    # Unset the env vars to avoid polluting the shell session
    unset PROFMAN_TEST_SCRIPT_DIR
    unset PROFMAN_TEST_USER_DATA_PATH
}

run_test() {
    local description="$1"
    local test_func="$2"

    printf "  - Test: %-50s" "$description"

    # Run the test function, which returns 0 for pass, 1 for fail
    if "$test_func"; then
        printf "[${GREEN}PASS${NC}]\n"
        tests_passed=$((tests_passed + 1))
    else
        printf "[${RED}FAIL${NC}]\n"
    fi
    tests_run=$((tests_run + 1))
}

# --- Test Cases ---

test_initial_file_creation() {
    # Setup: Ensure base_pref.json does not exist, so it will be created from the skeleton.
    rm -f "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json"

    # Action: Run a simple command that triggers file creation
    "$PROFMAN_SCRIPT" --list > /dev/null 2>&1
    # Verification: Check that the file was created and has the correct content from the skeleton.
    [ -f "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json" ] || { echo " -> FAIL: base_pref.json not created."; return 1; }
    local content
    content=$(jq -r '.vivaldi.some_setting' "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json")
    [ "$content" == "true" ] || { echo " -> FAIL: base_pref.json content does not match skeleton. Content was '$content'."; return 1; }

    [ -f "$PROFMAN_TEST_SCRIPT_DIR/menu_patch.json" ] || { echo " -> FAIL: menu_patch.json not created."; return 1; }
    return 0
}

test_local_override_creation() {
    # Setup: Ensure base_pref.json does not exist to test its creation logic.
    # This is necessary because a previous test may have already created it.
    rm -f "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json"
    echo '{"local_override": true}' > "$PROFMAN_TEST_SCRIPT_DIR/local.base_pref.json"

    # Action: Run a simple command that triggers file creation
    "$PROFMAN_SCRIPT" --list > /dev/null 2>&1

    # Verification: Check that the created base_pref.json came from the local override
    [ -f "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json" ] || { echo " -> FAIL: base_pref.json not created."; return 1; }
    local content
    content=$(jq -r '.local_override' "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json")
    [ "$content" == "true" ] || { echo " -> FAIL: local.base_pref.json was not used for creation."; return 1; }
    return 0
}

test_bookmark_replacement() {
    # Setup
    # The setup_test_env function creates the initial files.
    # We need to run a command first to ensure bookmarks.json is created from the skel.
    "$PROFMAN_SCRIPT" --list > /dev/null 2>&1

    # Action: Run with 'yes' to auto-confirm the prompt
    "$PROFMAN_SCRIPT" --profile 0 --bookmarks < <(yes) > /dev/null 2>&1

    # Verification
    local backup_file="$PROFMAN_TEST_USER_DATA_PATH/Default/Bookmarks.Default"
    [ -f "$backup_file" ] || { echo " -> FAIL: Backup bookmarks file not created."; return 1; }

    local backup_content
    backup_content=$(jq -r '.roots.bookmark_bar.children[0].name' "$backup_file")
    [ "$backup_content" == "Original" ] || { echo " -> FAIL: Backup content is wrong. Was '$backup_content'."; return 1; }

    local new_content
    new_content=$(jq -r '.roots.bookmark_bar.children[0].name' "$PROFMAN_TEST_USER_DATA_PATH/Default/Bookmarks")
    [ "$new_content" == "Skel" ] || { echo " -> FAIL: New content is wrong. Was '$new_content'."; return 1; }

    return 0
}

test_preference_merge() {
    # Setup
    echo '{ "enable_do_not_track": false }' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    echo '{ "enable_do_not_track": true }' > "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json"
    # Action
    "$PROFMAN_SCRIPT" --profile 0 --deploy < <(yes) > /dev/null 2>&1
    # Verification
    local result
    result=$(jq -r '.enable_do_not_track' "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences")
    [ "$result" == "true" ] || { echo " -> FAIL: Value was '$result', expected 'true'."; return 1; }
    return 0
}

test_preference_merge_adds_new_keys() {
    # Setup: Preferences file is missing a key that base_pref has.
    # This tests that the merge operation adds new keys, not just overwrites existing ones.
    echo '{"vivaldi":{"existing_setting":"foo"}}' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    echo '{"vivaldi":{"new_setting":"bar", "existing_setting": "overwritten"}}' > "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json"

    # Action
    "$PROFMAN_SCRIPT" --profile 0 --deploy < <(yes) > /dev/null 2>&1

    # Verification: Both keys should now exist, and the existing one should be updated.
    local new_content
    new_content=$(cat "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences")

    local existing_val
    existing_val=$(jq -r '.vivaldi.existing_setting' <<< "$new_content")
    [ "$existing_val" == "overwritten" ] || { echo " -> FAIL: Existing key was not overwritten. Value was '$existing_val'."; return 1; }

    local new_val
    new_val=$(jq -r '.vivaldi.new_setting' <<< "$new_content")
    [ "$new_val" == "bar" ] || { echo " -> FAIL: New key was not added. Value was '$new_val'."; return 1; }

    return 0
}

test_snapshot_creation() {
    # Setup
    echo '{}' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    # Action
    "$PROFMAN_SCRIPT" --profile 0 --snap > /dev/null 2>&1
    # Verification
    local snap_file
    snap_file=$(find "$PROFMAN_TEST_USER_DATA_PATH/Default" -name "Preferences.snap.1.*")
    [ -n "$snap_file" ] || { echo " -> FAIL: Snapshot file not found."; return 1; }
    return 0
}

test_menu_replacement() {
    # Setup
    # The setup_test_env function creates the initial files.
    # We need to run a command first to ensure menu_patch.json is created from the skel.
    "$PROFMAN_SCRIPT" --list > /dev/null 2>&1

    # Action
    "$PROFMAN_SCRIPT" --profile 0 --menus < <(yes) > /dev/null 2>&1

    # Verification
    local backup_file="$PROFMAN_TEST_USER_DATA_PATH/Default/contextmenu.json.bak-before-patch"
    [ -f "$backup_file" ] || { echo " -> FAIL: Backup menu file not created."; return 1; }

    local backup_content
    backup_content=$(jq -r '.[0].children[0].action' "$backup_file")
    [ "$backup_content" == "Original.Action" ] || { echo " -> FAIL: Backup content is wrong. Was '$backup_content'."; return 1; }

    local new_content
    new_content=$(jq -r '.[0].children[0].action' "$PROFMAN_TEST_USER_DATA_PATH/Default/contextmenu.json")
    [ "$new_content" == "Skel.Action" ] || { echo " -> FAIL: New content is wrong. Was '$new_content'."; return 1; }

    return 0
}

test_export_base() {
    # Setup:
    # - Preferences has a 'homepage' to overwrite the template's value.
    # - Preferences is MISSING 'some_setting', which exists in the template.
    # This tests both value replacement and key preservation.
    echo '{"vivaldi":{"homepage":"https://example.com"}}' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    echo '{"vivaldi":{"homepage":"", "some_setting": true}}' > "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json"

    # Action
    "$PROFMAN_SCRIPT" --export-base 0 > /dev/null 2>&1

    # Verification
    local exported_file="$PROFMAN_TEST_SCRIPT_DIR/base_pref.exported.json"
    [ -f "$exported_file" ] || { echo " -> FAIL: Exported file not created."; return 1; }

    local exported_content
    exported_content=$(cat "$exported_file")

    # Verification 1: Value from Preferences should overwrite template
    local homepage
    homepage=$(jq -r '.vivaldi.homepage' <<< "$exported_content")
    [ "$homepage" == "https://example.com" ] || { echo " -> FAIL: Exported homepage was '$homepage', not 'https://example.com'."; return 1; }

    # Verification 2: Key from template should be preserved if missing in Preferences
    local some_setting
    some_setting=$(jq -r '.vivaldi.some_setting' <<< "$exported_content")
    [ "$some_setting" == "true" ] || { echo " -> FAIL: Key 'some_setting' was not preserved from template. Value was '$some_setting'."; return 1; }
    return 0
}

test_create_and_delete_profile() {
    # Setup
    echo '{"profile":{"info_cache":{}}}' > "$PROFMAN_TEST_USER_DATA_PATH/Local State"
    # Action 1: Create
    # Use 'yes' to auto-confirm the prompt
    "$PROFMAN_SCRIPT" --create-profile < <(yes) > /dev/null 2>&1
    # Verification 1
    local profile_dir="$PROFMAN_TEST_USER_DATA_PATH/Profile 1"
    [ -d "$profile_dir" ] || { echo " -> FAIL: Profile 1 directory not created."; return 1; }
    local profile_entry
    profile_entry=$(jq -r '.profile.info_cache."Profile 1".name' "$PROFMAN_TEST_USER_DATA_PATH/Local State")
    [ "$profile_entry" == "Profile 1 (AUTO)" ] || { echo " -> FAIL: Profile 1 not registered in Local State."; return 1; }

    # Action 2: Delete
    # Pipe the required confirmation string into the command
    "$PROFMAN_SCRIPT" --profile 1 --delete-profile < <(echo "Profile 1") > /dev/null 2>&1
    # Verification 2
    [ ! -d "$profile_dir" ] || { echo " -> FAIL: Profile 1 directory not deleted."; return 1; }
    profile_entry=$(jq '.profile.info_cache | has("Profile 1")' "$PROFMAN_TEST_USER_DATA_PATH/Local State")
    [ "$profile_entry" == "false" ] || { echo " -> FAIL: Profile 1 not deregistered from Local State."; return 1; }
    return 0
}

test_confirm_action_abort() {
    # Setup: Create a dummy preferences file and a snapshot to "restore" from
    local original_content='{"original": true}'
    echo "$original_content" > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    touch "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences.snap.1.2024"

    # Action: Attempt to restore, but pipe 'n' to the confirmation prompt
    "$PROFMAN_SCRIPT" --profile 0 --restore 1 < <(echo "n") > /dev/null 2>&1

    # Verification: The Preferences file should be unchanged because the action was aborted
    local current_content
    current_content=$(cat "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences")
    # The file content should be identical to the original
    [ "$current_content" == "$original_content" ] || { echo " -> FAIL: Preferences file was modified even though confirmation was 'n'."; return 1; }
    return 0
}

test_restore_original() {
    # Setup: Manually create the files to simulate a post-deploy state
    local profile_path="$PROFMAN_TEST_USER_DATA_PATH/Default"
    local prefs_file="$profile_path/Preferences"
    local backup_file="$profile_path/Preferences.Default"
    local original_content='{"is_original":true}'
    local modified_content='{"is_original":false}'

    echo "$original_content" > "$backup_file"
    echo "$modified_content" > "$prefs_file"

    # Action: Restore the "original" backup, auto-confirming the prompt
    "$PROFMAN_SCRIPT" --profile 0 --restore original < <(yes) > /dev/null 2>&1

    # Verification: The Preferences file should now match the original backup
    local current_content
    current_content=$(cat "$prefs_file")
    [ "$current_content" == "$original_content" ] || { echo " -> FAIL: Preferences file was not restored. Content: $current_content"; return 1; }

    # Verification 2: Check that a backup-before-restore was made
    [ -f "$profile_path/Preferences.before-restore-original" ] || { echo " -> FAIL: Backup before restore was not created."; return 1; }
    return 0
}

test_clean_command() {
    # Setup: Create a variety of files that should be cleaned.
    local profile_path="$PROFMAN_TEST_USER_DATA_PATH/Default"
    touch "$profile_path/Preferences.snap.1.2023"
    touch "$profile_path/Preferences.test.1"
    touch "$profile_path/last.diff"
    touch "$profile_path/contextmenu.json.bak-before-patch"
    touch "$profile_path/Bookmarks.Default" # The file for this feature request
    # And a file that should NOT be cleaned
    touch "$profile_path/Preferences"

    # Action
    "$PROFMAN_SCRIPT" --profile 0 --clean > /dev/null 2>&1

    # Verification
    [ -f "$profile_path/Preferences.0.bak.zip" ] || { echo " -> FAIL: Zip archive not created."; return 1; }
    [ ! -f "$profile_path/Preferences.snap.1.2023" ] || { echo " -> FAIL: Snapshot file not cleaned."; return 1; }
    [ ! -f "$profile_path/Preferences.test.1" ] || { echo " -> FAIL: Test file not cleaned."; return 1; }
    [ ! -f "$profile_path/last.diff" ] || { echo " -> FAIL: Diff file not cleaned."; return 1; }
    [ ! -f "$profile_path/contextmenu.json.bak-before-patch" ] || { echo " -> FAIL: Menu backup not cleaned."; return 1; }
    [ ! -f "$profile_path/Bookmarks.Default" ] || { echo " -> FAIL: Bookmarks backup not cleaned."; return 1; }
    [ -f "$profile_path/Preferences" ] || { echo " -> FAIL: Main Preferences file was incorrectly removed."; return 1; }
    return 0
}


run_all_tests() {
    if [ ! -f "$PROFMAN_SCRIPT" ]; then
        echo -e "${RED}Error: profman.sh not found at '${PROFMAN_SCRIPT}'. Cannot run tests.${NC}"
        exit 1
    fi

    echo "Running profman.sh test suite..."
    echo "--------------------------------"

    tests_run=0
    tests_passed=0

    # Setup a clean environment for the tests
    setup_test_env
    # Ensure teardown happens even if a test fails catastrophically
    trap teardown_test_env EXIT

    # Run the tests
    run_test "Initial config file creation" test_initial_file_creation
    run_test "Local override for base_pref.json" test_local_override_creation
    run_test "Preference merge (in-place)" test_preference_merge
    run_test "Preference merge adds new keys" test_preference_merge_adds_new_keys
    run_test "Bookmark file replacement" test_bookmark_replacement
    run_test "Snapshot creation" test_snapshot_creation
    run_test "Context menu file replacement" test_menu_replacement
    run_test "Export base preferences" test_export_base
    run_test "Profile create and delete lifecycle" test_create_and_delete_profile
    run_test "Confirmation prompt aborts action" test_confirm_action_abort
    run_test "Restore original pre-deploy backup" test_restore_original
    run_test "Clean command archives all backups" test_clean_command
    run_test "Deploy-all command runs all deployments" test_deploy_all

    # Teardown is handled by the trap

    echo "--------------------------------"
    if [ "$tests_passed" -eq "$tests_run" ]; then
        echo -e "Result: ${GREEN}PASS${NC}"
        echo "All $tests_run tests passed successfully."
    else
        echo -e "Result: ${RED}FAIL${NC}"
        echo "$(($tests_run - $tests_passed)) of $tests_run tests failed."
        exit 1
    fi
}

run_all_tests
