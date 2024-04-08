#ifndef _LOADING_C
#define _LOADING_C

#include <stdio.h>
#include <stdint.h>
#include <windows.h>

// ANNODUE

typedef struct Mod {
	char Filename[256];
	char CopyFilename[256];
	BOOL Initialized;
	HINSTANCE Handle; // loaded plugin handle
	FILETIME WriteTime;
    uint32_t CheckFreq;
    uint32_t CheckLast;
	void(*Init)();
	void(*Deinit)();
} Mod;

struct Mod annodue; 

BOOL FiletimeEql(FILETIME *t1, FILETIME *t2) {
    return ((t1->dwLowDateTime == t2->dwLowDateTime) &&
        (t1->dwHighDateTime == t2->dwHighDateTime));
}

void ModInit(Mod *p, char *name) {
	snprintf(p->Filename, 256, "%s/%s.dll", name, name);
	snprintf(p->CopyFilename, 256, "%s/tmp/%s.tmp.dll", name, name);
	p->Initialized = FALSE;
	p->Handle = NULL;
	p->WriteTime.dwLowDateTime = 0; // ???
	p->WriteTime.dwHighDateTime = 0;
    p->CheckFreq = 1000 / 24; // ms
    p->CheckLast = 0;
	p->Init = NULL;
	p->Deinit = NULL;
}

BOOL ModLoad(Mod *p) {
    WIN32_FIND_DATAA fd1;
	HANDLE fd1h;
    fd1h = FindFirstFileA(p->Filename, &fd1);
    if (p->Initialized && FiletimeEql(&fd1.ftLastWriteTime, &p->WriteTime)) {
        return TRUE;
	}
	FindClose(fd1h);

    if (p->Handle != NULL) {
		p->Deinit();
        FreeLibrary(p->Handle);
    }

    // now we ball

    CopyFileA(p->Filename, p->CopyFilename, FALSE);
    p->Handle = LoadLibraryA(p->CopyFilename);
    p->WriteTime = fd1.ftLastWriteTime;

    p->Init = (void*)GetProcAddress(p->Handle, "Init");
    p->Deinit = (void*)GetProcAddress(p->Handle, "Deinit");

    if (p->Init == NULL || p->Deinit == NULL) {
        FreeLibrary(p->Handle);
        p->Initialized = FALSE;
        return FALSE;
    }

	p->Init();
	p->Initialized = TRUE;
    return TRUE;
}

// NOTE: don't need these just yet
// FIXME: also, crashing; not sure where the fault is, hot-reloading core wasn't 
// urgent so didn't bother looking lol
#if 0
void ModUpdate() {
    DWORD timestamp = timeGetTime();
    if (timestamp > annodue.CheckLast + annodue.CheckFreq) {
        ModLoad(&annodue);
        annodue.CheckLast = timestamp;
    }
}

size_t ModHook(size_t offset) {
	return intercept_call(offset, 0x49CE2A, ModUpdate, NULL);
}
#endif

#endif // _LOADING_C
