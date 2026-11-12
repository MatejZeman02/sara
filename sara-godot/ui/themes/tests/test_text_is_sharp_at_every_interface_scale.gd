## Text is as sharp at every interface scale as at 100%: each glyph is a bitmap
## rasterised at the window's scale and drawn on whole device pixels.
##
## The engine places a glyph on a whole logical pixel, which at a scale of 1.05
## or 0.85 is between two device pixels, so the bitmap was filtered soft, and an
## embedded docker's texture with it. A distance field hid that by being equally
## soft everywhere, and softest at the small text sizes. These cases hold the
## field off and the snap on wherever a window's scale is fractional, and
## `scripts/check_text_sharpness.py` measures the shots.
extends "res://tests/test_framework.gd"

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func test_the_project_draws_glyphs_as_bitmaps() -> void:
    assert_false(SaFonts.field_on(), "the font line of project.godot is off, so a glyph is rasterised at its size on screen")


func test_every_shipped_face_follows_the_line() -> void:
    for id: String in SaFonts.FAMILIES:
        if String(SaFonts.FAMILIES[id]["regular"]).is_empty():
            continue
        for face: Font in [SaFonts.regular(id), SaFonts.bold(id)]:
            var file := face as FontFile
            assert_not_null(file, "%s ships a FontFile" % id)
            if file != null:
                var said := "%s draws from the field only when the line asks for it" % id
                assert_eq(file.multichannel_signed_distance_field, SaFonts.field_on(), said)


func test_the_theme_holds_the_same_face() -> void:
    var face := SaFonts.regular(SaFonts.DEFAULT) as FontFile
    var theme := load("res://ui/themes/teal-orange.tres") as Theme
    assert_not_null(theme, "the shipped theme loads")
    if theme == null or face == null:
        return
    assert_true(theme.default_font == face, "the theme's Inter is the resource SaFonts wrote, not a second copy")
    var field := (theme.default_font as FontFile).multichannel_signed_distance_field
    assert_eq(field, SaFonts.field_on(), "so the theme draws as the line asks as well")


func test_the_engines_own_font_follows_the_line_by_itself() -> void:
    var fallback := ThemeDB.fallback_font as FontFile
    if fallback == null:
        return
    assert_eq(fallback.multichannel_signed_distance_field, SaFonts.field_on(), "Open Sans takes the line from the engine")


func test_a_fractional_scale_snaps_and_a_whole_one_does_not() -> void:
    for factor: float in [0.75, 0.85, 0.95, 1.05, 1.25, 1.4, 1.5, 2.5]:
        assert_true(SaUI.snaps_to_pixels(factor), "a scale of %s puts glyphs between device pixels, so it snaps" % factor)
    for factor: float in [1.0, 2.0, 3.0]:
        assert_false(SaUI.snaps_to_pixels(factor), "a scale of %s is already on the pixel grid" % factor)


func test_a_window_at_a_fractional_scale_draws_on_whole_pixels() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.05
    var window := Window.new()
    SaUI.apply_to_window(window)
    assert_true(window.snap_2d_vertices_to_pixel, "a window at 105% snaps its vertices")
    SaUI.user_scale = 1.0
    SaUI.apply_to_window(window)
    assert_false(window.snap_2d_vertices_to_pixel, "and lets go of the snap back at 100%")
    window.free()


func test_an_embedded_docker_snaps_by_its_hosts_scale() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var root := (Engine.get_main_loop() as SceneTree).root
    var kept_embedding := root.gui_embed_subwindows
    # A window that is not embedded would map a real OS window and block the run.
    root.gui_embed_subwindows = true
    var host := Node.new()
    EventBus.add_child(host)
    var docker := Window.new()
    docker.visible = false
    host.add_child(docker)
    assert_true(docker.is_embedded(), "the docker is drawn inside the root")
    SaUI.user_scale = 1.25
    SaUI.apply_to_window(docker)
    assert_almost_eq(docker.content_scale_factor, 1.0, 0.0001, "the docker's own factor stays 1.0 inside its host")
    assert_almost_eq(SaUI.screen_scale(docker), 1.25, 0.0001, "but it reaches the screen at its host's 125%")
    assert_true(docker.snap_2d_vertices_to_pixel, "so its glyphs snap as the host's do")
    SaUI.user_scale = 1.0
    SaUI.apply_to_window(docker)
    assert_false(docker.snap_2d_vertices_to_pixel, "and stop snapping when the host is back at 100%")
    host.free()
    root.gui_embed_subwindows = kept_embedding
