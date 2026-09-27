const rl = @import("raylib");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Timestamp = std.Io.Timestamp;
const Io = std.Io;

const screen_w = 1280;
const screen_h = 720;

const pixel_w = 10;
const pixel_h = 10;

const grid_w = screen_w / pixel_w;
const grid_h = screen_h / pixel_h;

const Grid = struct {
    const default_update_period_ns: i96 = 500_000_000; // 500 ms
    const min_update_period_ns: i96 = 100_000_000; // 100 ms
    const max_update_period_ns: i96 = 1_000_000_000; // 1000 ms
    const update_period_step_size: i96 = 100_000_000; // 100 ms

    width: usize,
    height: usize,

    arr: [grid_h][grid_w]bool,

    update_period_ns: i96 = default_update_period_ns,
    last_update: Timestamp = .zero,

    increase_period_input: DebouncedInput = .init(rl.KeyboardKey.down),
    decrease_period_input: DebouncedInput = .init(rl.KeyboardKey.up),
    reset_grid_input: DebouncedInput = .init(rl.KeyboardKey.r),

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

    fn update(self: *Grid, io: Io) void {
        if (self.increase_period_input.consume(io)) {
            if (self.update_period_ns <= Grid.max_update_period_ns) {
                self.update_period_ns += Grid.update_period_step_size;
            }
        } else if (self.decrease_period_input.consume(io)) {
            if (self.update_period_ns >= Grid.min_update_period_ns) {
                self.update_period_ns -= Grid.update_period_step_size;
            }
        }

        if (self.reset_grid_input.consume(io)) {
            const rng_impl: std.Random.IoSource = .{ .io = io };
            const rand = rng_impl.interface();

            self.arr = undefined;
            for (0..self.height) |i| {
                for (0..self.width) |j| {
                    self.arr[i][j] = if (rand.uintAtMost(u8, 1) == 1) true else false;
                }
            }

            self.last_update = .zero;
        }

        const now: Timestamp = .now(io, .boot);
        const time_since_last_update = Timestamp.durationTo(self.last_update, now);
        if (time_since_last_update.nanoseconds <= self.update_period_ns) {
            return;
        }
        self.last_update = now;

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

const Vector = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn diff(self: Vector, other: Vector) Vector {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn add(self: Vector, other: Vector) Vector {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn clampX(self: *Vector, min: i32, max: i32) void {
        if (self.x < min) {
            self.x = min;
        }
        if (self.x > max) {
            self.x = max;
        }
    }

    pub fn clampY(self: *Vector, min: i32, max: i32) void {
        if (self.y < min) {
            self.y = min;
        }
        if (self.y > max) {
            self.y = max;
        }
    }
};

fn getMousePos() Vector {
    return .{ .x = rl.getMouseX(), .y = rl.getMouseY() };
}

const DebouncedInput = struct {
    const Self = @This();

    const default_debounce_time_ns: i96 = 100_000_000; // 100ms

    debounce_time_ns: i96 = default_debounce_time_ns,
    last_input: Timestamp = .zero,

    key: rl.KeyboardKey,

    pub fn init(key: rl.KeyboardKey) Self {
        return .{ .key = key };
    }

    pub fn consume(self: *Self, io: Io) bool {
        if (!rl.isKeyPressed(self.key)) {
            return false;
        }
        const now: Timestamp = .now(io, .boot);
        const time_since_last_input = Timestamp.durationTo(self.last_input, now);
        if (time_since_last_input.nanoseconds <= self.debounce_time_ns) {
            return false;
        }
        self.last_input = now;
        return true;
    }
};

const DebugWindow = struct {
    const Self = @This();

    const default_w: i32 = 500;
    const default_h: i32 = 160;

    open_menu_input: DebouncedInput = .init(rl.KeyboardKey.o),

    open: bool = false,
    pos: Vector = .{},
    w: i32 = default_w,
    h: i32 = default_h,
    color: rl.Color = .blue,

    title: [:0]const u8 = "--Menu--",

    drag: ?Vector = null,

    fn inBounds(self: *const Self, p: Vector) bool {
        const in_x = p.x >= self.pos.x and p.x <= (self.pos.x + self.w);
        const in_y = p.y >= self.pos.y and p.y <= (self.pos.y + self.h);
        return in_x and in_y;
    }

    pub fn update(self: *Self, io: Io) void {
        if (!self.open and self.open_menu_input.consume(io)) {
            self.open = true;
        } else if (self.open and self.open_menu_input.consume(io)) {
            self.open = false;
        }
        if (!self.open) return;

        const m = getMousePos();
        const in_bounds = self.inBounds(m);

        if (in_bounds) {
            if (rl.isMouseButtonDown(rl.MouseButton.left)) {
                if (self.drag == null) {
                    // capture current delta between mouse and window position
                    self.drag = m.diff(self.pos);
                }
                self.pos = m.diff(self.drag orelse .{});
            } else {
                self.drag = null;
                // snap back to edges of main window
                self.pos.clampX(0, screen_w - self.w);
                self.pos.clampY(0, screen_h - self.h);
            }
        }
    }

    pub fn draw(self: *Self, gpa: Allocator) !void {
        if (!self.open) return;
        rl.drawRectangle(self.pos.x, self.pos.y, self.w, self.h, self.color);
        rl.drawText(self.title, self.pos.x + 10, self.pos.y + 10, 20, .white);

        const fps = rl.getFPS();
        const fps_text: [:0]const u8 = try std.fmt.allocPrintSentinel(gpa, "FPS: {d}", .{fps}, 0);
        defer gpa.free(fps_text);

        rl.drawText(fps_text, self.pos.x + 10, self.pos.y + 30, 20, .white);
        rl.drawText("-- Controls --", self.pos.x + 10, self.pos.y + 50, 20, .white);
        rl.drawText("Up Arrow: Increase Update Frequency", self.pos.x + 10, self.pos.y + 70, 20, .white);
        rl.drawText("Down Arrow: Decrease Update Frequency", self.pos.x + 10, self.pos.y + 90, 20, .white);
        rl.drawText("R: Reset and Randomize Grid", self.pos.x + 10, self.pos.y + 110, 20, .white);
        rl.drawText("Escape: Quit", self.pos.x + 10, self.pos.y + 130, 20, .white);
    }
};

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    const gpa = init.gpa;

    const rng_impl: std.Random.IoSource = .{ .io = io };
    const rand = rng_impl.interface();

    rl.initWindow(screen_w, screen_h, "Game of Life");
    defer rl.closeWindow();

    rl.setTargetFPS(120);

    var grid = Grid.init(grid_w, grid_h, rand);
    var dw: DebugWindow = .{};

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        grid.update(io);
        dw.update(io);

        rl.beginDrawing();
        defer rl.endDrawing();

        grid.draw();
        try dw.draw(gpa);

        rl.clearBackground(.black);
    }
}
