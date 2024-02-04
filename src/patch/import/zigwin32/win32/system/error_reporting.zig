//! NOTE: this file is autogenerated, DO NOT MODIFY
//--------------------------------------------------------------------------------
// Section: Constants (45)
//--------------------------------------------------------------------------------
pub const WER_FAULT_REPORTING_NO_UI = @as(u32, 32);
pub const WER_FAULT_REPORTING_FLAG_NO_HEAP_ON_QUEUE = @as(u32, 64);
pub const WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH = @as(u32, 128);
pub const WER_FAULT_REPORTING_DISABLE_SNAPSHOT_HANG = @as(u32, 256);
pub const WER_FAULT_REPORTING_CRITICAL = @as(u32, 512);
pub const WER_FAULT_REPORTING_DURABLE = @as(u32, 1024);
pub const WER_MAX_TOTAL_PARAM_LENGTH = @as(u32, 1720);
pub const WER_MAX_PREFERRED_MODULES = @as(u32, 128);
pub const WER_MAX_PREFERRED_MODULES_BUFFER = @as(u32, 256);
pub const APPCRASH_EVENT = "APPCRASH";
pub const PACKAGED_APPCRASH_EVENT = "MoAppCrash";
pub const WER_P0 = @as(u32, 0);
pub const WER_P1 = @as(u32, 1);
pub const WER_P2 = @as(u32, 2);
pub const WER_P3 = @as(u32, 3);
pub const WER_P4 = @as(u32, 4);
pub const WER_P5 = @as(u32, 5);
pub const WER_P6 = @as(u32, 6);
pub const WER_P7 = @as(u32, 7);
pub const WER_P8 = @as(u32, 8);
pub const WER_P9 = @as(u32, 9);
pub const WER_FILE_COMPRESSED = @as(u32, 4);
pub const WER_SUBMIT_BYPASS_POWER_THROTTLING = @as(u32, 16384);
pub const WER_SUBMIT_BYPASS_NETWORK_COST_THROTTLING = @as(u32, 32768);
pub const WER_DUMP_MASK_START = @as(u32, 1);
pub const WER_DUMP_NOHEAP_ONQUEUE = @as(u32, 1);
pub const WER_DUMP_AUXILIARY = @as(u32, 2);
pub const WER_MAX_REGISTERED_ENTRIES = @as(u32, 512);
pub const WER_MAX_REGISTERED_METADATA = @as(u32, 8);
pub const WER_MAX_REGISTERED_DUMPCOLLECTION = @as(u32, 4);
pub const WER_METADATA_KEY_MAX_LENGTH = @as(u32, 64);
pub const WER_METADATA_VALUE_MAX_LENGTH = @as(u32, 128);
pub const WER_MAX_SIGNATURE_NAME_LENGTH = @as(u32, 128);
pub const WER_MAX_EVENT_NAME_LENGTH = @as(u32, 64);
pub const WER_MAX_PARAM_LENGTH = @as(u32, 260);
pub const WER_MAX_PARAM_COUNT = @as(u32, 10);
pub const WER_MAX_FRIENDLY_EVENT_NAME_LENGTH = @as(u32, 128);
pub const WER_MAX_APPLICATION_NAME_LENGTH = @as(u32, 128);
pub const WER_MAX_DESCRIPTION_LENGTH = @as(u32, 512);
pub const WER_MAX_BUCKET_ID_STRING_LENGTH = @as(u32, 260);
pub const WER_MAX_LOCAL_DUMP_SUBPATH_LENGTH = @as(u32, 64);
pub const WER_MAX_REGISTERED_RUNTIME_EXCEPTION_MODULES = @as(u32, 16);
pub const WER_RUNTIME_EXCEPTION_EVENT_FUNCTION = "OutOfProcessExceptionEventCallback";
pub const WER_RUNTIME_EXCEPTION_EVENT_SIGNATURE_FUNCTION = "OutOfProcessExceptionEventSignatureCallback";
pub const WER_RUNTIME_EXCEPTION_DEBUGGER_LAUNCH = "OutOfProcessExceptionEventDebuggerLaunchCallback";

//--------------------------------------------------------------------------------
// Section: Types (34)
//--------------------------------------------------------------------------------
pub const WER_FILE = enum(u32) {
    ANONYMOUS_DATA = 2,
    DELETE_WHEN_DONE = 1,
    _,
    pub fn initFlags(o: struct {
        ANONYMOUS_DATA: u1 = 0,
        DELETE_WHEN_DONE: u1 = 0,
    }) WER_FILE {
        return @as(WER_FILE, @enumFromInt(
              (if (o.ANONYMOUS_DATA == 1) @intFromEnum(WER_FILE.ANONYMOUS_DATA) else 0)
            | (if (o.DELETE_WHEN_DONE == 1) @intFromEnum(WER_FILE.DELETE_WHEN_DONE) else 0)
        ));
    }
};
pub const WER_FILE_ANONYMOUS_DATA = WER_FILE.ANONYMOUS_DATA;
pub const WER_FILE_DELETE_WHEN_DONE = WER_FILE.DELETE_WHEN_DONE;

