pub const ActiveState = enum(u8) {
    Off = 0,
    On = 1,
    JustOff = 2,
    JustOn = 3,

    pub fn on(self: *const ActiveState) bool {
        return (@intFromEnum(self.*) & 1) > 0;
    }

    pub fn new(self: *const ActiveState) bool {
        return (@intFromEnum(self.*) & 2) > 0;
    }

    pub fn update(self: *ActiveState, down: bool) void {
        const next: u8 = @intFromBool(down);
        const changed: u8 = (next ^ @intFromBool(self.on())) << 1;
        self.* = @enumFromInt(next | changed);
    }
};
