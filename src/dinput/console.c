#ifndef _CONSOLE_C
#define _CONSOLE_C

#include <stdio.h>
#include <windows.h>
#include <stdarg.h>

// DEBUG CONSOLE

BOOL dbg_initialized = FALSE;
HANDLE dbg_handle;
HWND dbg_hwnd;

//ConsoleInit();
//ConsoleOut("[%s] start\n", __func__);

void ConsoleInit() {
	AllocConsole();

    dbg_handle = GetStdHandle(STD_OUTPUT_HANDLE);
	dbg_hwnd = GetConsoleWindow();
	dbg_initialized = TRUE;

    SetWindowPos(dbg_hwnd, NULL, 0, 0, 640, 960, 0);
    SetForegroundWindow(*(HWND*)0x52EE70); // game hwnd
}

void ConsoleOut(const char* fmt, ...) {
	if (dbg_initialized == FALSE) return;
	static char buf[1024];
	va_list args;

	va_start(args, fmt);
	vsnprintf_s(buf, 1024, 1024, fmt, args);
	va_end(args);
	
	WriteConsoleA(dbg_handle, &buf, strlen(buf), NULL, NULL);
}

#endif // _CONSOLE_C
