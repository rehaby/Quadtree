const std = @import("std");
const v = @import("vector2.zig");
const b = @import("box.zig");

pub fn Quadtree(comptime T: type, comptime UnitType: type) type {
    return struct {
        const Self = @This();
        const Vector2 = v.Vector2(UnitType);
        const Box = b.Box(UnitType);
        const Quadrant = enum(i8) { TopRight = 0, TopLeft = 1, BottomRight = 2, BottomLeft = 3, None = 5 };

        comptime Threshold: usize = 16,
        comptime MaxDepth: usize = 8,

        allocator: std.mem.Allocator,

        mBox: Box,
        mRoot: Node,
        mGetBox: *const fn (T) Box,
        mEqual: *const fn (T, T) bool,

        pub const ValuePair = struct { T, T };

        const Node = struct {
            children: [4]?*Node = .{ null, null, null, null },
            values: std.ArrayListUnmanaged(T),

            pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
                self.values.deinit(allocator);
                for (self.children) |child| {
                    if (child) |node| {
                        node.deinit(allocator);
                        allocator.destroy(node);
                    }
                }
            }
        };

        pub fn init(allocator: std.mem.Allocator, box: Box, GetBox: *const fn (T) Box, Equal: *const fn (T, T) bool) Self {
            return Self{ .allocator = allocator, .mBox = box, .mGetBox = GetBox, .mEqual = Equal, .mRoot = Node{ .values = std.ArrayListUnmanaged(T){} } };
        }

        pub fn deinit(self: *Self) void {
            self.mRoot.deinit(self.allocator);
        }

        pub fn add(self: *Self, value: T) !void {
            return self.add_value(&self.mRoot, 0, self.mBox, value);
        }

        pub fn remove(self: *Self, value: T) !void {
            _ = try self.remove_value(&self.mRoot, self.mBox, value);
        }

        pub fn query(self: Self, box: Box) !std.ArrayList(T) {
            var values = std.ArrayList(T).init(self.allocator);
            try self.query_box(self.mRoot, self.mBox, box, &values);
            return values;
        }

        //std::vector<std::pair<T, T>> findAllIntersections() const
        fn findAllIntersections(self: Self) !std.ArrayList(ValuePair) {
            var intersections = std.ArrayList(ValuePair).init(self.allocator);
            try self.findAllIntersections_in_node(self.mRoot, &intersections);
            return intersections;
        }

        fn isLeaf(node: Node) bool {
            return node.children[0] == null;
        }

        //Box<Float> computeBox(const Box<Float>& box, int i) const
        fn computeBox(box: Box, i: Quadrant) Box {
            std.debug.assert(@intFromEnum(Quadrant.TopRight) == 0);
            std.debug.assert(@intFromEnum(Quadrant.TopLeft) == 1);
            std.debug.assert(@intFromEnum(Quadrant.BottomRight) == 2);
            std.debug.assert(@intFromEnum(Quadrant.BottomLeft) == 3);

            const origin = box.getTopLeft();
            const childSize = box.getSize().div(2.0);
            return switch (i) {
                // North West
                Quadrant.TopRight => Box.fromVec(origin, childSize),
                // Norst East
                Quadrant.TopLeft => Box.fromVec(Vector2{ .x = origin.x + childSize.x, .y = origin.y }, childSize),
                // South West
                Quadrant.BottomRight => Box.fromVec(Vector2{ .x = origin.x, .y = origin.y + childSize.y }, childSize),
                // South East
                Quadrant.BottomLeft => Box.fromVec(origin.add(childSize), childSize),
                else => unreachable,
            };
        }

        //int getQuadrant(const Box<Float>& nodeBox, const Box<Float>& valueBox) const
        fn getQuadrant(nodeBox: Box, valueBox: Box) Quadrant {
            const center = nodeBox.getCenter();
            // West
            if (valueBox.getRight() < center.x) {
                // North West
                if (valueBox.getBottom() < center.y) {
                    return Quadrant.TopRight;
                }
                // South West
                else if (valueBox.top >= center.y) {
                    return Quadrant.BottomRight;
                }
                // Not contained in any quadrant
                else return Quadrant.None;
            }
            // East
            else if (valueBox.left >= center.x) {
                // North East
                if (valueBox.getBottom() < center.y) {
                    return Quadrant.TopLeft;
                }
                // South East
                else if (valueBox.top >= center.y) {
                    return Quadrant.BottomLeft;
                }
                // Not contained in any quadrant
                else return Quadrant.None;
            }
            // Not contained in any quadrant
            else return Quadrant.None;
        }

        fn getChild(node: *Node, quadrant: Quadrant) ?*Node {
            return switch (quadrant) {
                Quadrant.TopRight => node.children[0],
                Quadrant.TopLeft => node.children[1],
                Quadrant.BottomRight => node.children[2],
                Quadrant.BottomLeft => node.children[3],
                Quadrant.None => null,
            };
        }

        //void add(Node* node, std::size_t depth, const Box<Float>& box, const T& value)
        fn add_value(self: Self, node: *Node, depth: usize, box: Box, value: T) !void {
            std.debug.assert(box.contains(self.mGetBox(value)));

            if (isLeaf(node.*)) {
                // Insert the value in this node if possible
                if (depth >= self.MaxDepth or node.values.items.len < self.Threshold) {
                    try node.values.append(self.allocator, value);
                    // Otherwise, we split and we try again
                } else {
                    try self.split(node, box);
                    try self.add_value(node, depth, box, value);
                }
            } else {
                const i = getQuadrant(box, self.mGetBox(value));
                const child = getChild(node, i);
                // Add the value in a child if the value is entirely contained in it
                if (child) |kid| {
                    try self.add_value(kid, depth + 1, computeBox(box, i), value);
                }
                // Otherwise, we add the value in the current node
                else {
                    try node.values.append(self.allocator, value);
                }
            }
        }

        //void split(Node* node, const Box<Float>& box)
        fn split(self: Self, node: *Node, box: Box) !void {
            //assert(node != nullptr);
            std.debug.assert(isLeaf(node.*)); // && "Only leaves can be split");
            // Create children
            for (0..node.children.len) |i| {
                node.children[i] = try self.allocator.create(Node); //{ .values = std.ArrayList(T).init(self.allocator) };
                node.children[i].?.* = Node{ .values = std.ArrayListUnmanaged(T){} };
            }
            // Assign values to children
            var newValues = std.ArrayListUnmanaged(T){}; // New values for this node
            for (node.values.items) |value| {
                const i = getQuadrant(box, self.mGetBox(value));
                const child = getChild(node, i);
                if (child) |kid| {
                    try kid.values.append(self.allocator, value);
                } else {
                    try newValues.append(self.allocator, value);
                }
            }
            node.values.deinit(self.allocator);
            node.values = newValues;
        }

        //bool remove(Node* node, const Box<Float>& box, const T& value)
        fn remove_value(self: *Self, node: *Node, box: Box, value: T) !bool {
            std.debug.assert(box.contains(self.mGetBox(value)));
            if (isLeaf(node.*)) {
                // Remove the value from node
                try self.removeValue(node, value);
                return true;
            } else {
                // Remove the value in a child if the value is entirely contained in it
                const i = getQuadrant(box, self.mGetBox(value));
                const child = getChild(node, i);
                if (child) |kid| {
                    if (try self.remove_value(kid, computeBox(box, i), value)) {
                        return self.tryMerge(node);
                    }
                }
                // Otherwise, we remove the value from the current node
                else {
                    try self.removeValue(node, value);
                }
                return false;
            }
        }

        //void removeValue(Node* node, const T& value)
        fn removeValue(self: *Self, node: *Node, value: T) !void {
            var index: usize = std.math.maxInt(usize);
            for (0.., node.values.items) |i, item| {
                if (self.mEqual(value, item)) {
                    index = i;
                }
            }
            std.debug.assert(index < node.values.items.len);
            _ = node.values.swapRemove(index);
            // Find the value in node->values
            //auto it = std::find_if(std::begin(node->values), std::end(node->values),
            //[this, &value](const auto& rhs){ return mEqual(value, rhs); });
            //assert(it != std::end(node->values) && "Trying to remove a value that is not present in the node");
            // Swap with the last element and pop back
            //*it = std::move(node->values.back());
            //node->values.pop_back();
        }

        //bool tryMerge(Node* node)
        fn tryMerge(self: *Self, node: *Node) !bool {
            std.debug.assert(!isLeaf(node.*)); // && "Only interior nodes can be merged");
            var nbValues = node.values.items.len;
            for (node.children) |child| {
                if (!isLeaf(child.?.*)) {
                    return false;
                }
                nbValues += child.?.values.items.len;
            }
            if (nbValues <= self.Threshold) {
                try node.values.ensureTotalCapacity(self.allocator, nbValues); //reserve(nbValues);
                // Merge the values of all the children
                for (node.children) |child| {
                    for (child.?.values.items) |value| {
                        try node.values.append(self.allocator, value);
                    }
                }
                // Remove the children
                for (0..node.children.len) |i| {
                    node.children[i].?.deinit(self.allocator);
                    self.allocator.destroy(node.children[i].?);
                    node.children[i] = null;
                }

                return true;
            } else {
                return false;
            }
        }

        //void query(Node* node, const Box<Float>& box, const Box<Float>& queryBox, std::vector<T>& values) const
        fn query_box(self: Self, node: Node, box: Box, queryBox: Box, values: *std.ArrayList(T)) !void {
            //assert(node != nullptr);
            std.debug.assert(queryBox.intersects(box));
            for (node.values.items) |value| {
                if (queryBox.intersects(self.mGetBox(value))) {
                    try values.append(value);
                }
            }
            if (!isLeaf(node)) {
                for (0..node.children.len) |i| {
                    const childBox = computeBox(box, @enumFromInt(i));
                    if (queryBox.intersects(childBox)) {
                        try self.query_box(node.children[i].?.*, childBox, queryBox, values);
                    }
                }
            }
        }

        //void findAllIntersections(Node* node, std::vector<std::pair<T, T>>& intersections) const
        fn findAllIntersections_in_node(self: Self, node: Node, intersections: *std.ArrayList(ValuePair)) !void {
            // Find intersections between values stored in this node
            // Make sure to not report the same intersection twice
            for (0..node.values.items.len) |i| {
                for (0..i) |j| {
                    if (self.mGetBox(node.values.items[i]).intersects(self.mGetBox(node.values.items[j]))) {
                        try intersections.append(.{ node.values.items[i], node.values.items[j] });
                    }
                }
            }
            if (!isLeaf(node)) {
                // Values in this node can intersect values in descendants
                for (node.children) |child| {
                    for (node.values.items) |value| {
                        try self.findIntersectionsInDescendants(child.?.*, value, intersections);
                    }
                }
                // Find intersections in children
                for (node.children) |child| {
                    try self.findAllIntersections_in_node(child.?.*, intersections);
                }
            }
        }

        //void findIntersectionsInDescendants(Node* node, const T& value, std::vector<std::pair<T, T>>& intersections) const
        fn findIntersectionsInDescendants(self: Self, node: Node, value: T, intersections: *std.ArrayList(ValuePair)) !void {
            // Test against the values stored in this node
            for (node.values.items) |other| {
                if (self.mGetBox(value).intersects(self.mGetBox(other))) {
                    try intersections.append(.{ value, other });
                }
            }
            // Test against values stored into descendants of this node
            if (!isLeaf(node)) {
                for (node.children) |child| {
                    try self.findIntersectionsInDescendants(child.?.*, value, intersections);
                }
            }
        }
    };
}

