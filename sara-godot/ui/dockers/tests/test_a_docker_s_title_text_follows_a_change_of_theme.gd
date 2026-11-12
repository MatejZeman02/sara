## A docker's title text follows a change of theme.
##
## The title strip once set its label's colour as a plain override when it was
## built, so after a switch to a light palette or Pink the title stood in the
## old palette's colour on the new bar. The label is now bound to the palette's
## `text_primary`, and every switch repaints it. Each shipped palette is taken
## in turn, both at once and in slices as Quick settings does, and the colour
## the label draws with is read back each time.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"
var _bar: PanelContainer = null


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    SaTheme.use_named("default")
    _bar = DockerUtils.make_drag_bar("Layers")


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    SaTheme.use_named(_saved_theme)


func _title() -> Label:
    return _bar.find_child("TitleLabel", true, false) as Label


func _expected(id: String) -> Color:
    return (load(SaTheme.PALETTES[id]) as SaPalette).text_primary


func test_the_title_takes_each_palettes_text_colour_after_a_switch() -> void:
    var lbl := _title()
    assert_not_null(lbl, "The bar has a title label")
    if lbl == null:
        return
    var seen: Dictionary = {}
    for entry: Dictionary in SaTheme.builtin():
        var id: String = entry["id"]
        SaTheme.use_named(id)
        var want := _expected(id)
        seen[want.to_html()] = true
        assert_eq(lbl.get_theme_color("font_color"), want, "The title is in %s's text colour" % id)
    assert_true(seen.size() > 1, "The palettes walked hold more than one text colour, so a stale title would show")


func test_the_title_follows_a_switch_painted_in_slices() -> void:
    var lbl := _title()
    assert_not_null(lbl, "The bar has a title label")
    if lbl == null:
        return
    var tree := Engine.get_main_loop() as SceneTree
    for id: String in ["paper", "pink", "default"]:
        if not SaTheme.PALETTES.has(id):
            continue
        SaTheme.use_named_in_slices(id, 200, tree)
        var frames := 0
        while SaTheme.repainting() and frames < 600:
            await tree.process_frame
            frames += 1
        assert_false(SaTheme.repainting(), "The switch to %s ended" % id)
        assert_eq(lbl.get_theme_color("font_color"), _expected(id), "The title is in %s's text colour after a sliced switch" % id)
