## A maximised window draws its interface larger while it is filling its host,
## and puts the factor back when it goes back.
##
## Maximising a docker also makes the font and UI scale in it temporarily bigger.
##
## Everything here is about one number, `Window.content_scale_factor`, which
## only `SaUI.apply_to_window` may write. So the maximise asks for the
## factor by leaving `SaUI.EXTRA_SCALE_META` on the window and calling that one
## writer, and these assertions read the factor back rather than reading the
## maximise's own constant twice.
##
## A detached `Window` reports `is_embedded()` false, which is the OS-window
## branch of `SaUI.window_scale`, so the base factor here is `SaUI.scale()` and
## the override makes it a number of this file's choosing. An embedded docker
## takes base 1.0 and the same multiplication, which is the second case below at
## a base of one.
extends "res://tests/test_framework.gd"

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func _window(at: Vector2i, of_size: Vector2i) -> Window:
    var window := Window.new()
    window.title = "Scratch"
    window.position = at
    window.size = of_size
    SaUI.apply_to_window(window)
    return window


## The unit's claim, at a base of one: the factor goes up by the maximise's
## constant and comes back down to exactly what it was.
func test_a_maximised_window_draws_larger_and_comes_back() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0

    var window := _window(Vector2i(120, 90), Vector2i(300, 200))
    var before := window.content_scale_factor
    assert_almost_eq(before, 1.0, 0.0001, "A window that is not maximised draws at the factor its kind earns")

    SaDockerMaximise.toggle(window)
    assert_almost_eq(
        window.content_scale_factor,
        SaDockerMaximise.MAXIMISED_SCALE,
        0.0001,
        "and a maximised one draws larger by the maximise's own constant"
    )
    assert_almost_eq(
        window.content_scale_factor,
        SaUI.window_scale(window),
        0.0001,
        "which is what `SaUI` answers for that window, since nothing else may write the factor"
    )

    SaDockerMaximise.toggle(window)
    assert_almost_eq(window.content_scale_factor, before, 0.0001, "and it is back to what it was, not near it")
    assert_false(window.has_meta(SaUI.EXTRA_SCALE_META), "with nothing left on the window to ask for more")
    window.free()


## The extra multiplies whatever the window's kind earns rather than replacing
## it, so a painter on a 1.5 display gets 1.5 times the maximise's quarter again
## and not a docker that shrinks when it is maximised.
func test_the_factor_multiplies_the_one_the_window_already_had() -> void:
    SaUI.os_scale_override = 1.5
    SaUI.user_scale = 1.0

    var window := _window(Vector2i(0, 0), Vector2i(240, 160))
    assert_almost_eq(window.content_scale_factor, 1.5, 0.0001, "The window is at the display's scale")

    SaDockerMaximise.toggle(window)
    assert_almost_eq(
        window.content_scale_factor, 1.5 * SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "and at that times the extra maximised"
    )

    SaDockerMaximise.toggle(window)
    assert_almost_eq(window.content_scale_factor, 1.5, 0.0001, "and back at the display's scale alone")
    window.free()


## The rectangle is written after the factor, because `apply_to_window` rescales
## `size` and `min_size` by the change and would otherwise leave a maximised
## window a quarter too large for its host.
func test_the_window_still_fills_its_host_exactly_at_the_larger_factor() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0

    var window := _window(Vector2i(120, 90), Vector2i(300, 200))
    var host := SaDockerMaximise.host_rect(window)

    SaDockerMaximise.toggle(window)
    assert_eq(window.size, host.size, "The maximised window is the host's size, not the host's size times the factor")
    assert_eq(window.position, host.position, "at the host's corner")

    SaDockerMaximise.toggle(window)
    assert_eq(window.size, Vector2i(300, 200), "and the kept rectangle survives the scale going up and down")
    assert_eq(window.position, Vector2i(120, 90), "position as well as size")
    window.free()


## What `SaUI` was taught, on its own: a window asking for nothing is unchanged,
## which is every window in Sara but a maximised one.
func test_a_window_that_asks_for_nothing_is_left_alone() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0

    var window := _window(Vector2i(0, 0), Vector2i(100, 100))
    assert_almost_eq(SaUI.extra_scale(window), 1.0, 0.0001, "No metadata is no extra")
    assert_almost_eq(SaUI.extra_scale(null), 1.0, 0.0001, "and neither is no window")

    window.set_meta(SaUI.EXTRA_SCALE_META, 0.0)
    assert_almost_eq(SaUI.extra_scale(window), 1.0, 0.0001, "A factor of nothing is refused rather than obeyed")
    window.remove_meta(SaUI.EXTRA_SCALE_META)
    window.free()
