## Under Wayland a raise asks the compositor for activation, and on Windows and
## X11 it stays the raise it was.
##
## `move_to_foreground` puts nothing on a Wayland wire, so `SaWindowForward`
## adds `request_attention` there, the engine's one call that sends an
## `xdg_activation_v1` token and an activation. Which server asks is a pure
## answer read here. What the compositor does with the request is read on a
## seat with mutter inside, by hand, since a
## headless run has no compositor to ask.
extends "res://tests/test_framework.gd"


func test_wayland_asks_for_attention() -> void:
    assert_true(SaWindowForward.asks_for_attention("Wayland"), "under Wayland a raise also asks the compositor for activation")


func test_windows_and_x11_keep_the_raise_they_had() -> void:
    for server: String in ["Windows", "X11", "macOS", "Android"]:
        assert_false(SaWindowForward.asks_for_attention(server), "%s keeps the raise without an asked attention" % server)


func test_a_run_with_no_display_asks_nothing() -> void:
    assert_false(SaWindowForward.asks_for_attention("headless"), "a headless run has no compositor to ask")
