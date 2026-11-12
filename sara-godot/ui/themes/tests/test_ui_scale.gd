## Tests for the UI scale authority.
##
## The bug these guard against: SaUI.px() multiplied every font and margin by the
## system scale, and Window.content_scale_factor scaled the viewport again, so a
## 4K display at 2x got both and the UI came out twice the intended size. On a
## FullHD display the system scale is 1.0, so nothing doubled and it looked right
## which is exactly why it only reproduced on one machine.
##
## SaUI.os_scale_override makes this deterministic without a 4K display.
extends "res://tests/test_framework.gd"

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func test_scale_is_system_times_user() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0
    assert_almost_eq(SaUI.scale(), 2.0, 0.0001, "System 2x with no user preference is 2x")

    SaUI.user_scale = 1.5
    assert_almost_eq(SaUI.scale(), 3.0, 0.0001, "User preference multiplies the system scale")

    SaUI.os_scale_override = 1.0
    assert_almost_eq(SaUI.scale(), 1.5, 0.0001, "On a 1x display the user preference stands alone")


## Window geometry is in physical pixels and is not touched by
## content_scale_factor, so it is the one thing that still needs converting.
func test_physical_conversion_round_trips() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0
    assert_eq(SaUI.to_physical(260), 520, "260 logical is 520 physical at 2x")
    assert_eq(SaUI.to_physical_v(Vector2i(260, 420)), Vector2i(520, 840), "Vector conversion matches")
    assert_eq(SaUI.to_logical(520), 260, "Physical converts back to logical")


## px() is the logical-unit identity now. Roughly 150 call sites still use it,
## and every one of them must pass the value through untouched.
func test_px_is_an_identity_shim() -> void:
    SaUI.os_scale_override = 3.0
    SaUI.user_scale = 2.0
    assert_eq(SaUI.px(20), 20, "px() must not scale: content_scale_factor does that")
    assert_almost_eq(SaUI.pxf(12.5), 12.5, 0.0001, "pxf() must not scale either")


## The 4K startup half of the bug: a docker got its content_scale_factor only
## when ui_scale_changed fired, so at launch it had scale 1.0 while its fonts had
## already been doubled by px().
func test_apply_to_window_sets_content_scale() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0

    var window := Window.new()
    SaUI.apply_to_window(window)
    assert_almost_eq(window.content_scale_factor, 2.0, 0.0001, "A window must be scaled when it is created")
    window.free()


## The other half: the handler multiplied size by content_scale_factor / 1.0 on
## every call, so repeated scale changes compounded.
func test_apply_to_window_is_idempotent() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0

    var window := Window.new()
    window.size = Vector2i(400, 300)
    SaUI.apply_to_window(window)
    var after_first := window.size

    SaUI.apply_to_window(window)
    SaUI.apply_to_window(window)
    assert_eq(window.size, after_first, "Re-applying the same scale must not resize the window again")
    window.free()


func test_scale_change_round_trips_window_size() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0

    var window := Window.new()
    window.size = Vector2i(400, 300)
    SaUI.apply_to_window(window)
    var original := window.size

    SaUI.user_scale = 1.5
    SaUI.apply_to_window(window)
    assert_true(window.size != original, "Changing scale should resize the window")

    SaUI.user_scale = 1.0
    SaUI.apply_to_window(window)
    assert_eq(window.size, original, "Returning to the original scale should restore the original size")
    window.free()


## A window created before any scale change must end up identical to one created
## after, since dockers are built at startup and rescaled later.
func test_window_created_before_and_after_a_change_agree() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0

    var early := Window.new()
    early.size = SaUI.to_physical_v(Vector2i(260, 420))
    SaUI.apply_to_window(early)

    SaUI.user_scale = 1.25
    SaUI.apply_to_window(early)

    var late := Window.new()
    late.size = SaUI.to_physical_v(Vector2i(260, 420))
    SaUI.apply_to_window(late)

    assert_almost_eq(early.content_scale_factor, late.content_scale_factor, 0.0001, "Both windows scale the same")
    assert_eq(early.size, late.size, "Both windows end at the same physical size")

    early.free()
    late.free()


## X11 reports no display scale, so the only signal left is physical DPI, which
## measures the panel, not how the desktop is scaled. A 4K laptop panel reports
## 287 DPI while its desktop runs at 2x, and 287/96 rounds to 3, so the raw ratio
## overshoots badly. Over-scaling is far worse than under-scaling: a 3x UI leaves
## nothing on screen to fix it with.
func test_dpi_inference_is_capped() -> void:
    assert_almost_eq(SaUI.infer_scale_from_dpi(96), 1.0, 0.0001, "A standard-density panel is 1x")
    assert_almost_eq(SaUI.infer_scale_from_dpi(192), 2.0, 0.0001, "Double density is 2x")
    assert_almost_eq(SaUI.infer_scale_from_dpi(287), 2.0, 0.0001, "A 4K laptop panel must cap at 2x, not 3x")
    assert_almost_eq(SaUI.infer_scale_from_dpi(600), 2.0, 0.0001, "Absurd DPI must still cap at 2x")


func test_dpi_inference_never_shrinks_the_ui() -> void:
    assert_almost_eq(SaUI.infer_scale_from_dpi(48), 1.0, 0.0001, "A low-DPI panel must not scale below 1x")
    assert_almost_eq(SaUI.infer_scale_from_dpi(0), 1.0, 0.0001, "An unknown DPI must fall back to 1x")
    assert_almost_eq(SaUI.infer_scale_from_dpi(-1), 1.0, 0.0001, "A negative DPI must fall back to 1x")


## An embedded subwindow renders inside the host viewport, which content_scale_factor
## has already scaled, and its geometry is in the host's logical space. Giving it its
## own factor scales its contents twice and treating its size as physical pixels makes
## it enormous, this produced dockers 3070 wide inside a 1920-logical viewport.
##
## A Window that is not in a tree reports is_embedded() == false, which is the OS-window
## case, so that is what these assert against. The embedded path is covered by the app
## behaving correctly with gui_embed_subwindows on.
func test_os_window_scales_itself() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0

    var window := Window.new()
    assert_false(window.is_embedded(), "A detached Window is not embedded")
    assert_almost_eq(SaUI.window_scale(window), 2.0, 0.0001, "A real OS window carries the full scale")
    assert_eq(SaUI.window_size_for(window, Vector2i(260, 420)), Vector2i(520, 840), "Its geometry is physical")
    window.free()


func test_window_scale_of_null_falls_back_to_the_app_scale() -> void:
    SaUI.os_scale_override = 2.0
    SaUI.user_scale = 1.0
    assert_almost_eq(SaUI.window_scale(null), 2.0, 0.0001, "A missing window must not report an unscaled 1.0")
