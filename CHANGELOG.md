# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Cam7: analog deadzone customization via settings
- Cam7: ability to toggle planar movement with `TAB(kb) or B(xinput)`
- Cam7: pan and orbit with `RCtrl(kb) or X(xinput)`
- Cam7: cycle movement speed with `Q or LB` and `E or RB`
- Cam7: cycle rotation speed with `Z or LSB` and `C or RSB`
- Cam7: cycle smoothing instead of speed by holding `X or Y(xinput)` while pressing movement/rotation buttons
- Cam7: return movement or rotation to default by pressing both up+down together
- Cam7: toggle hiding ui with `6`
- Cam7: toggle disabling pod input with `7`
- Cam7: orient camera to pod with `\`
- Cam7: move pod to camera by holding `BKSP(kb) or A(xinput)` when exiting free-cam
- Cam7: sfx during camera motion
- Core: notify on plugin reload
- CollisionViewer: depth bias customization for correcting model-collision visual mismatch ([#5](https://github.com/everalert/annodue/pull/5))
- Developer: Visualization of matrices via hijacking the debug spline markers
- Savestate: Flame effects (Smok entities) added to saved state
- Savestate: Dust clouds (Toss entities) added to saved state
- InputDisplay: Now shows inputs from savestate rewind
- QOL: Option to skip podium cutscene
- QOL: Option to remove 1px gap at screen edge
- Setting: 'cam7' -> 'stick_deadzone_inner'
- Setting: 'cam7' -> 'stick_deadzone_outer'
- Setting: 'cam7' -> 'default_move_speed'
- Setting: 'cam7' -> 'default_move_smoothing'
- Setting: 'cam7' -> 'default_rotation_speed'
- Setting: 'cam7' -> 'default_rotation_smoothing'
- Setting: 'cam7' -> 'default_planar_movement'
- Setting: 'cam7' -> 'default_hide_ui'
- Setting: 'cam7' -> 'default_disable_input'
- Setting: 'cam7' -> 'flip_look_x_inverted'
- Setting: 'cam7' -> 'sfx_volume'
- Setting: 'cam7' -> 'fog_patch'
- Setting: 'cam7' -> 'fog_disable'
- Setting: 'cam7' -> 'visuals_patch'
- Setting: 'collisionviewer' -> 'depth_bias'
- Setting: 'developer' -> 'visualize_matrices'
- Setting: `overlay` -> `show_fps` `show_lap_times` `show_heat_timer` `show_death_count` `show_fall_timer`
- Setting: `SETTING_SAVE_DEFAULTS` `SETTINGS_SAVE_AUTO` `PLUGIN_HOT_RELOAD`
- Setting: some settings now saved between sessions by syncing settings file with game actions - `cam7->default_disable_input` `cam7->default_hide_ui` `collisionviewer->depth_bias` `qol->default_laps` `qol->default_racers` `qol->fps_limiter_default`
- Backend(Core): `appinfo` module for externally-facing defs
- Backend(Core): `GDRAW_VERSION` (now `4`) added to Compatibility Version sum
- Backend(Core): custom triggers via `RTrigger` module/api
- Backend(Core): custom terrain via `RTerrain` module/api
- Backend(Core): added `RTerrainRequest` `RTerrainRelease` `RTerrainReleaseAll` to global functions
- Backend(Core): added `RTriggerRequest` `RTriggerRelease` `RTriggerReleaseAll` to global functions
- Backend(Core): added `ASettingSectionOccupy` `ASettingSectionVacate` `ASettingSectionRunUpdate` `ASettingOccupy` `ASettingVacate` `ASettingVacateAll` `ASettingUpdate` `ASettingSectionResetDefault` `ASettingSectionResetFile` `ASettingSectionClean` `ASettingResetAllDefault` `ASettingResetAllFile` `ASettingCleanAll` `ASettingSave` `ASettingSaveAuto` to global functions
- Backend(Core): enforcing semantic versioning for plugins
- Backend(Core): enforcing minimum implemented functions for core-side plugins
- Backend(Core): `OnPluginInit` `OnPluginLateInit` `OnPluginDeinitA` hook functions, usable by core-side plugins
- Backend(Core): plugin identity tracking, for use with handle-based resources
- Backend(Core): `GDraw` global api, for unrestricted drawing
- Backend(Core): `GDraw` layers `Default`, `DefaultP`, `Overlay`, `OverlayP`, `System`, `SystemP`
- Backend(Core): `GDrawText`, `GDrawRect`, `GDrawRectBdr` to global functions
- Backend(Core): `HideRaceUI` global api, adjusted existing plugins to check for this
- Backend(Core): `GHideRaceUIEnable` `GHideRaceUIDisable` `GHideRaceUIIsHidden` global functions
- Backend(RacerLib): Added `Random`, `Vector`, `Matrix`, `Model`
- Backend(RacerLib): Added new defs to `entity/Hang`, `entity/Jdge`, `Input`, `Timing`
- Backend(RacerLib): Added new defs to `Model`, `Quad`, `Text`
- Backend(RacerLib): Added new defs to `entity`, `entity/Test`, `entity/Toss`, `entity/Trig`
- Backend(RacerLib): Added `Random`, `Vector`, `Matrix`, `Model`
- Backend(RacerLib): Added new defs to `entity/Hang`, `entity/Jdge`, `Input`, `Timing`, `Quad`
- Backend(Util): Added `handle_map` and `handle_map_static` for handle-based resource management
- Backend(Util): Added `deadzone` util, `spatial` util defs
- Backend(Util): `PCompileError`, `PPanic` to debug util for formatted compile/panic error messages
- Backend(Util): x86 - helper functions and defs

### Changed

- Cam7: lateral movement speed - `650` -> `125..16000`
- Cam7: vertical movement speed - `350` -> `62.5..8000`
- Cam7: movement smoothing - `8` -> `none,16,8,4`
- Cam7: movement speed curve - `quadratic` -> `quartic` 
- Cam7: rotation speed - `360` -> `80..810`
- Cam7: rotation smoothing - `none` -> `none,36,24,12,6`
- Core: reworked toast animation/aesthetics
- Backend(Build): release versioning now based on `appinfo` module
- Backend(Core): Global Function version `15` to `28`
- Backend(Core): Global Functions renamed `Game*` to `G*` (e.g. `GameFreezeEnable` to `GFreezeEnable`)
- Backend(Core): Global Functions `GFreezeEnable->GFreezeOn` `GFreezeDisable->GFreezeOff` `GFreezeIsFrozen->GFreezeIsOn`
- Backend(Core): Global Functions `GHideRaceUIEnable->GHideRaceUIOn` `GHideRaceUIDisable->GHideRaceUIOff` `GHideRaceUIIsHidden->GHideRaceUIIsOn`
- Backend(Core): GFreeze switched from plugin-defined identifiers to internal ids
- Backend(Core): GHideRaceUI switched from plugin-defined identifiers to internal ids
- Backend(Core): moved `cosmetic->show_trigger_display` functionality to `RTrigger`
- Backend(Util): make rewind compression logic available in `temporal_compression` util
- Backent(Util): x86 - migrate `push_*`, `pop_*` functions to generalized `push`, `pop`

### Removed

- Backend(Build): `-Dver` option in `release` builds
- Backend(Build): `-Dminver` option in `release` builds

### Fixed

- Cam7: Corrected steering while upside-down to be more intuitive
- Cam7: Corrected Y/Z movement while upside-down in planar movement mode
- Cam7: Minimap lagging behind camera motion while in free cam
- Cam7: Faster rotation toward diagonals with keyboard input
- Cam7: Z-orientation not straightening out when transitioning into free-cam
- Cam7: Main camera being in first-person internal (cam5) changing free-cam FOV
- Savestate: Rewind ignoring saved inputs
- Savestate: Rewind not restoring UI correctly
- Savestate: Stuttering during rewind scrubbing
- Savestate: Delayed camera when rewind scrubbing
- Backend(Build): compile error building without hashfile present when build doesn't use hashfile
- Backend(Core): slowdown due to excessively opening search handles during plugin hot reloading
- Backend(Core): crashing when unloading a plugin that doesn't reload during hot-reload process
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

[unreleased]: https://github.com/everalert/annodue/compare/0.1.5...HEAD
[0.1.5]: https://github.com/everalert/annodue/compare/0.1.4...0.1.5
[0.1.4]: https://github.com/everalert/annodue/compare/0.1.3...0.1.4
[0.1.3]: https://github.com/everalert/annodue/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/everalert/annodue/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/everalert/annodue/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/everalert/annodue/releases/tag/0.1.0