pub const WER_SUBMIT_FLAGS = enum(u32) {
    ADD_REGISTERED_DATA = 16,
    HONOR_RECOVERY = 1,
    HONOR_RESTART = 2,
    NO_ARCHIVE = 256,
    NO_CLOSE_UI = 64,
    NO_QUEUE = 128,
    OUTOFPROCESS = 32,
    OUTOFPROCESS_ASYNC = 1024,
    QUEUE = 4,
    SHOW_DEBUG = 8,
    START_MINIMIZED = 512,
    BYPASS_DATA_THROTTLING = 2048,
    ARCHIVE_PARAMETERS_ONLY = 4096,
    REPORT_MACHINE_ID = 8192,
    _,
    pub fn initFlags(o: struct {
        ADD_REGISTERED_DATA: u1 = 0,
        HONOR_RECOVERY: u1 = 0,
        HONOR_RESTART: u1 = 0,
        NO_ARCHIVE: u1 = 0,
        NO_CLOSE_UI: u1 = 0,
        NO_QUEUE: u1 = 0,
        OUTOFPROCESS: u1 = 0,
        OUTOFPROCESS_ASYNC: u1 = 0,
        QUEUE: u1 = 0,
        SHOW_DEBUG: u1 = 0,
        START_MINIMIZED: u1 = 0,
        BYPASS_DATA_THROTTLING: u1 = 0,
        ARCHIVE_PARAMETERS_ONLY: u1 = 0,
        REPORT_MACHINE_ID: u1 = 0,
    }) WER_SUBMIT_FLAGS {
        return @as(WER_SUBMIT_FLAGS, @enumFromInt(
              (if (o.ADD_REGISTERED_DATA == 1) @intFromEnum(WER_SUBMIT_FLAGS.ADD_REGISTERED_DATA) else 0)
            | (if (o.HONOR_RECOVERY == 1) @intFromEnum(WER_SUBMIT_FLAGS.HONOR_RECOVERY) else 0)
            | (if (o.HONOR_RESTART == 1) @intFromEnum(WER_SUBMIT_FLAGS.HONOR_RESTART) else 0)
            | (if (o.NO_ARCHIVE == 1) @intFromEnum(WER_SUBMIT_FLAGS.NO_ARCHIVE) else 0)
            | (if (o.NO_CLOSE_UI == 1) @intFromEnum(WER_SUBMIT_FLAGS.NO_CLOSE_UI) else 0)
            | (if (o.NO_QUEUE == 1) @intFromEnum(WER_SUBMIT_FLAGS.NO_QUEUE) else 0)
            | (if (o.OUTOFPROCESS == 1) @intFromEnum(WER_SUBMIT_FLAGS.OUTOFPROCESS) else 0)
            | (if (o.OUTOFPROCESS_ASYNC == 1) @intFromEnum(WER_SUBMIT_FLAGS.OUTOFPROCESS_ASYNC) else 0)
            | (if (o.QUEUE == 1) @intFromEnum(WER_SUBMIT_FLAGS.QUEUE) else 0)
            | (if (o.SHOW_DEBUG == 1) @intFromEnum(WER_SUBMIT_FLAGS.SHOW_DEBUG) else 0)
            | (if (o.START_MINIMIZED == 1) @intFromEnum(WER_SUBMIT_FLAGS.START_MINIMIZED) else 0)
            | (if (o.BYPASS_DATA_THROTTLING == 1) @intFromEnum(WER_SUBMIT_FLAGS.BYPASS_DATA_THROTTLING) else 0)
            | (if (o.ARCHIVE_PARAMETERS_ONLY == 1) @intFromEnum(WER_SUBMIT_FLAGS.ARCHIVE_PARAMETERS_ONLY) else 0)
            | (if (o.REPORT_MACHINE_ID == 1) @intFromEnum(WER_SUBMIT_FLAGS.REPORT_MACHINE_ID) else 0)
        ));
    }
};
pub const WER_SUBMIT_ADD_REGISTERED_DATA = WER_SUBMIT_FLAGS.ADD_REGISTERED_DATA;
pub const WER_SUBMIT_HONOR_RECOVERY = WER_SUBMIT_FLAGS.HONOR_RECOVERY;
pub const WER_SUBMIT_HONOR_RESTART = WER_SUBMIT_FLAGS.HONOR_RESTART;
pub const WER_SUBMIT_NO_ARCHIVE = WER_SUBMIT_FLAGS.NO_ARCHIVE;
pub const WER_SUBMIT_NO_CLOSE_UI = WER_SUBMIT_FLAGS.NO_CLOSE_UI;
pub const WER_SUBMIT_NO_QUEUE = WER_SUBMIT_FLAGS.NO_QUEUE;
pub const WER_SUBMIT_OUTOFPROCESS = WER_SUBMIT_FLAGS.OUTOFPROCESS;
pub const WER_SUBMIT_OUTOFPROCESS_ASYNC = WER_SUBMIT_FLAGS.OUTOFPROCESS_ASYNC;
pub const WER_SUBMIT_QUEUE = WER_SUBMIT_FLAGS.QUEUE;
pub const WER_SUBMIT_SHOW_DEBUG = WER_SUBMIT_FLAGS.SHOW_DEBUG;
pub const WER_SUBMIT_START_MINIMIZED = WER_SUBMIT_FLAGS.START_MINIMIZED;
pub const WER_SUBMIT_BYPASS_DATA_THROTTLING = WER_SUBMIT_FLAGS.BYPASS_DATA_THROTTLING;
pub const WER_SUBMIT_ARCHIVE_PARAMETERS_ONLY = WER_SUBMIT_FLAGS.ARCHIVE_PARAMETERS_ONLY;
pub const WER_SUBMIT_REPORT_MACHINE_ID = WER_SUBMIT_FLAGS.REPORT_MACHINE_ID;

