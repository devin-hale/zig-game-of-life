const rl = @import("raylib");
const std = @import("std");

const screen_w = 1280;
const screen_h = 720;

const pixel_w = 10;
const pixel_h = 10;

const grid_w = screen_w / pixel_w;
const grid_h = screen_h / pixel_h;

const Grid = struct {
    width: usize,
    height: usize,

    arr: [grid_h][grid_w]bool,

    fn init(w: usize, h: usize, rand: std.Random) Grid {
        var grid: Grid = .{ .width = w, .height = h, .arr = undefined };
        for (0..grid_h) |i| {
            for (0..grid_w) |j| {
                grid.arr[i][j] = if (rand.uintAtMost(u8, 1) == 1) true else false;
            }
        }
        return grid;
    }

    fn init_random(w: usize, h: usize, rand: std.Random) Grid {
        var grid: Grid = .{ .width = w, .height = h, .arr = undefined };
        for (0..grid_h) |i| {
            for (0..grid_w) |j| {
                grid.arr[i][j] = if (rand.uintAtMost(u8, 1) == 1) true else false;
            }
        }
        return grid;
    }

    fn progress(self: *Grid) void {
        var copy: [grid_h][grid_w]bool = undefined;
        @memcpy(&copy, &self.arr);

        for (self.arr, 0..) |row, y| {
            for (row, 0..) |sq, x| {
                const nc = self.live_neighbor_count(x, y);
                if (sq == true) {
                    if (nc < 2) {
                        copy[y][x] = false;
                    } else if (nc > 3) {
                        copy[y][x] = false;
                    }
                } else if (sq == false and nc == 3) {
                    copy[y][x] = true;
                }
            }
        }

        @memcpy(&self.arr, &copy);
    }

    pub fn draw(grid: *Grid) void {
        for (grid.arr, 0..) |row, y| {
            for (row, 0..) |sq, x| {
                if (sq == true) {
                    const offset_x: i32 = @intCast(x * pixel_w);
                    const offset_y: i32 = @intCast(y * pixel_h);
                    rl.drawRectangle(offset_x, offset_y, pixel_w, pixel_h, .white);
                }
            }
        }
    }

    fn get(self: *Grid, x: usize, y: usize) ?bool {
        if (x >= self.width or y >= self.height) return null;
        return self.arr[y][x];
    }

    fn live_neighbor_count(self: *Grid, x: usize, y: usize) usize {
        var count: usize = 0;

        const start_y = if (y == 0) y else y - 1;
        const end_y = y + 1;

        const start_x = if (x == 0) x else x - 1;
        const end_x = x + 1;

        for (start_y..(end_y + 1)) |ypos| {
            for (start_x..(end_x + 1)) |xpos| {
                if ((xpos != x or ypos != y) and self.get(xpos, ypos) == true) {
                    count += 1;
                }
            }
        }

        return count;
    }
};

pub fn main() anyerror!void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const rng_impl: std.Random.IoSource = .{ .io = io };
    const rand = rng_impl.interface();

    rl.initWindow(screen_w, screen_h, "basic window");
    defer rl.closeWindow();

    rl.setTargetFPS(120);

    var grid = Grid.init(grid_w, grid_h, rand);

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        rl.beginDrawing();
        defer rl.endDrawing();
        grid.progress();
        grid.draw();
        rl.clearBackground(.black);
    }
}
