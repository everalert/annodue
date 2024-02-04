//! NOTE: this file is autogenerated, DO NOT MODIFY
//--------------------------------------------------------------------------------
// Section: Constants (3)
//--------------------------------------------------------------------------------
pub const ID_DOCUMENTPACKAGETARGET_MSXPS = Guid.initString("9cae40a8-ded1-41c9-a9fd-d735ef33aeda");
pub const ID_DOCUMENTPACKAGETARGET_OPENXPS = Guid.initString("0056bb72-8c9c-4612-bd0f-93012a87099d");
pub const ID_DOCUMENTPACKAGETARGET_OPENXPS_WITH_3D = Guid.initString("63dbd720-8b14-4577-b074-7bb11b596d28");

//--------------------------------------------------------------------------------
// Section: Types (11)
//--------------------------------------------------------------------------------
pub const XPS_JOB_COMPLETION = enum(i32) {
    IN_PROGRESS = 0,
    COMPLETED = 1,
    CANCELLED = 2,
    FAILED = 3,
};
pub const XPS_JOB_IN_PROGRESS = XPS_JOB_COMPLETION.IN_PROGRESS;
pub const XPS_JOB_COMPLETED = XPS_JOB_COMPLETION.COMPLETED;
pub const XPS_JOB_CANCELLED = XPS_JOB_COMPLETION.CANCELLED;
pub const XPS_JOB_FAILED = XPS_JOB_COMPLETION.FAILED;

pub const XPS_JOB_STATUS = extern struct {
    jobId: u32,
    currentDocument: i32,
    currentPage: i32,
    currentPageTotal: i32,
    completion: XPS_JOB_COMPLETION,
    jobStatus: HRESULT,
};

// TODO: this type is limited to platform 'windows6.1'
const IID_IXpsPrintJobStream_Value = Guid.initString("7a77dc5f-45d6-4dff-9307-d8cb846347ca");
pub const IID_IXpsPrintJobStream = &IID_IXpsPrintJobStream_Value;
pub const IXpsPrintJobStream = extern struct {
    pub const VTable = extern struct {
        base: ISequentialStream.VTable,
        Close: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IXpsPrintJobStream,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IXpsPrintJobStream,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace ISequentialStream.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IXpsPrintJobStream_Close(self: *const T) callconv(.Inline) HRESULT {
            return @as(*const IXpsPrintJobStream.VTable, @ptrCast(self.vtable)).Close(@as(*const IXpsPrintJobStream, @ptrCast(self)));
        }
    };}
    pub usingnamespace MethodMixin(@This());
};

// TODO: this type is limited to platform 'windows6.1'
const IID_IXpsPrintJob_Value = Guid.initString("5ab89b06-8194-425f-ab3b-d7a96e350161");
pub const IID_IXpsPrintJob = &IID_IXpsPrintJob_Value;
pub const IXpsPrintJob = extern struct {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        Cancel: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IXpsPrintJob,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IXpsPrintJob,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
        GetJobStatus: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IXpsPrintJob,
                jobStatus: ?*XPS_JOB_STATUS,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IXpsPrintJob,
                jobStatus: ?*XPS_JOB_STATUS,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace IUnknown.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IXpsPrintJob_Cancel(self: *const T) callconv(.Inline) HRESULT {
            return @as(*const IXpsPrintJob.VTable, @ptrCast(self.vtable)).Cancel(@as(*const IXpsPrintJob, @ptrCast(self)));
        }
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IXpsPrintJob_GetJobStatus(self: *const T, jobStatus: ?*XPS_JOB_STATUS) callconv(.Inline) HRESULT {
            return @as(*const IXpsPrintJob.VTable, @ptrCast(self.vtable)).GetJobStatus(@as(*const IXpsPrintJob, @ptrCast(self)), jobStatus);
        }
    };}
    pub usingnamespace MethodMixin(@This());
};

const CLSID_PrintDocumentPackageTarget_Value = Guid.initString("4842669e-9947-46ea-8ba2-d8cce432c2ca");
pub const CLSID_PrintDocumentPackageTarget = &CLSID_PrintDocumentPackageTarget_Value;

const CLSID_PrintDocumentPackageTargetFactory_Value = Guid.initString("348ef17d-6c81-4982-92b4-ee188a43867a");
pub const CLSID_PrintDocumentPackageTargetFactory = &CLSID_PrintDocumentPackageTargetFactory_Value;

