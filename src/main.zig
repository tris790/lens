const std = @import("std");

const xlib = @import("xlib.zig");
const libPng = @import("png.zig");

const Selection = struct {
    start_x: c_int = 0,
    start_y: c_int = 0,
    end_x: c_int = 0,
    end_y: c_int = 0,
};

const App = struct {
    display: *xlib.Display,
    screen: i32,
    root: xlib.Window,
    window: xlib.Window,
    graphic_context: xlib.GC,
    screenshot: *xlib.XImage,
    cropped_screenshot: Screenshot = undefined,
};

pub fn main() anyerror!void {
    var app = createApp();
    var selection = Selection{};
    var event: xlib.XEvent = undefined;

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
                app.display,
                app.window,
                app.graphic_context,
                app.screenshot,
                selection.start_x,
                selection.start_y,
                0,
                0,
                @as(c_uint, @as(u32, @intCast(selection.end_x - selection.start_x))),
                @as(c_uint, @as(u32, @intCast(selection.end_y - selection.start_y))),
            );
        }

        _ = xlib.XNextEvent(app.display, &event);

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
                    onSelectionCompleted(&selection, &app);
                    isDirty = true;
                }
            },
            xlib.ClientMessage => {},
            xlib.ConfigureNotify => {
                isDirty = true;
            },
            xlib.SelectionRequest => {
                std.log.info("CopyPaste requested\n", .{});

                sendImage(&event.xselectionrequest, &app);
            },
            else => {},
        }
    }

    _ = xlib.XDestroyWindow(app.display, app.window);
    _ = xlib.XCloseDisplay(app.display);
}

fn drawImage(display_handle: *xlib.Display, where_to_draw: xlib.Drawable, graphics_context: xlib.GC, image: [*c]xlib.XImage, src_x: c_int, src_y: c_int, dest_x: c_int, dest_y: c_int, width: c_uint, height: c_uint) void {
    var result = xlib.XPutImage(display_handle, where_to_draw, graphics_context, image, src_x, src_y, dest_x, dest_y, width, height);
    std.log.info("Draw {}\n", .{result});
}

fn createApp() App {
    var display: *xlib.Display = xlib.XOpenDisplay(null).?;
    var screen: i32 = xlib.XDefaultScreen(display);
    var root = xlib.XRootWindow(display, screen);

    var root_attributes: xlib.XWindowAttributes = undefined;
    _ = xlib.XGetWindowAttributes(display, root, &root_attributes);
    var win_width = @as(c_uint, @intCast(root_attributes.width));
    var win_height = @as(c_uint, @intCast(root_attributes.height));

    var window = xlib.XCreateSimpleWindow(display, root, 0, 0, win_width, win_height, 0, xlib.XBlackPixel(display, screen), xlib.XWhitePixel(display, screen));

    var window_type = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE", 0);
    var window_value = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", 0);
    _ = xlib.XChangeProperty(display, window, window_type, @as(xlib.Atom, 4), 32, xlib.PropModeReplace, @as([*c]const u8, @ptrCast(&window_value)), 1);

    const event_flag_mask = xlib.KeyPressMask | xlib.PointerMotionMask | xlib.ButtonPressMask | xlib.ButtonReleaseMask | xlib.StructureNotifyMask;
    _ = xlib.XSelectInput(display, window, event_flag_mask);
    _ = xlib.XMapWindow(display, window);

    var gc = xlib.XDefaultGC(display, screen);

    var fullscreen_screenshot = xlib.XGetImage(display, root, @as(c_int, @intCast(root_attributes.x)), @as(c_int, @intCast(root_attributes.y)), @as(c_uint, @intCast(root_attributes.width)), @as(c_uint, @intCast(root_attributes.height)), xlib.AllPlanes, xlib.ZPixmap);

    var window_attributes: xlib.XWindowAttributes = undefined;
    _ = xlib.XGetWindowAttributes(display, root, &window_attributes);
    drawImage(display, window, gc, fullscreen_screenshot, 0, 0, 0, 0, @as(c_uint, @intCast(window_attributes.width)), @as(c_uint, @intCast(window_attributes.height)));
    return App{
        .display = display,
        .screen = screen,
        .root = root,
        .window = window,
        .graphic_context = gc,
        .screenshot = fullscreen_screenshot,
    };
}

fn onSelectionCompleted(selection: *Selection, app: *App) void {
    const selection_width = @as(c_uint, @intCast(selection.end_x - selection.start_x));
    const selection_height = @as(c_uint, @intCast(selection.end_y - selection.start_y));

    _ = xlib.XResizeWindow(app.display, app.window, selection_width, selection_height);
    var cropped_screenshot = xlib.XGetImage(app.display, app.root, 0, 0, selection_width, selection_height, xlib.AllPlanes, xlib.ZPixmap);

    var png = xImageToPng(cropped_screenshot);
    app.cropped_screenshot = png;
    copyPngImage(app);
    std.log.info("selection: {}\n", .{selection});
    std.log.info("png: {}x{}\n", .{ png.width, png.height });
}

