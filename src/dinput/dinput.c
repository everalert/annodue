#include <stdio.h>
#include <stdint.h>
#include <dinput.h>
#include <windows.h>
#include <stdarg.h>

#include "console.c"
#include "memory.c"
#include "loading.c"

// OUTPUT

const size_t MEMORY_SIZE = 1024;
char MEMORY[1024] = {0};
//size_t memory = (uintptr_t)VirtualAlloc(NULL, MEMORY_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);

BOOL WINAPI DllMain(
	HINSTANCE hinstDLL,
	DWORD fdwReason,
	LPVOID lpReserved
) {
	return TRUE;
}

HRESULT WINAPI DirectInputCreateA(
	HINSTANCE hinst,
	DWORD dwVersion,
	LPDIRECTINPUT* lplpDirectInput,
	LPUNKNOWN punkOuter
) {
	static HRESULT(WINAPI *o_DirectInputCreateA)(HINSTANCE, DWORD, LPDIRECTINPUT*, LPUNKNOWN) = NULL;

	if (o_DirectInputCreateA == NULL) {
		HMODULE dll = LoadLibrary("c:/windows/system32/dinput.dll");
		o_DirectInputCreateA = (void*)GetProcAddress(dll, "DirectInputCreateA");

		ModInit(&annodue, "annodue");
		ModLoad(&annodue);
		//memory = ModHook(memory);
	}

	return o_DirectInputCreateA(hinst, dwVersion, lplpDirectInput, punkOuter);
}
