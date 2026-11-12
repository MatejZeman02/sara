## The Layer menu and the Layers docker's More menu are drawn
## from one list of rows, `SaLayerMenuRows`.
##
## The two were two lists and named one job two ways, Duplicate Layer and
## Duplicate, Clear Layer and Clear, Lock Layer and Lock Painting. The menu
## said Group on a group and ungrouped, Rename and Isolate Group were only in
## the docker, the kinds of layer only behind its arrow, and the arrow's last
## row, Group, added nothing. What this suite holds is that the rows the two
## share come in one order under one name, Ungroup on a group in both, that the
## Layer menu has Rename and the kinds, and that the arrow has no Group.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document both menus are drawn for.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The rows a layer that is not a group cannot take on a group.
const LAYER_ONLY: Array[StringName] = [&"layer_merge_down", &"layer_bake", &"layer_lock", &"layer_alpha_lock", &"layer_clear"]

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
    # All four folded into the menu, so every row the two share is there.
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


## The Layer menu's rows as `[id, words]`, in order, built afresh, one array
## for the menu's own list and one for each submenu, because rows of one kind
## stand under a row of their own and the order is each list's.
func _layer_lists() -> Array:
    var menu := _layer_menu()
    menu.populate()
    var list := SaLayerMenuRows.new(_document(), _registries.commands, _registries.layer_types)
    var out := []
    for popup: SaChoicePopup in SaMenu.lists_of(menu.popup):
        var rows := []
        for key: StringName in popup.row_ids():
            rows.append([list.id_at(SaMenu.id_of(key)), popup.label_button(key).text])
        out.append(rows)
    return out


## Every row of the Layer menu and its submenus, as `[id, words]`.
func _layer_rows() -> Array:
    var out := []
    for rows: Array in _layer_lists():
        out.append_array(rows)
    return out


## Whether the rows the More menu shares with each of the Layer menu's lists
## come in that list's order and words.
func _in_each_lists_order(more: Array) -> bool:
    for rows: Array in _layer_lists():
        var shared := _shared(rows, more)
        var ids := shared.map(func(row: Array) -> StringName: return row[0])
        if more.filter(func(row: Array) -> bool: return ids.has(row[0])) != shared:
            return false
    return true


## The More menu's rows as `[id, words]`, in order, built afresh. The Colour
## row is the right click's own, a list of the docker's beside it, so it
## is left out of what the two share.
func _more_rows() -> Array:
    var actions := _docker.actions
    actions.sync_from_active_layer()
    var out := []
    for id: StringName in actions.menu.row_ids():
        if id != SaLayerActions.COLOUR:
            out.append([id, actions.menu.label_button(id).text])
    return out


## *rows* less those whose id the More menu does not draw.
func _shared(rows: Array, more: Array) -> Array:
    var ids := more.map(func(row: Array) -> StringName: return row[0])
    return rows.filter(func(row: Array) -> bool: return ids.has(row[0]))


func _words_of(rows: Array, id: StringName) -> String:
    for row: Array in rows:
        if row[0] == id:
            return row[1]
    return ""


func test_the_rows_the_two_share_come_in_one_order_under_one_name() -> void:
    var more := _more_rows()
    var layer := _layer_rows()
    var why_words := "the More menu reads the Layer menu's rows in its words: %s"
    assert_true(more.all(func(row: Array) -> bool: return layer.has(row)), why_words % [more])
    assert_true(_in_each_lists_order(more), "and in the order of the list or submenu each is on")
    var why := "every row but the adds, Delete and, on a layer with no mask, the five that act on one: %s"
    assert_eq(more.size(), 18, why % [more])
    assert_eq(_words_of(more, &"layer_duplicate"), "Duplicate Layer", "Duplicate is the command's Duplicate Layer")
    assert_eq(_words_of(more, &"layer_clear"), "Clear Layer", "Clear is Clear Layer")
    assert_eq(_words_of(more, &"layer_lock"), "Lock Layer", "and Lock Painting is Lock Layer")
    var left_out := layer.filter(func(row: Array) -> bool: return not more.has(row))
    for id: StringName in [&"layer_new_paint", &"layer_new_double", &"layer_delete"]:
        assert_true(left_out.any(func(row: Array) -> bool: return row[0] == id), "%s is the row's own button" % id)


func test_a_command_rows_chord_and_sentence_read_alike_in_both() -> void:
    _docker.actions.sync_from_active_layer()
    var menu := _layer_menu()
    menu.populate()
    var hints := {}
    for popup: SaChoicePopup in SaMenu.lists_of(menu.popup):
        for entry: Dictionary in popup.row_report():
            hints[String(entry["label"])] = entry
    for entry: Dictionary in _docker.actions.menu.row_report():
        var label := String(entry["label"])
        if StringName(entry["id"]) == SaLayerActions.COLOUR:
            continue
        assert_eq(String(entry.get("hint", "")), String(hints[label].get("hint", "")), "%s shows one chord in both" % label)
    var number := SaLayerMenuRows.number_of(&"layer_move_up")
    assert_eq(
        _docker.actions.menu.label_button(&"layer_move_up").tooltip_text,
        SaMenu.list_holding(menu.popup, SaMenu.key(number)).label_button(SaMenu.key(number)).tooltip_text,
        "and says one sentence on hover"
    )
    assert_false(_docker.actions.menu.label_button(&"layer_move_up").tooltip_text.is_empty(), "which is the command's")


