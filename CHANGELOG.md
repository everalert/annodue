# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Bugfix: Map text rendering not accounting for hi-res flag
- Core: Global State `race_state` `race_state_prev` `race_state_new`
- Core: Ability to toggle Practice Mode OFF in race scene before countdown
- Hook: `TextRenderA`
- Hook: `MapRenderB` `MapRenderA`
- Setting: `qol` `fps_limiter_default` `u32`
- Setting: Allow `on` `off` for `bool` settings
- Quick Race: Apply FPS without restart in practice mode
- Quick Race: Can now hold button to open instead of double-tap
- Quick Race: Scroll through FPS presets with hotkey
- Quick Race: Scroll through tracks by planet with hotkey


### Changed

- Core: `PLUGIN_VERSION` - `17`→`18`
- Quick Race: Upgrade presets now require highlighting any upgrade first
- Quick Race: XInput Quick Confirm - `B`→`Start`
- Quick Race: XInput Close - `Start`→`B`
- Quick Race: Keyboard Quick Confirm - `Enter`→`Space`
- Quick Race: Keyboard Interact - `Space`→`Enter`
- Quick Reset: Input combination more lenient
- Quick Reset: Keyboard - `Esc+F1`→`Esc+Tab`

### Removed

- Core: Global State `player.in_race_count` `player.in_race_results` `player.in_race_racing`

### Fixed

- Hook: TextRenderB insertion point after text render
- Quick Race: Cantina not synced when setting number of racers
- Updater: Mouse cursor not visible when showing restart message

## [0.1.3] -- 2024-04-30

### Added

- Feature: Dumping crash info to `crashlog.txt`
- Feature: Fast countdown timer
- Feature: Patch Jinn Reeso cheat to also toggle off
- Feature: Patch Cy Yunga cheat to also toggle off
- Feature: Fix Cy Yunga cheat audio
- Setting: `[qol] fast_countdown_enable`
- Setting: `[qol] fast_countdown_duration`

### Changed

- Improved framerate limiter pacing and CPU impact

### Fixed

- Wrong position of lap times on race end screen with milliseconds timer off

## [0.1.2] -- 2024-04-23

### Added

- Feature: Sideload user-provided `dinput.dll` instead of the one in `system32`

### Fixed

- Release archives not separating directories with `/` when building on Windows

## [0.1.1] -- 2024-04-22

### Fixed

- DirectInput hook not creating `annodue/tmp` as needed

## [0.1.0] -- 2024-04-21

### Added

- Plugin system (custom plugins disabled for now)
- Update system
- Free Camera
- Savestates & Rewinding
- Quick Race Menu
- Input display
- Extended post-race summary
- Extended race UI overlay
- Framerate limiter
- Pause mapped to gamepad
- Race restart hotkey
- Showing milliseconds digit on all timers
- Configurable defaults for free-play racers and laps
- Skip planet cutscenes
- Double mouse cursor fix
- Collisions disabled in multiplayer
- Pod upgrades in multiplayer
- Hi-res fonts
- Triggered race events displayed on UI
- Rainbow-colored race UI elements

[unreleased]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.3...HEAD
[0.1.3]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/olivierlacan/keep-a-changelog/releases/tag/0.1.0