pub const WER_FAULT_REPORTING = enum(u32) {
    FLAG_DISABLE_THREAD_SUSPENSION = 4,
    FLAG_NOHEAP = 1,
    FLAG_QUEUE = 2,
    FLAG_QUEUE_UPLOAD = 8,
    ALWAYS_SHOW_UI = 16,
    _,
    pub fn initFlags(o: struct {
        FLAG_DISABLE_THREAD_SUSPENSION: u1 = 0,
        FLAG_NOHEAP: u1 = 0,
        FLAG_QUEUE: u1 = 0,
        FLAG_QUEUE_UPLOAD: u1 = 0,
        ALWAYS_SHOW_UI: u1 = 0,
    }) WER_FAULT_REPORTING {
        return @as(WER_FAULT_REPORTING, @enumFromInt(
              (if (o.FLAG_DISABLE_THREAD_SUSPENSION == 1) @intFromEnum(WER_FAULT_REPORTING.FLAG_DISABLE_THREAD_SUSPENSION) else 0)
            | (if (o.FLAG_NOHEAP == 1) @intFromEnum(WER_FAULT_REPORTING.FLAG_NOHEAP) else 0)
            | (if (o.FLAG_QUEUE == 1) @intFromEnum(WER_FAULT_REPORTING.FLAG_QUEUE) else 0)
            | (if (o.FLAG_QUEUE_UPLOAD == 1) @intFromEnum(WER_FAULT_REPORTING.FLAG_QUEUE_UPLOAD) else 0)
            | (if (o.ALWAYS_SHOW_UI == 1) @intFromEnum(WER_FAULT_REPORTING.ALWAYS_SHOW_UI) else 0)
        ));
    }
};
pub const WER_FAULT_REPORTING_FLAG_DISABLE_THREAD_SUSPENSION = WER_FAULT_REPORTING.FLAG_DISABLE_THREAD_SUSPENSION;
pub const WER_FAULT_REPORTING_FLAG_NOHEAP = WER_FAULT_REPORTING.FLAG_NOHEAP;
pub const WER_FAULT_REPORTING_FLAG_QUEUE = WER_FAULT_REPORTING.FLAG_QUEUE;
pub const WER_FAULT_REPORTING_FLAG_QUEUE_UPLOAD = WER_FAULT_REPORTING.FLAG_QUEUE_UPLOAD;
pub const WER_FAULT_REPORTING_ALWAYS_SHOW_UI = WER_FAULT_REPORTING.ALWAYS_SHOW_UI;

// TODO: this type has a FreeFunc 'WerReportCloseHandle', what can Zig do with this information?
// TODO: this type has an InvalidHandleValue of '0', what can Zig do with this information?
pub const HREPORT = isize;

// TODO: this type has a FreeFunc 'WerStoreClose', what can Zig do with this information?
// TODO: this type has an InvalidHandleValue of '0', what can Zig do with this information?
pub const HREPORTSTORE = isize;

pub const WER_REPORT_UI = enum(i32) {
    AdditionalDataDlgHeader = 1,
    IconFilePath = 2,
    ConsentDlgHeader = 3,
    ConsentDlgBody = 4,
    OnlineSolutionCheckText = 5,
    OfflineSolutionCheckText = 6,
    CloseText = 7,
    CloseDlgHeader = 8,
    CloseDlgBody = 9,
    CloseDlgButtonText = 10,
    Max = 11,
};
pub const WerUIAdditionalDataDlgHeader = WER_REPORT_UI.AdditionalDataDlgHeader;
pub const WerUIIconFilePath = WER_REPORT_UI.IconFilePath;
pub const WerUIConsentDlgHeader = WER_REPORT_UI.ConsentDlgHeader;
pub const WerUIConsentDlgBody = WER_REPORT_UI.ConsentDlgBody;
pub const WerUIOnlineSolutionCheckText = WER_REPORT_UI.OnlineSolutionCheckText;
pub const WerUIOfflineSolutionCheckText = WER_REPORT_UI.OfflineSolutionCheckText;
pub const WerUICloseText = WER_REPORT_UI.CloseText;
pub const WerUICloseDlgHeader = WER_REPORT_UI.CloseDlgHeader;
pub const WerUICloseDlgBody = WER_REPORT_UI.CloseDlgBody;
pub const WerUICloseDlgButtonText = WER_REPORT_UI.CloseDlgButtonText;
pub const WerUIMax = WER_REPORT_UI.Max;

pub const WER_REGISTER_FILE_TYPE = enum(i32) {
    UserDocument = 1,
    Other = 2,
    Max = 3,
};
pub const WerRegFileTypeUserDocument = WER_REGISTER_FILE_TYPE.UserDocument;
pub const WerRegFileTypeOther = WER_REGISTER_FILE_TYPE.Other;
pub const WerRegFileTypeMax = WER_REGISTER_FILE_TYPE.Max;

