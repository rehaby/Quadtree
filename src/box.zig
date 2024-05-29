const v = @import("vector2.zig");

pub fn Box(comptime T: type) type {
    return struct {
        left: T,
        top: T,
        width: T,
        height: T,

        pub fn makeZero() Box(T) {
            return Box(T){ .left = 0, .top = 0, .width = 0, .height = 0 };
        }

        pub fn fromVec(position: v.Vector2(T), size: v.Vector2(T)) Box(T) {
            return Box(T){ .left = position.x, .top = position.y, .width = size.x, .height = size.y };
        }

        pub fn getRight(self: @This()) T {
            return self.left + self.width;
        }

        pub fn getBottom(self: @This()) T {
            return self.top + self.height;
        }

        pub fn getTopLeft(self: @This()) v.Vector2(T) {
            return v.Vector2(T){ .x = self.left, .y = self.top };
        }

        pub fn getCenter(self: @This()) v.Vector2(T) {
            return v.Vector2(T){ .x = (self.left + self.width) / 2, .y = (self.top + self.height) / 2 };
        }

        pub fn getSize(self: @This()) v.Vector2(T) {
            return v.Vector2(T){ .x = self.width, .y = self.height };
        }

        pub fn contains(self: Box(T), box: Box(T)) bool {
            return self.left <= box.left and box.getRight() <= self.getRight() and
                self.top <= box.top and box.getBottom() <= self.getBottom();
        }

        pub fn intersects(self: Box(T), box: Box(T)) bool {
            return !(self.left >= box.getRight() or self.getRight() <= box.left or
                self.top >= box.getBottom() or self.getBottom() <= box.top);
        }
    };
}
