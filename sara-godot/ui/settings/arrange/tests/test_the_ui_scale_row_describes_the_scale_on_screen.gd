## The Workspace page's UI scale row describes the scale on screen, not the
## one the page was built at.
##
## A move of the slider wrote the line's two labels by hand and left the row's
## `label` and `explanation` as they were, so the screen said 95 per cent and a
## dump of the same frame said 100. What is here is the page in the tree, the
## slider moved under a held grabber so the setting behind it is never written,
## and the row read back through its fields, its dump, its line and the title
## the search reads.
##
## The row says when the scale held would leave the painting
## less than `DockerLayoutStore.PAINTING_SHARE` of the window between the
## dockers open in it, measured on a store planted with three probe dockers.
##
## The number is not in the title but beside the
## slider, "95%" under "UI scale", so what follows the hand is the readout and
## the hint, and the title reads the same at every scale.
extends "res://tests/test_framework.gd"

## The sentence the hint adds, up to the share it names.
const CROWDED := "At this scale the dockers open now would leave less than"

var _host: Node = null
var _page: SaWorkspacePage = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "Host"
    EventBus.add_child(_host)
    _page = SaWorkspacePage.new()
    _host.add_child(_page)


func after_each() -> void:
    if is_instance_valid(_page):
        _page.free()
    if is_instance_valid(_host):
        _host.free()


## Moves a slider the way a hand dragging its grabber does: the labels follow
## and the setting waits for the release, which this never sends, so the
## interface of the running suite keeps its scale.
func _drag_to(slider: HSlider, value: float) -> void:
    slider.drag_started.emit()
    slider.value = value
    slider.value_changed.emit(slider.value)


func _other_than(current: float) -> float:
    return 1.05 if is_equal_approx(current, 0.95) else 0.95


func _pct(fraction: float) -> int:
    return int(round(fraction * 100.0))


func _readout(slider: HSlider) -> String:
    return (slider.get_parent().get_node(NodePath(SaPage.READOUT_NAME)) as Label).text


func test_the_scale_row_reads_the_scale_it_was_moved_to() -> void:
    var row := _page.page.row(&"ui_scale")
    assert_not_null(row, "the page declares the UI scale row")
    var built_at := SaSettings.ui_scale
    var moved_to := _other_than(built_at)
    var system_pct := int(round(SaUI.scale() / maxf(0.01, SaUI.user_scale) * 100.0))
    var drawn := "drawn at %d%%" % int(round(moved_to * system_pct))

    var slider := _page.slider_named("ui_scale")
    _drag_to(slider, moved_to)

    assert_eq(_readout(slider), "%d%%" % _pct(moved_to), "the readout beside the slider is the scale it was moved to")
    var title := "UI scale"
    assert_eq(row.label, title, "the row's label stays the title, with no number in it")
    assert_true(row.explanation.contains(drawn), "and its explanation follows, '%s'" % row.explanation)
    var dump := row.describe()
    assert_eq(String(dump["label"]), title, "the dump reads the same label")
    assert_true(String(dump["explain"]).contains(drawn), "and the same explanation")
    assert_eq((row.line.get_node(^"Labels/Title") as Label).text, title, "the line on screen agrees")
    assert_true((row.line.get_node(^"Labels/Hint") as Label).text.contains(drawn), "and so does its hint")
    assert_eq(String(row.line.get_meta(SaSettingsRows.TITLE_META, "")), title, "the search reads the title on screen")
    assert_eq(String(row.control.get_meta(SaSettingsRows.TITLE_META, "")), title, "off the slider's box as well")
    assert_eq(
        slider.tooltip_text,
        "Resize every window, row and control at once.",
        "and the slider's tooltip says what it does, as WORDING.md asks"
    )
    assert_eq(SaSettings.ui_scale, built_at, "a held grabber has not written the setting")


func test_the_font_row_follows_as_well() -> void:
    var row := _page.page.row(&"font_size")
    assert_not_null(row, "the page declares the Font size row")
    var moved_to := _other_than(SaSettings.ui_text_size)

    var slider := _page.slider_named("font_size")
    _drag_to(slider, moved_to)

    var stored := moved_to * SaSettingsValues.DEFAULT_FONT_SCALE
    var points := "at %d points" % maxi(1, int(round(float(SaUI.BASE_FONT_SIZE) * stored)))
    assert_eq(_readout(slider), "%d%%" % _pct(moved_to), "the readout is the size it was moved to")
    assert_eq(String(row.describe()["label"]), "Font size", "and the dump reads the title alone")
    assert_true(row.explanation.contains(points), "and the points it gives, '%s'" % row.explanation)
    assert_eq((row.line.get_node(^"Labels/Title") as Label).text, "Font size", "the line on screen agrees")


## A store under the name the page looks it up by, over a host 1280 wide at
## scale 1 with the toolbox, the Brush Presets and the Colour Picker open where
## the default opens them on it, 680 of the width between them.
func _plant_dockers() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(int(1280.0 / SaUI.user_scale), 800)
    viewport.gui_embed_subwindows = true
    _host.add_child(viewport)
    var configs: Array = []
    for span: Vector2i in [Vector2i(0, 60), Vector2i(70, 310), Vector2i(960, 310)]:
        var probe := Window.new()
        probe.position = Vector2i(span.x, 78)
        probe.size = Vector2i(span.y, 300)
        viewport.add_child(probe)
        configs.append({"node": probe})
    var hidden := Window.new()
    hidden.position = Vector2i(400, 78)
    hidden.size = Vector2i(500, 300)
    viewport.add_child(hidden)
    hidden.hide()
    configs.append({"node": hidden})
    var store := DockerLayoutStore.new()
    store.name = "DockerLayoutStore"
    store.path = SaDataRoot.path("test_never_written.cfg")
    store.dockers_provider = func() -> Array: return configs
    _host.add_child(store)


func test_the_hint_says_when_the_scale_held_leaves_too_little_to_paint_in() -> void:
    _plant_dockers()
    var built_at := SaSettings.ui_scale
    var row := _page.page.row(&"ui_scale")
    var slider := _page.slider_named("ui_scale")
    _drag_to(slider, 2.0)
    assert_true(row.explanation.contains(CROWDED), "at 200 per cent 680 of 640 is over the share, '%s'" % row.explanation)
    var share := "%d%%" % _pct(DockerLayoutStore.PAINTING_SHARE)
    assert_true(row.explanation.contains(share), "and the share is named, %s" % share)
    _drag_to(slider, 1.0)
    assert_false(row.explanation.contains(CROWDED), "at 100 per cent 600 of 1280 is left and it says nothing")
    assert_eq(SaSettings.ui_scale, built_at, "and the held grabber wrote nothing")


func test_the_dockers_cover_the_width_they_stand_on_once() -> void:
    var spans: Array[Vector2i] = [Vector2i(70, 380), Vector2i(0, 60), Vector2i(70, 300), Vector2i(960, 1270)]
    assert_eq(SaWorkspacePage.covered_width(spans), 680, "two dockers in one column count once")
    assert_eq(SaWorkspacePage.covered_width([] as Array[Vector2i]), 0, "and none cover nothing")


func test_a_row_not_yet_drawn_keeps_the_words() -> void:
    var row := SaPageRow.new()
    row.retitle("Size: 3", "Three of them.")
    assert_eq(row.label, "Size: 3", "a row with no line takes the title")
    assert_eq(row.explanation, "Three of them.", "and the explanation, for when it is drawn")
