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
            return Self{
                .left = 0,
                .top = 0,
                .width = 0,
                .height = 0,
            };
        }

        pub fn fromVec(position: *const Vector2, size: *const Vector2) Self {
            return Self{
                .left = position.x,
                .top = position.y,
                .width = size.x,
                .height = size.y,
            };
        }

        pub fn getRight(self: *const Self) T {
            return self.left + self.width;
        }

        pub fn getBottom(self: *const Self) T {
            return self.top + self.height;
        }

        pub fn getTopLeft(self: *const Self) Vector2 {
            return v.Vector2(T){
                .x = self.left,
                .y = self.top,
            };
        }

        pub fn getCenter(self: *const Self) Vector2 {
            return v.Vector2(T){
                .x = (self.left + self.width) / 2,
                .y = (self.top + self.height) / 2,
            };
        }

        pub fn getSize(self: *const Self) Vector2 {
            return v.Vector2(T){
                .x = self.width,
                .y = self.height,
            };
        }

        pub fn contains(self: *const Self, box: *const Self) bool {
            return self.left <= box.left and
                box.getRight() <= self.getRight() and
                self.top <= box.top and
                box.getBottom() <= self.getBottom();
        }

        pub fn intersects(self: *const Self, box: *const Self) bool {
            return !(self.left >= box.getRight() or
                self.getRight() <= box.left or
                self.top >= box.getBottom() or
                self.getBottom() <= box.top);
        }
    };
}
