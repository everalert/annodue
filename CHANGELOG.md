# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Migrated `patch/util/racer*` to `racer` module

## [0.1.4] - 2024-05-09

### Added

- Bugfix:
	- Map text rendering not accounting for hi-res flag
- Core: Global State
	- `race_state`
	- `race_state_prev`
	- `race_state_new`
- Core:
	- Ability to toggle Practice Mode OFF in race scene before countdown
	- Added hooking single-param functions to util library ([#1](https://github.com/everalert/annodue/pull/1))
- Hook:
	- `TextRenderA`
	- `MapRenderB`
	- `MapRenderA`
- Overlay:
	- FPS readout
	- death count tracker
	- fall timer
- Post-Race Stats:
	- `Distance`
	- `Top Speed`
	- `Avg. Speed`
	- `Boost Duration`
	- `Avg. Boost Duration`
	- `Boost Distance`
	- `Avg. Boost Distance`
- Savestates:
	- Load count tracker
- Setting:
	- `qol -> fps_limiter_default (u32)`
	- Allow `on` and `off` for `bool` settings
- Quick Race:
	- Apply FPS without restart in practice mode
	- Can now hold button to open instead of double-tap
	- Scroll through FPS presets with hotkey
	- Scroll through tracks by planet with hotkey

### Changed

- Core:
	- `PLUGIN_VERSION` - `17`→`19`
	- Show Practice Mode label the whole way through race end to start race in cantina
	- Moved zig-ini dependency to package manager
- Quick Race:
	- Upgrade presets now require highlighting any upgrade first
	- XInput Quick Confirm - `B`→`Start`
	- XInput Close - `Start`→`B`
	- Keyboard Quick Confirm - `Enter`→`Space`
	- Keyboard Interact - `Space`→`Enter`
- Quick Reset:
	- Input combination more lenient
	- Keyboard - `Esc+F1`→`Esc+Tab`

### Removed

- Core: Global State
	- `player -> in_race_count`
	- `player -> in_race_results`
	- `player -> in_race_racing`

### Fixed

- Build:
	- Release directory enforced and impacting graph even when not building release step
- Hook:
	- `TextRenderB` insertion point after text render
- Quick Race:
	- Cantina not synced when setting number of racers
- Savestates:
	- Loading state overriding settings when game is loading new scene
	- Memory leak when hot-reloading plugin
- Updater:
	- Mouse cursor not visible when showing restart message

## [0.1.3] - 2024-04-30

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

## [0.1.2] - 2024-04-23

### Added

- Feature: Sideload user-provided `dinput.dll` instead of the one in `system32`

### Fixed

- Release archives not separating directories with `/` when building on Windows

## [0.1.1] - 2024-04-22

### Fixed

- DirectInput hook not creating `annodue/tmp` as needed

## [0.1.0] - 2024-04-21

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

[unreleased]: https://github.com/everalert/annodue/compare/0.1.4...HEAD
[0.1.4]: https://github.com/everalert/annodue/compare/0.1.3...0.1.4
[0.1.3]: https://github.com/everalert/annodue/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/everalert/annodue/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/everalert/annodue/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/everalert/annodue/releases/tag/0.1.0
