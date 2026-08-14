/// Boolean state tracking that encodes whether or not the state changed during
/// the most recent update. Used to differentiate behaviours based on new-ness
/// of the state, such as clicking vs holding a button.
///
/// This is encoded as a bitfield as follows:
///   1<<0    current on/off state
///   1<<1    state changed during the last call to `update`
pub const ToggleState = enum(u8) {
    Off = 0b00,
    On = 0b01,
    /// state is OFF, and was ON before the last call to `update`
    JustOff = 0b10,
    /// state is ON, and was OFF before the last call to `update`
    JustOn = 0b11,

    pub fn on(self: *const ToggleState) bool {
        return (@intFromEnum(self.*) & 1) > 0;
    }

    pub fn new(self: *const ToggleState) bool {
        return (@intFromEnum(self.*) & 2) > 0;
    }

    pub fn update(self: *ToggleState, down: bool) void {
        const next: u8 = @intFromBool(down);
        const changed: u8 = (next ^ @intFromBool(self.on())) << 1;
        self.* = @enumFromInt(next | changed);
    }
};
