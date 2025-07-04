# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2025-07-04

### Changed

-   **BREAKING**: The script's primary execution logic has been clarified to prevent accidental merges.
    -   In version 0.7.x, running the script with only `--profile <id>` would implicitly execute the merge operation. This was confusing as `--profile` also acted as a parameter for other commands.
    -   The merge action has been moved to an explicit `--deploy` command. The `--profile` flag now acts *only* as a parameter to specify a target profile and no longer triggers an action on its own.
    -   **Example**: `_Old: ./profman.sh --profile 0_` is now `_New: ./profman.sh --profile 0 --deploy_`.

## [0.7.0] - 2025-07-03

### Added

-   Initial release with core features: preference merging (via `--profile`), profile listing (`--list`), snapshots (`--snap`), diffing (`--diff`), and cleaning (`--clean`).
