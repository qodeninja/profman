# Changelog

All notable changes to this project will be documented in this file. Only minor and patch changes for the current major version is recorded.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0-0.8.2]  - 2025-07-04

### Added
- **`--deploy-all` command:** A new convenience command that runs `--deploy`, `--bookmarks`, and `--menus` in sequence for a specified profile. This streamlines the process of applying a full set of configurations.
- **`--restore original` option:** The `--restore` command can now accept the keyword `original` in addition to a snapshot number. This allows for restoring the very first backup of a profile's `Preferences` file, which is created automatically on the first run of `--deploy`.

### Changed
- The `--clean` command now also archives bookmark backups (e.g., `Bookmarks.Default`, `Bookmarks.1`).
- Updated documentation (`README.md`) and tests to reflect the new features.

### Breaking Changes
- In version 0.7.x the `--profile` flag used to act as both a command and a parameter. In 0.8.x the command function was spun off into the new command `--deploy` and `--deploy-all` while `--profile` is only a parameter for selecting the current working profile. This change was made to prevent accidental merging where  `--profile` might have been used unintentionally.
- The default skeleton files (`base_pref.skel.json`, `bookmarks.skel.json`) are now more minimal. Deploying them to an existing profile without prior customization will result in a "debloated" UX, which may remove existing themes, bookmarks, and menu items. It is highly recommended to back up or export settings before the first deployment.

---
*Older versions are not documented in this changelog.*
