# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dumping crash info to `crashlog.txt`
- Quality of Life
	- Patch Jinn Reeso cheat to also toggle off
	- Patch Cy Yunga cheat to also toggle off

## [0.1.2] -- 2024-04-23

### Added

- Ability to sideload a secondary `dinput.dll` in place of the one in `system32`

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
- Quick Race Menu - setup a new race without going back to the cantina
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

[unreleased]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.2...HEAD
[0.1.2]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/olivierlacan/keep-a-changelog/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/olivierlacan/keep-a-changelog/releases/tag/0.1.0