const Screenshot = struct {
    data: []u8,
    width: u32,
    height: u32,
};

const LibPngBuffer = struct {
    buffer: libPng.png_bytep,
    bufsize: libPng.png_uint_32,
};

fn xImageToPng(ximage: *xlib.XImage) Screenshot {
    var rgba = ximage.data;
    var buffer: LibPngBuffer = std.mem.zeroInit(LibPngBuffer, .{});
    var png_write_ptr = libPng.png_create_write_struct(libPng.PNG_LIBPNG_VER_STRING, null, null, null);
    var png_info_ptr = libPng.png_create_info_struct(png_write_ptr);

    libPng.png_set_write_fn(png_write_ptr, &buffer, pngWriteData, null);
    libPng.png_set_IHDR(png_write_ptr, png_info_ptr, @as(c_uint, @intCast(ximage.width)), @as(c_uint, @intCast(ximage.height)), 8, libPng.PNG_COLOR_TYPE_RGB_ALPHA, libPng.PNG_INTERLACE_NONE, libPng.PNG_COMPRESSION_TYPE_BASE, libPng.PNG_FILTER_TYPE_BASE);
    libPng.png_write_info(png_write_ptr, png_info_ptr);

    var rows: libPng.png_bytep = (std.heap.c_allocator.alloc(libPng.png_byte, @as(usize, @intCast(4 * ximage.width))) catch {
        unreachable;
    }).ptr;

    var y: u32 = 0;
    var x: u32 = 0;
    while (y < ximage.height) : (y += 1) {
        while (x < ximage.width) : (x += 1) {
            rows[x * 4] = rgba[(y * @as(u32, @intCast(ximage.width)) + x) * 4];
            rows[x * 4 + 1] = rgba[(y * @as(u32, @intCast(ximage.width)) + x) * 4 + 1];
            rows[x * 4 + 2] = rgba[(y * @as(u32, @intCast(ximage.width)) + x) * 4 + 2];
            rows[x * 4 + 3] = rgba[(y * @as(u32, @intCast(ximage.width)) + x) * 4 + 3];
        }

        libPng.png_write_row(png_write_ptr, rows);
    }

    libPng.png_write_end(png_write_ptr, null);

    return Screenshot{
        .data = buffer.buffer[0..buffer.bufsize],
        .width = @as(u32, @intCast(ximage.width)),
        .height = @as(u32, @intCast(ximage.height)),
    };
}

fn pngWriteData(png_structp: libPng.png_structp, png_bytep: libPng.png_bytep, length: usize) callconv(.C) void {
    var p: *LibPngBuffer = @as(*LibPngBuffer, @ptrCast(@alignCast(libPng.png_get_io_ptr(png_structp).?)));
    var nSize: u32 = p.bufsize + @as(u32, @intCast(length));

    p.buffer = (std.heap.c_allocator.alloc(libPng.png_byte, nSize) catch {
        unreachable;
    }).ptr;

    @memcpy(p.buffer[0..length], png_bytep[0..length]);
    p.bufsize += @as(u32, @intCast(length));
}

fn copyPngImage(app: *App) void {
    var clipboard_atom = xlib.XInternAtom(app.display, "CLIPBOARD", 0);
    _ = xlib.XSetSelectionOwner(app.display, clipboard_atom, app.root, 0);
    std.log.info("Took clipboard\n", .{});
}

fn sendImage(selection_request: *xlib.XSelectionRequestEvent, app: *App) void {
    var png_atom = xlib.XInternAtom(app.display, "image/png", 0);
    _ = xlib.XChangeProperty(app.display, selection_request.requestor, selection_request.property, png_atom, 8, xlib.PropModeReplace, app.cropped_screenshot.data.ptr, @as(c_int, @intCast(app.cropped_screenshot.data.len)));

    var send_event = xlib.XSelectionEvent{
        .type = xlib.SelectionNotify,
        .requestor = selection_request.requestor,
        .selection = selection_request.selection,
        .target = selection_request.target,
        .property = selection_request.property,
        .time = selection_request.time,
        .serial = undefined,
        .send_event = undefined,
        .display = undefined,
    };
    _ = xlib.XSendEvent(app.display, selection_request.requestor, 1, xlib.NoEventMask, @as([*c]xlib.union__XEvent, @ptrCast(&send_event)));
}
