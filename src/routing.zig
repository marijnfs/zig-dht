const std = @import("std");
const time = std.time;

const index = @import("index.zig");
const default = index.default;
const utils = index.utils;
const id_ = index.id;
const hex = index.hex;

const ID = index.ID;
const Hash = index.Hash;

const Record = struct {
    id: ID = std.mem.zeroes(ID),
    address: std.net.Address = undefined,
    red_flags: usize = 0,
    last_connect: i64 = 0,
    public: bool = false,

    fn active(record: *Record, milliThreshold: usize) bool {
        return time.milliTimestamp() - record.last_connect < milliThreshold;
    }

    pub fn format(record: *const Record, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Record, id:{}, addr: {}, last connect: {} ", .{ index.hex(&record.id), record.address, record.last_connect });
    }
};

pub const RoutingTable = struct {
    id: ID,
    addresses_seen: std.AutoHashMap(Hash, std.net.Address),

    records: std.ArrayList(*Record),
    ip_index: std.StringHashMap(*Record),
    id_index: std.AutoHashMap(ID, *Record),

    pub fn init(id: ID) !*RoutingTable {
        var table = try default.allocator.create(RoutingTable);
        table.* = .{
            .id = id,
            .addresses_seen = std.AutoHashMap(Hash, std.net.Address).init(default.allocator),

            .records = std.ArrayList(*Record).init(default.allocator),
            .ip_index = std.StringHashMap(*Record).init(default.allocator),
            .id_index = std.AutoHashMap(ID, *Record).init(default.allocator),
        };

        return table;
    }

    pub fn deinit(table: *RoutingTable) void {
        table.addresses_seen.deinit();
    }

    pub fn get_closest_active_record(table: *RoutingTable, id: ID, require_public: bool) ?Record {
        var closest_record: ?Record = null;
        var closest_distance = id_.ones();

        for (table.records.items) |record| {
            if (!record.active(20000)) {
                continue;
            }
            if (require_public and !record.public) {
                continue;
            }
            const distance = id_.xor(id, record.id);

            if (id_.less(distance, closest_distance)) {
                closest_distance = distance;
                closest_record = record.*;
            }
        }

        return closest_record;
    }

    pub fn get_record_by_ip(table: *RoutingTable, address: std.net.Address) ?Record {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{address});
        return table.ip_index.get(ip_string);
    }

    pub fn get_record_by_id(table: *RoutingTable, id: ID) ?Record {
        return table.id_index.get(id);
    }

    pub fn update_ip_id_pair(table: *RoutingTable, id: ID, addr: std.net.Address, public: bool) !void {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});

        // Get current record or make a new one
        var record = b: {
            if (table.ip_index.get(ip_string)) |record| {
                break :b record;
            } else {
                var record = try default.allocator.create(Record);
                try table.records.append(record);
                break :b record;
            }
        };

        record.* = .{
            .id = id,
            .address = addr,
            .public = public,
            .last_connect = time.milliTimestamp(),
        };

        try table.id_index.put(id, record);
        try table.ip_index.put(ip_string, record);
    }

    pub fn update_ip(table: *RoutingTable, addr: std.net.Address) !void {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});
        defer default.allocator.free(ip_string);

        if (table.ip_index.get(ip_string)) |record| {
            record.last_connect = time.milliTimestamp();
        }
    }

    pub fn get_addresses_seen(table: *RoutingTable) ![]std.net.Address {
        var addresses = try default.allocator.alloc(std.net.Address, table.addresses_seen.count());
        var it = table.addresses_seen.valueIterator();

        var i: usize = 0;
        while (it.next()) |address| {
            addresses[i] = address.*;
            i += 1;
        }
        return addresses;
    }

    // Store directly observed addresses
    pub fn add_address_seen(table: *RoutingTable, addr: std.net.Address) !void {
        std.log.debug("saw ip: {}", .{addr});
        const addr_string = try std.fmt.allocPrint(default.allocator, "{}", .{addr});
        const hash = utils.calculate_hash(addr_string);
        try table.addresses_seen.put(hash, addr);
    }

    pub fn select_random_known_addresses(table: *RoutingTable, n_ips: usize) !std.ArrayList(std.net.Address) {
        var addresses = std.ArrayList(std.net.Address).init(default.allocator);

        var selection = try utils.random_selection(n_ips, table.records.items.len);
        defer default.allocator.free(selection);

        for (selection) |s| {
            try addresses.append(table.records.items[s].address);
        }

        return addresses;
    }

    pub fn get_random_active_record(table: *RoutingTable) !?Record {
        var active_records = std.ArrayList(*Record).init(default.allocator);
        defer active_records.deinit();

        for (table.records.items) |record| {
            if (record.active()) {
                try active_records.add(record);
            }
        }

        if (active_records.items.len == 0) {
            std.log.debug("Didn't find random active connection", .{});
            return null;
        }

        var selection = try utils.random_selection(1, active_records.items.len);
        defer default.allocator.free(selection);

        return active_records.items[selection[0]];
    }

    pub fn verify_address(table: *RoutingTable, address: std.net.Address) !bool {
        const ip_string = try std.fmt.allocPrint(default.allocator, "{}", .{address});
        if (table.ip_index.get(ip_string)) |record| {
            //known
            if (record.red_flags > 1) //drop message
            {
                std.log.debug("Dropping red-flag message, flags: {}", .{record.red_flags});
                return false;
            }
        } else {
            // No record, since we don't have grounds to block we optimistically allow
            return true;
        }
        return true;
    }

    pub fn summarize(table: *RoutingTable, writer: anytype) !void {
        for (table.records.items) |rec| {
            try writer.print("route id:{} addr:{} act:{}\n", .{ hex(rec.id[0..8]), rec.address, rec.active(20000) });
        }
    }
};

test "Basics" {
    var routing = try RoutingTable.init(index.id.rand_id(), 8);
    defer routing.deinit();

    var adresses = try routing.get_addresses_seen();
    try std.testing.expect(adresses.len == 0);

    var count: usize = 0;
    var iter = routing.iter_finger_table();
    while (iter.next()) |kv| {
        count += 1;
        std.log.debug("{}", .{kv});
    }
    try std.testing.expect(count == 8);
}
