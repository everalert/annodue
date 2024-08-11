# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.6] - 2024-08-11

### Added

- Cam7: Analog deadzone customization
- Cam7: Toggle planar movement with `Tab (keyboard)` or `B (xinput)`
- Cam7: Pan and Orbit with `RCtrl (keyboard)` or `X (xinput)`
- Cam7: Cycle movement speed with `Q/E (keyboard)` or `LB/RB (xinput)`
- Cam7: Cycle rotation speed with `Z/C (keyboard)` or `LSB/RSB (xinput)`
- Cam7: Cycle smoothing instead of speed by holding `X (keyboard)` or `Y (xinput)`
- Cam7: Return movement or rotation to default by pressing both cycle direction buttons together
- Cam7: Toggle hiding ui with `6`
- Cam7: Toggle disabling pod input with `7`
- Cam7: Orient camera to pod with `\` -- sets rotation point to pod when pressed in pan & orbit mode
- Cam7: Teleport pod to camera by holding `Backspace (keyboard)` or `X (xinput)` when exiting free-cam
- Cam7: SFX during camera motion
- Cam7: Fog and track section visibility customization
- Cam7: Default speed and smoothness customization
- Core: Toast notification on plugin reload
- CollisionViewer: Depth bias customization for correcting model-collision visual mismatch ([#5](https://github.com/everalert/annodue/pull/5))
- Developer: Visualization of matrices via hijacking the debug spline markers
- Overlay: Toggles for individual elements
- QOL: Option to skip podium cutscene
- QOL: Option to remove 1px gap at screen edge
- Savestate: Flame effects added to saved state
- Savestate: Dust clouds added to saved state
- Setting: New global settings
	- `SETTINGS_SAVE_DEFAULTS`
	- `SETTINGS_SAVE_AUTO`
	- `PLUGIN_HOT_RELOAD`
- Setting: Following settings now persist between play sessions when changed in-game
    - `[cam7] default_planar_movement`
	- `[cam7] default_disable_input`
	- `[cam7] default_hide_ui`
	- `[collisionviewer] depth_bias`
	- `[qol] default_laps`
	- `[qol] default_racers`
	- `[qol] fps_limiter_default`
- Backend(Build): Warning for when accumulated build files too large
- Backend(Build): Helper script for cleaning build output
- Backend(Core): `appinfo` module for externally-facing defs
- Backend(Core): `GDRAW_VERSION` (now `4`) added to Compatibility Version sum
- Backend(Core): Custom Triggers via `RTrigger`
- Backend(Core): Custom Terrain via `RTerrain`
- Backend(Core): Unrestricted drawing via `GDraw`
- Backend(Core): `GDraw` layers `Default` `DefaultP` `Overlay` `OverlayP` `System` `SystemP` `Debug`
- Backend(Core): Race UI Hiding via `GHideRaceUI`
- Backend(Core): Plugin - Enforcing semantic versioning for plugins
- Backend(Core): Plugin - Enforcing minimum implemented functions for core modules
- Backend(Core): Plugin - Identity tracking, for use with handle-based resources
- Backend(Core): Settings - String type values
- Backend(Core): Auto Update - Now also checks for `autoupdate` filename suffix
- Backend(Core): Global Functions
	- `ASettingSectionOccupy`
	- `ASettingSectionVacate`
	- `ASettingSectionRunUpdate`
	- `ASettingOccupy`
	- `ASettingVacate`
	- `ASettingVacateAll`
	- `ASettingUpdate`
	- `ASettingSectionResetDefault`
	- `ASettingSectionResetFile`
	- `ASettingSectionClean`
	- `ASettingResetAllDefault`
	- `ASettingResetAllFile`
	- `ASettingCleanAll`
	- `ASettingSave`
	- `ASettingSaveAuto`
	- `GDrawText`
	- `GDrawRect`
	- `GDrawRectBdr`
	- `GHideRaceUIEnable`
	- `GHideRaceUIDisable`
	- `GHideRaceUIIsHidden`
	- `RTerrainRequest`
	- `RTerrainRelease`
	- `RTerrainReleaseAll`
	- `RTriggerRequest`
	- `RTriggerRelease`
	- `RTriggerReleaseAll`
- Backend(Core): Hook Functions
	- `OnPluginInitA` (core modules only)
	- `OnPluginLateInitA` (core modules only)
	- `OnPluginDeinitA` (core modules only)
- Backend(RacerLib): Modules
	- `Random`
	- `Vector`
	- `Matrix`
	- `Model`
- Backend(RacerLib): New defs in modules
	- `Quad`
	- `Text`
	- `Input`
	- `Timing`
	- `entity`
	- `entity/Test`
	- `entity/Toss`
	- `entity/Trig`
	- `entity/Hang`
	- `entity/Jdge`
- Backend(Util): Modules
	- `handle_map`
	- `handle_map_static`
	- `handle_map_soa`
	- `deadzone`
	- `file_system`
- Backend(Util): New defs in modules
	- `spatial`
	- `debug`
	- `x86`

### Changed

- Cam7: Lateral movement speed `650` to `125..16000`
- Cam7: Vertical movement speed `350` to `62.5..8000`
- Cam7: Movement smoothing `8` to `none, 16, 8, 4`
- Cam7: Movement speed curve `quadratic` to `quartic`
- Cam7: Rotation speed `360` to `80..810`
- Cam7: Rotation smoothing `none` to `none, 36, 24, 12, 6`
- Core: Reworked toast notification animation/aesthetics
- InputDisplay: Now shows recorded inputs during savestate rewind
- Setting: `[cosmetic] patch_trigger_display` changed to `[core/RTrigger] notify_trigger`
- Setting: Following settings now update dynamically when settings file edited (no longer launch-only)
	- `[cam7] fog_remove`
	- `[gameplay] death_speed_mod_enable`
	- `[gameplay] death_speed_drop`
	- `[gameplay] death_speed_min`
	- `[developer] dump_fonts` (single-use arbitrary enable)
- Backend(Build): release versioning now based on `appinfo` module
- Backend(Core): Settings version `1` to `2`
- Backend(Core): Settings back-end rewritten to support plugin-directed settings definitions
- Backend(Core): Global Function version `15` to `29`
- Backend(Core): Renamed Global Functions
	- `Game*` to `G*` (e.g. `GameFreezeEnable` to `GFreezeEnable`)
	- `GFreezeEnable` to `GFreezeOn`
	- `GFreezeDisable` to `GFreezeOff`
	- `GFreezeIsFrozen` to `GFreezeIsOn`
	- `GHideRaceUIEnable` to `GHideRaceUIOn`
	- `GHideRaceUIDisable` to `GHideRaceUIOff`
	- `GHideRaceUIIsHidden` to `GHideRaceUIIsOn`
- Backend(Core): `GFreeze` switched from plugin-defined identifiers to internal IDs
- Backend(Core): `GHideRaceUI` switched from plugin-defined identifiers to internal IDs
- Backend(Core): `[cosmetic] patch_trigger_display` functionality moved to `RTrigger`
- Backend(Util): Rewind compression logic moved to `temporal_compression`
- Backend(Util): `x86` - migrated `push_*` `pop_*` functions to generalized `push` `pop`

### Removed

- Backend(Core): `Settings.zig`
- Backend(Core): Global Functions
	- `SettingGetB`
	- `SettingGetU`
	- `SettingGetI`
	- `SettingGetF`
- Backend(Build): `-Dver` option in `release` builds
- Backend(Build): `-Dminver` option in `release` builds
- Backend(Util): `settings.zig`

### Fixed

- Cam7: Corrected steering while upside-down to be more intuitive, with option to retain previous behaviour
- Cam7: Corrected Y/Z movement while upside-down in planar movement mode
- Cam7: Minimap lagging behind camera motion while in free cam
- Cam7: Faster rotation toward diagonals with keyboard input
- Cam7: Z-orientation not straightening out when transitioning into free-cam
- Cam7: Main camera being in first-person internal (cam5) changing free-cam FOV
- Savestate: Rewind ignoring saved inputs
- Savestate: Rewind not restoring UI correctly
- Savestate: Movement stuttering during rewind scrubbing
- Savestate: Delayed camera when rewind scrubbing
- Backend(Build): Compile error building without hashfile present when build doesn't use hashfile
- Backend(Core): Slowdown due to excessively opening search handles during plugin hot reloading
- Backend(Core): Crashing when unloading a plugin that doesn't reload during hot-reload process
- Backend(Core): XInput state not clearing when controller unplugged

## [0.1.5] - 2024-05-12

### Added

- Build: Compile `dinput.dll` via Zig
- Plugin: Collision Viewer ([#3](https://github.com/everalert/annodue/pull/3))

### Changed

- Build: Convert tooling to cross-platform compatible code
- Core: Migrated `patch/util/racer*` to `racer` module

### Removed

- Build: `-Ddbp` option

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

[unreleased]: https://github.com/everalert/annodue/compare/0.1.6...HEAD
[0.1.6]: https://github.com/everalert/annodue/compare/0.1.5...0.1.6
[0.1.5]: https://github.com/everalert/annodue/compare/0.1.4...0.1.5
[0.1.4]: https://github.com/everalert/annodue/compare/0.1.3...0.1.4
[0.1.3]: https://github.com/everalert/annodue/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/everalert/annodue/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/everalert/annodue/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/everalert/annodue/releases/tag/0.1.0
