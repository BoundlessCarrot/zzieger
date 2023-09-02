const std = @import("std");
const arrayList = std.ArrayList;
const assert = std.debug.assert;
const fs = std.fs;
const print = std.debug.print;
const PI = 3.14159;
var prng = std.rand.DefaultPrng.init(0);

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
};

fn draw_rectangle(image: *arrayList(Color), width: usize, height: usize, x: usize, y: usize, w: usize, h: usize, color: Color) !void {
    assert(image.items.len == width * height);
    var i: usize = 0;
    var j: usize = 0;

    while (i < w) : (i += 1) {
        while (j < h) : (j += 1) {
            var cx: usize = x + i;
            var cy: usize = y + j;

            if (cx >= width or cy >= height) {
                continue;
            }

            const c_list: [1]Color = .{color};
            _ = try image.replaceRange(cx + cy * width, 1, &c_list);
        }

        j = 0;
    }
}

fn drop_ppm_image(filename: []const u8, image: arrayList(Color), width: usize, height: usize) !void {
    assert(image.items.len == width * height);

    const file = try fs.cwd().createFile(filename, .{});
    defer file.close();
    var writer = file.writer();

    try writer.print("P3\n{} {}\n255\n", .{ width, height });

    for (image.items) |pixel| {
        try writer.print("{} {} {}\n", .{ pixel.r, pixel.g, pixel.b });
    }
}

fn whiteout(framebuffer: *arrayList(Color), len: usize) !void {
    framebuffer.clearAndFree();
    var i: usize = 0;
    while (i < len) : (i += 1) {
        try framebuffer.append(Color.init(255, 255, 255, 255));
    }
}

pub fn main() !void {
    const width = 1024;
    const height = 512;

    var framebuffer = arrayList(Color).init(std.heap.page_allocator);
    defer framebuffer.deinit();

    try whiteout(&framebuffer, width * height);

    // create our map
    const map_width = 16;
    const map_height = 16;

    const map =
        \\0000222222220000
        \\1              0
        \\1      11111   0
        \\1     0        0
        \\0     0  1110000
        \\0     3        0
        \\0   10000      0
        \\0   0   11100  0
        \\0   0   0      0
        \\0   0   1  00000
        \\0       1      0
        \\2       1      0
        \\0       0      0
        \\0 0000000      0
        \\0              0
        \\0002222222200000
    ; // our game map

    // set player position and view
    const player_x = 3.456;
    const player_y = 2.345;
    var player_a: f32 = 0.0;
    const fov = PI / 3.0;

    var color_set: [10]Color = undefined;

    const num_colors = 10;
    const rand = prng.random();
    var j: u8 = 0;
    while (j < num_colors) : (j += 1) {
        color_set[j] = Color.init(rand.int(u8), rand.int(u8), rand.int(u8), 255);
    }

    const rect_w = width / (map_width * 2);
    const rect_h = height / map_height;

    // offset for newline chars
    const actual_width = map_width + 1;
    var frame: usize = 0;

    while (frame < 360) : (frame += 1) {
        print("frame {d}\r", .{frame});
        player_a += 2 * PI / 360.0;

        try whiteout(&framebuffer, width * height); // clear screen

        var k: usize = 0;
        var l: usize = 0;

        // draw the map
        while (k < map_height) : (k += 1) {
            inner: while (l < map_width) : (l += 1) {
                var char = map[l + (k * (actual_width))];
                if (char == ' ' or char == '\n') {
                    continue :inner;
                }

                var rect_x: usize = l * rect_w;
                var rect_y: usize = k * rect_h;

                var icolor: usize = char - '0';
                assert(icolor < num_colors);

                try draw_rectangle(&framebuffer, width, height, rect_x, rect_y, rect_w, rect_h, color_set[icolor]);
            }
            l = 0;
        }

        // draw the player on the map
        // try draw_rectangle(&framebuffer, width, height, @floatToInt(usize, player_x * rect_w), @floatToInt(usize, player_y * rect_h), 5, 5, Color.init(0, 255, 255, 255));

        // draw intersection cone as well as the 3D view
        var s: usize = 0;
        var t: f32 = 0.0;

        while (s < width / 2) : (s += 1) {
            var angle: f32 = player_a - (fov / 2.0) + fov * @intToFloat(f32, s) / @intToFloat(f32, width / 2);
            while (t < 20) : (t += 0.05) {
                var cx: f32 = player_x + (t * @cos(angle));
                var cy: f32 = player_y + (t * @sin(angle));

                var pos = map[@floatToInt(usize, cx) + @floatToInt(usize, cy) * actual_width];

                var pix_x: usize = @floatToInt(usize, cx * rect_w);
                var pix_y: usize = @floatToInt(usize, cy * rect_h);

                const c_list: [1]Color = .{Color.init(160, 160, 160, 255)}; // intersection cone
                try framebuffer.replaceRange(pix_x + pix_y * width, 1, &c_list);

                if (pos != ' ') {
                    var column_height: usize = @floatToInt(usize, height / (t * @cos(angle - player_a)));

                    var icolor: usize = pos - '0';
                    assert(icolor < num_colors);
                    try draw_rectangle(&framebuffer, width, height, width / 2 + s, height / 2 - column_height / 2, 1, column_height, color_set[icolor]);
                    break;
                }
            }
            t = 0;
        }

        const f_name = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "frames/000{d}.ppm",
            .{frame},
        );
        defer std.heap.page_allocator.free(f_name);
        try drop_ppm_image(f_name, framebuffer, width, height);
    }
}