const test_node = struct { box: b.Box(f32), id: usize };

fn test_node_less_than(context: void, node1: *const test_node, node2: *const test_node) bool {
    _ = context;
    return node1.*.id < node2.*.id;
}

fn test_valuePair_less_than(context: void, node1: Quadtree(*const test_node, f32).ValuePair, node2: Quadtree(*const test_node, f32).ValuePair) bool {
    _ = context;
    if (node1[0].id == node2[0].id) {
        return node1[1].id < node2[1].id;
    }
    return node1[0].id < node2[0].id;
}

//std::vector<Node> generateRandomNodes(std::size_t n)
fn generateRandomNodes(n: usize, allocator: std.mem.Allocator) !std.ArrayList(test_node) {
    var generator = std.rand.DefaultPrng.init(0); //TODO seed
    //const originDistribution = generator.random().
    //auto generator = std::default_random_engine();
    //auto originDistribution = std::uniform_real_distribution(0.0f, 1.0f);
    //auto sizeDistribution = std::uniform_real_distribution(0.0f, 0.01f);
    //auto nodes = std::vector<Node>(n);
    var nodes = std.ArrayList(test_node).init(allocator);
    try nodes.resize(n);
    //try nodes.ensureTotalCapacity(n);
    //for (auto i = std::size_t(0); i < n; ++i)
    for (0..n) |i| {
        //try nodes.append(test_node{ .id = i, .box = b.Box(f32){ .left = generator.random().float(f32) / 10.0, .top = generator.random().float(f32) / 10.0, .width = @min(1.0 - nodes.items[i].box.left, generator.random().float(f32)), .height = @min(1.0 - nodes.items[i].box.top, generator.random().float(f32)) } });
        nodes.items[i].box.left = generator.random().float(f32) / 10.0; //originDistribution(generator);
        nodes.items[i].box.top = generator.random().float(f32) / 10.0; //originDistribution(generator);
        nodes.items[i].box.width = @min(1.0 - nodes.items[i].box.left, generator.random().float(f32));
        nodes.items[i].box.height = @min(1.0 - nodes.items[i].box.top, generator.random().float(f32));
        nodes.items[i].id = i;
    }
    return nodes;
}

