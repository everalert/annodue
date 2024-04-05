# Annodue

**A universal extension platform for *STAR WARS Episode I Racer* oriented toward speedrunning.**

######Functionality

- Plugin system (custom plugins disabled for now)
- New game features
	- Free Camera
	- Savestates & Rewinding
	- Quick Race Menu - setup a new race without going back to the cantina
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
	- Double mouse cursor fix
	- Collisions disabled in multiplayer
	- Pod upgrades in multiplayer
- Cosmetic
	- Hi-res fonts
	- Triggered race events displayed on UI
	- Rainbow-colored race UI elements

See [MANUAL.md](MANUAL.md) for full details and configuration.


######*Disclaimer*

*Annodue is in active development and not yet greenlit for submissions to Speedrun.com at the time of writing. For current information on how this can be used for speedrunning, please contact the speedrun moderators via the [Racer discord server](https://discord.com/servers/star-wars-episode-i-racer-441839750555369474) or [speedrun.com](https://www.speedrun.com/swe1r).*

## Installation

### From release

- Copy `dinput.dll` and the `annodue` folder into the game directory.

### From build

- Build the DLL files as described below.
- Copy the `annodue` folder into the game directory.
- Copy the compiled `dinput.dll` into the game directory.
- Copy the compiled `annodue.dll` into the `annodue` folder in the game directory.

## Configuration

Once installed, certain features can be toggled on or off.

For now, all configuration is done via `settings.ini` and effectively act as launch options.

1. In the game directory, open `/annodue/settings.ini` and edit the options.
2. Run the game.

If you are already running the game, it will need to be closed and re-launched to enable the new configuration.

## Building from source

The source code can be found on github: [annodue](https://github.com/everalert/annodue)

### annodue.dll

The main component of Annodue is written in Zig, and requires `Zig 0.11.0` to build.

1. Open a terminal in the project directory and run the following:
```
zig build
```

1. The compiled `annodue.dll` can be found in `/zig-out/lib`.

### dinput.dll (Windows MSYS2)

Run code in this section in a MinGW32 shell.

1. Install build dependencies:
```
pacman -S git mingw32/mingw-w64-i686-cmake mingw32/mingw-w64-i686-gcc
```

1. Move the project files to your MinGW32 filesystem, found at `C:/msys64/home/<user>/`. To do this in the shell, run:
```
git clone https://github.com/everalert/annodue.git
```

1. Compile `dinput.dll`:
```
cd annodue
mkdir build
cd build
cmake ../src/dinput -G "MSYS Makefiles"
make
```

1. The compiled `dinput.dll` can be found in `C:/msys64/home/<user>/annodue/build`.

<!---
### macOS / Linux

It is assumed you have git, cmake and a compatible compiler installed.

```
cd <appdir>
mkdir build
cd build
cmake ..
make
```
-->

## License

This project is under the MIT License. The portions of the project this does not apply to have their own license notifications.