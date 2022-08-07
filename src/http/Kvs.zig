const Kvs = @This();
const std = @import("std");
const ArrayList = std.ArrayList;
const allocPrintZ = std.fmt.allocPrintZ;
const Allocator = std.mem.Allocator;
const HashMap = std.StringHashMap([:0]const u8);
const KeyIterator = HashMap.KeyIterator;

allocator: Allocator = undefined,
store: HashMap = undefined,
strings: ArrayList([:0]const u8) = undefined,

pub fn init(allocator: Allocator) Kvs {
    const self = Kvs{
        .allocator = allocator,
        .store = HashMap.init(allocator),
        .strings = ArrayList([:0]const u8).init(allocator),
    };
    errdefer self.deinit();
    return self;
}

pub fn deinit(self: *Kvs) void {
    // remove strings
    for (self.strings.items) |item| {
        self.allocator.free(item);
    }
    self.strings.deinit();
    self.store.deinit();
    self.* = undefined;
}

pub fn get(self: *Kvs, key: [:0]const u8) ?[:0]const u8 {
    const lowerCaseKey: [:0]const u8 = self.toLowerCase(key) catch {
        return null;
    };
    var value: ?[:0]const u8 = self.store.get(lowerCaseKey);
    self.allocator.free(lowerCaseKey);
    return value;
}

// * lower-case the name but store the value as is

pub fn set(self: *Kvs, key: []const u8, value: []const u8) !void {
    const savedkey: [:0]const u8 = try allocPrintZ(self.allocator, "{s}", .{key});
    try self.strings.append(savedkey);
    const lowerCaseSavedKey: [:0]const u8 = try self.toLowerCase(savedkey);
    try self.strings.append(lowerCaseSavedKey);
    const savedValue: [:0]const u8 = try allocPrintZ(self.allocator, "{s}", .{value});
    try self.strings.append(savedValue);
    try self.store.put(lowerCaseSavedKey, savedValue);
}

pub fn contains(self: *Kvs, key: [:0]const u8) bool {
    const lowerCaseKey: [:0]const u8 = self.toLowerCase(key) catch {
        return false;
    };
    var result: bool = self.store.contains(lowerCaseKey);
    self.allocator.free(lowerCaseKey);
    return result;
}

fn toLowerCase(self: *Kvs, st: [:0]const u8) ![:0]const u8 {
    const result: [:0]u8 = try self.allocator.allocSentinel(u8, st.len, 0); // []T - pointer to runtime-known number of items so const is possible
    for (st) |c, i| result[i] = std.ascii.toLower(c);
    return result;
}

test "Kvs init/deinit" {
    const test_allocator = std.testing.allocator;
    var k = Kvs.init(test_allocator);
    defer k.deinit();
}

test "Kvs get/set/contains" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const eql = std.mem.eql;
    var k = Kvs.init(test_allocator);
    defer k.deinit();
    var value = k.get("kEy");
    try expect(value == null);
    try k.set("kEy", "Value");
    try expect(k.contains("Key"));
    try expect(!k.contains("NoKey"));
    value = k.get("keY");
    try expect(value != null);
    try expect(eql(u8, value.?, "Value"));
}