// TODO: this type is limited to platform 'windows8.0'
const IID_IPrintDocumentPackageTarget_Value = Guid.initString("1b8efec4-3019-4c27-964e-367202156906");
pub const IID_IPrintDocumentPackageTarget = &IID_IPrintDocumentPackageTarget_Value;
pub const IPrintDocumentPackageTarget = extern struct {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        GetPackageTargetTypes: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IPrintDocumentPackageTarget,
                targetCount: ?*u32,
                targetTypes: [*]?*Guid,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IPrintDocumentPackageTarget,
                targetCount: ?*u32,
                targetTypes: [*]?*Guid,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
        GetPackageTarget: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IPrintDocumentPackageTarget,
                guidTargetType: ?*const Guid,
                riid: ?*const Guid,
                ppvTarget: ?*?*anyopaque,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IPrintDocumentPackageTarget,
                guidTargetType: ?*const Guid,
                riid: ?*const Guid,
                ppvTarget: ?*?*anyopaque,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
        Cancel: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IPrintDocumentPackageTarget,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IPrintDocumentPackageTarget,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace IUnknown.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IPrintDocumentPackageTarget_GetPackageTargetTypes(self: *const T, targetCount: ?*u32, targetTypes: [*]?*Guid) callconv(.Inline) HRESULT {
            return @as(*const IPrintDocumentPackageTarget.VTable, @ptrCast(self.vtable)).GetPackageTargetTypes(@as(*const IPrintDocumentPackageTarget, @ptrCast(self)), targetCount, targetTypes);
        }
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IPrintDocumentPackageTarget_GetPackageTarget(self: *const T, guidTargetType: ?*const Guid, riid: ?*const Guid, ppvTarget: ?*?*anyopaque) callconv(.Inline) HRESULT {
            return @as(*const IPrintDocumentPackageTarget.VTable, @ptrCast(self.vtable)).GetPackageTarget(@as(*const IPrintDocumentPackageTarget, @ptrCast(self)), guidTargetType, riid, ppvTarget);
        }
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IPrintDocumentPackageTarget_Cancel(self: *const T) callconv(.Inline) HRESULT {
            return @as(*const IPrintDocumentPackageTarget.VTable, @ptrCast(self.vtable)).Cancel(@as(*const IPrintDocumentPackageTarget, @ptrCast(self)));
        }
    };}
    pub usingnamespace MethodMixin(@This());
};

pub const PrintDocumentPackageCompletion = enum(i32) {
    InProgress = 0,
    Completed = 1,
    Canceled = 2,
    Failed = 3,
};
pub const PrintDocumentPackageCompletion_InProgress = PrintDocumentPackageCompletion.InProgress;
pub const PrintDocumentPackageCompletion_Completed = PrintDocumentPackageCompletion.Completed;
pub const PrintDocumentPackageCompletion_Canceled = PrintDocumentPackageCompletion.Canceled;
pub const PrintDocumentPackageCompletion_Failed = PrintDocumentPackageCompletion.Failed;

pub const PrintDocumentPackageStatus = extern struct {
    JobId: u32,
    CurrentDocument: i32,
    CurrentPage: i32,
    CurrentPageTotal: i32,
    Completion: PrintDocumentPackageCompletion,
    PackageStatus: HRESULT,
};

// TODO: this type is limited to platform 'windows8.0'
const IID_IPrintDocumentPackageStatusEvent_Value = Guid.initString("ed90c8ad-5c34-4d05-a1ec-0e8a9b3ad7af");
pub const IID_IPrintDocumentPackageStatusEvent = &IID_IPrintDocumentPackageStatusEvent_Value;
pub const IPrintDocumentPackageStatusEvent = extern struct {
    pub const VTable = extern struct {
        base: IDispatch.VTable,
        PackageStatusUpdated: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IPrintDocumentPackageStatusEvent,
                packageStatus: ?*PrintDocumentPackageStatus,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IPrintDocumentPackageStatusEvent,
                packageStatus: ?*PrintDocumentPackageStatus,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace IDispatch.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IPrintDocumentPackageStatusEvent_PackageStatusUpdated(self: *const T, packageStatus: ?*PrintDocumentPackageStatus) callconv(.Inline) HRESULT {
            return @as(*const IPrintDocumentPackageStatusEvent.VTable, @ptrCast(self.vtable)).PackageStatusUpdated(@as(*const IPrintDocumentPackageStatusEvent, @ptrCast(self)), packageStatus);
        }
    };}
    pub usingnamespace MethodMixin(@This());
};

