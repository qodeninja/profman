#!/bin/bash

# author: qodeninja (c) 2025 ARR
# version: 0.3.0

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
    # Action: Run a simple command that triggers file creation
    "$PROFMAN_SCRIPT" --list > /dev/null 2>&1
    # Verification
    [ -f "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json" ] || { echo " -> FAIL: base_pref.json not created."; return 1; }
    [ -f "$PROFMAN_TEST_SCRIPT_DIR/menu_patch.json" ] || { echo " -> FAIL: menu_patch.json not created."; return 1; }
    return 0
}

test_local_override_creation() {
    # Setup: Create a local override file. The base_pref.json should NOT exist yet.
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
    "$PROFMAN_SCRIPT" --profile 0 > /dev/null 2>&1
    # Verification
    local result
    result=$(jq -r '.enable_do_not_track' "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences")
    [ "$result" == "true" ] || { echo " -> FAIL: Value was '$result', expected 'true'."; return 1; }
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
    # Setup
    echo '{"vivaldi":{"homepage":"https://example.com"}}' > "$PROFMAN_TEST_USER_DATA_PATH/Default/Preferences"
    echo '{"vivaldi":{"homepage":""}}' > "$PROFMAN_TEST_SCRIPT_DIR/base_pref.json" # The template to match against
    # Action
    "$PROFMAN_SCRIPT" --export-base 0 > /dev/null 2>&1
    # Verification
    local exported_file="$PROFMAN_TEST_SCRIPT_DIR/base_pref.exported.json"
    [ -f "$exported_file" ] || { echo " -> FAIL: Exported file not created."; return 1; }
    local homepage
    homepage=$(jq -r '.vivaldi.homepage' "$exported_file")
    [ "$homepage" == "https://example.com" ] || { echo " -> FAIL: Exported homepage was '$homepage', not 'https://example.com'."; return 1; }
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
    run_test "Bookmark file replacement" test_bookmark_replacement
    run_test "Snapshot creation" test_snapshot_creation
    run_test "Context menu file replacement" test_menu_replacement
    run_test "Export base preferences" test_export_base
    run_test "Profile create and delete lifecycle" test_create_and_delete_profile
    run_test "Clean command archives all backups" test_clean_command

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
