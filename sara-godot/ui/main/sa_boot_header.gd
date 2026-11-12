## The mark, the build, and what Sara is actually running on.
##
## Printed once at startup, in one place, rather than as scattered lines between
## the shader and module reports. Split out of `ui/main/main.gd`: none of it touches
## the scene, so it was the one block there that had no reason to be a method on
## a Node.
##
## The engine prints most of this itself and the launch wrapper suppresses it
## with `--no-header`, so if this stops printing the information is simply lost
## rather than duplicated elsewhere.
class_name SaBootHeader
extends RefCounted


static func print_header(ds_name: String) -> void:
    # One source for the version, and the commit beside it, rather than a
    # default argument here that can disagree with project.godot, because a bug
    # report that names a version nobody can map to a commit is a report that cannot
    # be acted on.
    var build := SaBuildInfo.read()
    SaConsole.banner("v" + str(build["version"]))

    SaConsole.section("ENVIRONMENT")
    SaConsole.field("Build", SaBuildInfo.describe(build))
    (
        SaConsole
        . field(
            "Renderer",
            (
                "%s %s  %s  %s"
                % [
                    driver_name(),
                    RenderingServer.get_video_adapter_api_version(),
                    SaConsole.tint("·", SaConsole.DIM),
                    rendering_method(),
                ]
            )
        )
    )
    SaConsole.field("Device", SaConsole.tint(RenderingServer.get_video_adapter_name(), SaConsole.INFO))
    SaConsole.field("Floor", SaDeviceFloor.summary())

    var screen_size := DisplayServer.screen_get_size()
    var hertz := screen_hz()
    SaStrokeLedger.follow_display(hertz)
    SaConsole.field("Display", display_row(ds_name, screen_size, SaUI.scale(), hertz))
    SaConsole.blank()

    # XWayland cannot report a display scale, so the UI size has to be inferred
    # from DPI and capped. Worth saying out loud rather than leaving the user to
    # wonder why the UI looks wrong.
    if ds_name == "X11" and OS.has_environment("WAYLAND_DISPLAY"):
        SaConsole.notice("Running under XWayland - UI scale is inferred from DPI. Prefer --display-driver wayland.")
        SaConsole.blank()

    GlobalShaderCompiler.report_compilation()


## The Display row's value: the server, the size, the scale, and the rate the
## window's screen refreshes at, which the row says is unknown when the driver
## answers -1.
static func display_row(ds_name: String, size: Vector2i, scale: float, hertz: float) -> String:
    return (
        "%s  %s  %d×%d %s %.2f×  %s  %s"
        % [
            ds_name,
            SaConsole.tint("·", SaConsole.DIM),
            size.x,
            size.y,
            SaConsole.tint("@", SaConsole.DIM),
            scale,
            SaConsole.tint("·", SaConsole.DIM),
            rate_text(hertz),
        ]
    )


## The display's rate as the row reads it: "60 Hz", and the words for a driver
## that answered -1 and for a run with no screen to ask.
static func rate_text(hertz: float) -> String:
    return "%.0f Hz" % hertz if hertz > 0.0 else "refresh rate unknown"


## The rate the window's screen refreshes at, in Hz, or -1 where the server will
## not say and where there is no screen for the window to be on. The ledger's
## frame budget follows it, so a frame is late against one refresh of the screen
## a painter is actually looking at.
static func screen_hz() -> float:
    var screen := DisplayServer.window_get_current_screen()
    return DisplayServer.screen_get_refresh_rate(screen) if screen >= 0 else -1.0


## "vulkan" -> "Vulkan".
static func driver_name() -> String:
    var driver := RenderingServer.get_current_rendering_driver_name()
    match driver:
        "vulkan":
            return "Vulkan"
        "d3d12":
            return "Direct3D 12"
        "metal":
            return "Metal"
        "opengl3":
            return "OpenGL 3"
        _:
            return driver.capitalize()


## "forward_plus" -> "Forward+".
static func rendering_method() -> String:
    var method := RenderingServer.get_current_rendering_method()
    match method:
        "forward_plus":
            return "Forward+"
        "mobile":
            return "Mobile"
        "gl_compatibility":
            return "Compatibility"
        _:
            return method.capitalize()