// TODO: this type is limited to platform 'windows8.0'
const IID_IPrintDocumentPackageTargetFactory_Value = Guid.initString("d2959bf7-b31b-4a3d-9600-712eb1335ba4");
pub const IID_IPrintDocumentPackageTargetFactory = &IID_IPrintDocumentPackageTargetFactory_Value;
pub const IPrintDocumentPackageTargetFactory = extern struct {
    pub const VTable = extern struct {
        base: IUnknown.VTable,
        CreateDocumentPackageTargetForPrintJob: switch (@import("builtin").zig_backend) {
            .stage1 => fn(
                self: *const IPrintDocumentPackageTargetFactory,
                printerName: ?[*:0]const u16,
                jobName: ?[*:0]const u16,
                jobOutputStream: ?*IStream,
                jobPrintTicketStream: ?*IStream,
                docPackageTarget: ?*?*IPrintDocumentPackageTarget,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
            else => *const fn(
                self: *const IPrintDocumentPackageTargetFactory,
                printerName: ?[*:0]const u16,
                jobName: ?[*:0]const u16,
                jobOutputStream: ?*IStream,
                jobPrintTicketStream: ?*IStream,
                docPackageTarget: ?*?*IPrintDocumentPackageTarget,
            ) callconv(@import("std").os.windows.WINAPI) HRESULT,
        },
    };
    vtable: *const VTable,
    pub fn MethodMixin(comptime T: type) type { return struct {
        pub usingnamespace IUnknown.MethodMixin(T);
        // NOTE: method is namespaced with interface name to avoid conflicts for now
        pub fn IPrintDocumentPackageTargetFactory_CreateDocumentPackageTargetForPrintJob(self: *const T, printerName: ?[*:0]const u16, jobName: ?[*:0]const u16, jobOutputStream: ?*IStream, jobPrintTicketStream: ?*IStream, docPackageTarget: ?*?*IPrintDocumentPackageTarget) callconv(.Inline) HRESULT {
            return @as(*const IPrintDocumentPackageTargetFactory.VTable, @ptrCast(self.vtable)).CreateDocumentPackageTargetForPrintJob(@as(*const IPrintDocumentPackageTargetFactory, @ptrCast(self)), printerName, jobName, jobOutputStream, jobPrintTicketStream, docPackageTarget);
        }
    };}
    pub usingnamespace MethodMixin(@This());
};


//--------------------------------------------------------------------------------
// Section: Functions (2)
//--------------------------------------------------------------------------------
// TODO: this type is limited to platform 'windows6.1'
pub extern "xpsprint" fn StartXpsPrintJob(
    printerName: ?[*:0]const u16,
    jobName: ?[*:0]const u16,
    outputFileName: ?[*:0]const u16,
    progressEvent: ?HANDLE,
    completionEvent: ?HANDLE,
    printablePagesOn: [*:0]u8,
    printablePagesOnCount: u32,
    xpsPrintJob: ?*?*IXpsPrintJob,
    documentStream: ?*?*IXpsPrintJobStream,
    printTicketStream: ?*?*IXpsPrintJobStream,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.1'
pub extern "xpsprint" fn StartXpsPrintJob1(
    printerName: ?[*:0]const u16,
    jobName: ?[*:0]const u16,
    outputFileName: ?[*:0]const u16,
    progressEvent: ?HANDLE,
    completionEvent: ?HANDLE,
    xpsPrintJob: ?*?*IXpsPrintJob,
    printContentReceiver: ?*?*IXpsOMPackageTarget,
) callconv(@import("std").os.windows.WINAPI) HRESULT;


//--------------------------------------------------------------------------------
// Section: Unicode Aliases (0)
//--------------------------------------------------------------------------------
const thismodule = @This();
pub usingnamespace switch (@import("../../zig.zig").unicode_mode) {
    .ansi => struct {
    },
    .wide => struct {
    },
    .unspecified => if (@import("builtin").is_test) struct {
    } else struct {
    },
};
//--------------------------------------------------------------------------------
// Section: Imports (9)
//--------------------------------------------------------------------------------
const Guid = @import("../../zig.zig").Guid;
const HANDLE = @import("../../foundation.zig").HANDLE;
const HRESULT = @import("../../foundation.zig").HRESULT;
const IDispatch = @import("../../system/com.zig").IDispatch;
const ISequentialStream = @import("../../system/com.zig").ISequentialStream;
const IStream = @import("../../system/com.zig").IStream;
const IUnknown = @import("../../system/com.zig").IUnknown;
const IXpsOMPackageTarget = @import("../../storage/xps.zig").IXpsOMPackageTarget;
const PWSTR = @import("../../foundation.zig").PWSTR;

test {
    @setEvalBranchQuota(
        comptime @import("std").meta.declarations(@This()).len * 3
    );

    // reference all the pub declarations
    if (!@import("builtin").is_test) return;
    inline for (comptime @import("std").meta.declarations(@This())) |decl| {
        _ = @field(@This(), decl.name);
    }
}
