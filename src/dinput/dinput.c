//#include <stdio.h>
//#include <stdint.h>
//#include <dinput.h>
//#include <windows.h>
//#include <stdarg.h>
//
//#include "console.c"
//#include "memory.c"
//#include "loading.c"
//
//// OUTPUT
//
//const size_t MEMORY_SIZE = 1024;
//char MEMORY[1024] = {0};
////size_t memory = (uintptr_t)VirtualAlloc(NULL, MEMORY_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
//
//BOOL WINAPI DllMain(
//	HINSTANCE hinstDLL,
//	DWORD fdwReason,
//	LPVOID lpReserved
//) {
//	return TRUE;
//}
//
//HRESULT WINAPI DirectInputCreateA(
//	HINSTANCE hinst,
//	DWORD dwVersion,
//	LPDIRECTINPUT* lplpDirectInput,
//	LPUNKNOWN punkOuter
//) {
//	static HRESULT(WINAPI *o_DirectInputCreateA)(HINSTANCE, DWORD, LPDIRECTINPUT*, LPUNKNOWN) = NULL;
//
//	if (o_DirectInputCreateA == NULL) {
//		HMODULE dll = LoadLibrary("c:/windows/system32/dinput.dll");
//		o_DirectInputCreateA = (void*)GetProcAddress(dll, "DirectInputCreateA");
//
//		ModInit(&annodue, "annodue");
//		ModLoad(&annodue);
//		//memory = ModHook(memory);
//	}
//
//	return o_DirectInputCreateA(hinst, dwVersion, lplpDirectInput, punkOuter);
//}

#include <stdio.h>
#include <stdint.h>
#include <dinput.h>
#include <windows.h>

// TODO: move to lib
// TODO: don't assume '/'
/// @return     requested directory exists
BOOL WINAPI EnsureDirectoryExists(const char* relpath, int len) {
	int i = len;
	for (; relpath[i] != '/' && i>0; i--);

	if (i > 0) {
		char buf[512];
		memcpy(&buf, relpath, i);
		buf[i] = 0;
		EnsureDirectoryExists(buf, i);
	}

    if (0 != CreateDirectoryA(relpath, NULL)) return TRUE;
    if (GetLastError() == ERROR_ALREADY_EXISTS) return TRUE;

    return FALSE;
}

BOOL WINAPI DllMain(
	HINSTANCE hinstDLL,
	DWORD fdwReason,
	LPVOID lpReserved
) {
	return TRUE;
}

// TODO: properly error check the whole tihng xd
HRESULT WINAPI DirectInputCreateA(
	HINSTANCE hinst,
	DWORD dwVersion,
	LPDIRECTINPUT* lplpDirectInput,
	LPUNKNOWN punkOuter
) {
	static HRESULT(WINAPI *o_DirectInputCreateA)(HINSTANCE, DWORD, LPDIRECTINPUT*, LPUNKNOWN) = NULL;
	static void(*Patch)() = NULL;

	if (o_DirectInputCreateA == NULL) {
		if (EnsureDirectoryExists("annodue/tmp", 12) == FALSE) {
			MessageBoxA(NULL, "Creating temp directory failed.", "dinput.dll", 0);
			goto RETURN;
		}
		CopyFileA("annodue/annodue.dll", "annodue/tmp/annodue.tmp.dll", FALSE);
		HMODULE patch_dll = LoadLibrary("annodue/tmp/annodue.tmp.dll");
		Patch = (void*)GetProcAddress(patch_dll, "Init");
		Patch();

		HMODULE dll = LoadLibrary("c:/windows/system32/dinput.dll");
		o_DirectInputCreateA = (void*)GetProcAddress(dll, "DirectInputCreateA");

#if 0
		char buf[1024];
		sprintf(buf, "Hooked 0x%X", o_DirectInputCreateA);
		MessageBoxA(NULL, buf, "annodue dinput.dll", 0);
#endif
	}

RETURN:
	return o_DirectInputCreateA(hinst, dwVersion, lplpDirectInput, punkOuter);
}