pub const WER_FILE_TYPE = enum(i32) {
    Microdump = 1,
    Minidump = 2,
    Heapdump = 3,
    UserDocument = 4,
    Other = 5,
    Triagedump = 6,
    CustomDump = 7,
    AuxiliaryDump = 8,
    EtlTrace = 9,
    Max = 10,
};
pub const WerFileTypeMicrodump = WER_FILE_TYPE.Microdump;
pub const WerFileTypeMinidump = WER_FILE_TYPE.Minidump;
pub const WerFileTypeHeapdump = WER_FILE_TYPE.Heapdump;
pub const WerFileTypeUserDocument = WER_FILE_TYPE.UserDocument;
pub const WerFileTypeOther = WER_FILE_TYPE.Other;
pub const WerFileTypeTriagedump = WER_FILE_TYPE.Triagedump;
pub const WerFileTypeCustomDump = WER_FILE_TYPE.CustomDump;
pub const WerFileTypeAuxiliaryDump = WER_FILE_TYPE.AuxiliaryDump;
pub const WerFileTypeEtlTrace = WER_FILE_TYPE.EtlTrace;
pub const WerFileTypeMax = WER_FILE_TYPE.Max;

pub const WER_SUBMIT_RESULT = enum(i32) {
    ReportQueued = 1,
    ReportUploaded = 2,
    ReportDebug = 3,
    ReportFailed = 4,
    Disabled = 5,
    ReportCancelled = 6,
    DisabledQueue = 7,
    ReportAsync = 8,
    CustomAction = 9,
    Throttled = 10,
    ReportUploadedCab = 11,
    StorageLocationNotFound = 12,
    SubmitResultMax = 13,
};
pub const WerReportQueued = WER_SUBMIT_RESULT.ReportQueued;
pub const WerReportUploaded = WER_SUBMIT_RESULT.ReportUploaded;
pub const WerReportDebug = WER_SUBMIT_RESULT.ReportDebug;
pub const WerReportFailed = WER_SUBMIT_RESULT.ReportFailed;
pub const WerDisabled = WER_SUBMIT_RESULT.Disabled;
pub const WerReportCancelled = WER_SUBMIT_RESULT.ReportCancelled;
pub const WerDisabledQueue = WER_SUBMIT_RESULT.DisabledQueue;
pub const WerReportAsync = WER_SUBMIT_RESULT.ReportAsync;
pub const WerCustomAction = WER_SUBMIT_RESULT.CustomAction;
pub const WerThrottled = WER_SUBMIT_RESULT.Throttled;
pub const WerReportUploadedCab = WER_SUBMIT_RESULT.ReportUploadedCab;
pub const WerStorageLocationNotFound = WER_SUBMIT_RESULT.StorageLocationNotFound;
pub const WerSubmitResultMax = WER_SUBMIT_RESULT.SubmitResultMax;

pub const WER_REPORT_TYPE = enum(i32) {
    NonCritical = 0,
    Critical = 1,
    ApplicationCrash = 2,
    ApplicationHang = 3,
    Kernel = 4,
    Invalid = 5,
};
pub const WerReportNonCritical = WER_REPORT_TYPE.NonCritical;
pub const WerReportCritical = WER_REPORT_TYPE.Critical;
pub const WerReportApplicationCrash = WER_REPORT_TYPE.ApplicationCrash;
pub const WerReportApplicationHang = WER_REPORT_TYPE.ApplicationHang;
pub const WerReportKernel = WER_REPORT_TYPE.Kernel;
pub const WerReportInvalid = WER_REPORT_TYPE.Invalid;

pub const WER_REPORT_INFORMATION = extern struct {
    dwSize: u32,
    hProcess: ?HANDLE,
    wzConsentKey: [64]u16,
    wzFriendlyEventName: [128]u16,
    wzApplicationName: [128]u16,
    wzApplicationPath: [260]u16,
    wzDescription: [512]u16,
    hwndParent: ?HWND,
};

pub const WER_REPORT_INFORMATION_V3 = extern struct {
    dwSize: u32,
    hProcess: ?HANDLE,
    wzConsentKey: [64]u16,
    wzFriendlyEventName: [128]u16,
    wzApplicationName: [128]u16,
    wzApplicationPath: [260]u16,
    wzDescription: [512]u16,
    hwndParent: ?HWND,
    wzNamespacePartner: [64]u16,
    wzNamespaceGroup: [64]u16,
};

pub const WER_DUMP_CUSTOM_OPTIONS = extern struct {
    dwSize: u32,
    dwMask: u32,
    dwDumpFlags: u32,
    bOnlyThisThread: BOOL,
    dwExceptionThreadFlags: u32,
    dwOtherThreadFlags: u32,
    dwExceptionThreadExFlags: u32,
    dwOtherThreadExFlags: u32,
    dwPreferredModuleFlags: u32,
    dwOtherModuleFlags: u32,
    wzPreferredModuleList: [256]u16,
};

pub const WER_DUMP_CUSTOM_OPTIONS_V2 = extern struct {
    dwSize: u32,
    dwMask: u32,
    dwDumpFlags: u32,
    bOnlyThisThread: BOOL,
    dwExceptionThreadFlags: u32,
    dwOtherThreadFlags: u32,
    dwExceptionThreadExFlags: u32,
    dwOtherThreadExFlags: u32,
    dwPreferredModuleFlags: u32,
    dwOtherModuleFlags: u32,
    wzPreferredModuleList: [256]u16,
    dwPreferredModuleResetFlags: u32,
    dwOtherModuleResetFlags: u32,
};

pub const WER_REPORT_INFORMATION_V4 = extern struct {
    dwSize: u32,
    hProcess: ?HANDLE,
    wzConsentKey: [64]u16,
    wzFriendlyEventName: [128]u16,
    wzApplicationName: [128]u16,
    wzApplicationPath: [260]u16,
    wzDescription: [512]u16,
    hwndParent: ?HWND,
    wzNamespacePartner: [64]u16,
    wzNamespaceGroup: [64]u16,
    rgbApplicationIdentity: [16]u8,
    hSnapshot: ?HANDLE,
    hDeleteFilesImpersonationToken: ?HANDLE,
};

