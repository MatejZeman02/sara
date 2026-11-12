## Every menu row that opens another list ends in the arrow, "›", in the column
## a command row shows its chord, and no other row does.
##
## The Filter menu's sections and the Modules menu's Active Modules showed it,
## while the Layer menu's Ground, Duplicate To and its Adjustment and Effect
## rows, which open a list as surely, looked like commands. The walk covers
## every menu of the bar and the Layers docker's three lists, the More button's,
## the one a right click opens and the arrow's, so a menu added later is held
## to the same rule without a line here.
##
## A row opens another list when the popup holds it as a branch, or when it
## adds a kind that holds filters, whose row opens the list of them in
## `SaLayerKindBrowser` before there is a layer.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the Layer rows are drawn for.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The mark itself rather than the constant, so the suite holds the glyph a
## painter reads and not whatever the constant was last set to.
const ARROW := "›"


## A filter of the suite's own, so the Filter menu has a section row to read
## without the base module loaded.
class Smear:
    extends SaFilter

    func title() -> String:
        return "Smear"

    func family() -> StringName:
        return &"blur"

    func run(_ctx: SaFilterContext) -> void:
        pass


var _bar: TopMenuBar = null
var _docker: LayersDocker = null
var _registries: SaRegistries = null


func before_each() -> void:
    var note_mode := SaNoteMode.new()
    _registries = Fixtures.make_menu_registries(note_mode)
    var alpha := _registries.context.for_module(&"alpha")
    alpha.register_filter_section(&"blur", "Blur", 400)
    alpha.register_filter(Smear.new())
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
    _bar.add_child(note_mode)
    _bar.bind_commands(_registries.commands)
    var layer_menu := _bar.menu("Layer") as SaLayerMenu
    layer_menu.document = _docker.target_canvas.document
    layer_menu.layer_types = _registries.layer_types
    layer_menu.populate()
    (_bar.menu("Filter") as SaFilterMenu).filters = _registries.filters
    _bar.menu("Filter").populate()


func after_each() -> void:
    _bar.free()
    _docker.target_canvas.free()
    _registries = null


## Whether the kind *id* holds filters, an adjustment or an effect layer.
func _holds_filters(id: StringName) -> bool:
    var descriptor := _registries.layer_types.get_descriptor(id) if id != &"" else null
    return descriptor != null and not descriptor.input.is_empty()


## Every row of *popup* that breaks the rule, as "menu: row (hint)", where
## *kind_of* names the kind a row adds, or `&""` for a row that adds none.
func _broken(menu_name: String, popup: SaChoicePopup, kind_of: Callable) -> Array[String]:
    var out: Array[String] = []
    for list: SaChoicePopup in SaMenu.lists_of(popup):
        for id: StringName in list.row_ids():
            var hint := list.row_of(id).hint_text()
            var opens := list.is_branch(id) or _holds_filters(kind_of.call(id))
            if hint.ends_with(ARROW) != opens:
                out.append("%s: %s (%s)" % [menu_name, list.label_button(id).text, hint])
    return out


## The labels of the rows that end in the arrow on *popup* and on the
## submenus it holds, where a long menu groups its rows.
func _marked(popup: SaChoicePopup) -> Array[String]:
    var out: Array[String] = []
    for list: SaChoicePopup in SaMenu.lists_of(popup):
        for id: StringName in list.row_ids():
            if list.row_of(id).hint_text().ends_with(ARROW):
                out.append(list.label_button(id).text)
    return out


## The kind the Layer menu's row *id* adds, through its number.
func _layer_menu_kind(id: StringName) -> StringName:
    var rows := SaLayerMenuRows.new(_docker.target_canvas.document, _registries.commands, _registries.layer_types)
    return rows.id_at(SaMenu.id_of(id))


func test_every_menu_of_the_bar_marks_the_rows_that_open_a_list_and_only_those() -> void:
    var broken: Array[String] = []
    for menu_name: String in _bar.menus:
        var kind_of := _layer_menu_kind if menu_name == "Layer" else func(_id: StringName) -> StringName: return &""
        broken.append_array(_broken(menu_name, _bar.menus[menu_name], kind_of))
    assert_eq(broken, [] as Array[String], "every row that opens a list ends in the arrow, and no other row")
    var layer := _marked(_bar.menus["Layer"])
    for words: String in ["Ground", "Duplicate To", "Adjustment Layer", "Effect Layer"]:
        assert_true(layer.has(words), "the Layer menu's %s opens a list and says so: %s" % [words, layer])
    assert_true(_marked(_bar.menus["Modules"]).has("Active Modules"), "and Active Modules still does")
    assert_false(_marked(_bar.menus["Filter"]).is_empty(), "and so do the Filter menu's sections")


func test_the_layers_docker_s_three_lists_mark_the_rows_that_open_a_list_and_only_those() -> void:
    var actions := _docker.actions
    var own := func(id: StringName) -> StringName: return id
    actions.sync_from_active_layer()
    var broken := _broken("More", actions.menu, own)
    actions.open_menu_at(Vector2.ZERO)
    var pointer := _marked(actions.menu)
    broken.append_array(_broken("Pointer", actions.menu, own))
    actions.pointer.forget()
    actions.fill_add_type_menu()
    broken.append_array(_broken("Arrow", actions._add_type_menu, own))
    assert_eq(broken, [] as Array[String], "every row that opens a list ends in the arrow, and no other row")
    for words: String in ["Ground", "Duplicate To", "Adjustment Layer", "Effect Layer", "Colour"]:
        assert_true(pointer.has(words), "the right click's %s opens a list and says so: %s" % [words, pointer])
    var arrow := _marked(actions._add_type_menu)
    for words: String in ["Ground", "Adjustment Layer", "Effect Layer"]:
        assert_true(arrow.has(words), "the arrow's %s opens a list and says so: %s" % [words, arrow])
