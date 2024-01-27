#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>
#include <sys/types.h>
#include <windows.h>


BOOL WINAPI DllMain(
	HINSTANCE hinstDLL,
	DWORD fdwReason,
	LPVOID lpReserved
) {
	return TRUE;
}

HRESULT WINAPI DirectInputCreateA(uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
	static HRESULT(WINAPI *o_DirectInputCreateA)(uint32_t, uint32_t, uint32_t, uint32_t) = NULL;
	static void(*Patch)() = NULL;

	if (o_DirectInputCreateA == NULL) {
		HMODULE patch_dll = LoadLibrary("patch.dll");
		Patch = (void*)GetProcAddress(patch_dll, "Patch");
		Patch();

		HMODULE dll = LoadLibrary("c:/windows/system32/dinput.dll");
		o_DirectInputCreateA = (void*)GetProcAddress(dll, "DirectInputCreateA");

#if 0
		char buf[1024];
		sprintf(buf, "Hooked 0x%X", o_DirectInputCreateA);
		MessageBoxA(NULL, buf, mb_title, 0);
#endif
	}

	return o_DirectInputCreateA(a, b, c, d);
}
