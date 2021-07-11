const net = @import("net");

const Server = struct {
    config: Config,

    const Config = struct {
        name: []u8,
        port: u16,
    };
};
