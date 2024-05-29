const std = @import("std");

pub fn Vector2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        pub fn add(self: Vector2(T), other: Vector2(T)) Vector2(T) {
            return Vector2(T){ .x = self.x + other.x, .y = self.y + other.y };
        }

        pub fn plus_equal(self: *Vector2(T), other: Vector2(T)) void {
            self.x = self.x + other.x;
            self.y = self.y + other.y;
        }

        pub fn div(self: Vector2(T), value: T) Vector2(T) {
            return Vector2(T){ .x = self.x / value, .y = self.y / value };
        }

        pub fn div_equal(self: *Vector2(T), value: T) void {
            self.x = self.x / value;
            self.y = self.y / value;
        }
    };
}

test "vector add" {
    std.testing.refAllDecls(Vector2(f64));
    const one = Vector2(f64){ .x = 1, .y = 2 };
    const two = Vector2(f64){ .x = 3, .y = 4 };
    const three = one.add(two);

    try std.testing.expect(one.x == 1);
    try std.testing.expect(one.y == 2);
    try std.testing.expect(three.x == 4);
    try std.testing.expect(three.y == 6);
}

test "vector div" {
    const one = Vector2(f64){ .x = 12, .y = 16 };

    const three = one.div(2.0);

    try std.testing.expect(one.x == 12);
    try std.testing.expect(one.y == 16);
    try std.testing.expect(three.x == 6);
    try std.testing.expect(three.y == 8);
}