pub const WER_REPORT_INFORMATION_V5 = extern struct {
    dwSize: u32,
    hProcess: ?HANDLE,
    wzConsentKey: [64]u16,
    wzFriendlyEventName: [128]u16,
    wzApplicationName: [128]u16,
    wzApplicationPath: [260]u16,
    wzDescription: [512]u16,
    hwndParent: ?HWND,
    wzNamespacePartner: [64]u16,
    wzNamespaceGroup: [64]u16,
    rgbApplicationIdentity: [16]u8,
    hSnapshot: ?HANDLE,
    hDeleteFilesImpersonationToken: ?HANDLE,
    submitResultMax: WER_SUBMIT_RESULT,
};

pub const WER_DUMP_CUSTOM_OPTIONS_V3 = extern struct {
    dwSize: u32,
    dwMask: u32,
    dwDumpFlags: u32,
    bOnlyThisThread: BOOL,
    dwExceptionThreadFlags: u32,
    dwOtherThreadFlags: u32,
    dwExceptionThreadExFlags: u32,
    dwOtherThreadExFlags: u32,
    dwPreferredModuleFlags: u32,
    dwOtherModuleFlags: u32,
    wzPreferredModuleList: [256]u16,
    dwPreferredModuleResetFlags: u32,
    dwOtherModuleResetFlags: u32,
    pvDumpKey: ?*anyopaque,
    hSnapshot: ?HANDLE,
    dwThreadID: u32,
};

pub const WER_EXCEPTION_INFORMATION = extern struct {
    pExceptionPointers: ?*EXCEPTION_POINTERS,
    bClientPointers: BOOL,
};

pub const WER_CONSENT = enum(i32) {
    NotAsked = 1,
    Approved = 2,
    Denied = 3,
    AlwaysPrompt = 4,
    Max = 5,
};
pub const WerConsentNotAsked = WER_CONSENT.NotAsked;
pub const WerConsentApproved = WER_CONSENT.Approved;
pub const WerConsentDenied = WER_CONSENT.Denied;
pub const WerConsentAlwaysPrompt = WER_CONSENT.AlwaysPrompt;
pub const WerConsentMax = WER_CONSENT.Max;

pub const WER_DUMP_TYPE = enum(i32) {
    None = 0,
    MicroDump = 1,
    MiniDump = 2,
    HeapDump = 3,
    TriageDump = 4,
    Max = 5,
};
pub const WerDumpTypeNone = WER_DUMP_TYPE.None;
pub const WerDumpTypeMicroDump = WER_DUMP_TYPE.MicroDump;
pub const WerDumpTypeMiniDump = WER_DUMP_TYPE.MiniDump;
pub const WerDumpTypeHeapDump = WER_DUMP_TYPE.HeapDump;
pub const WerDumpTypeTriageDump = WER_DUMP_TYPE.TriageDump;
pub const WerDumpTypeMax = WER_DUMP_TYPE.Max;

pub const WER_RUNTIME_EXCEPTION_INFORMATION = extern struct {
    dwSize: u32,
    hProcess: ?HANDLE,
    hThread: ?HANDLE,
    exceptionRecord: EXCEPTION_RECORD,
    context: CONTEXT,
    pwszReportId: ?[*:0]const u16,
    bIsFatal: BOOL,
    dwReserved: u32,
};

pub const PFN_WER_RUNTIME_EXCEPTION_EVENT = switch (@import("builtin").zig_backend) {
    .stage1 => fn(
        pContext: ?*anyopaque,
        pExceptionInformation: ?*const WER_RUNTIME_EXCEPTION_INFORMATION,
        pbOwnershipClaimed: ?*BOOL,
        pwszEventName: [*:0]u16,
        pchSize: ?*u32,
        pdwSignatureCount: ?*u32,
    ) callconv(@import("std").os.windows.WINAPI) HRESULT,
    else => *const fn(
        pContext: ?*anyopaque,
        pExceptionInformation: ?*const WER_RUNTIME_EXCEPTION_INFORMATION,
        pbOwnershipClaimed: ?*BOOL,
        pwszEventName: [*:0]u16,
        pchSize: ?*u32,
        pdwSignatureCount: ?*u32,
    ) callconv(@import("std").os.windows.WINAPI) HRESULT,
} ;

pub const PFN_WER_RUNTIME_EXCEPTION_EVENT_SIGNATURE = switch (@import("builtin").zig_backend) {
    .stage1 => fn(
        pContext: ?*anyopaque,
        pExceptionInformation: ?*const WER_RUNTIME_EXCEPTION_INFORMATION,
        dwIndex: u32,
        pwszName: [*:0]u16,
        pchName: ?*u32,
        pwszValue: [*:0]u16,
        pchValue: ?*u32,
    ) callconv(@import("std").os.windows.WINAPI) HRESULT,
    else => *const fn(
        pContext: ?*anyopaque,
        pExceptionInformation: ?*const WER_RUNTIME_EXCEPTION_INFORMATION,
        dwIndex: u32,
        pwszName: [*:0]u16,
        pchName: ?*u32,
        pwszValue: [*:0]u16,
        pchValue: ?*u32,
    ) callconv(@import("std").os.windows.WINAPI) HRESULT,
} ;