fn generateRandomRemoved(n: usize, allocator: std.mem.Allocator) !std.ArrayList(bool) {
    var generator = std.rand.DefaultPrng.init(0); //TODO seed
    var removed = std.ArrayList(bool).init(allocator);
    try removed.resize(n);

    for (removed.items) |*remove| {
        remove.* = generator.random().int(u1) != 0;
    }

    return removed;
}

//std::vector<Node*> query(const Box<float>& box, std::vector<Node>& nodes, const std::vector<bool>& removed)
fn query(box: b.Box(f32), nodes: std.ArrayList(test_node), removed: *std.ArrayList(bool), allocator: std.mem.Allocator) !std.ArrayList(*const test_node) {
    var intersections = std.ArrayList(*const test_node).init(allocator);
    for (nodes.items) |*n| {
        if (removed.*.items.len == 0 or !removed.*.items[n.id]) {
            if (box.intersects(n.box)) {
                try intersections.append(n);
            }
        }
    }
    return intersections;
}

//bool checkIntersections(std::vector<Node*> nodes1, std::vector<Node*> nodes2)
fn checkIntersections(nodes1: std.ArrayList(*const test_node), nodes2: std.ArrayList(*const test_node)) bool {
    if (nodes1.items.len != nodes2.items.len) {
        std.debug.print("len one: {d}, two: {d}\n", .{ nodes1.items.len, nodes2.items.len });
        return false;
    }

    std.mem.sort(*const test_node, nodes1.items, {}, test_node_less_than);
    std.mem.sort(*const test_node, nodes2.items, {}, test_node_less_than);

    // for (0..nodes1.items.len) |i| {
    //     if (nodes1.items[i].id != nodes2.items[i].id) {
    //         return false;
    //     }
    // }
    // return true;
    return std.mem.eql(*const test_node, nodes1.items, nodes2.items); //nodes1 == nodes2;
}