func test_both_say_ungroup_on_a_group_and_isolate_it() -> void:
    _docker.actions.toggle_group()
    assert_true(_document().active_layer.is_group, "the active layer is a group")
    var more := _more_rows()
    var layer := _layer_rows()
    assert_eq(_words_of(more, &"layer_group"), "Ungroup", "the More menu says Ungroup")
    assert_eq(_words_of(layer, &"layer_group"), "Ungroup", "and so does the Layer menu")
    assert_true(more.all(func(row: Array) -> bool: return layer.has(row)), "and the two still read alike")
    assert_true(_in_each_lists_order(more), "in one order")

    var menu := _layer_menu()
    var isolate := SaMenu.key(SaLayerMenuRows.number_of(SaLayerMenuRows.ISOLATE))
    assert_false(menu.popup.is_disabled(isolate), "the Layer menu offers Blend Group on Its Own on a group")
    menu.on_id_pressed(SaLayerMenuRows.number_of(SaLayerMenuRows.ISOLATE))
    assert_true(_document().active_layer.isolated, "and its press isolates it")
    assert_true(menu.is_item_checked(SaLayerMenuRows.number_of(SaLayerMenuRows.ISOLATE)), "and the tick says so")


func test_a_layer_only_row_is_dimmed_on_a_group_in_both_and_says_why() -> void:
    _docker.actions.toggle_group()
    _docker.actions.sync_from_active_layer()
    var menu := _layer_menu()
    menu.populate()
    for id: StringName in LAYER_ONLY:
        var key := SaMenu.key(SaLayerMenuRows.number_of(id))
        var list := SaMenu.list_holding(menu.popup, key)
        assert_true(list.is_disabled(key), "%s is dimmed in the Layer menu" % id)
        assert_true(_docker.actions.menu.is_disabled(id), "and in the More menu")
        assert_eq(list.label_button(key).tooltip_text, SaLayerMenuRows.NOT_ON_A_GROUP, "and says why")
        assert_false(list.is_checked(key), "with no tick lit")
    var lock := SaMenu.key(SaLayerMenuRows.number_of(&"layer_lock"))
    assert_true(SaMenu.list_holding(menu.popup, lock).check_box(lock).disabled, "and a dimmed lock's box takes no press either")


func test_the_layer_menu_has_rename_and_the_kinds_the_arrow_adds() -> void:
    var layer := _layer_rows()
    assert_eq(_words_of(layer, SaLayerMenuRows.RENAME), "Rename...", "the Layer menu has Rename")
    var kinds: Array = []
    var first := -1
    var addable := SaLayerMenuRows.addable(_registries.layer_types).filter(
        func(descriptor: SaLayerTypeDescriptor) -> bool: return descriptor.id != SaLayerTypeDescriptor.PLAIN
    )
    for index in addable.size():
        if not SaGeneratedLayer.answers_height(addable[index]):
            kinds.append([addable[index].id, SaLayerMenuRows.kind_words(addable[index])])
            first = index if first < 0 else first
    kinds.append([SaGroundChoice.ROW, SaGroundChoice.WORDS])
    assert_true(kinds.size() >= 3, "the adjustment and the effect layer, and one Ground row: %s" % [kinds])
    # The kinds stand under a submenu of their own, so the menu fits a
    # screen, and that submenu's row follows New Layer at Double Resolution.
    var lists := _layer_lists()
    var own: Array = lists[0]
    var at := own.map(func(row: Array) -> StringName: return row[0]).find(&"layer_new_double")
    assert_eq(own[at + 1][1], "Other Layers", "the kinds' submenu after New Layer at Double Resolution")
    assert_true(lists.has(kinds), "each kind in that submenu, under its name: %s" % [lists])

    var before := SaLayerOps.new(_document()).layers().size()
    _layer_menu().on_id_pressed(SaLayerMenuRows.FIRST_KIND + first)
    assert_eq(SaLayerOps.new(_document()).layers().size(), before + 1, "a kind's row adds a layer")
    assert_eq(_document().active_layer.layer_type, kinds[0][0], "of that kind")


func test_the_arrow_has_no_group_row() -> void:
    _docker.actions.fill_add_type_menu()
    var arrow: SaChoicePopup = _docker.actions._add_type_menu
    assert_false(arrow.row_labels().has("Group"), "the arrow's rows are kinds: %s" % [arrow.row_labels()])
    var ids: Array[StringName] = []
    for descriptor: SaLayerTypeDescriptor in SaLayerMenuRows.addable(_registries.layer_types):
        if not SaGeneratedLayer.answers_height(descriptor):
            ids.append(descriptor.id)
    ids.append(SaGroundChoice.ROW)
    assert_eq(arrow.row_ids(), ids, "and every kind is there, the grounds one Ground row")


## The list's own words for a command row are what a docker in a suite reads,
## and its ticks are its own reading of the layer, so both are held against the
## commands they stand in for.
func test_the_lists_words_and_ticks_are_the_commands() -> void:
    var apps_own := [
        SaLayerMenuRows.KINDS,
        SaLayerMenuRows.GROUND,
        SaLayerMenuRows.DUPLICATE_TO,
        SaLayerMenuRows.RENAME,
        SaLayerMenuRows.ISOLATE,
        SaEffectsLut.COMMAND,
    ]
    for entry: Variant in SaLayerMenuRows.ROWS:
        if not entry is Array or entry[0] in apps_own:
            continue
        var descriptor := _registries.commands.get_descriptor(entry[0])
        assert_not_null(descriptor, "%s is a registered command" % entry[0])
        if descriptor == null:
            continue
        assert_eq(entry[4], descriptor.menu_label(), "%s's words are its command's" % entry[0])
        assert_eq(SaLayerMenuRows.TICKS.has(entry[0]), descriptor.has_tick(), "%s has a tick where its command does" % entry[0])
