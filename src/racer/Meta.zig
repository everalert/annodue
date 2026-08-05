pub const IMAGE_BASE: u32 = 0x400000;
pub const IMAGE_SIZE: u32 = 0xAD0000;
pub const IMAGE_END: u32 = IMAGE_BASE + IMAGE_SIZE;
pub const CODE_BASE: u32 = IMAGE_BASE + 0x001000;
pub const DATA_BASE: u32 = IMAGE_BASE + 0x0AC000;
pub const ENTRY_POINT: u32 = IMAGE_BASE + 0x0A0A60;

// name, virtual address, virtual size, flags, alignment
pub const SECTIONS: [4]struct { [:0]const u8, u32, u32, u32, u32 } = .{
    .{ "text", 0x401000, 0x0AA750, 0x60000020, 4 },
    .{ "rdata", 0x4AC000, 0x0054A2, 0x40000040, 4 },
    .{ "data", 0x4B2000, 0x023600, 0xC0000040, 4 },
    .{ "rsrc", 0xECE000, 0x0017B8, 0x40000020, 4 },
};

//  objdump -x SWEP1RCR.exe
//
//    SWEP1RCR.exe:     file format pei-i386
//    SWEP1RCR.exe
//    architecture: i386, flags 0x0000010a:
//    EXEC_P, HAS_DEBUG, D_PAGED
//    start address 0x004a0a60
//
//    Characteristics 0x10f
//            relocations stripped
//            executable
//            line numbers stripped
//            symbols stripped
//            32 bit words
//
//    Time/Date               Wed Feb 06 10:22:20 2002
//    Magic                   010b    (PE32)
//    MajorLinkerVersion      5
//    MinorLinkerVersion      10
//    SizeOfCode              000aa800
//    SizeOfInitializedData   00a22600
//    SizeOfUninitializedData 00000000
//    AddressOfEntryPoint     000a0a60
//    BaseOfCode              00001000
//    BaseOfData              000ac000
//    ImageBase               00400000
//    SectionAlignment        00001000
//    FileAlignment           00000200
//    MajorOSystemVersion     4
//    MinorOSystemVersion     0
//    MajorImageVersion       0
//    MinorImageVersion       0
//    MajorSubsystemVersion   4
//    MinorSubsystemVersion   0
//    Win32Version            00000000
//    SizeOfImage             00ad0000
//    SizeOfHeaders           00000400
//    CheckSum                00000000
//    Subsystem               00000002        (Windows GUI)
//    DllCharacteristics      00000000
//    SizeOfStackReserve      00100000
//    SizeOfStackCommit       00001000
//    SizeOfHeapReserve       00100000
//    SizeOfHeapCommit        00001000
//    LoaderFlags             00000000
//    NumberOfRvaAndSizes     00000010
//
//    The Data Directory
//    Entry 0 00000000 00000000 Export Directory [.edata (or where ever we found it)]
//    Entry 1 000b0608 00000104 Import Directory [parts of .idata]
//    Entry 2 00ace000 000017b8 Resource Directory [.rsrc]
//    Entry 3 00000000 00000000 Exception Directory [.pdata]
//    Entry 4 00000000 00000000 Security Directory
//    Entry 5 00000000 00000000 Base Relocation Directory [.reloc]
//    Entry 6 00000000 00000000 Debug Directory
//    Entry 7 00000000 00000000 Description Directory
//    Entry 8 00000000 00000000 Special Directory
//    Entry 9 00000000 00000000 Thread Storage Directory [.tls]
//    Entry a 00000000 00000000 Load Configuration Directory
//    Entry b 00000000 00000000 Bound Import Directory
//    Entry c 000ac000 00000290 Import Address Table Directory
//    Entry d 00000000 00000000 Delay Import Directory
//    Entry e 00000000 00000000 CLR Runtime Header
//    Entry f 00000000 00000000 Reserved
//
//    There is an import table in .rdata at 0x4b0608
//
//    The Import Tables (interpreted .rdata section contents)
//     vma:            Hint    Time      Forward  DLL       First
//                     Table   Stamp     Chain    Name      Thunk
//     000b0608       000b0774 00000000 00000000 000b0bb8 000ac068
//
//            DLL Name: KERNEL32.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0b7e     298  GetStdHandle
//            b0b5a      72  DebugBreak
//            b0b68     442  OutputDebugStringA
//            b0b8e     520  SetConsoleTextAttribute
//            b0af6      42  CreateDirectoryA
//            b0b30      78  DeleteFileA
//            b0b4a     135  FindNextFileA
//            b0b3e     126  FindClose
//            b0b1c     479  RemoveDirectoryA
//            b0a94     254  GetModuleHandleA
//            b0a7e     618  WaitForSingleObject
//            b0a70      24  CloseHandle
//            b0a5e     583  TerminateThread
//            b0a4e      46  CreateEventA
//            b0a3e      67  CreateThread
//            b0a32     532  SetEvent
//            b0a22     577  SuspendThread
//            b0a12     482  ResumeThread
//            b09fc     535  SetFileAttributesA
//            b09e8     174  GetComputerNameA
//            b09d0      88  EnterCriticalSection
//            b0b0a     130  FindFirstFileA
//            b0abe     244  GetLastError
//            b0ae6     223  GetDriveTypeA
//            b0ace     335  GetVolumeInformationA
//            b0ba8     624  WriteConsoleA
//            b0aa8     622  WideCharToMultiByte
//            b099c     377  InitializeCriticalSection
//            b1116     382  InterlockedIncrement
//            b125e     603  VirtualAlloc
//            b13f6     485  RtlUnwind
//            b13ea     265  GetOEMCP
//            b13e0     157  GetACP
//            b13d4     163  GetCPInfo
//            b13ba     227  GetEnvironmentStringsW
//            b13a2     225  GetEnvironmentStrings
//            b1388     151  FreeEnvironmentStringsW
//            b136e     150  FreeEnvironmentStringsA
//            b1358     252  GetModuleFileNameA
//            b133c     592  UnhandledExceptionFilter
//            b132c     528  SetEndOfFile
//            b131c     553  SetStdHandle
//            b1310     635  WriteFile
//            b1304     470  ReadFile
//            b12f2     537  SetFilePointer
//            b12e0     539  SetHandleCount
//            b12d2     586  TlsGetValue
//            b12c2     542  SetLastError
//            b12b6     584  TlsAlloc
//            b12a8     587  TlsSetValue
//            b1292     214  GetCurrentThreadId
//            b1280     302  GetStringTypeW
//            b09b8     399  LeaveCriticalSection
//            b1488     529  SetEnvironmentVariableA
//            b1476      31  CompareStringW
//            b1464      30  CompareStringA
//            b1452     247  GetLocaleInfoW
//            b126e     299  GetStringTypeA
//            b11ac     119  FileTimeToLocalFileTime
//            b1250     606  VirtualFree
//            b1242     362  HeapCreate
//            b1234     364  HeapDestroy
//            b1438     328  GetTimeZoneInformation
//            b1428     400  LoadLibraryA
//            b1224     398  LCMapStringW
//            b1214     397  LCMapStringA
//            b1414     142  FlushFileBuffers
//            b11fe     427  MultiByteToWideChar
//            b11ec     278  GetProcAddress
//            b11d4      76  DeleteCriticalSection
//            b11c6     369  HeapReAlloc
//            b10fe     379  InterlockedDecrement
//            b1194     120  FileTimeToSystemTime
//            b1402     246  GetLocaleInfoA
//            b112e     366  HeapFree
//            b10c8     107  ExitProcess
//            b10d6     582  TerminateProcess
//            b10ea     211  GetCurrentProcess
//            b1186     332  GetVersion
//            b1162     296  GetStartupInfoA
//            b113a     360  HeapAlloc
//            b1146     239  GetFileType
//            b1154      49  CreateFileA
//            b1174     170  GetCommandLineA
//
//     000b061c       000b08dc 00000000 00000000 000b0e1a 000ac1d0
//
//            DLL Name: USER32.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0ce0     612  wsprintfA
//            b0bc6     255  GetKeyNameTextA
//            b0bd8     237  GetCursorPos
//            b0be8     494  SetCursorPos
//            b0bf8     405  MessageBoxA
//            b0c06     396  MapVirtualKeyA
//            b0c18     557  ShowWindow
//            b0c26     228  GetClientRect
//            b0c36     317  GetWindowRect
//            b0c46     142  DialogBoxParamA
//            b0c58     314  GetWindowLongA
//            b0c6a     498  SetDlgItemTextA
//            b0c7c      47  CheckDlgButton
//            b0c8e     539  SetWindowLongA
//            b0ca0     474  SendMessageA
//            b0cb0     243  GetDlgItem
//            b0cbe     180  EndDialog
//            b0cca     354  IsDlgButtonChecked
//            b0d64     581  TranslateMessage
//            b0cec     413  MoveWindow
//            b0cfa     240  GetDesktopWindow
//            b0d0e     553  ShowCursor
//            b0d1c      54  ClientToScreen
//            b0d2e     300  GetSystemMetrics
//            b0d42     205  FindWindowA
//            b0e08     435  PostQuitMessage
//            b0df6     128  DefWindowProcA
//            b0dea     374  LoadIconA
//            b0ddc     370  LoadCursorA
//            b0dc8     447  RegisterClassExA
//            b0db6      85  CreateWindowExA
//            b0da6     593  UpdateWindow
//            b0d96     542  SetWindowPos
//            b0d86     431  PeekMessageA
//            b0d78     277  GetMessageA
//            b0d50     144  DispatchMessageA
//
//     000b0630       000b0740 00000000 00000000 000b0e8e 000ac034
//
//            DLL Name: GDI32.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0e34      70  DeleteObject
//            b0e60     330  SelectObject
//            b0e70     337  SetBkMode
//            b0e50     370  SetTextColor
//            b0e7c     250  GetStockObject
//            b0e26      43  CreateFontA
//            b0e44     387  TextOutA
//
//     000b0644       000b070c 00000000 00000000 000b0eee 000ac000
//
//            DLL Name: ADVAPI32.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0eca     302  RegOpenKeyExA
//            b0e98     279  RegCloseKey
//            b0ea6     283  RegCreateKeyExA
//            b0eb8     321  RegSetValueExA
//            b0eda     310  RegQueryValueExA
//
//     000b0658       000b0988 00000000 00000000 000b0f44 000ac27c
//
//            DLL Name: ole32.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0f32      72  CoUninitialize
//            b0f22      38  CoInitialize
//            b0f0e      12  CoCreateInstance
//            b0efc     243  StringFromGUID2
//
//     000b066c       000b072c 00000000 00000000 000b0f7a 000ac020
//
//            DLL Name: DDRAW.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0f66       6  DirectDrawCreate
//            b0f4e       8  DirectDrawEnumerateA
//
//     000b0680       000b0738 00000000 00000000 000b0f9a 000ac02c
//
//            DLL Name: DINPUT.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0f84       0  DirectInputCreateA
//
//     000b0694       000b0980 00000000 00000000 000b0fb4 000ac274
//
//            DLL Name: WINMM.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0fa6     151  timeGetTime
//
//     000b06a8       000b0724 00000000 00000000 000b0fbe 000ac018
//
//            DLL Name: COMCTL32.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            80000011           17  <none>
//
//     000b06bc       000b0970 00000000 00000000 000b100e 000ac264
//
//            DLL Name: VERSION.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b0ff4       1  GetFileVersionInfoSizeA
//            b0fde       0  GetFileVersionInfoA
//            b0fcc      10  VerQueryValueA
//
//     000b06d0       000b0760 00000000 00000000 000b1074 000ac054
//
//            DLL Name: IFORCE2.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b101a       8  _IFReleaseProject@4
//            b1048       7  _IFReleaseEffects@8
//            b105e       1  _IFCreateEffects@12
//            b1030       2  _IFLoadProjectFile@8
//
//     000b06e4       000b08c8 00000000 00000000 000b10be 000ac1bc
//
//            DLL Name: Smush.dll
//            vma:  Hint/Ord Member-Name Bound-To
//            b109c       1  SmushSetVolume
//            b1090       0  SmushPlay
//            b1080       2  SmushShutdown
//            b10ae       3  SmushStartup
//
//     000b06f8       00000000 00000000 00000000 00000000 00000000
//
//    The .rsrc Resource Directory section:
//    000  Type Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 5
//    010   Entry: ID: 0x000003, Value: 0x80000038
//    038    Name Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 2
//    048     Entry: ID: 0x000001, Value: 0x800000d0
//    0d0      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    0e0       Entry: ID: 0x000409, Value: 0x0001a8
//    1a8        Leaf: Addr: 0xace858, Size: 0x0002e8, Codepage: 0
//    050     Entry: ID: 0x000002, Value: 0x800000e8
//    0e8      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    0f8       Entry: ID: 0x000409, Value: 0x0001b8
//    1b8        Leaf: Addr: 0xaceb40, Size: 0x0008a8, Codepage: 0
//    018   Entry: ID: 0x000005, Value: 0x80000058
//    058    Name Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 1, IDs: 3
//    068     Entry: name: [val: 80000238 len 17]: IDD_STARTUPDIALOG, Value: 0x80000100
//    100      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    110       Entry: ID: 0x000409, Value: 0x0001c8
//    1c8        Leaf: Addr: 0xace260, Size: 0x0002d2, Codepage: 0
//    070     Entry: ID: 0x000065, Value: 0x80000118
//    118      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    128       Entry: ID: 0x000409, Value: 0x0001d8
//    1d8        Leaf: Addr: 0xace6c8, Size: 0x000178, Codepage: 0
//    078     Entry: ID: 0x000068, Value: 0x80000130
//    130      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    140       Entry: ID: 0x000409, Value: 0x0001e8
//    1e8        Leaf: Addr: 0xace538, Size: 0x0000aa, Codepage: 0
//    080     Entry: ID: 0x000069, Value: 0x80000148
//    148      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    158       Entry: ID: 0x000409, Value: 0x0001f8
//    1f8        Leaf: Addr: 0xace5e8, Size: 0x0000de, Codepage: 0
//    020   Entry: ID: 0x00000e, Value: 0x80000088
//    088    Name Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    098     Entry: ID: 0x000071, Value: 0x80000160
//    160      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    170       Entry: ID: 0x000409, Value: 0x000208
//    208        Leaf: Addr: 0xacf3e8, Size: 0x000022, Codepage: 0
//    028   Entry: ID: 0x000010, Value: 0x800000a0
//    0a0    Name Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    0b0     Entry: ID: 0x000001, Value: 0x80000178
//    178      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    188       Entry: ID: 0x000409, Value: 0x000218
//    218        Leaf: Addr: 0xacf410, Size: 0x0003a4, Codepage: 0
//    030   Entry: ID: 0x0000f0, Value: 0x800000b8
//    0b8    Name Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 1, IDs: 0
//    0c8     Entry: name: [val: 80000238 len 17]: IDD_STARTUPDIALOG, Value: 0x80000190
//    190      Language Table: Char: 0, Time: 00000000, Ver: 0/0, Num Names: 0, IDs: 1
//    1a0       Entry: ID: 0x000409, Value: 0x000228
//    228        Leaf: Addr: 0xace840, Size: 0x000014, Codepage: 0
//     String table starts at offset: 0x238
//     Resources start at offset: 0x858
//
//    Sections:
//    Idx Name          Size      VMA       LMA       File off  Algn
//      0 .text         000aa750  00401000  00401000  00000400  2**2
//                      CONTENTS, ALLOC, LOAD, READONLY, CODE
//      1 .rdata        000054a2  004ac000  004ac000  000aac00  2**2
//                      CONTENTS, ALLOC, LOAD, READONLY, DATA
//      2 .data         00023600  004b2000  004b2000  000b0200  2**2
//                      CONTENTS, ALLOC, LOAD, DATA
//      3 .rsrc         000017b8  00ece000  00ece000  000d3800  2**2
//                      CONTENTS, ALLOC, LOAD, READONLY, DATA
//    SYMBOL TABLE:
//    no symbols