//bool checkIntersections_pairs(std::vector<std::pair<Node*, Node*>> intersections1,
//    std::vector<std::pair<Node*, Node*>> intersections2)
fn checkIntersections_pairs(intersections1: std.ArrayList(Quadtree(*const test_node, f32).ValuePair), intersections2: std.ArrayList(Quadtree(*const test_node, f32).ValuePair)) bool {
    if (intersections1.items.len != intersections2.items.len) {
        std.debug.print("Intersect 1 len {d}, Intersect 2 len {d}\n", .{ intersections1.items.len, intersections2.items.len });
        return false;
    }

    for (intersections1.items) |*intersection| {
        if (intersection[0].*.id >= intersection[1].*.id) {
            std.mem.swap(*const test_node, &intersection[0], &intersection[1]);
        }
    }
    for (intersections2.items) |*intersection| {
        if (intersection[0].*.id >= intersection[1].*.id) {
            std.mem.swap(*const test_node, &intersection[0], &intersection[1]);
        }
    }

    std.mem.sort(Quadtree(*const test_node, f32).ValuePair, intersections1.items, {}, test_valuePair_less_than);
    std.mem.sort(Quadtree(*const test_node, f32).ValuePair, intersections2.items, {}, test_valuePair_less_than);

    for (intersections1.items, intersections2.items) |item1, item2| {
        if ((!std.meta.eql(item1[0], item2[0])) or
            (!std.meta.eql(item1[1], item2[1])))
        {
            std.debug.print("Item 0 id {d}:{d}, Item 1 id {d}:{d}\n", .{ item1[0].*.id, item2[0].*.id, item1[1].*.id, item2[1].*.id });
            return false;
        }
    }

    return true;
}

