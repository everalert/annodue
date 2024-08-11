# User Manual

##### *Disclaimer*

*Annodue is in early active development. Everything indicated in this document is volatile and subject to change, including overall structure and naming. Several major features are not yet implemented. In future updates, you may be required to redo your configuration if there are breaking changes to the settings format.*

#### Key Information & Notes

Hold `Shift` while launching the game to run it in vanilla mode (no Annodue modifications).

Press `P` to toggle Practice Mode. This mode is required to use certain features, and cannot be toggled off during a race.

Control configuration is planned, but currently not possible. Similarly, DirectInput support is planned, but not yet implemented.

If you normally need to run a specific `dinput.dll` to prevent the game from crashing, you can place it in the `annodue` folder and the game use it.

Settings can be changed by editing `annodue/settings.ini`. Changes will be reflected in the game in realtime when you save this file, unless indicated otherwise below. In-game editing of settings is planned, but not yet implemented.

##### Setting Types

|Type|Possible Values|Note
|:---|:---|:---|:---|
|`bool`|`1`, `on` or `true` to enable|&nbsp;
|`u32` |`0` to `4294967295`|whole number
|`i32` |`-2147483648` to `2147483647`|whole number
|`f32` |any decimal number|rounded to 2 decimal places
|`str` |any text up to 63 characters|individual setting may only accept specific strings

##### Global Settings

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`SETTINGS_SAVE_AUTO`    |`bool`|`on`|&nbsp;
|`SETTINGS_SAVE_DEFAULTS`|`bool`|`on`|Save settings to file even when not customized
|`AUTO_UPDATE`           |`bool`|`on`|&nbsp;
|`PLUGIN_HOT_RELOAD`     |`bool`|`on`|&nbsp;

## Features

##### Feature Summary

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
	- Hi-res fonts
	- Triggered race events displayed on UI
	- Rainbow-colored race UI elements

### Free Camera

Usable both in race and in cantina. Controlling the camera will not override game inputs, meaning you can still drive around and navigate menus while in free look.

##### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Toggle                 |`0`                 |`Back`     |&nbsp;
|XY-move                |`W A S D`           |`L Stick`  |&nbsp;
|XY-rotate              |`Mouse` or `↑ ↓ ← →`|`R Stick`  |&nbsp;
|Z-move up              |`Space`             |`L Trigger`|&nbsp;
|Z-move down            |`Shift`             |`R Trigger`|&nbsp;
|movement up            |`E`                 |`RB`       |&nbsp;
|movement down          |`Q`                 |`LB`       |up+down to return to default
|rotation up            |`Z`                 |`RSB`      |&nbsp;
|rotation down          |`C`                 |`LSB`      |up+down to return to default
|damping                |`X`                 |`Y`        |hold to edit movement/rotation smoothness instead of speed
|toggle planar movement |`Tab`               |`B`        |&nbsp;
|toggle hide ui         |`6`                 |&nbsp;     |&nbsp;
|toggle disable input   |`7`                 |&nbsp;     |pod will not drive when on
|pan and orbit mode     |`RCtrl`             |`X`        |hold
|move pod to camera     |`Bksp`              |`X`        |hold while exiting free-cam
|orient camera to pod   |`\`                 |&nbsp;     |will set rotation point to pod in pan/orbit mode

##### Settings

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
|`default_planar_movement`   |`bool`|`off` |movement is always level; turn off to move based on the view angle
|`default_hide_ui`           |`bool`|`off` |&nbsp;
|`default_disable_input`     |`bool`|`off` |&nbsp;
|`mouse_dpi`                 |`u32` |`1600`|reference for mouse sensitivity calculations; does not change mouse
|`mouse_cm360`               |`f32` |`24`  |physical range of motion for one 360° camera rotation in cm<br>if you don't know what that means, just treat this number as sensitivity

### Savestates & Rewind

*Usable in Practice Mode only*

- Set and restore a save point to quickly retry parts of a track
- Time delay when restoring a state, to help with getting your hand back in position in time
- Freeze, rewind and scrub to any moment in the run

##### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Save State       |`1`|`D-Down` |&nbsp;
|Reload State     |`2`|`D-Up`   |Will load beginning of race if no state saved
|Toggle Scrub Mode|`2`|`D-Up`   |Double-tap `Reload State`
|Scrub Back       |`3`|`D-Left` |Hold to rewind
|Scrub Forward    |`4`|`D-Right`|Hold to fast-forward

##### Settings

Configurable under `[savestate]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`savestate_enable`|`bool`|`off`|&nbsp;
|`load_delay`      |`u32` |`500`|Amount of time to delay restoring a savestate in milliseconds

*Setting `load_delay` too low can interfere with ability to enter scrub mode*

### Input Display

Simple input visualization during races. Shows inputs as they are after the game finishes device read merging and post-processing.

##### Settings

Configurable under `[inputdisplay]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`|`bool`|`off`|&nbsp;
|`pos_x` |`i32` |`420`|Screen X-position
|`pos_y` |`i32` |`432`|Screen Y-position

*Game considers screen to be 640x480 regardless of window size*

### Overlay

*Usable in Practice Mode only*

- Show individual lap times during race
- Show time to overheat and underheat
- Show death count
- Show fall timer
- Show FPS readout

##### Settings
Configured under `[overlay]`

|Option|Type|Default|
|:---|:---|:---|:---|
|`enable`          |`bool`|`off`|
|`show_fps`        |`bool`|`on` |
|`show_lap_times`  |`bool`|`on` |
|`show_heat_timer` |`bool`|`on` |
|`show_death_count`|`bool`|`on` |
|`show_fall_timer` |`bool`|`on` |

