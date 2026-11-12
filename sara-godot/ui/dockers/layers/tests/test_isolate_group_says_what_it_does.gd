## The row that sets how a group blends reads Blend Group on
## Its Own, and every word a painter reads about it says the same.
##
## It read Isolate Group, which a painter from Krita's Isolate Layer or
## Photoshop's solo takes for a view that shows only the group, so ticking it
## and seeing the canvas unchanged read as a broken row. What it sets is the
## group's blend, its layers with each other first rather than one by one into
## what is below. What this suite holds is the row's words and sentence in both
## menus, the mark it lights on the group's row and that mark's two tooltips,
## the box's tip while a mask or a filter holds the group, the More button's
## tooltip and the history step's name, and that none of them says isolate.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document both menus are drawn for.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const WORDS := "Blend Group on Its Own"
const SENTENCE := "Blend the group's layers with each other first, and the result with what is below it."
const MARK := "Blends on its own: its layers blend with each other first"
const MARK_HELD := "Blends on its own while it carries a mask or a filter: its layers blend with each other first"
const MASK_TIP := "The group's mask makes it blend on its own. Delete the mask to blend its layers one by one."
const FILTER_TIP := "A filter on the group makes it blend on its own. Detach it or switch it off to blend its layers one by one."
const STEP := "Group Blending"

var _bar: TopMenuBar = null
var _docker: LayersDocker = null
var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    canvas.add_child(_docker)
    _docker.target_canvas = canvas
    _docker._ready()
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.actions.op_buttons.commands = _registries.commands
    _docker.actions.op_buttons.fit(0.0)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    var menu := _layer_menu()
    menu.document = _document()
    menu.layer_types = _registries.layer_types


func after_each() -> void:
    _bar.free()
    _docker.target_canvas.free()
    _registries = null


func _layer_menu() -> SaLayerMenu:
    return _bar.menu("Layer") as SaLayerMenu


func _document() -> SaDocument:
    return _docker.target_canvas.document


## The active layer wrapped in a group, which is then active, as the More
## menu's Group does it.
func _group() -> SaLayer:
    _docker.actions.toggle_group()
    _docker.actions.sync_from_active_layer()
    return _document().active_layer


## The row in the docker's list that carries *layer*, the list built afresh.
func _row_of(layer: SaLayer) -> SaRowFrame:
    _docker.sync_layer_list()
    var list: SaLayerList = _docker.item_list
    for i: int in list.row_count():
        if list.layer_at(i) == layer:
            return list.rows[i]
    return null


## The Layer menu's row for the group's blend, under the key its popup holds
## it by, the menu built afresh.
func _layer_menu_key() -> StringName:
    _layer_menu().populate()
    return SaMenu.key(SaLayerMenuRows.number_of(SaLayerMenuRows.ISOLATE))


## The More menu's id for the same row, the menu built afresh.
func _more_id() -> StringName:
    _docker.actions.sync_from_active_layer()
    return _docker.actions.row_id_of(SaLayerActions.Item.ISOLATE)


func test_both_menus_read_blend_group_on_its_own_with_its_sentence() -> void:
    _group()
    var popup := _layer_menu().popup
    var key := _layer_menu_key()
    assert_eq(popup.label_button(key).text, WORDS, "the Layer menu's row reads Blend Group on Its Own")
    assert_eq(popup.label_button(key).tooltip_text, SENTENCE, "and says on hover what it does")
    assert_false(popup.is_disabled(key), "and is offered on a group")
    var more := _docker.actions.menu
    var id := _more_id()
    assert_eq(more.label_button(id).text, WORDS, "the More menu's row reads the same")
    assert_eq(more.label_button(id).tooltip_text, SENTENCE, "with the same sentence")
    assert_true(Array(_docker.actions.menu_titles()).has(WORDS), "and the docker's own list of titles has it")


