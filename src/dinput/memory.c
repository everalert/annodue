#ifndef _MEMORY_C
#define _MEMORY_C

#include <stdint.h>
#include <windows.h>

// ASSEMBLY

static size_t write(size_t offset, const void* data, size_t size) {
	void* addr = (void*)(uintptr_t)offset;
	DWORD old_protect;
	VirtualProtect(addr, size, PAGE_EXECUTE_READWRITE, &old_protect);
	memcpy(addr, data, size);
	VirtualProtect(addr, size, old_protect, &old_protect);
	return offset + size;
}

static void read(const void* offset, void* data, size_t size) {
    memcpy(data, offset, size);
}

const uint32_t ALIGN_SIZE = 16;
const uint8_t inst_call = 0xE8;
const uint8_t inst_retn = 0xC3;
const uint8_t inst_nop = 0x90;

static size_t call(size_t offset, size_t addr) {
	size_t target = addr - (offset + 4);
	offset = write(offset, &inst_call, 1);
	offset = write(offset, &target, 4);
	return offset;
}

static size_t retn(size_t offset) {
	return write(offset, &inst_retn, 1);
}

static size_t nop(size_t offset) {
	return write(offset, &inst_nop, 1);
}

static size_t nop_align(size_t offset, size_t increment) {
	while (offset % increment > 0)
		offset = nop(offset);
	return offset;
}

static size_t addr_from_call(size_t src_call) {
    size_t orig_dest_rel;
	read((void*)(src_call + 1), &orig_dest_rel, 4);

    return (src_call + 5) + orig_dest_rel;
}

static size_t intercept_call(size_t offset, size_t off_call, void(*BeforeFn)(), void(*AfterFn)()) {
    size_t call_target = addr_from_call(off_call);

    call(off_call, offset);

    if (BeforeFn) offset = call(offset, (size_t)BeforeFn);
    offset = call(offset, call_target);
    if (AfterFn) offset = call(offset, (size_t)AfterFn);
    offset = retn(offset);
    offset = nop_align(offset, ALIGN_SIZE);

    return offset;
}

#endif // _MEMORY_C
