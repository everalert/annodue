const w32 = @import("zigwin32");
const w32f = w32.foundation;
const w32fs = w32.storage.file_system;

/// check if file written to since given filetime, and update the filetime with the new write time if true
pub fn filetime_checkNewerWriteTime(filename: ?[*:0]const u8, last_filetime: *w32f.FILETIME) bool {
    var fd: w32fs.WIN32_FIND_DATAA = undefined;

    const find_handle = w32fs.FindFirstFileA(filename, &fd);
    defer _ = w32fs.FindClose(find_handle);
    if (-1 == find_handle) return false;

    if (filetime_eql(&fd.ftLastWriteTime, last_filetime))
        return false;

    last_filetime.* = fd.ftLastWriteTime;

    return true;
}

pub fn filetime_eql(t1: *w32f.FILETIME, t2: *w32f.FILETIME) bool {
    return (t1.dwLowDateTime == t2.dwLowDateTime and
        t1.dwHighDateTime == t2.dwHighDateTime);
}
