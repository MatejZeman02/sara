## A layer's name in its row shows whole in a language longer
## than English.
##
## Under the test language the row cut "Background" to 128 of the 196 pixels its
## words ask for. A name Sara wrote is one the catalogue translates, and the row
## now lets it wrap onto a second line, breaking inside the word when it is one
## word wider than its column. A painter's own name is in no catalogue and keeps
## its one line and its ellipsis, and in English nothing wraps, so no row moves.
##
## The row is built through `SaLayerRowView` and laid out by hand, as the hover
## test beside this one does, because a docker is a `Window` and adding one in a
## headless run hangs. The catalogue is a one-message `Translation` made here,
## so the test leans on no module. The scenario
## `scenarios/a-layer-s-name-in-its-row-shows-whole-in-a-language-longer-than-english.py`
## photographs the docker under the real test language.
extends "res://tests/test_framework.gd"

## The row carries a thumbnail, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const RowView = preload("res://ui/dockers/layers/list/layer_row_view.gd")

const LOCALE := "eo"
const LONG_BACKGROUND := "‹Бáčķğřóúñďжщыюжщыю›"
const PAINTERS_NAME := "Evening light over the harbour wall"
## The share of the name's one-line width the label is given, so the name is
## cut on one line at any interface scale and fits on two.
const ROOM := 0.65

var _catalogue: Translation
var _locale_before := ""


func before_each() -> void:
    _locale_before = TranslationServer.get_locale()
    _catalogue = Translation.new()
    _catalogue.locale = LOCALE
    _catalogue.add_message("Background", LONG_BACKGROUND)
    TranslationServer.add_translation(_catalogue)


func after_each() -> void:
    TranslationServer.set_locale(_locale_before)
    TranslationServer.remove_translation(_catalogue)


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## Sorts every container under *node*, outside in. A test cannot await a frame.
func _sort_children(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort_children(child)


## A row for *layer*, wide enough to give the label ROOM of the name's one-line
## width, and as tall as it then asks to be.
func _row(layer: SaLayer, document: SaDocument) -> SaLayerRowView:
    var item: SaLayerRowView = RowView.new(str(layer.name), 0, false, 0, layer)
    EventBus.add_child(item)
    item.refresh(document)
    var width := item.get_combined_minimum_size().x + ROOM * _one_line_width(item, item.lbl.atr(item.lbl.text))
    # A wrapping label knows its height only once it has its width, so the row
    # is laid out again until the height it asks for stops changing.
    for _pass in 4:
        item.lbl.update_minimum_size()
        item.hbox.update_minimum_size()
        item.update_minimum_size()
        item.size = Vector2(width, 0.0)
        _sort_children(item)
    return item


## The default document's layer named Background, renaming the active one when
## there is none, since a node's name is unique among its siblings.
func _background(document: SaDocument) -> SaLayer:
    var found := document.get_node_or_null(^"Background") as SaLayer
    if found != null:
        return found
    document.active_layer.name = "Background"
    return document.active_layer


func _one_line_width(item: SaLayerRowView, text: String) -> float:
    var font := item.lbl.get_theme_font(&"font")
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, item.lbl.get_theme_font_size(&"font_size")).x


func test_background_in_a_longer_language_shows_whole_on_two_lines() -> void:
    TranslationServer.set_locale(LOCALE)
    var easel := _easel()
    var layer := _background(easel.document)
    var item := _row(layer, easel.document)
    var shown := item.lbl.atr(item.lbl.text)
    assert_eq(shown, LONG_BACKGROUND, "The row draws the catalogue's Background")
    assert_true(
        _one_line_width(item, shown) > item.lbl.size.x,
        "which is wider than its column, %.1f of %.1f" % [_one_line_width(item, shown), item.lbl.size.x]
    )
    assert_eq(item.lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "so the name Sara wrote wraps")
    assert_true(item.lbl.get_line_count() >= 2, "onto a second line, %d lines" % item.lbl.get_line_count())
    assert_eq(item.lbl.get_visible_line_count(), item.lbl.get_line_count(), "and every line shows")
    assert_true(item.size.y >= item.lbl.get_minimum_size().y, "because the row grows to the label's height, %.1f" % item.size.y)
    assert_true(item.size.y < 2.0 * item.custom_minimum_size.y, "and no further than two lines, %.1f" % item.size.y)
    assert_eq(item.get_tooltip(Vector2(4.0, 4.0)), "", "A name shown whole asks no tooltip")
    item.free()
    easel.free()


func test_a_painters_long_name_keeps_one_line_and_its_ellipsis() -> void:
    TranslationServer.set_locale(LOCALE)
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.name = PAINTERS_NAME
    var item := _row(layer, easel.document)
    assert_eq(item.lbl.autowrap_mode, TextServer.AUTOWRAP_OFF, "A name the painter typed is in no catalogue and does not wrap")
    assert_eq(int(item.size.y), int(item.custom_minimum_size.y), "so its row keeps the one line's height")
    assert_eq(item.get_tooltip(Vector2(4.0, 4.0)), PAINTERS_NAME, "and the name cut short is read whole on hover")
    item.free()
    easel.free()


func test_in_english_background_is_one_line_as_it_always_was() -> void:
    TranslationServer.set_locale("en")
    var easel := _easel()
    var layer := _background(easel.document)
    var item := _row(layer, easel.document)
    assert_eq(item.lbl.autowrap_mode, TextServer.AUTOWRAP_OFF, "English translates Background to itself, so nothing wraps")
    assert_eq(int(item.size.y), int(item.custom_minimum_size.y), "and the row is the height it was")
    item.free()
    easel.free()