//std::vector<std::pair<Node*, Node*>> findAllIntersections(std::vector<Node>& nodes, const std::vector<bool>& removed)
fn findAllIntersections(nodes: std.ArrayList(test_node), removed: std.ArrayList(bool), allocator: std.mem.Allocator) !std.ArrayList(Quadtree(*const test_node, f32).ValuePair) {
    var intersections = std.ArrayList(Quadtree(*const test_node, f32).ValuePair).init(allocator);
    for (0..nodes.items.len) |i| {
        if (removed.items.len == 0 or !removed.items[i]) {
            for (0..i) |j| {
                if (removed.items.len == 0 or !removed.items[j]) {
                    if (nodes.items[i].box.intersects(nodes.items[j].box)) {
                        try intersections.append(.{ &nodes.items[i], &nodes.items[j] });
                    }
                }
            }
        }
    }
    return intersections;
}

fn test_GetBox(value: *const test_node) b.Box(f32) {
    return value.box;
}

fn test_Equal(a: *const test_node, bb: *const test_node) bool {
    return a.id == bb.id;
}

fn test_quadtree_add_and_query(n: usize) !void {
    const allocator = std.testing.allocator;
    const nodes = try generateRandomNodes(n, allocator);
    defer nodes.deinit();

    const box = b.Box(f32){ .left = 0, .top = 0, .width = 1, .height = 1 };
    var quadtree = Quadtree(*const test_node, f32).init(allocator, box, test_GetBox, test_Equal);
    defer quadtree.deinit();

    for (nodes.items) |*node| {
        try quadtree.add(node);
    }

    var intersections1 = std.ArrayList(std.ArrayList(*const test_node)).init(allocator);
    defer intersections1.deinit();
    defer for (intersections1.items) |item| {
        item.deinit();
    };

    try intersections1.resize(nodes.items.len);
    for (nodes.items) |node| {
        intersections1.items[node.id] = try quadtree.query(node.box);
    }

    var intersections2 = std.ArrayList(std.ArrayList(*const test_node)).init(allocator);
    defer intersections2.deinit();
    defer for (intersections2.items) |item| {
        item.deinit();
    };

    try intersections2.resize(nodes.items.len);
    // Brute force
    for (nodes.items) |node| {
        var removed = std.ArrayList(bool).init(allocator);
        defer removed.deinit();
        intersections2.items[node.id] = try query(node.box, nodes, &removed, allocator);
    }
    // Check
    for (nodes.items) |node| {
        try std.testing.expect(checkIntersections(intersections1.items[node.id], intersections2.items[node.id]));
    }
}

test "quadtree add and query" {
    for (1..200) |i| {
        try test_quadtree_add_and_query(i);
    }
    try test_quadtree_add_and_query(1000);
}

