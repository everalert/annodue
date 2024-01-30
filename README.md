# Annodue

**A universal modification platform for STAR WARS Episode I Racer.**

Currently functionality:
- Fully ported [swe1r-patcher](https://github.com/everalert/swe1r-patcher) features (the "multiplayer mod")
- Miscellaneous "toy" features (see configuration)

Immediate concerns:
- Porting core [swe1r-overlay](https://github.com/everalert/swe1r-overlay) functionality
- Plugin system
- Automatic updates

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
git clone https://github.com/JayFoxRox/swe1r-patcher.git
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