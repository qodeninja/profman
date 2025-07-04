![ Profman Image ](imgs/logo.png)

# Profile Manager for Vivaldi (`profman.sh`)

`profman.sh` is a powerful BASH command-line tool for managing Vivaldi browser profiles. It allows you to define a base set of preferences and apply them across multiple profiles, create and restore snapshots, manage bookmarks and context menus, and perform advanced operations like diffing configurations and creating/deleting profiles programmatically. This README file explains the features, patterns and limitations of the tool.


## ✨ Features

- **Profile Management**: List, create, and permanently delete Vivaldi profiles.
- **Preference Merging**: Define a `base_pref.json` file and merge its settings into any profile, preserving other settings.
- **Snapshot System**: Create timestamped snapshots of a profile's preferences, compare them, and restore to any previous state.
- **Configuration Templating**: Replace a profile's Bookmarks or context menus with a master version from your configuration directory.
- **Settings Export**: Export the configuration from an existing profile to create a new base template.
- **Housekeeping**: Clean up all generated backup and diff files into a single zip archive.
- **Cross-Platform**: Works on Linux, macOS, and in WSL for Windows.

## Default Experience

The default skeleton preferences for Profman create a clean debloated UX that you can deploy to all your profiles out-of-the-box: 

![ Default Setup ](imgs/clean.png)


## Prerequisites

Before using `profman.sh`, you need to have the following command-line utilities installed:

- `jq`: For processing JSON data.
- `zip`: For the `--clean` command.
- `diffutils`: For the `--diff` command.

On Debian/Ubuntu, you can install them all with:
```bash
sudo apt-get update
sudo apt-get install jq zip diffutils
```

## ⚠️ Important Notes!

**Beta Software**. This script is in active development. Features may change, and Vivaldi updates could introduce breaking changes. Use at your own risk

🔄 *Version 0.8.x introduces a breaking change. Please review the [CHANGELOG.md](CHANGELOG.md) for details*

**Contributions**. If you're a BASH enthusiast, your ideas are welcome! Please update test.sh with relevant test cases when submitting a pull request. 

**Always Backup**. Profman is powerful but opinionated. Before you start, manually back up your Preferences, Bookmarks, and contextmenu.json files for any existing profiles. 

**Nuked Settings**. The default skeleton files are designed to be minimal. They will remove all existing themes (except a system dark/light), bookmarks, and context menus. Export/Copy your settings first if you want to keep them! 

**Security & Syncing**. Profman does not manage Vivaldi Sync. Disable syncing before making changes to avoid corruption. Never use Profman to modify encrypted settings, as it can corrupt your profile permanently.

**Test For Portability**. Use `test.sh` to validate Profman's behavior on your OS. Not all features are tested across all systems. Compatibility testing is your responsibility.

![ Test Pass Image ](imgs/test.png)

## 🔧 Setup and Configuration

1.  **Make Scripts Executable**:
    ```bash
    chmod +x profman.sh test.sh
    ```

2.  **Configure Vivaldi Path**: The script needs to find your Vivaldi "User Data" directory.
    -   **WSL**: The script auto-detects WSL. Just set the `WIN_USER_ROOT` environment variable in your `.bashrc` or `.zshrc`:
        ```bash
        export WIN_USER_ROOT="/mnt/c/Users/YourWindowsUsername"
        ```
    -   **Linux/macOS**: Edit `profman.sh` and set the `VIVALDI_USER_DATA_PATH_MANUAL` variable to the correct absolute path.

3.  **Generate Config Files**: Run the script for the first time to create your master configuration files (`base_pref.json`, `bookmarks.json`, `menu_patch.json`).
    ```bash
    ./profman.sh --list
    ```
    The script will not overwrite these files once they exist, so you can customize them freely.

### Configuration Overrides

-   **Local Preferences**: To use your own starting template for `base_pref.json`, create a file named `local.base_pref.json` in the project root. If this file exists during the initial run, it will be used as the source instead of the default skeleton.
-   **Bookmarks & Menus**: To use your own master files, simply place your customized `bookmarks.json` and `menu_patch.json` in the project root before the initial run.

## 💻 Command Reference

![ Help Usage ](imgs/cmds.png)


### Profile Selection

**IMPORTANT: Always ensure Vivaldi is completely closed before running any commands that modify profile data. Do not configure or enable profile syncing until AFTER you're done making the changes you want.**

All commands that operate on a profile require the `--profile` argument.

`--profile <id|name>`
: Specifies the target profile.
  - Use `0` for the `Default` profile.
  - Use a number (e.g., `1`) for `Profile 1`.
  - Use the full quoted name (e.g., `"Profile 1"`).

---

### Core Commands

