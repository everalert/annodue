# User Manual

> [!WARNING]
> Annodue is in early active development. Everything indicated in this document is 
> volatile and subject to change, including overall structure and naming. Several 
> major features are not yet implemented. In future updates, you may be required to 
> redo your configuration if there are breaking changes to the settings format.

### Key Information & Notes

- Hold `Shift` while launching the game to run it in vanilla mode (no Annodue modifications).
- Press `P` to toggle Practice Mode. 
    - Features which change gameplay or provide an unfair information advantage
  	  require Practice Mode to be in effect. See [features](#features) for details.
    - Practice Mode can be toggled ON at any time. Practice Mode cannot be toggled
      OFF during a race, except for before the countdown starts.
- Control configuration is planned, but currently not possible. Similarly, DirectInput 
  support for Annodue interactions is planned, but not yet implemented.
- If you normally need to run a specific `dinput.dll` to prevent the game from 
  crashing, you can place it in the `annodue` folder and the game will use it.

### Settings

<!-- 
	NOTE: candidates for Practice Mode restriction:
		- QOL: Fast countdown timer
		- QOL: F1-F4 camera input fix
		- Cam7: General restriction
		- Cam7: Teleport pod to camera
		
	NOTE: known Practice Mode restriction issues:
		- QOL: some settings not being disabled if Practice Mode is toggled OFF before race countdown
-->

> [!IMPORTANT]
> Annodue does not ship with a settings file. To create a settings file, load the
> game to the title screen after installing Annodue.

- Settings can be changed by editing `annodue/settings.ini`.
- Some settings will also be updated when using various features, so that the
  effect is persistent across game sessions. See [features](#features) for details.
- Generally, settings can be changed by editing the settings file while the game
  is running, and the effect can be seen without restarting the game. Some exceptions
  apply; see [features](#features) for details.
- The settings file will be updated by Annodue at the following times:
  	- When first reaching the title screen.
  	- On loading screen transitions. When going between race and menu scenes, or
  	  when restarting a race.
  	- On menu transitions. For example, when selecting a vehicle and moving to the
  	  track select.
  	- On race state transitions. For example, when the camera sweep ends and the
  	  countdown begins.
  	- At special moments defined by plugins. See [features](#features) for details.
- An in-game interface for editing settings is planned, but not yet implemented.

#### Setting Types

Each setting uses a specific format. Refer to the following table to know how each 
setting should be formatted.

|Type|Possible Values|Note|
|:---|:---|:---|
|`bool`|`1`, `on` or `true` to enable|&nbsp;
|`u32` |`0` to `4294967295`|whole number
|`i32` |`-2147483648` to `2147483647`|whole number
|`f32` |any decimal number|rounded to 2 decimal places
|`str` |any ascii text up to 63 characters long|individual setting may only accept specific strings

#### Global Settings

Top-level settings that do not belong to a specific feature group.

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`SETTINGS_SAVE_AUTO`    |`bool`|`on`|&nbsp;
|`SETTINGS_SAVE_DEFAULTS`|`bool`|`on`|Save settings to file even when not customized
|`AUTO_UPDATE`           |`bool`|`on`|&nbsp;
|`PLUGIN_HOT_RELOAD`     |`bool`|`on`|&nbsp;

## Features

#### Feature Summary

- Plugin system (custom plugins disabled for now)
- New game features
	- Free Camera
	- Savestates & Rewinding
	- Quick Race Menu - setup a new race without going back to the cantina
    - Collision visualization (by [tly000](https://github.com/tly000))
	- Input display
	- Extended post-race summary
	- Extended race UI overlay
	- Framerate limiter
	- Custom font support, shipping with HD font
- Quality of life
	- Pause mapped to gamepad
	- Race restart hotkey
	- Showing milliseconds digit on all timers
	- Configurable defaults for free-play racers and laps
	- Skip planet cutscenes
	- Skip podium cutscene
	- Fast countdown timer
	- Double mouse cursor fix
	- Jinn Reeso and Cy Yunga cheat toggling
	- Cy Yunga cheat audio fix
	- Map rendering hi-res text fix
	- Viewport edge gap fix
	- Collisions disabled in multiplayer
	- Pod upgrades in multiplayer
- Cosmetic
	- Triggered race events displayed on UI
	- Rainbow-colored race UI elements

### Free Camera

Usable both in race and in cantina. Controlling the camera will not override game 
inputs, meaning you can still drive around and navigate menus while in free look.

- FPS-style controls
- Adjustable speed, smoothness and mouse sensitivity
- Pan-and-orbit alternate mode
- Planar movement alternate mode
- Look at pod hotkey
- Teleport pod to camera hotkey
- Ability to disable race inputs while in free camera
- Ability to disable UI while in free camera

The following features affect saved settings during normal use:
- Disabling race inputs: toggling with hotkey affects `default_disable_input` setting
- Disabling UI: toggling with hotkey affects `default_hide_ui` setting

#### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Toggle                 |`0`                 |`Back`     |&nbsp;
|Move                   |`W A S D`           |`L Stick`  |&nbsp;
|Look                   |`Mouse` or `↑ ↓ ← →`|`R Stick`  |&nbsp;
|Z-move up              |`Space`             |`L Trigger`|&nbsp;
|Z-move down            |`Shift`             |`R Trigger`|&nbsp;
|Movement speed up      |`E`                 |`RB`       |&nbsp;
|Movement speed down    |`Q`                 |`LB`       |up+down to return to default
|Rotation speed up      |`Z`                 |`RSB`      |&nbsp;
|Rotation speed down    |`C`                 |`LSB`      |up+down to return to default
|Damping                |`X`                 |`Y`        |hold to edit movement/rotation smoothness instead of speed
|Toggle planar movement |`Tab`               |`B`        |&nbsp;
|Toggle hiding UI       |`6`                 |&nbsp;     |&nbsp;
|Toggle disabling input |`7`                 |&nbsp;     |pod will not drive when on
|Pan-and-orbit mode     |`RCtrl`             |`X`        |hold
|Move pod to camera     |`Bksp`              |`X`        |hold while exiting free-cam
|Look at pod            |`\`                 |&nbsp;     |will set rotation point to pod in pan-and-orbit mode

#### Settings

Configured under `[cam7]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`                    |`bool`|`off` |&nbsp;
|`fog_patch`                 |`bool`|`on`  |override normal fog
|`fog_disable`               |`bool`|`off` |infinite draw distance (needs `fog_patch` on)
|`visuals_patch`             |`bool`|`on`  |show entire track
|`sfx_volume`                |`f32` |`0.7` |0.0 to 1.0
|`flip_look_x`               |`bool`|`off` |Invert x-axis rotation
|`flip_look_y`               |`bool`|`off` |Invert y-axis rotation
|`flip_look_x_inverted`      |`bool`|`off` |Invert x-axis rotation while upside-down
|`stick_deadzone_inner`      |`f32` |`0.05`|0.0 to 0.5
|`stick_deadzone_outer`      |`f32` |`0.95`|0.5 to 1.0
|`default_move_speed`        |`u32` |`3`   |0 to 6
|`default_move_smoothing`    |`u32` |`2`   |0 to 3
|`default_rotation_speed`    |`u32` |`3`   |0 to 4
|`default_rotation_smoothing`|`u32` |`0`   |0 to 3
|`default_planar_movement`   |`bool`|`off` |movement is always level; turn off to allow vertical movement based on view angle
|`default_hide_ui`           |`bool`|`off` |&nbsp;
|`default_disable_input`     |`bool`|`off` |&nbsp;
|`mouse_dpi`                 |`u32` |`1600`|reference for mouse sensitivity calculations; does not change mouse
|`mouse_cm360`               |`f32` |`24`  |physical range of motion for one 360° camera rotation in cm<br>if you don't know what that means, just treat this number as sensitivity

### Savestates & Rewind

> [!IMPORTANT]
> All features in this category are restricted to Practice Mode

- Set and restore a save point to quickly retry parts of a track
- Time delay when restoring a state, to help with getting your hand back in position in time
- Freeze, rewind and scrub to any moment in the run

#### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Save State       |`1`|`D-Down` |&nbsp;
|Reload State     |`2`|`D-Up`   |Will load beginning of race if no state saved
|Toggle Scrub Mode|`2`|`D-Up`   |Double-tap `Reload State`
|Scrub Back       |`3`|`D-Left` |Hold to rewind
|Scrub Forward    |`4`|`D-Right`|Hold to fast-forward

#### Settings

Configurable under `[savestate]`

> [!WARNING]
> Setting `load_delay` too low can interfere with ability to enter scrub mode

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`savestate_enable`|`bool`|`off`|&nbsp;
|`load_delay`      |`u32` |`500`|Amount of time to delay restoring a savestate in milliseconds

### Input Display

Simple input visualization during races. Shows inputs as they are after the game finishes device read merging and post-processing.

#### Settings

Configurable under `[inputdisplay]`

> [!NOTE]
> Game considers screen to be 640x480 regardless of window size

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`|`bool`|`off`|&nbsp;
|`pos_x` |`i32` |`420`|Screen X-position
|`pos_y` |`i32` |`432`|Screen Y-position

### Overlay

- Show individual lap times during race
- Show FPS readout, with simplified option

The following additional features are available in Practice Mode:
- Show time to overheat and underheat
- Show death count
- Show fall timer
- Show MFG (bounce glitch) timer
- Show detailed speed readout, with raw speed only option
- Show speed effects from FAST, SLOW and SWST terrain

#### Settings
Configured under `[overlay]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`            |`bool`|`off`|&nbsp;
|`show_fps`          |`bool`|`on` |&nbsp;
|`show_fps_simple`   |`bool`|`off`|&nbsp;
|`show_speed`        |`bool`|`on` |&nbsp;
|`show_speed_raw`    |`bool`|`on` |&nbsp;
|`show_speed_offsets`|`bool`|`on` |&nbsp;
|`show_lap_times`    |`bool`|`on` |&nbsp;
|`show_heat_timer`   |`bool`|`on` |&nbsp;
|`show_death_count`  |`bool`|`on` |&nbsp;
|`show_fall_timer`   |`bool`|`on` |&nbsp;

### Quality of Life

> [!NOTE]
> Opening and closing the Quick Race Menu will trigger a settings save.

- Fix double mouse cursor
- Patch Jinn Reeso and Cy Yunga cheats to also toggle off
- Fix Cy Yunga cheat audio
- Fix map rendering hi-res text
- Fix changing camera with F1-F4 keys not persisting after a crash
- Fix 1px gap on right and bottom of viewport when rendering sprites at the edge
    - This may cause the sprite to be clipped instead, depending on your resolution settings
- Map controller `Start` to `Esc`
- Race restart hotkey
- Quick Race Menu
- Post-race stats readout
- Show true values of times on post-race screen, via the underlying hexadecimal number
- Show milliseconds on all timers
- Skip planet cutscenes
- Skip podium cutscene
- Custom default number of racers
- Custom default number of laps
- Custom default race camera, with option to auto-update
- Fast countdown timer
- Run game in background
- Patch truguts cheat to give more truguts and have infinite uses
- Auto-reset on missed first boost, underheat, engine fire and death
- Remember track selection between game sessions, similar to vehicle selection
- Fast menu navigation
- Allow D-PAD input for menu navigation
- Limit framerate during races (configurable via Quick Race Menu)
- N64 Pitch input toggle (experimental) (accessible via Quick Race Menu)

The following features have Practice Mode limitations:
- Limit framerate during races: actual FPS will only change when Practice Mode is OFF or the race is restarted
- N64 Pitch input toggle: active in Practice Mode only

The following features affect saved settings during normal use:
- Custom default number of racers: changing number of racers in-game will affect the `default_racers` setting
- Custom default number of laps: changing number of laps in-game will affect the `default_laps` setting
- Custom default race camera: changing the race camera will affect the `default_camera` setting if `default_camera_auto` is `on`
- Remember track selection: changing track selection in-game will affect the `trackselect_last` setting
- Quick Race Menu: FPS limiter: applying a new FPS limit will affect the `fps_limiter_default` setting
- Quick Race Menu: Favorite vehicles: toggling a vehicle favorite will affect the `favorite_characters` setting

#### Quick Race Menu Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Open                      |`Esc`       |`Start`      |Hold or double-tap while unpaused
|Close                     |`Esc`       |`B`          |&nbsp;
|Navigate                  |`↑ ↓`       |`D-Up` `D-Dn`|&nbsp;
|Scroll item options       |`← →`       |`D-Lf` `D-Rt`|&nbsp;
|Tab-scroll item options   |`Home` `End`|`LB` `RB`    |&nbsp;
|Interact                  |`Enter`     |`A`          |Special behavior depending on menu item
|Quick Confirm             |`Space`     |`Start`      |"Race!" immediately from any menu item
|All Upgrades OFF          |Tab-left    |Tab-left     |While selecting any upgrade
|All Upgrades MAX          |Tab-right   |Tab-right    |While selecting any upgrade
|Apply FPS immediately     |Interact    |Interact     |While selecting `FPS` (Practice Mode only)
|Scroll FPS preset         |Tab-scroll  |Tab-scroll   |While selecting `FPS`
|Swap track order          |Interact    |Interact     |While selecting `TRACK`
|Scroll track by planet    |Tab-scroll  |Tab-scroll   |While selecting `TRACK` in `PLANET` order
|Scroll track by circuit   |Tab-scroll  |Tab-scroll   |While selecting `TRACK` in `CIRCUIT` order
|Toggle vehicle as favorite|Interact    |Interact     |While selecting `VEHICLE`
|Scroll favorite vehicle   |Tab-scroll  |Tab-scroll   |While selecting `VEHICLE`

#### Other QOL Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Clear track Best Lap     |`1+Backspace`|&nbsp;      |On track detail screen
|Clear track 3-Lap Record |`3+Backspace`|&nbsp;      |On track detail screen
|Race restart             |`Esc+Tab`    |`Back+Start`|&nbsp;

#### Settings

Configured under `[qol]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`quick_restart_enable`       |`bool`|`off` |&nbsp;
|`quick_race_menu_enable`     |`bool`|`off` |&nbsp;
|`ms_timer_enable`            |`bool`|`off` |&nbsp;
|`ms_timer_hud_enable`        |`bool`|`off` |Timer on the race HUD
|`ms_timer_finish_enable`     |`bool`|`off` |Timers shown after finishing a race, before the results screen
|`fps_limiter_enable`         |`bool`|`off` |&nbsp;
|`fps_limiter_default`        |`u32` |`24`  |&nbsp;
|`skip_planet_cutscenes`      |`bool`|`off` |&nbsp;
|`skip_podium_cutscene`       |`bool`|`off` |&nbsp;
|`default_racers`             |`u32` |`12`  |1 to 12
|`default_laps`               |`u32` |`3`   |1 to 5
|`default_camera`             |`u32` |`1`   |1,2,4,5
|`default_camera_auto`        |`bool`|`off` |&nbsp;
|`fast_countdown_enable`      |`bool`|`off` |&nbsp;
|`fast_countdown_duration`    |`f32` |`1.00`|0.05 to 3.00
|`fix_viewport_edges`         |`bool`|`off` |May cause sprites at edge to be slightly cut off
|`run_in_background`          |`bool`|`off` |&nbsp;
|`autoreset_enable`           |`bool`|`off` |&nbsp;
|`autoreset_dead_enable`      |`bool`|`off` |&nbsp;
|`autoreset_dead_delay`       |`f32` |`0.50`|&nbsp;
|`autoreset_fire_enable`      |`bool`|`off` |&nbsp;
|`autoreset_fire_delay`       |`f32` |`3.00`|time limit per engine fire
|`autoreset_firstboost_enable`|`bool`|`off` |&nbsp;
|`autoreset_firstboost_delay` |`f32` |`0.25`|time limit from when the first boost is ready
|`autoreset_underheat_enable` |`bool`|`off` |&nbsp;
|`autoreset_underheat_delay`  |`f32` |`3.00`|time limit per underheat
|`trackselect_remember`       |`bool`|`off` |apply `trackselect_last` to the track selection menu
|`trackselect_last`           |`u32` |`0`   |0 to 24
|`fast_navigation`            |`bool`|`off` |&nbsp;
|`dpad_navigation`            |`bool`|`off` |&nbsp;
|`show_postrace_times_hex`    |`bool`|`off` |&nbsp;
|`clear_records_enable`       |`bool`|`off` |&nbsp;
|`favorite_characters`        |`u32` |`0`   |bitfield where character id = nth bit
|`menu_track_order`           |`str` |`0`   |`PLANET` or `CIRCUIT`

### Collision Viewer

> [!NOTE]
> Opening and closing the Collision Viewer menu will trigger a settings save.

Credit to ([tly000](https://github.com/tly000)) for plugin.

- Visualize collision faces
- Visualize collision mesh
- Visualize spline

#### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Open/Close Menu      |`9`       |&nbsp; |&nbsp;
|Toggle visualization |`8`       |&nbsp; |&nbsp;

#### Settings

Configured under `[collisionviewer]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`depth_bias`           |`i32`|`10`|correct misalignment between game and collision visuals; this setting is updated when adjusting depth bias in the Collision Viewer menu

### Font

- High-resolution fonts
- Custom font loading system, shipping with existing high definition font (set `font` to `HD`)
- Adjust font glyphs for better appearance and character support
- Bugfix font glyph UV mapping corruption during clipping
- Ability to display font testing text
- (dev-only) Ability to dump base game font data to file

To use a custom font, place the font in `<game>/annodue/custom/font` and set `font`
to its filename without the path or extension. For example, the font 
`<game>/annodue/custom/font/HD.gif` should be written as `HD` in the setting.

The font can be changed any number of times without closing the game. In future, 
this will be configurable via an in-game menu.

For information about creating custom fonts, see: `<game>/annodue/images/font-template`

#### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Show font test text    |`O` |&nbsp; |&nbsp;
|Dump base font data    |`I` |&nbsp; |(disabled in release)
|Dump base font glyphs  |`E` |&nbsp; |(disabled in release)
|Soft-toggle font system|`K` |&nbsp; |(disabled in release)
|Soft-toggle user font  |`L` |&nbsp; |(disabled in release)

#### Settings

Configurable under `[font]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`           |`bool`  |`on`   |enable custom font system and basic font fixes
|`font`             |`string`|`STOCK`|name of gif file (in `/annodue/custom/font`) used for currently shown font; `STOCK` displays base game font with fixes
|`can_show_test`    |`bool`  |`off`  |enable displaying font test text
|`can_dump_data`    |`bool`  |`off`  |(dev-only) enable dumping source ingame font data to /annodue/developer
|`can_dump_glyphs`  |`bool`  |`off`  |(dev-only) enable dumping glyph binary data of currently loaded font
|`can_toggle_system`|`bool`  |`off`  |(dev-only) enable soft-disabling custom font system
|`can_toggle_custom`|`bool`  |`off`  |(dev-only) enable toggling between stock and custom fonts

### Cosmetic

- Rotating rainbow colors for race UI elements
- Show race triggers via game notification system
- (disabled) High-fidelity audio
- (disabled) Load sprites from TGA

#### Settings

Configurable under `[cosmetic]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`rainbow_enable`       |`bool`|`off`|&nbsp;
|`rainbow_value_enable` |`bool`|`off`|Values shown above `LAP`, `TIME` and `POS`
|`rainbow_label_enable` |`bool`|`off`|The `LAP`, `TIME` and `POS` text itself
|`rainbow_speed_enable` |`bool`|`off`|&nbsp;
|`patch_audio`          |`bool`|`off`|*Disabled*
|`patch_tga_loader`     |`bool`|`off`|*Disabled*

### Multiplayer

- Disable multiplayer collisions
- Max upgrades in multiplayer
- Patch GUID to prevent joined players using different multiplayer settings

#### Settings

Configurable under `[multiplayer]`

> [!WARNING]
> All settings in this section require game restart to apply

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`    |`bool`|`off`|&nbsp;
|`patch_guid`|`bool`|`off`|&nbsp;
|`patch_r100`|`bool`|`off`|Use R-100 traction in the patched upgrade stack

### Gameplay Tweak

*Disabled in current release*

- Patch `DeathSpeedMin` (minimum speed required to die from collision)
- Patch `DeathSpeedDrop` (minimum speed loss in 1 frame to die from collision)

#### Settings

Configurable under `[gameplay]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`death_speed_mod_enable`|`bool`|`off`|&nbsp;
|`death_speed_min`       |`f32` |`325`|&nbsp;
|`death_speed_drop`      |`f32` |`140`|&nbsp;

### Developer Tools

*Disabled in current release*

- Visualize matrices via hijacking debug spline markers

#### Settings

Configurable under `[developer]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`visualize_matrices`|`bool`|`off`|&nbsp;

### RTrigger System

- System for plugin developers to implement custom track behaviours
- Show race triggers via game notification system

#### Settings

Configurable under `[core/RTrigger]`

|Option|Type|Default|
|:---|:---|:---|
|`notify_trigger`|`bool`|`off`

### Asset Buffer Patches

- Patches to enable loading larger amounts of data from asset files
- NOTE: Changing the actual amount of memory available for loading assets is not yet implemented

#### Settings

Configurable under `[core/GAssetBuffer]`

> [!WARNING]
> All settings in this section require game restart to apply

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`texbuf_enable`|`bool`|`off`|&nbsp;
|`texbuf_size`|`u32`|`5120`|Expanded TextureBlock texture limit (`1700..8192`)