pub const PFN_WER_RUNTIME_EXCEPTION_DEBUGGER_LAUNCH = switch (@import("builtin").zig_backend) {
    .stage1 => fn(
        pContext: ?*anyopaque,
        pExceptionInformation: ?*const WER_RUNTIME_EXCEPTION_INFORMATION,
        pbIsCustomDebugger: ?*BOOL,
        pwszDebuggerLaunch: [*:0]u16,
        pchDebuggerLaunch: ?*u32,
        pbIsDebuggerAutolaunch: ?*BOOL,
    ) callconv(@import("std").os.windows.WINAPI) HRESULT,
    else => *const fn(
        pContext: ?*anyopaque,
        pExceptionInformation: ?*const WER_RUNTIME_EXCEPTION_INFORMATION,
        pbIsCustomDebugger: ?*BOOL,
        pwszDebuggerLaunch: [*:0]u16,
        pchDebuggerLaunch: ?*u32,
        pbIsDebuggerAutolaunch: ?*BOOL,
    ) callconv(@import("std").os.windows.WINAPI) HRESULT,
} ;

pub const REPORT_STORE_TYPES = enum(i32) {
    USER_ARCHIVE = 0,
    USER_QUEUE = 1,
    MACHINE_ARCHIVE = 2,
    MACHINE_QUEUE = 3,
    INVALID = 4,
};
pub const E_STORE_USER_ARCHIVE = REPORT_STORE_TYPES.USER_ARCHIVE;
pub const E_STORE_USER_QUEUE = REPORT_STORE_TYPES.USER_QUEUE;
pub const E_STORE_MACHINE_ARCHIVE = REPORT_STORE_TYPES.MACHINE_ARCHIVE;
pub const E_STORE_MACHINE_QUEUE = REPORT_STORE_TYPES.MACHINE_QUEUE;
pub const E_STORE_INVALID = REPORT_STORE_TYPES.INVALID;

pub const WER_REPORT_PARAMETER = extern struct {
    Name: [129]u16,
    Value: [260]u16,
};

pub const WER_REPORT_SIGNATURE = extern struct {
    EventName: [65]u16,
    Parameters: [10]WER_REPORT_PARAMETER,
};

pub const WER_REPORT_METADATA_V2 = extern struct {
    Signature: WER_REPORT_SIGNATURE,
    BucketId: Guid,
    ReportId: Guid,
    CreationTime: FILETIME,
    SizeInBytes: u64,
    CabId: [260]u16,
    ReportStatus: u32,
    ReportIntegratorId: Guid,
    NumberOfFiles: u32,
    SizeOfFileNames: u32,
    FileNames: ?PWSTR,
};

pub const WER_REPORT_METADATA_V3 = extern struct {
    Signature: WER_REPORT_SIGNATURE,
    BucketId: Guid,
    ReportId: Guid,
    CreationTime: FILETIME,
    SizeInBytes: u64,
    CabId: [260]u16,
    ReportStatus: u32,
    ReportIntegratorId: Guid,
    NumberOfFiles: u32,
    SizeOfFileNames: u32,
    FileNames: ?PWSTR,
    FriendlyEventName: [128]u16,
    ApplicationName: [128]u16,
    ApplicationPath: [260]u16,
    Description: [512]u16,
    BucketIdString: [260]u16,
    LegacyBucketId: u64,
};

pub const WER_REPORT_METADATA_V1 = extern struct {
    Signature: WER_REPORT_SIGNATURE,
    BucketId: Guid,
    ReportId: Guid,
    CreationTime: FILETIME,
    SizeInBytes: u64,
};

pub const EFaultRepRetVal = enum(i32) {
    Ok = 0,
    OkManifest = 1,
    OkQueued = 2,
    Err = 3,
    ErrNoDW = 4,
    ErrTimeout = 5,
    LaunchDebugger = 6,
    OkHeadless = 7,
    ErrAnotherInstance = 8,
    ErrNoMemory = 9,
    ErrDoubleFault = 10,
};
pub const frrvOk = EFaultRepRetVal.Ok;
pub const frrvOkManifest = EFaultRepRetVal.OkManifest;
pub const frrvOkQueued = EFaultRepRetVal.OkQueued;
pub const frrvErr = EFaultRepRetVal.Err;
pub const frrvErrNoDW = EFaultRepRetVal.ErrNoDW;
pub const frrvErrTimeout = EFaultRepRetVal.ErrTimeout;
pub const frrvLaunchDebugger = EFaultRepRetVal.LaunchDebugger;
pub const frrvOkHeadless = EFaultRepRetVal.OkHeadless;
pub const frrvErrAnotherInstance = EFaultRepRetVal.ErrAnotherInstance;
pub const frrvErrNoMemory = EFaultRepRetVal.ErrNoMemory;
pub const frrvErrDoubleFault = EFaultRepRetVal.ErrDoubleFault;

pub const pfn_REPORTFAULT = switch (@import("builtin").zig_backend) {
    .stage1 => fn(
        param0: ?*EXCEPTION_POINTERS,
        param1: u32,
    ) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal,
    else => *const fn(
        param0: ?*EXCEPTION_POINTERS,
        param1: u32,
    ) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal,
} ;

pub const pfn_ADDEREXCLUDEDAPPLICATIONA = switch (@import("builtin").zig_backend) {
    .stage1 => fn(
        param0: ?[*:0]const u8,
    ) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal,
    else => *const fn(
        param0: ?[*:0]const u8,
    ) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal,
} ;

