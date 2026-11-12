## An edit the painter makes to the dockers reaches the file of the layout in
## use, the painter's own or the fork of a shipped one, so going to another
## layout and back finds the dockers as the painter last left them.
##
## The fork is written on every edit and not on the first only, and a painter's
## own layout after its save as well, or the arrangement made since is gone on
## the way back while the corner notice says the layout was kept. A load, a resize
## of the host and a scale change still write nothing into a named layout's
## file, since none of them is somebody arranging the dockers.
##
## Built on `MainDockers` and its Window menu rows, which connect the doors
## a real window has: the drag handle's signal, the host's resize and the scale.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1280, 800)

## Every docker the shipped layouts place, at the floors the real ones keep.
const FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "BrushPresetsDocker": Vector2i(295, 212),
    "ToolOptionsDocker": Vector2i(206, 255),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
    "ReferenceDocker": Vector2i(184, 213),
}

const OWN := "named layout edits"
const FORK := "useful (custom)"

static var scratch_live: String = SaDataRoot.path("test_named_layout_edits.cfg")

var _root: Node = null
var _viewport: SubViewport = null
var _dockers: MainDockers = null
var _menu: SaChoicePopup = null
var _saved_scale: float = 1.0
## The element state and scale a shipped layout's load writes, put back after
## each case so the suites after this one read the profile they expect.
var _saved_state := ConfigFile.new()


func before_each() -> void:
    _saved_scale = SaSettings.ui_scale
    SaFocusMode.active = false
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)

    _root = Node.new()
    _root.name = "NamedLayoutEditsHost"
    EventBus.add_child(_root)
    _viewport = SubViewport.new()
    _viewport.size = HOST
    _viewport.gui_embed_subwindows = true
    _root.add_child(_viewport)
    var parent := Control.new()
    parent.set_anchors_preset(Control.PRESET_FULL_RECT)
    _viewport.add_child(parent)

    var registries := SaRegistries.new()
    for section: String in FLOORS:
        var probe := Window.new()
        probe.name = section
        probe.min_size = FLOORS[section]
        probe.size = FLOORS[section]
        parent.add_child(probe)
        registries.ui.register_docker(StringName(section), section, func() -> Window: return Window.new(), &"docker_stub")
        registries.ui.set_docker_node(StringName(section), probe)
    var store := DockerLayoutStore.new()
    store.path = scratch_live
    _saved_state = ConfigFile.new()
    store.presets().capture(_saved_state)
    # The layouts folder beside the scratch file is every suite's.
    store.delete_preset(OWN)
    store.delete_preset(FORK)
    store.delete_preset("default (custom)")
    _dockers = MainDockers.new(registries.ui, store)
    _viewport.add_child(_dockers)
    _menu = SaChoicePopup.new()
    _dockers.append_menu_rows(_menu)
    _dockers.load_docker_layout()


func after_each() -> void:
    if _dockers != null:
        _dockers.layout_store.presets().apply(_saved_state)
        for preset_name: String in [OWN, FORK, "default (custom)"]:
            _dockers.layout_store.delete_preset(preset_name)
    if _root != null:
        _root.free()
        _root = null
        _dockers = null
    if _menu != null:
        _menu.free()
        _menu = null
    SaFocusMode.active = false
    SaSettings.ui_scale = _saved_scale
    if FileAccess.file_exists(scratch_live):
        DirAccess.remove_absolute(scratch_live)


func _colour() -> Window:
    return _dockers.registered_docker_node(&"ColorDocker")


func _rect() -> Rect2i:
    return Rect2i(_colour().position, _colour().size)


## What the drag handle and the resizer do: the window moved and sized, and
## their one signal emitted.
func _painter_edit(rect: Rect2i) -> void:
    _colour().position = rect.position
    _colour().size = rect.size
    EventBus.docker_layout_changed.emit()


func _file_of(preset_name: String) -> String:
    return FileAccess.get_file_as_string(_dockers.layout_store.presets().read_path(preset_name))


func _stored_rect(preset_name: String) -> Rect2i:
    var cfg := ConfigFile.new()
    cfg.load(_dockers.layout_store.presets().read_path(preset_name))
    var section := DockerLayoutStore.section_for({"id": "ColorDocker", "name": "ColorDocker"})
    return Rect2i(cfg.get_value(section, "position", Vector2i(-1, -1)), cfg.get_value(section, "size", Vector2i(-1, -1)))


func test_an_edit_under_the_painters_own_layout_comes_back_with_it() -> void:
    assert_true(_dockers.layout_store.save_preset(OWN), "The painter saves a layout of their own")
    var saved := _rect()
    var edited := Rect2i(Vector2i(420, 230), Vector2i(300, 260))
    assert_true(saved != edited, "and the edit is a change: %s" % saved)

    _painter_edit(edited)
    assert_eq(_dockers.layout_store.current_preset(), OWN, "An edit stays in the painter's layout")
    assert_eq(_stored_rect(OWN), edited, "and is written into its file")

    assert_true(_dockers.layout_store.load_preset("default"), "Default loads")
    assert_true(_rect() != edited, "and puts the docker elsewhere")
    assert_true(_dockers.layout_store.load_preset(OWN), "The painter's layout loads again")
    assert_eq(_rect(), edited, "with the docker at the edited size and place")


func test_the_second_edit_under_a_shipped_layout_comes_back_with_its_fork() -> void:
    assert_true(_dockers.layout_store.load_preset("useful"), "Useful loads")
    var as_it_ships := _rect()
    var first := Rect2i(Vector2i(400, 200), Vector2i(260, 230))
    var second := Rect2i(Vector2i(520, 280), Vector2i(320, 270))
    assert_true(as_it_ships != first, "and the first edit is a change: %s" % as_it_ships)

    _painter_edit(first)
    assert_eq(_dockers.layout_store.current_preset(), FORK, "The first edit forks Useful")
    _painter_edit(second)
    assert_eq(_dockers.layout_store.current_preset(), FORK, "and the second stays in the fork")
    assert_eq(_stored_rect(FORK), second, "and is written into its file")

    assert_true(_dockers.layout_store.load_preset("minimalistic"), "Another shipped layout loads")
    assert_true(_dockers.layout_store.load_preset(FORK), "and the fork again")
    assert_eq(_rect(), second, "with the docker as the second edit left it")

    assert_true(_dockers.layout_store.load_preset("useful"), "Useful loads again")
    assert_eq(_rect(), as_it_ships, "with the docker as it ships")


func test_a_load_a_resize_and_a_scale_change_write_nothing_into_the_layout_in_use() -> void:
    _painter_edit(Rect2i(Vector2i(420, 230), Vector2i(300, 260)))
    assert_true(_dockers.layout_store.save_preset(OWN), "The painter saves a layout of their own")
    var written := _file_of(OWN)
    assert_false(written.is_empty(), "which is a file")

    assert_true(_dockers.layout_store.load_preset(OWN), "A load of it")
    assert_eq(_dockers.layout_store.current_preset(), OWN, "keeps it in use")
    assert_eq(_file_of(OWN), written, "and writes nothing into its file")

    _viewport.size = Vector2i(900, 560)
    _viewport.size = HOST
    assert_eq(_file_of(OWN), written, "A resize of the host and back writes nothing into it")

    _viewport.size_2d_override = Vector2i(Vector2(HOST) / 1.5)
    SaSettings.ui_scale = 1.5
    _viewport.size_2d_override = Vector2i()
    SaSettings.ui_scale = 1.0
    assert_eq(_file_of(OWN), written, "and nor does a scale change and back")
    assert_eq(_dockers.layout_store.current_preset(), OWN, "with the layout still in use")