`--deploy`
: Merges the settings from `base_pref.json` into the specified profile's `Preferences` file.
  ```bash
  # Merge base settings into the Default profile
  ./profman.sh --profile 0 --deploy
  ```

`--list`
: Lists all available Vivaldi profiles with their corresponding IDs.
  ```bash
  ./profman.sh --list
  ```

`--snap`
: Creates a numbered, timestamped snapshot of the target profile's `Preferences` file.
  ```bash
  # Create a snapshot for Profile 1
  ./profman.sh --profile 1 --snap
  ```

`--restore <snap_num>`
: Replaces a profile's current `Preferences` with a specific snapshot. A backup of the current settings is created first.
  ```bash
  # Restore Profile 1 to its state from snapshot #2
  ./profman.sh --profile 1 --restore 2
  ```

`--diff [n1] [n2]`
: Compares preference files and shows the differences.
  - **No args**: Compares the current `Preferences` with the backup from the last merge.
  - **One arg (n1)**: Compares the current `Preferences` with snapshot `n1`.
  - **Two args (n1, n2)**: Compares snapshot `n1` with snapshot `n2`.
  ```bash
  # See what changed in Default profile since the last merge
  ./profman.sh --profile 0 --diff

  # Compare current settings of Profile 1 with its 3rd snapshot
  ./profman.sh --profile 1 --diff 3
  ```

`--clean`
: Finds all generated files (`.snap.*`, `.test.*`, `.diff`, backups) for a profile, archives them into a `.zip` file, and removes the originals.
  ```bash
  ./profman.sh --profile 1 --clean
  ```

---

### File Replacement Commands

> **⚠️ Note on Merge vs. Copy**
> Unlike the `--deploy` command which intelligently *merges* settings, the `--menus` and `--bookmarks` commands perform a brute-force copy, completely overwriting the target file.
> - The default `bookmarks.json` skeleton is pristine and nearly empty.
> - The default `menu_patch.json` skeleton adds "Inspect Element" and "View Source" to context menus while removing the "Create QR Code" option.
> - To use your own custom files, manually copy them into the project root and rename them. An export feature is not yet implemented.

`--menus`
: Replaces the profile's `contextmenu.json` file with your master `menu_patch.json`. A backup of the original file is created.
  ```bash
  ./profman.sh --profile 2 --menus
  ```

`--bookmarks`
: Replaces the profile's `Bookmarks` file with your master `bookmarks.json`. A backup of the original file is created.
  ```bash
  ./profman.sh --profile 2 --bookmarks
  ```

---

### Advanced & Destructive Commands

`--create-profile`
: Programmatically creates a new, numbered Vivaldi profile by updating the `Local State` file. Note that this function only adds the scaffolding, you'll have to manually open the profile in Vivaldi in order for it to generate its first-run files before adding prefernces to it.
  ```bash
  ./profman.sh --create-profile
  ```

`--delete-profile`
: **IRREVERSIBLE**. Permanently deletes a profile directory and deregisters it from the `Local State` file. You will be asked for confirmation.
  ```bash
  ./profman.sh --profile 4 --delete-profile
  ```

`--export-base <id>`
: Creates a new `base_pref.exported.json` file. This file will contain the settings from the specified profile, but only for the keys that already exist in your `base_pref.json` template. This is useful for updating your base configuration from a profile you've configured in the UI.
  ```bash
  ./profman.sh --export-base 0
  ```

---

### Deploy Options

These options modify the behavior of the `--deploy` command.

`--out <file>`
: Writes the result of a merge to a specified file instead of modifying the profile's `Preferences` file in-place.

`--auto`
: A "dry run" mode. Automatically names and creates a test output file (e.g., `Preferences.test.1`) in the profile directory without modifying the original.
  ```bash
  # Do a dry run merge on Profile 2
  ./profman.sh --profile 2 --deploy --auto
  ```

## 🏃‍♂️Example Workflow

1.  **Initialize**: Run `./profman.sh --list` to generate your config files.
2.  **Configure**: Open `base_pref.json` and customize the settings to your liking.
3.  **Apply**: Run `./profman.sh --profile 0 --deploy` to merge your settings into the Default profile.
4.  **Snapshot**: Create a baseline snapshot: `./profman.sh --profile 0 --snap`.
5.  **Use Vivaldi**: Launch Vivaldi, use the browser, and change some settings via the UI.
6.  **Review Changes**: Close Vivaldi and run `./profman.sh --profile 0 --diff` to see exactly what settings were changed by your UI interactions.
7.  **Update Base Config**: If you like the changes, use `./profman.sh --export-base 0` and review the exported file to update your `base_pref.json`.

## ✅ Testing

The project includes a test suite to verify its core functionality. It runs in a temporary, isolated environment and will not affect your real Vivaldi data.

To run the tests:
```bash
./test.sh
```

## License

MIT.
