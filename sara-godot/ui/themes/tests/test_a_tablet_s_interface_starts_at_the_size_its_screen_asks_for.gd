## A tablet's interface starts at the size its screen asks for.
##
## A tablet of 2944 by 1840 pixels on 12.7 inches, about 273 dots per
## inch, would start at 2x because Android files it under the 320 bucket, and
## wants 1.7.
## is that 1.7. A Pixel 6a, 1080 by 2400 at about 429, must keep buttons a
## fingertip can hit, and a desktop monitor must read what it read before.
extends "res://tests/test_framework.gd"

const TABLET_DPI: float = 273.0
const PIXEL_6A_DPI: float = 429.0

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func test_the_tablet_starts_near_a_painters_own_pick() -> void:
    # 2944 by 1840 is the tablet's resolution, and 273 is its diagonal of
    # 3472 pixels over 12.7 inches. Android reports the 320 bucket as 2.
    assert_almost_eq(
        SaUI.starting_scale("Android", "android", 2.0, TABLET_DPI), 1.7, 0.1, "The tablet starts within 0.1 of the 1.7 wanted"
    )


func test_a_phone_keeps_buttons_a_finger_can_hit() -> void:
    var phone := SaUI.starting_scale("Android", "android", 2.625, PIXEL_6A_DPI)
    assert_true(phone >= 2.0, "A Pixel 6a starts at 2 or more, read %s" % phone)


func test_an_unknown_android_density_starts_at_one() -> void:
    assert_almost_eq(SaUI.starting_scale("Android", "android", 2.0, 0.0), 1.0, 0.0001, "No figure is Android's own baseline of 1")


func test_a_desktop_monitor_reads_what_it_read_before() -> void:
    assert_almost_eq(SaUI.starting_scale("Linux", "Wayland", 2.0, 163.0), 2.0, 0.0001, "A Wayland 4K monitor at 2x stays 2x")
    assert_almost_eq(
        SaUI.starting_scale("Linux", "Wayland", 1.0, 287.0), 1.0, 0.0001, "A Wayland 1x is the truth, whatever the panel's dots"
    )
    assert_almost_eq(SaUI.starting_scale("Windows", "Windows", 1.5, 144.0), 1.5, 0.0001, "Windows at 150 percent stays 1.5")
    assert_almost_eq(
        SaUI.starting_scale("Linux", "X11", 1.0, 287.0),
        SaUI.infer_scale_from_dpi(287),
        0.0001,
        "X11 still guesses from the panel as before"
    )
    assert_almost_eq(SaUI.starting_scale("Linux", "X11", 1.0, 96.0), 1.0, 0.0001, "A plain 1080p X11 monitor is 1x")


func test_the_painters_own_scale_still_multiplies_the_start() -> void:
    SaUI.os_scale_override = SaUI.starting_scale("Android", "android", 2.0, TABLET_DPI)
    SaUI.user_scale = 1.2
    assert_almost_eq(SaUI.scale(), SaUI.os_scale_override * 1.2, 0.0001, "Preferences' scale multiplies the tablet's start")
