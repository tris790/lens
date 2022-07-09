const std = @import("std");

const xlib = @import("xlib.zig");

const Selection = struct {
    start_x: c_int = 0,
    start_y: c_int = 0,
    end_x: c_int = 0,
    end_y: c_int = 0,
};

pub fn main() anyerror!void {
    var display: *xlib.Display = xlib.XOpenDisplay(null).?;
    var screen: i32 = xlib.XDefaultScreen(display);
    var root = xlib.XRootWindow(display, screen);

    var root_attributes: xlib.XWindowAttributes = undefined;
    _ = xlib.XGetWindowAttributes(display, root, &root_attributes);
    var win_width = @intCast(c_uint, root_attributes.width);
    var win_height = @intCast(c_uint, root_attributes.height);

    var window = xlib.XCreateSimpleWindow(display, root, 0, 0, win_width, win_height, 0, xlib.XBlackPixel(display, screen), xlib.XWhitePixel(display, screen));

    var window_type = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE", 0);
    var window_value = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", 0);
    _ = xlib.XChangeProperty(display, window, window_type, @as(xlib.Atom, 4), 32, xlib.PropModeReplace, @ptrCast([*c]const u8, &window_value), 1);

    const event_flag_mask = xlib.KeyPressMask | xlib.PointerMotionMask | xlib.ButtonPressMask | xlib.ButtonReleaseMask | xlib.StructureNotifyMask;
    _ = xlib.XSelectInput(display, window, event_flag_mask);
    _ = xlib.XMapWindow(display, window);

    var event: xlib.XEvent = undefined;
    var gc = xlib.XDefaultGC(display, screen);

    var screenshot = xlib.XGetImage(
        display,
        root,
        @intCast(c_int, root_attributes.x),
        @intCast(c_int, root_attributes.y),
        @intCast(c_uint, root_attributes.width),
        @intCast(c_uint, root_attributes.height),
        xlib.AllPlanes,
        xlib.ZPixmap,
    );

    var window_attributes: xlib.XWindowAttributes = undefined;
    _ = xlib.XGetWindowAttributes(display, root, &window_attributes);
    drawImage(display, window, gc, screenshot, 0, 0, 0, 0, @intCast(c_uint, window_attributes.width), @intCast(c_uint, window_attributes.height));

    var selection = Selection{};

    var isDirty = true;
    var lastTime = try std.time.Instant.now();
    while (true) {
        var currentTime = try std.time.Instant.now();
        var delta_time = currentTime.since(lastTime);
        if (isDirty and delta_time > 100_000_000) {
            std.log.info("Was dirty {}\n", .{delta_time});
            isDirty = false;
            lastTime = currentTime;
            drawImage(
                display,
                window,
                gc,
                screenshot,
                selection.start_x,
                selection.start_y,
                0,
                0,
                @intCast(c_uint, selection.end_x - selection.start_x),
                @intCast(c_uint, selection.end_y - selection.start_y),
            );
        }

        _ = xlib.XNextEvent(display, &event);

        switch (event.type) {
            xlib.ButtonPress => {
                if (event.xbutton.button == xlib.Button4) {
                    std.log.info("up\n", .{});
                    isDirty = true;
                }
                if (event.xbutton.button == xlib.Button5) {
                    std.log.info("down\n", .{});
                    isDirty = true;
                }
                if (event.xbutton.button == xlib.Button1) {
                    selection.start_x = event.xbutton.x;
                    selection.start_y = event.xbutton.y;
                }
            },
            xlib.ButtonRelease => {
                if (event.xbutton.button == xlib.Button1) {
                    selection.end_x = event.xbutton.x;
                    selection.end_y = event.xbutton.y;
                    _ = xlib.XResizeWindow(
                        display,
                        window,
                        @intCast(c_uint, selection.end_x - selection.start_x),
                        @intCast(c_uint, selection.end_y - selection.start_y),
                    );

                    std.log.info("selection: {}\n", .{selection});
                    isDirty = true;
                }
            },
            xlib.ClientMessage => {},
            xlib.ConfigureNotify => {
                isDirty = true;
            },
            else => {},
        }
    }

    _ = xlib.XDestroyWindow(display, window);
    _ = xlib.XCloseDisplay(display);
}

fn drawImage(
    display_handle: *xlib.Display,
    where_to_draw: xlib.Drawable,
    graphics_context: xlib.GC,
    image: [*c]xlib.XImage,
    src_x: c_int,
    src_y: c_int,
    dest_x: c_int,
    dest_y: c_int,
    width: c_uint,
    height: c_uint,
) void {
    var result = xlib.XPutImage(display_handle, where_to_draw, graphics_context, image, src_x, src_y, dest_x, dest_y, width, height);
    std.log.info("Draw {}\n", .{result});
}
