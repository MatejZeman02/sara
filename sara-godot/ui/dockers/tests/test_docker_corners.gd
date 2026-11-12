## The docker background's corners, and the reader that grades them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The corner shape is about texels, and texels are the scenario's job:
## `scenarios/round-corners-all-the-way-in.json` walks every corner of two
## dockers at two UI scales and the run log names what each texel is. What is
## here is the mechanism behind that reading, which no capture can show: the
## panel is rounded, it casts no shadow into the wedge the radius leaves, and the
## comparison the walk is made of answers what it should.
extends "res://tests/test_framework.gd"


func test_the_docker_background_is_rounded_on_all_four_corners() -> void:
    var host := Control.new()
    var panel := DockerUtils.create_docker_background(host)

    var style := panel.get_theme_stylebox("panel") as StyleBoxFlat

    assert_not_null(style, "the panel carries its own box")
    for corner: int in [
        style.corner_radius_top_left,
        style.corner_radius_top_right,
        style.corner_radius_bottom_right,
        style.corner_radius_bottom_left
    ]:
        assert_true(corner > 0, "every corner has a radius, or there is nothing to creep into")
    host.free()


## The whole of the fix. A docker window is exactly this panel's rectangle, so
## the shadow is clipped away along every straight edge and is drawn **only** in
## the four corners, in the wedge the radius leaves between the panel and the
## square window. It measured 5a5a5a at the top and 393939 at the bottom against
## a 7f7f7f canvas, on every corner of every docker, and the same texels read the
## canvas with the shadow off.
func test_the_docker_background_casts_no_shadow_into_its_own_corners() -> void:
    var host := Control.new()
    var panel := DockerUtils.create_docker_background(host)

    var style := panel.get_theme_stylebox("panel") as StyleBoxFlat

    assert_eq(style.shadow_size, 0, "no shadow, so a rounded corner shows what is behind the docker and nothing else")
    assert_true(SaTheme.make_docker_background_style().shadow_size > 0, "and the theme still offers one to anyone else")
    host.free()


## The corner walk starts on the corner texel and goes outward, and it takes for
## granted that every one of those texels is outside the rounded panel. That
## holds because the corner texel sits `sqrt(2) * radius` from the arc's centre
## while the arc is `radius`, which is a claim about the radius rather than about
## the walk, so it is asserted where the radius lives.
func test_the_corner_texel_is_outside_the_arc_at_the_radius_the_panel_uses() -> void:
    var host := Control.new()
    var panel := DockerUtils.create_docker_background(host)
    var radius := float((panel.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left)

    assert_true(sqrt(2.0) * radius > radius + 1.0, "the corner texel is over a texel clear of the arc at radius %f" % radius)
    host.free()


func test_two_texels_a_hair_apart_read_as_the_same_colour() -> void:
    # A rounded edge is drawn antialiased, so the reader has to forgive a blend
    # of a texel or so. Wide enough for that and nothing like wide enough for the
    # shadow, which was 37 of 255 away from the canvas at its palest.
    var canvas := Color8(127, 127, 127)

    assert_true(SaDockerWindowCapture._alike(canvas, Color8(129, 126, 128)), "a texel of antialiasing is the same colour")
    assert_false(SaDockerWindowCapture._alike(canvas, Color8(90, 90, 90)), "and the palest shadow texel measured is not")
