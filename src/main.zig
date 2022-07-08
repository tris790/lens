const std = @import("std");

const xlib = @import("xlib.zig");

const RECT_X = 20;
const RECT_Y = 20;
const RECT_WIDTH = 10;
const RECT_HEIGHT = 10;
const WIN_X = 10;
const WIN_Y = 10;
const WIN_WIDTH = 800;
const WIN_HEIGHT = 600;
const WIN_BORDER = 1;

pub fn main() anyerror!void {
    var display: ?*xlib.Display = xlib.XOpenDisplay(null);
    var screen: i32 = xlib.XDefaultScreen(display);
    var window = xlib.XCreateSimpleWindow(display, xlib.XRootWindow(display, screen), WIN_X, WIN_Y, WIN_WIDTH, WIN_HEIGHT, WIN_BORDER, xlib.XBlackPixel(display, screen), xlib.XWhitePixel(display, screen));
    var del_window = xlib.XInternAtom(display, "VW_DELETE_WINDOW", 0);
    _ = xlib.XSetWMProtocols(display, window, &del_window, 1);
    _ = xlib.XSelectInput(display, window, xlib.ExposureMask | xlib.KeyPressMask);
    _ = xlib.XMapWindow(display, window);

    std.log.info("Event loop\n", .{});
    var event: xlib.XEvent = undefined;

    var gc = xlib.XDefaultGC(display, screen);
    var root = xlib.XDefaultRootWindow(display);
    var screenshot = xlib.XGetImage(display, root, 0, 0, WIN_WIDTH, WIN_HEIGHT, xlib.AllPlanes, xlib.ZPixmap);
    _ = xlib.XPutImage(display, window, gc, screenshot, 0, 0, 0, 0, WIN_WIDTH, WIN_HEIGHT);

    while (true) {
        _ = xlib.XNextEvent(display, &event);

        switch (event.type) {
            xlib.KeyPress => {},
            xlib.ClientMessage => {},
            xlib.Expose => {},
            else => {},
        }
    }

    _ = xlib.XDestroyWindow(display, window);
    _ = xlib.XCloseDisplay(display);
}
