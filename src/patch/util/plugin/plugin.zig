pub const helper = @import("plugin_helper.zig");

pub const PluginAPI = @import("plugin_api.zig").PluginAPI;
pub const PLUGIN_API_VERSION = @import("plugin_api.zig").PLUGIN_API_VERSION;

//------------------------------------------------------------------------------
// ASettings

const core_settings = @import("../core/core_settings.zig");
pub const ASettingHandle = core_settings.Handle;
pub const ASETTING_HANDLE_NULL = core_settings.HANDLE_NULL;
pub const ASettingMessage = core_settings.Message;
pub const ASettingMValue = core_settings.MessageValue;
//pub const ASettingSetting = core_settings.Setting;
//pub const ASettingSValue = core_settings.SettingValue;
pub const ASettingKind = core_settings.Kind;

//------------------------------------------------------------------------------
// RAddress

const core_address = @import("../core/core_address.zig");
pub const RAddressHandle = core_address.AddressHandleOpaque;
pub const RADDRESS_HANDLE_NULL = core_address.ADDRESS_HANDLE_OPAQUE_NULL;

//------------------------------------------------------------------------------
// AInput

const core_input = @import("../core/core_input.zig");
pub const AInputXInputAxis = core_input.XInputAxis;
pub const AInputXInputButton = core_input.XInputButton;
pub const AInputPoint = core_input.Point;
pub const AInputVirtualKey = core_input.VirtualKey;

//------------------------------------------------------------------------------
// GDraw

const core_draw = @import("../core/core_draw.zig");
pub const GDrawLayer = core_draw.Layer;
