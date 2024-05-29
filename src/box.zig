const v = @import("vector2.zig");

pub fn Box(comptime T: type) type {
    return struct {
        const Self = @This();
        const Vector2 = v.Vector2(T);
        left: T,
        top: T,
        width: T,
        height: T,

        pub fn makeZero() Self {
            return Self{ .left = 0, .top = 0, .width = 0, .height = 0 };
        }

        pub fn fromVec(position: Vector2, size: Vector2) Self {
            return Self{ .left = position.x, .top = position.y, .width = size.x, .height = size.y };
        }

        pub fn getRight(self: Self) T {
            return self.left + self.width;
        }

        pub fn getBottom(self: Self) T {
            return self.top + self.height;
        }

        pub fn getTopLeft(self: Self) Vector2 {
            return v.Vector2(T){ .x = self.left, .y = self.top };
        }

        pub fn getCenter(self: Self) Vector2 {
            return v.Vector2(T){ .x = (self.left + self.width) / 2, .y = (self.top + self.height) / 2 };
        }

        pub fn getSize(self: Self) Vector2 {
            return v.Vector2(T){ .x = self.width, .y = self.height };
        }

        pub fn contains(self: Self, box: Self) bool {
            return self.left <= box.left and box.getRight() <= self.getRight() and
                self.top <= box.top and box.getBottom() <= self.getBottom();
        }

        pub fn intersects(self: Self, box: Self) bool {
            return !(self.left >= box.getRight() or self.getRight() <= box.left or
                self.top >= box.getBottom() or self.getBottom() <= box.top);
        }
    };
}