pub const pfn_ADDEREXCLUDEDAPPLICATIONW = switch (@import("builtin").zig_backend) {
    .stage1 => fn(
        param0: ?[*:0]const u16,
    ) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal,
    else => *const fn(
        param0: ?[*:0]const u16,
    ) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal,
} ;


//--------------------------------------------------------------------------------
// Section: Functions (41)
//--------------------------------------------------------------------------------
// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportCreate(
    pwzEventType: ?[*:0]const u16,
    repType: WER_REPORT_TYPE,
    pReportInformation: ?*WER_REPORT_INFORMATION,
    phReportHandle: ?*HREPORT,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportSetParameter(
    hReportHandle: HREPORT,
    dwparamID: u32,
    pwzName: ?[*:0]const u16,
    pwzValue: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportAddFile(
    hReportHandle: HREPORT,
    pwzPath: ?[*:0]const u16,
    repFileType: WER_FILE_TYPE,
    dwFileFlags: WER_FILE,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportSetUIOption(
    hReportHandle: HREPORT,
    repUITypeID: WER_REPORT_UI,
    pwzValue: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportSubmit(
    hReportHandle: HREPORT,
    consent: WER_CONSENT,
    dwFlags: WER_SUBMIT_FLAGS,
    pSubmitResult: ?*WER_SUBMIT_RESULT,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportAddDump(
    hReportHandle: HREPORT,
    hProcess: ?HANDLE,
    hThread: ?HANDLE,
    dumpType: WER_DUMP_TYPE,
    pExceptionParam: ?*WER_EXCEPTION_INFORMATION,
    pDumpCustomOptions: ?*WER_DUMP_CUSTOM_OPTIONS,
    dwFlags: u32,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerReportCloseHandle(
    hReportHandle: HREPORT,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "kernel32" fn WerRegisterFile(
    pwzFile: ?[*:0]const u16,
    regFileType: WER_REGISTER_FILE_TYPE,
    dwFlags: WER_FILE,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "kernel32" fn WerUnregisterFile(
    pwzFilePath: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "kernel32" fn WerRegisterMemoryBlock(
    pvAddress: ?*anyopaque,
    dwSize: u32,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "kernel32" fn WerUnregisterMemoryBlock(
    pvAddress: ?*anyopaque,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "kernel32" fn WerRegisterExcludedMemoryBlock(
    address: ?*const anyopaque,
    size: u32,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "kernel32" fn WerUnregisterExcludedMemoryBlock(
    address: ?*const anyopaque,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "kernel32" fn WerRegisterCustomMetadata(
    key: ?[*:0]const u16,
    value: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "kernel32" fn WerUnregisterCustomMetadata(
    key: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "kernel32" fn WerRegisterAdditionalProcess(
    processId: u32,
    captureExtraInfoForThreadId: u32,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "kernel32" fn WerUnregisterAdditionalProcess(
    processId: u32,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.16299'
pub extern "kernel32" fn WerRegisterAppLocalDump(
    localAppDataRelativePath: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.16299'
pub extern "kernel32" fn WerUnregisterAppLocalDump(
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "kernel32" fn WerSetFlags(
    dwFlags: WER_FAULT_REPORTING,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "kernel32" fn WerGetFlags(
    hProcess: ?HANDLE,
    pdwFlags: ?*WER_FAULT_REPORTING,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerAddExcludedApplication(
    pwzExeName: ?[*:0]const u16,
    bAllUsers: BOOL,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "wer" fn WerRemoveExcludedApplication(
    pwzExeName: ?[*:0]const u16,
    bAllUsers: BOOL,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.1'
pub extern "kernel32" fn WerRegisterRuntimeExceptionModule(
    pwszOutOfProcessCallbackDll: ?[*:0]const u16,
    pContext: ?*anyopaque,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows6.1'
pub extern "kernel32" fn WerUnregisterRuntimeExceptionModule(
    pwszOutOfProcessCallbackDll: ?[*:0]const u16,
    pContext: ?*anyopaque,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "wer" fn WerStoreOpen(
    repStoreType: REPORT_STORE_TYPES,
    phReportStore: ?*HREPORTSTORE,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "wer" fn WerStoreClose(
    hReportStore: HREPORTSTORE,
) callconv(@import("std").os.windows.WINAPI) void;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "wer" fn WerStoreGetFirstReportKey(
    hReportStore: HREPORTSTORE,
    ppszReportKey: ?*?PWSTR,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "wer" fn WerStoreGetNextReportKey(
    hReportStore: HREPORTSTORE,
    ppszReportKey: ?*?PWSTR,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "wer" fn WerStoreQueryReportMetadataV2(
    hReportStore: HREPORTSTORE,
    pszReportKey: ?[*:0]const u16,
    pReportMetadata: ?*WER_REPORT_METADATA_V2,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

pub extern "wer" fn WerStoreQueryReportMetadataV3(
    hReportStore: HREPORTSTORE,
    pszReportKey: ?[*:0]const u16,
    pReportMetadata: ?*WER_REPORT_METADATA_V3,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows10.0.15063'
pub extern "wer" fn WerFreeString(
    pwszStr: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) void;

pub extern "wer" fn WerStorePurge(
) callconv(@import("std").os.windows.WINAPI) HRESULT;

pub extern "wer" fn WerStoreGetReportCount(
    hReportStore: HREPORTSTORE,
    pdwReportCount: ?*u32,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

pub extern "wer" fn WerStoreGetSizeOnDisk(
    hReportStore: HREPORTSTORE,
    pqwSizeInBytes: ?*u64,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

pub extern "wer" fn WerStoreQueryReportMetadataV1(
    hReportStore: HREPORTSTORE,
    pszReportKey: ?[*:0]const u16,
    pReportMetadata: ?*WER_REPORT_METADATA_V1,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

pub extern "wer" fn WerStoreUploadReport(
    hReportStore: HREPORTSTORE,
    pszReportKey: ?[*:0]const u16,
    dwFlags: u32,
    pSubmitResult: ?*WER_SUBMIT_RESULT,
) callconv(@import("std").os.windows.WINAPI) HRESULT;

// TODO: this type is limited to platform 'windows5.1.2600'
pub extern "faultrep" fn ReportFault(
    pep: ?*EXCEPTION_POINTERS,
    dwOpt: u32,
) callconv(@import("std").os.windows.WINAPI) EFaultRepRetVal;

// TODO: this type is limited to platform 'windows5.1.2600'
pub extern "faultrep" fn AddERExcludedApplicationA(
    szApplication: ?[*:0]const u8,
) callconv(@import("std").os.windows.WINAPI) BOOL;

// TODO: this type is limited to platform 'windows5.1.2600'
pub extern "faultrep" fn AddERExcludedApplicationW(
    wszApplication: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) BOOL;

// TODO: this type is limited to platform 'windows6.0.6000'
pub extern "faultrep" fn WerReportHang(
    hwndHungApp: ?HWND,
    pwzHungApplicationName: ?[*:0]const u16,
) callconv(@import("std").os.windows.WINAPI) HRESULT;


//--------------------------------------------------------------------------------
// Section: Unicode Aliases (2)
//--------------------------------------------------------------------------------
const thismodule = @This();
pub usingnamespace switch (@import("../zig.zig").unicode_mode) {
    .ansi => struct {
        pub const pfn_ADDEREXCLUDEDAPPLICATION = thismodule.pfn_ADDEREXCLUDEDAPPLICATIONA;
        pub const AddERExcludedApplication = thismodule.AddERExcludedApplicationA;
    },
    .wide => struct {
        pub const pfn_ADDEREXCLUDEDAPPLICATION = thismodule.pfn_ADDEREXCLUDEDAPPLICATIONW;
        pub const AddERExcludedApplication = thismodule.AddERExcludedApplicationW;
    },
    .unspecified => if (@import("builtin").is_test) struct {
        pub const pfn_ADDEREXCLUDEDAPPLICATION = *opaque{};
        pub const AddERExcludedApplication = *opaque{};
    } else struct {
        pub const pfn_ADDEREXCLUDEDAPPLICATION = @compileError("'pfn_ADDEREXCLUDEDAPPLICATION' requires that UNICODE be set to true or false in the root module");
        pub const AddERExcludedApplication = @compileError("'AddERExcludedApplication' requires that UNICODE be set to true or false in the root module");
    },
};
//--------------------------------------------------------------------------------
// Section: Imports (11)
//--------------------------------------------------------------------------------
const Guid = @import("../zig.zig").Guid;
const BOOL = @import("../foundation.zig").BOOL;
const CONTEXT = @import("../system/diagnostics/debug.zig").CONTEXT;
const EXCEPTION_POINTERS = @import("../system/diagnostics/debug.zig").EXCEPTION_POINTERS;
const EXCEPTION_RECORD = @import("../system/diagnostics/debug.zig").EXCEPTION_RECORD;
const FILETIME = @import("../foundation.zig").FILETIME;
const HANDLE = @import("../foundation.zig").HANDLE;
const HRESULT = @import("../foundation.zig").HRESULT;
const HWND = @import("../foundation.zig").HWND;
const PSTR = @import("../foundation.zig").PSTR;
const PWSTR = @import("../foundation.zig").PWSTR;

test {
    // The following '_ = <FuncPtrType>' lines are a workaround for https://github.com/ziglang/zig/issues/4476
    if (@hasDecl(@This(), "PFN_WER_RUNTIME_EXCEPTION_EVENT")) { _ = PFN_WER_RUNTIME_EXCEPTION_EVENT; }
    if (@hasDecl(@This(), "PFN_WER_RUNTIME_EXCEPTION_EVENT_SIGNATURE")) { _ = PFN_WER_RUNTIME_EXCEPTION_EVENT_SIGNATURE; }
    if (@hasDecl(@This(), "PFN_WER_RUNTIME_EXCEPTION_DEBUGGER_LAUNCH")) { _ = PFN_WER_RUNTIME_EXCEPTION_DEBUGGER_LAUNCH; }
    if (@hasDecl(@This(), "pfn_REPORTFAULT")) { _ = pfn_REPORTFAULT; }
    if (@hasDecl(@This(), "pfn_ADDEREXCLUDEDAPPLICATIONA")) { _ = pfn_ADDEREXCLUDEDAPPLICATIONA; }
    if (@hasDecl(@This(), "pfn_ADDEREXCLUDEDAPPLICATIONW")) { _ = pfn_ADDEREXCLUDEDAPPLICATIONW; }

    @setEvalBranchQuota(
        comptime @import("std").meta.declarations(@This()).len * 3
    );

    // reference all the pub declarations
    if (!@import("builtin").is_test) return;
    inline for (comptime @import("std").meta.declarations(@This())) |decl| {
        _ = @field(@This(), decl.name);
    }
}