### Quality of Life

- Fix double mouse cursor
- Patch Jinn Reeso and Cy Yunga cheats to also toggle off
- Fix Cy Yunga cheat audio
- Fix map rendering hi-res text
- Fix 1px gap on right and bottom of viewport when rendering sprites at the edge
    - This may cause the sprite to be clipped instead, depending on your resolution settings
- Map controller `Start` to `Esc`
- Race restart hotkey -- `Esc + Tab` or `Back + Start`
- Quick Race Menu
- End-race stats readout
- Show milliseconds on all timers
- Limit framerate during races (configurable via Quick Race Menu)
- Skip planet cutscenes
- Skip podium cutscene
- Custom default number of racers
- Custom default number of laps
- Fast countdown timer

##### Quick Race Menu Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Open                   |`Esc`     |`Start` |Hold or double-tap while unpaused
|Close                  |`Esc`     |`B`     |&nbsp;
|Navigate               |`↑ ↓ ← →` |`D-Pad` |&nbsp;
|Interact               |`Enter`   |`A`     |&nbsp;
|Quick Confirm          |`Space`   |`Start` |&nbsp;
|All Upgrades OFF       |`Home`    |`LB`    |While highlighing any upgrade
|All Upgrades MAX       |`End`     |`RB`    |While highlighing any upgrade
|Scroll prev FPS preset |`Home`    |`LB`    |&nbsp;
|Scroll next FPS preset |`End`     |`RB`    |&nbsp;
|Scroll prev planet     |`Home`    |`LB`    |While highlighting `TRACK`
|Scroll next planet     |`End`     |`RB`    |While highlighting `TRACK`

##### Settings

Configured under `[qol]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`quick_restart_enable`   |`bool`|`off` |&nbsp;
|`quick_race_menu_enable` |`bool`|`off` |&nbsp;
|`ms_timer_enable`        |`bool`|`off` |&nbsp;
|`fps_limiter_enable`     |`bool`|`off` |&nbsp;
|`fps_limiter_default`    |`u32` |`24`  |&nbsp;
|`skip_planet_cutscenes`  |`bool`|`off` |&nbsp;
|`skip_podium_cutscene`   |`bool`|`off` |&nbsp;
|`default_racers`         |`u32` |`12`  |1 to 12
|`default_laps`           |`u32` |`3`   |1 to 5
|`fast_countdown_enable`  |`bool`|`off` |&nbsp;
|`fast_countdown_duration`|`f32` |`1.00`|0.05 to 3.00
|`fix_viewport_edges`     |`bool`|`off` |May cause sprites at edge to be slightly cut off

### Collision Viewer

Credit to ([tly000](https://github.com/tly000)) for plugin.

- Visualize collision faces
- Visualize collision mesh
- Visualize spline

##### Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Open/Close Menu      |`9`       |&nbsp; |&nbsp;
|Toggle visualization |`8`       |&nbsp; |&nbsp;

##### Settings

Configured under `[collisionviewer]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`depth_bias`           |`i32`|`10`|correct misalignment between game and collision visuals

### Cosmetic

- High-resolution fonts
- Rotating rainbow colors for race UI elements
- Show race triggers via game notification system
- (disabled) High-fidelity audio
- (disabled) Load sprites from TGA

##### Settings

Configurable under `[cosmetic]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`rainbow_enable`       |`bool`|`off`|&nbsp;
|`rainbow_value_enable` |`bool`|`off`|Values shown above `LAP`, `TIME` and `POS`
|`rainbow_label_enable` |`bool`|`off`|The `LAP`, `TIME` and `POS` text itself
|`rainbow_speed_enable` |`bool`|`off`|&nbsp;
|`patch_fonts`          |`bool`|`off`|*Requires game restart to apply*
|`patch_audio`          |`bool`|`off`|*Disabled*
|`patch_tga_loader`     |`bool`|`off`|*Disabled*

### Multiplayer

- Disable multiplayer collisions
- Max upgrades in multiplayer
- Patch GUID to prevent joined players using different multiplayer settings

##### Settings

Configurable under `[multiplayer]`

*All settings in this section require game restart to apply*

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`enable`    |`bool`|`off`|&nbsp;
|`patch_guid`|`bool`|`off`|&nbsp;
|`patch_r100`|`bool`|`off`|Use R-100 traction in the patched upgrade stack

### Gameplay Tweak

*Disabled in current release*

- Patch DeathSpeedMin (minimum speed required to die from collision)
- Patch DeathSpeedDrop (minimum speed loss in 1 frame to die from collision)

##### Settings

Configurable under `[gameplay]`

|Option|Type|Default|
|:---|:---|:---|:---|
|`death_speed_mod_enable`|`bool`|`off`|
|`death_speed_min`       |`f32` |`325`|
|`death_speed_drop`      |`f32` |`140`|

### Developer Tools

*Disabled in current release*

- Dump font data to file on launch
- Visualize matrices via hijacking debug spline markers

##### Settings

Configurable under `[developer]`

|Option|Type|Default|Note|
|:---|:---|:---|:---|
|`dump_fonts`        |`bool`|`off`|*Requires game restart to re-dump*
|`visualize_matrices`|`bool`|`off`|&nbsp;

### RTrigger System

- System for plugin developers to implement custom track behaviours
- Show race triggers via game notification system

##### Settings

Configurable under `[core/RTrigger]`

|Option|Type|Default|
|:---|:---|:---|
|`notify_trigger`|`bool`|`off`
