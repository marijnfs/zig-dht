const std = @import("std");
const net = std.net;

pub const Server = struct {
    config: Config,
    state: State = .Init,
    stream_server: net.StreamServer = undefined,

    pub fn initialize(server: *Server) !void {
        server.stream_server = net.StreamServer.init(net.StreamServer.Options{});
        const localhost = try net.Address.parseIp(server.config.name, server.config.port);
        try server.stream_server.listen(localhost);
    }

    pub fn accept_loop(server: *Server) !void {
        while (true) {
            var connection = try server.stream_server.accept();
            defer connection.stream.close();
            std.log.info("connection from {}", .{connection});
            var buf: [100]u8 = undefined;

            while (true) {
                var frame = async connection.stream.read(&buf);
                const len = try await frame;
                // const len = try connection.stream.read(&buf);
                std.log.info("read {s}", .{buf[0..len]});
                if (len == 0)
                    break;
            }

            //time to schedule event loop to start connection

        }
    }

    pub fn deinit(server: *Server) void {
        server.stream_server.deinit();
    }

    const Config = struct {
        name: []u8,
        port: u16,
    };

    const State = enum {
        Init,
        Ready,
        Done,
        Error,
    };
};