func test_ticking_it_lights_the_groups_mark_in_the_same_words_as_one_step() -> void:
    var group := _group()
    var row := _row_of(group)
    assert_not_null(row, "the group has a row in the list")
    if row == null:
        return
    assert_false(row.isolated_mark.visible, "a group that blends its layers one by one carries no mark")

    _layer_menu().on_id_pressed(SaLayerMenuRows.number_of(SaLayerMenuRows.ISOLATE))
    assert_true(group.isolated, "ticking it in the Layer menu sets the group's blend")
    row = _row_of(group)
    assert_true(row.isolated_mark.visible, "and lights the mark on the group's row")
    assert_eq(row.isolated_mark.tooltip_text, MARK, "which says Blends on its own")
    assert_eq(_document().undo_redo.get_current_action_name(), STEP, "and the history step is Group Blending")
    assert_true(_layer_menu().popup.is_checked(_layer_menu_key()), "and the Layer menu's tick says so")
    assert_true(_docker.actions.menu.is_checked(_more_id()), "and so does the More menu's")

    _docker.actions.press_item(SaLayerActions.Item.ISOLATE)
    assert_false(group.isolated, "pressing the More menu's row unticks it")
    assert_eq(_document().undo_redo.get_current_action_name(), STEP, "as a step of the same name")
    assert_false(_row_of(group).isolated_mark.visible, "and the mark goes")

    _document().undo()
    assert_true(group.isolated, "and an undo gives the tick back")


func test_a_mask_holding_it_says_so_in_the_same_words() -> void:
    var group := _group()
    group.add_mask()
    var row := _row_of(group)
    assert_true(row.isolated_mark.visible, "a group carrying a mask blends on its own")
    assert_eq(row.isolated_mark.tooltip_text, MARK_HELD, "and its mark says what holds it")
    var popup := _layer_menu().popup
    var key := _layer_menu_key()
    assert_true(popup.is_disabled(key), "the row is dimmed, since unticking it would change nothing")
    assert_eq(popup.check_box(key).tooltip_text, MASK_TIP, "and its box says why in the row's words")
    assert_eq(_docker.actions.menu.check_box(_more_id()).tooltip_text, MASK_TIP, "in the More menu as well")


func test_a_filter_holding_it_says_so_in_the_same_words() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(256, 256))
    var doc := easel.document
    var group := SaLayerOps.new(doc).group_layers([doc.get_node("Layer 1") as SaLayer])
    doc.set_active_layer(group)
    SaFilterOps.new(doc).attach(group, Bench.INVERT)
    var row := SaLayerRowView.new(str(group.name), 0, true, 0, group)
    row.refresh(doc)
    assert_true(row.isolated_mark.visible, "a group carrying a filter blends on its own")
    assert_eq(row.isolated_mark.tooltip_text, MARK_HELD, "and its mark says what holds it")
    var tip := ""
    for drawn: Variant in SaLayerMenuRows.new(doc).rows(true):
        if drawn is SaLayerMenuRows.Row and (drawn as SaLayerMenuRows.Row).id == SaLayerMenuRows.ISOLATE:
            tip = (drawn as SaLayerMenuRows.Row).box_tip
    assert_eq(tip, FILTER_TIP, "and the row's box says why in the row's words")
    row.free()
    easel.free()


## The words a painter reads about the group's blend, every one of them, with
## the More button's own, and none says isolate.
func test_no_word_about_it_says_isolate() -> void:
    var more_tip := _docker.actions.more_btn.tooltip_text
    # The More button's tooltip is three words and does not list what is
    # behind it, so the row's own words are no longer in it.
    assert_eq(more_tip, "More layer actions", "the More button says what it opens")
    var group := _group()
    var read: Array[String] = [more_tip]
    for held: bool in [false, true]:
        if held:
            group.add_mask()
        else:
            SaLayerOps.new(_document()).set_isolated(group, true)
        read.append(_row_of(group).isolated_mark.tooltip_text)
        for drawn: Variant in SaLayerMenuRows.new(_document(), _registries.commands).rows(false):
            if drawn is SaLayerMenuRows.Row and (drawn as SaLayerMenuRows.Row).id == SaLayerMenuRows.ISOLATE:
                var shown := drawn as SaLayerMenuRows.Row
                read.append(shown.words)
                read.append(shown.sentence)
                read.append(shown.box_tip)
    read.append(_document().undo_redo.get_current_action_name())
    for words: String in read:
        assert_false(words.to_lower().contains("isolat"), "no word a painter reads says isolate: %s" % words)
    assert_eq(read.size(), 10, "and every one was read: %s" % [read])
