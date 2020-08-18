const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub fn RC(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,
        destructor: ?fn (Self) void,
        ref_count: *usize,
        item: *T,

        pub fn init(a: *Allocator) !Self {
            var temp: Self = Self{
                .allocator = a,
                .destructor = null,
                .ref_count = undefined,
                .item = undefined,
            };

            temp.ref_count = try a.create(usize);
            errdefer a.destroy(temp.ref_count);
            temp.item = try a.create(T);
            errdefer a.destroy(temp.item); //redundant

            temp.ref_count.* = 1;
            return temp;
        }

        pub fn initWithDestructor(a: *Allocator, d: fn (Self) void) !Self {
            var temp = try Self.init(a);
            temp.destructor = d;
            return temp;
        }

        pub fn inc(self: Self) Self {
            _ = @atomicRmw(usize, self.ref_count, .Add, 1, .Monotonic);
            return self;
        }

        pub fn dec(self: Self) void {
            const ref_count = @atomicRmw(usize, self.ref_count, .Sub, 1, .Monotonic);
            if (ref_count == 1) { //returns the previous value, 1=0
                if (self.destructor) |f| {
                    f(self);
                } else {
                    self.deinit();
                }
            }
        }

        //this is called automatically once the ref count reaches 0
        //only use this for custom destructors
        pub fn deinit(self: Self) void {
            self.allocator.destroy(self.ref_count);
            self.allocator.destroy(self.item);
        }
    };
}

fn rcTestNormal(r: RC(i32)) void {
    defer r.dec();
}

test "RC normal" {
    const allocator = &testing.allocator_instance.allocator;
    var rc = try RC(i32).init(allocator);
    defer rc.dec();

    rcTestNormal(rc.inc());
}

fn rcTestDestructor(r: RC(*i32)) void {
    r.allocator.destroy(r.item.*); //**i32 => *i32
    r.deinit();
}

test "RC custom destructor" {
    const allocator = &testing.allocator_instance.allocator;

    var rc = try RC(*i32).initWithDestructor(allocator, rcTestDestructor);
    defer rc.dec();

    const x = try allocator.create(i32);

    rc.item.* = x;
}
