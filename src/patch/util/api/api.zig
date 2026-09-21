pub const helper = @import("api_helper.zig");

//------------------------------------------------------------------------------
// ASettings

const core_settings = @import("../core/core_settings.zig");
pub const ASettingHandle = core_settings.Handle;
pub const ASETTING_HANDLE_NULL = core_settings.HANDLE_NULL;
pub const ASettingMessage = core_settings.Message;
pub const ASettingMValue = core_settings.Message.Value;
//pub const ASettingSetting = core_settings.Setting;
//pub const ASettingSValue = core_settings.Setting.Value;
pub const ASettingKind = core_settings.Kind;

//------------------------------------------------------------------------------
// RAddress

const core_address = @import("../core/core_address.zig");
pub const RAddressHandle = core_address.AddressHandleOpaque;
pub const RADDRESS_HANDLE_NULL = core_address.ADDRESS_HANDLE_OPAQUE_NULL;
