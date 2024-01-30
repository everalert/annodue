#include <stdio.h>
#include <stdint.h>
#include <dinput.h>
#include <windows.h>

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
	static void(*Patch)() = NULL;

	if (o_DirectInputCreateA == NULL) {
		HMODULE patch_dll = LoadLibrary("annodue/annodue.dll");
		Patch = (void*)GetProcAddress(patch_dll, "Patch");
		Patch();

		HMODULE dll = LoadLibrary("c:/windows/system32/dinput.dll");
		o_DirectInputCreateA = (void*)GetProcAddress(dll, "DirectInputCreateA");

#if 0
		char buf[1024];
		sprintf(buf, "Hooked 0x%X", o_DirectInputCreateA);
		MessageBoxA(NULL, buf, "annodue dinput.dll", 0);
#endif
	}

	return o_DirectInputCreateA(hinst, dwVersion, lplpDirectInput, punkOuter);
}
