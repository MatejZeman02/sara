## A right click on a layer's row opens the whole Layer menu,
## and a layer with no mask shows only the mask rows that add one.
##
## The Photoshop hour found the right click's menu without Duplicate, Delete or
## Merge Down, because it was the More list, which leaves out what the docker's
## buttons do, and found six greyed mask rows on a layer with no mask. What this
## suite holds is that the menu at the pointer reads the Layer menu's rows in
## its order and words, that both docker menus draw the five rows that act on a
## mask only while there is one, and that the More list is what it was.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the menus are drawn for.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The two rows that add a mask.
const ADDS: Array[StringName] = [SaMaskOps.ADD, SaMaskOps.ADD_FROM_SELECTION]

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
    _docker.actions.op_buttons.fit(100000.0)
    # A second layer, so Merge Down has one below it to merge into.
    SaLayerOps.new(_document()).add(SaLayerTypeDescriptor.PLAIN, _registries.layer_types)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    var menu := _bar.menu("Layer") as SaLayerMenu
    menu.document = _document()
    menu.layer_types = _registries.layer_types


func after_each() -> void:
    _bar.free()
    _docker.target_canvas.free()
    _registries = null


func _document() -> SaDocument:
    return _docker.target_canvas.document


## The popup's rows as `[id, words]`, in order, the docker's own Colour and
## conversion rows left out, since the Layer menu has none of them.
func _drawn() -> Array:
    var menu := _docker.actions.menu
    var out := []
    for id: StringName in menu.row_ids():
        if not id in [SaLayerActions.COLOUR, SaLayerActions.LAYER_TO_FILTER, SaLayerActions.EFFECT_INPUT]:
            out.append([id, menu.label_button(id).text])
    return out


## The right click's rows, built as a press on a row builds them. The suite's
## docker is in no tree, so the popup is filled and not shown.
func _pointer_rows() -> Array:
    _docker.actions.open_menu_at(Vector2(40, 40))
    return _drawn()


func _more_rows() -> Array:
    _docker.actions.pointer.forget()
    _docker.actions.sync_from_active_layer()
    return _drawn()


## The menu bar's Layer menu rows as `[id, words]`, in order, one array for
## the menu's own list and one for each of its submenus.
func _layer_lists() -> Array:
    var menu := _bar.menu("Layer") as SaLayerMenu
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


func _ids(rows: Array) -> Array:
    return rows.map(func(row: Array) -> StringName: return row[0])


func _words(rows: Array, id: StringName) -> String:
    for row: Array in rows:
        if row[0] == id:
            return row[1]
    return ""


func test_the_right_click_on_a_layer_with_no_mask_reads_the_rows_that_act() -> void:
    var rows := _pointer_rows()
    var wanted := {
        &"layer_duplicate": "Duplicate Layer",
        &"layer_delete": "Delete Layer",
        &"layer_merge_down": "Merge Down",
        &"layer_clear": "Clear Layer",
        SaMaskOps.ADD: "Add Mask",
        SaMaskOps.ADD_FROM_SELECTION: "Add Mask from Selection",
    }
    for id: StringName in wanted:
        assert_eq(_words(rows, id), wanted[id], "the right click reads %s: %s" % [wanted[id], [_ids(rows)]])
    for id: StringName in SaLayerMenuRows.ON_A_MASK:
        assert_false(_ids(rows).has(id), "and not %s, on a layer with no mask" % id)
    assert_false(_docker.actions.menu.is_disabled(SaMaskOps.ADD), "Add Mask is live")
    assert_false(_docker.actions.menu.is_disabled(&"layer_merge_down"), "and Merge Down, with a layer below")


func test_a_layer_with_a_mask_reads_the_five_live_and_the_adds_dimmed() -> void:
    SaMaskOps.new(_document()).add(_document().active_layer)
    var rows := _pointer_rows()
    for id: StringName in SaLayerMenuRows.ON_A_MASK:
        assert_true(_ids(rows).has(id), "%s is drawn on a layer with a mask" % id)
        assert_false(_docker.actions.menu.is_disabled(id), "and live")
    for id: StringName in ADDS:
        assert_true(_ids(rows).has(id), "%s is drawn" % id)
        assert_true(_docker.actions.menu.is_disabled(id), "and dimmed, there being a mask")


## Today's More list, with the four buttons standing and a mask to act on: the
## rows the More list draws, less the four, the Colour row after Rename left
## out as `_drawn` leaves it.
func test_the_more_menu_with_the_four_buttons_standing_reads_as_it_did() -> void:
    SaMaskOps.new(_document()).add(_document().active_layer)
    var standing: Array[StringName] = []
    for entry: Array in SaLayerOpButtons.ENTRIES:
        assert_not_null(_docker.actions.op_buttons.on_row(entry[0]), "%s stands on the row" % entry[0])
        standing.append(entry[0])
    var expected := []
    for entry: Variant in SaLayerMenuRows.ROWS:
        if not entry is Array or not entry[3] or standing.has(entry[0]):
            continue
        # A command the suite's registry does not hold is drawn by no menu.
        if _registries.commands.has(entry[0]) or entry[0] in [SaLayerMenuRows.RENAME, SaLayerMenuRows.ISOLATE]:
            expected.append(entry[0])
    assert_eq(_ids(_more_rows()), expected, "the More list is the rows the menu draws")
    var bare := SaLayerOps.new(_document()).add(SaLayerTypeDescriptor.PLAIN, _registries.layer_types)
    assert_eq(_document().active_layer, bare, "a new layer with no mask is active")
    for id: StringName in SaLayerMenuRows.ON_A_MASK:
        assert_false(_ids(_more_rows()).has(id), "and on it the More list leaves out %s too" % id)


func test_the_right_click_reads_the_layer_menus_rows_in_its_order_and_words() -> void:
    var pointer := _pointer_rows()
    var layer := _layer_rows()
    assert_true(pointer.all(func(row: Array) -> bool: return layer.has(row)), "the right click reads the Layer menu's words")
    for rows: Array in _layer_lists():
        var shared := rows.filter(func(row: Array) -> bool: return _ids(pointer).has(row[0]))
        var on_it := pointer.filter(func(row: Array) -> bool: return _ids(shared).has(row[0]))
        assert_eq(on_it, shared, "and the order of the list or submenu each row is on")
    var missing := _ids(layer).filter(func(id: StringName) -> bool: return not _ids(pointer).has(id))
    var flips_and_after := missing.filter(func(id: StringName) -> bool: return SaLayerMenuRows.number_of(id) < 0)
    var rest := missing.filter(func(id: StringName) -> bool: return SaLayerMenuRows.number_of(id) >= 0)
    assert_eq(str(rest), str(SaLayerMenuRows.ON_A_MASK), "nothing of the list is left out but the five a mask needs")
    assert_eq(flips_and_after.size(), missing.size() - rest.size(), "beside the menu bar's own rows after it")


func test_the_right_clicks_delete_and_duplicate_act() -> void:
    _pointer_rows()
    var before := SaLayerOps.new(_document()).layers().size()
    assert_true(_docker.actions.menu.press_row(&"layer_duplicate"), "Duplicate Layer takes its press")
    assert_eq(SaLayerOps.new(_document()).layers().size(), before + 1, "and duplicates the layer")
    _pointer_rows()
    assert_true(_docker.actions.menu.press_row(&"layer_delete"), "Delete Layer takes its press")
    assert_eq(SaLayerOps.new(_document()).layers().size(), before, "and deletes it")
