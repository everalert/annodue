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

void WINAPI ErrorMessage(char* message, DWORD error_code) {
	char buf[1024];
	sprintf(buf, "%s failed with error %lu", message, error_code);
	MessageBoxA(NULL, buf, "dinput.dll", 0);
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
	HMODULE patch_dll, dll;

	if (o_DirectInputCreateA == NULL) {
		if (FALSE == EnsureDirectoryExists("annodue/tmp", 12)) {
			ErrorMessage("EnsureDirectoryExists(annodue/tmp)", GetLastError());
			goto RETURN;
		}
		CopyFileA("annodue/annodue.dll", "annodue/tmp/annodue.tmp.dll", FALSE);

		if (NULL == (patch_dll = LoadLibrary("annodue/tmp/annodue.tmp.dll"))) {
			ErrorMessage("LoadLibrary(annodue.dll)", GetLastError());
			goto RETURN;
		}
		if (NULL == (Patch = (void*)GetProcAddress(patch_dll, "Init"))) {
			ErrorMessage("GetProcAddress(Init)", GetLastError());
			goto RETURN;
		}
		Patch();

		if (NULL == (dll = LoadLibrary("annodue/dinput.dll"))) {
			DWORD e = GetLastError();
			if (NULL == (dll = LoadLibrary("c:/windows/system32/dinput.dll"))) {
				ErrorMessage("LoadLibrary(annodue/dinput.dll)", e);
				ErrorMessage("LoadLibrary(system32/dinput.dll)", GetLastError());
				goto RETURN;
			}
		}
		if (NULL == (o_DirectInputCreateA = (void*)GetProcAddress(dll, "DirectInputCreateA"))) {
			ErrorMessage("GetProcAddress(DirectInputCreateA)", GetLastError());
			goto RETURN;
		}
	}

#if 0
	char buf[1024];
	sprintf(buf, "Hooked 0x%X", o_DirectInputCreateA);
	MessageBoxA(NULL, buf, "annodue dinput.dll", 0);
#endif

RETURN:
	return o_DirectInputCreateA(hinst, dwVersion, lplpDirectInput, punkOuter);
}

__asm__(".global DirectInputCreateA\n"
        "DirectInputCreateA=_DirectInputCreateA@16\n");
