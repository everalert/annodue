# dinput-hook demo

Hooks DirectInputCreateA in dinput.dll

## Build instructions

### Windows (MSYS2)

The project files must be in the MinGW32 filesystem, likely something like `C:\msys64\home\<User>\`.

Run the following in a MinGW32 Shell:

```
cd <appdir>
mkdir build
cd build
cmake .. -G "MSYS Makefiles"
make
```

### macOS / Linux

It is assumed you have git, cmake and a compatible compiler installed.

```
cd <appdir>
mkdir build
cd build
cmake ..
make
```
