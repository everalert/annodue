#User Manual

######*Disclaimer*

*Annodue is in early active development. Everything indicated in this document is volatile and subject to change, including overall structure and naming. Several major features are not yet implemented. In future updates, you may be required to redo your configuration if there are breaking changes to the settings format.*

####Key Information & Notes

Hold `Shift` while launching the game to launch it without any modifications.

Press `P` to toggle Practice Mode. This mode is required to use certain features, and cannot be toggled off during a race.

Control configuration is planned, but currently not possible. Similarly, DirectInput support is planned, but not yet implemented.

Settings can be changed by editing `annodue/settings.ini`. Changes will be reflected in the game in realtime when you save this file, unless indicated otherwise below. In-game editing of settings is planned, but not yet implemented.

##Features

###Free Camera

Usable both in race and in cantina. Controlling the camera will not override game inputs, meaning you can still drive around and navigate menus while in free look.

#####Controls

|Action|Keyboard|XInput|
|:---|:---|:---|
|Toggle     |`0`                 |`Back`
|XY-move    |`W A S D`           |`L Stick`
|XY-rotate  |`Mouse` or `↑ ↓ ← →`|`R Stick`
|Z-move up  |`Space`             |`L Trigger`
|Z-move down|`Shift`             |`R Trigger`

#####Settings

Configured under `[cam7]`

|Option|Type|Note|
|:---|:---|:---|
|`enable`     |`bool`|&nbsp;
|`flip_look_x`|`bool`|Invert x-axis rotation
|`flip_look_y`|`bool`|Invert y-axis rotation
|`mouse_dpi`  |`u32` |reference for mouse sensitivity calculations; does not change mouse
|`mouse_cm360`|`f32` |physical range of motion for one 360° camera rotation in cm<br>if you don't know what that means, just treat this number as sensitivity

###Savestates & Rewind

*Usable in Practice Mode only*

- Set and restore a save point to quickly retry parts of a track
- Time delay when restoring a state, to help with getting your hand back in position in time
- Freeze, rewind and scrub to any moment in the run

#####Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Save State       |`1`|`D-Down` |&nbsp;
|Reload State     |`2`|`D-Up`   |Will load beginning of race if no state saved
|Toggle Scrub Mode|`2`|`D-Up`   |Press during reload delay when toggling on (i.e. double-tap reload)
|Scrub Back       |`3`|`D-Left` |Hold to rewind
|Scrub Forward    |`4`|`D-Right`|Hold to fast-forward

#####Settings

Configurable under `[savestate]`

|Option|Type|Note|
|:---|:---|:---|
|`savestate_enable`|`bool`|&nbsp;
|`load_delay`      |`u32` |Amount of time to delay restoring a savestate in milliseconds

*Setting `load_delay` too low can interfere with ability to enter scrub mode*

###Input Display

Simple input visualization during races. Shows inputs as they are after the game finishes device read merging and post-processing.

#####Settings

Configurable under `[inputdisplay]`

|Option|Type|
|:---|:---|
|`enable`|`bool`|
|`pos_x` |`i32` |
|`pos_y` |`i32` |

*Game considers screen to be 640x480 regardless of window size*

###Overlay

*Usable in Practice Mode only*

- Show individual lap times during race
- Show time to overheat and underheat

#####Settings
Configured under `[overlay]`

|Option|Type|
|:---|:---|
|`enable`|`bool`|

###Quality of Life

- Fix double mouse cursor
- Map controller `Start` to `Esc`
- Race restart hotkey -- `F1 + Esc` or `Back + Start`
- Quick Race Menu
- End-race stats readout
- Show milliseconds on all timers
- Limit framerate during races (configurable via Quick Race Menu)
- Skip planet cutscenes
- Custom default number of racers
- Custom default number of laps

#####Quick Race Menu Controls

|Action|Keyboard|XInput|Note|
|:---|:---|:---|:---|
|Open/Close              |`Esc`     |`Start`       |Press during normal pause delay (i.e. double-tap pause)
|Navigate                |`↑ ↓ ← →` |`D-Pad`       |&nbsp;
|Interact                |`Space`   |`A`           |&nbsp;
|Quick Confirm           |`Enter`   |`B`           |&nbsp;
|Set all upgrades to none|`Home`    |`LB`          |&nbsp;
|Set all upgrades to max |`End`     |`RB`          |&nbsp;

#####Settings

Configured under `[qol]`

|Option|Type|Note|
|:---|:---|:---|
|`quick_restart_enable`  |`bool`|&nbsp;
|`quick_race_menu_enable`|`bool`|&nbsp;
|`ms_timer_enable`       |`bool`|&nbsp;
|`fps_limiter_enable`    |`bool`|&nbsp;
|`skip_planet_cutscenes` |`bool`|&nbsp;
|`default_racers`        |`u32` |1 to 12
|`default_laps`          |`u32` |1 to 5

###Cosmetic

- High-resolution fonts
- Rotating rainbow colors for race UI elements
- Show race triggers via game notification system
- (disabled) High-fidelity audio
- (disabled) Load sprites from TGA

#####Settings

Configurable under `[cosmetic]`

|Option|Type|Note|
|:---|:---|:---|
|`rainbow_enable`       |`bool`|&nbsp;
|`rainbow_value_enable` |`bool`|Values shown above `LAP`, `TIME` and `POS`
|`rainbow_label_enable` |`bool`|The `LAP`, `TIME` and `POS` text itself
|`rainbow_speed_enable` |`bool`|&nbsp;
|`patch_fonts`          |`bool`|*Requires game restart to apply*
|`patch_trigger_display`|`bool`|*Requires game restart to apply*
|`patch_audio`          |`bool`|*Disabled*
|`patch_tga_loader`     |`bool`|*Disabled*

###Multiplayer

- Disable multiplayer collisions
- Max upgrades in multiplayer
- Patch GUID to prevent joined players using different multiplayer settings

#####Settings

Configurable under `[multiplayer]`

*All settings in this section require game restart to apply*

|Option|Type|Note|
|:---|:---|:---|
|`enable`    |`bool`|&nbsp;
|`patch_guid`|`bool`|&nbsp;
|`patch_r100`|`bool`|Use R-100 traction in the patched upgrade stack

###Gameplay Tweak

*Disabled in current release*

- Patch DeathSpeedMin (minimum speed required to die from collision)
- Patch DeathSpeedDrop (minimum speed loss in 1 frame to die from collision)

#####Settings

Configurable under `[gameplay]`

*All settings in this section require game restart to apply*

|Option|Type|
|:---|:---|
|`death_speed_mod_enable`|`bool`|
|`death_speed_min`       |`f32` |
|`death_speed_drop`      |`f32` |

###Developer Tools

*Disabled in current release*

- Dump font data to file on launch

#####Settings

Configurable under `[developer]`

*All settings in this section require game restart to apply*

|Option|Type|
|:---|:---|
|`dump_fonts`|`bool`|