fn test_quadtree_add_and_findAllIntersecions(n: usize) !void {
    const allocator = std.testing.allocator;
    const nodes = try generateRandomNodes(n, allocator);
    defer nodes.deinit();

    const box = b.Box(f32){ .left = 0, .top = 0, .width = 1, .height = 1 };
    var quadtree = Quadtree(*const test_node, f32).init(allocator, box, test_GetBox, test_Equal);
    defer quadtree.deinit();

    for (nodes.items) |*node| {
        try quadtree.add(node);
    }

    const intersections1 = try quadtree.findAllIntersections();
    defer intersections1.deinit();

    var removed = std.ArrayList(bool).init(allocator);
    defer removed.deinit();

    const intersections2 = try findAllIntersections(nodes, removed, allocator);
    defer intersections2.deinit();

    try std.testing.expect(checkIntersections_pairs(intersections1, intersections2));
}

test "quadtree add and findAllIntersections" {
    for (1..200) |i| {
        try test_quadtree_add_and_findAllIntersecions(i);
    }
    try test_quadtree_add_and_findAllIntersecions(1000);
}

fn test_quadtree_add_remove_and_query(n: usize) !void {
    const allocator = std.testing.allocator;
    const nodes = try generateRandomNodes(n, allocator);
    defer nodes.deinit();

    const box = b.Box(f32){ .left = 0, .top = 0, .width = 1, .height = 1 };
    var quadtree = Quadtree(*const test_node, f32).init(allocator, box, test_GetBox, test_Equal);
    defer quadtree.deinit();

    for (nodes.items) |*node| {
        try quadtree.add(node);
    }

    var removed = try generateRandomRemoved(n, allocator);
    defer removed.deinit();

    for (nodes.items) |node| {
        if (removed.items[node.id]) {
            try quadtree.remove(&node);
        }
    }

    var intersections1 = std.ArrayList(std.ArrayList(*const test_node)).init(allocator);
    defer intersections1.deinit();
    defer for (intersections1.items) |item| {
        item.deinit();
    };

    try intersections1.resize(nodes.items.len);
    for (nodes.items) |node| {
        intersections1.items[node.id] = try quadtree.query(node.box);
    }

    var intersections2 = std.ArrayList(std.ArrayList(*const test_node)).init(allocator);
    defer intersections2.deinit();
    defer for (intersections2.items) |item| {
        item.deinit();
    };

    try intersections2.resize(nodes.items.len);
    // Brute force
    for (nodes.items) |node| {
        intersections2.items[node.id] = try query(node.box, nodes, &removed, allocator);
    }
    // Check
    for (nodes.items) |node| {
        try std.testing.expect(checkIntersections(intersections1.items[node.id], intersections2.items[node.id]));
    }
}

test "quadtree add remove and query" {
    for (1..200) |i| {
        try test_quadtree_add_remove_and_query(i);
    }
    try test_quadtree_add_remove_and_query(1000);
}

fn test_quadtree_add_remove_and_find_all_intersections(n: usize) !void {
    const allocator = std.testing.allocator;
    const nodes = try generateRandomNodes(n, allocator);
    defer nodes.deinit();

    const box = b.Box(f32){ .left = 0, .top = 0, .width = 1, .height = 1 };
    var quadtree = Quadtree(*const test_node, f32).init(allocator, box, test_GetBox, test_Equal);
    defer quadtree.deinit();

    for (nodes.items) |*node| {
        try quadtree.add(node);
    }

    var removed = try generateRandomRemoved(n, allocator);
    defer removed.deinit();

    for (nodes.items) |node| {
        if (removed.items[node.id]) {
            try quadtree.remove(&node);
        }
    }

    const intersections1 = try quadtree.findAllIntersections();
    defer intersections1.deinit();

    const intersections2 = try findAllIntersections(nodes, removed, allocator);
    defer intersections2.deinit();

    try std.testing.expect(checkIntersections_pairs(intersections1, intersections2));
}

test "quadtree add remove and find all intersections" {
    for (1..200) |i| {
        try test_quadtree_add_remove_and_find_all_intersections(i);
    }

    try test_quadtree_add_remove_and_find_all_intersections(1000);
}
