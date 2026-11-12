## A right press under the Eraser lends Brush Presets as under the Brush, and
## the docker it lends shows a title and a way home.
##
## With the Brush a right press parked
## Brush Presets under the pointer with no way back but a second right press,
## and with the Eraser it opened a menu of the brush's options. The Eraser now
## opts in on its descriptor, and the lent docker's head shows its title and a
## close that sends it home rather than hiding it, while the second right press
## still does the same.
##
## The manager is built as the right press suite beside this one builds it, out of the
## tree over a store on a scratch file, with the Window menu's rows appended so
## the close is wired as in the app. The running app's half is the scenario
## `scenarios/a-right-press-under-the-eraser-*.json`.
extends "res://tests/test_framework.gd"

const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

const REQUIRES_GPU := true

static var scratch_layout_path: String = SaDataRoot.path("test_eraser_presets_layout.cfg")

const STORED_AT := Vector2i(700, 420)
const PRESSED_AT := Vector2i(160, 120)
const TEST_SIZE := Vector2i(200, 200)


func after_each() -> void:
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


## The two tools that share the presets both take the right press for them, and
## a tool that takes no presets leaves it to its menu.
func test_the_brush_and_the_eraser_opt_in_and_a_tool_with_no_presets_does_not() -> void:
    var registry := SaTestFixtures.make_tool_registry()
    var brush := registry.get_descriptor(&"brush")
    var eraser := registry.get_descriptor(&"eraser")
    assert_not_null(brush, "the base modules register the Brush")
    assert_not_null(eraser, "and the Eraser")
    if brush == null or eraser == null:
        return
    assert_true(brush.opens_docker_on_right_click, "the Brush lends a docker on a right press")
    assert_true(eraser.opens_docker_on_right_click, "and so does the Eraser")
    assert_eq(eraser.preset_engine, brush.preset_engine, "because the two take the same presets")

    var without: Array[String] = []
    for descriptor: SaToolDescriptor in registry.list_descriptors():
        if descriptor.preset_engine != &"":
            continue
        without.append(String(descriptor.id))
        assert_false(descriptor.opens_docker_on_right_click, "%s takes no presets and keeps its menu" % descriptor.id)
    assert_true(without.has("eyedropper"), "the Eyedropper is one such tool, read among %s" % [without])


## The lent docker's head carries the title and a close, and the close sends it
## home to its dock, shown as the press found it, rather than hiding it.
func test_the_lent_docker_shows_a_title_and_a_close_that_sends_it_home() -> void:
    var built := _build(true)
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var dockers: MainDockers = built["dockers"]
    var section := String(SaDockerIds.BRUSH_PRESETS)
    # The head switched off in the layout, which a lend shows all the same.
    docker.drag_handle.visible = false

    assert_true(docker.toggle_at(Vector2(PRESSED_AT), dockers), "the right press lends it")
    assert_true(dockers.layout_store.is_borrowed(section), "out on a borrow")
    assert_true(docker.lent, "and the docker knows it is out")
    var title := docker.find_child("TitleLabel", true, false) as Label
    assert_not_null(title, "the head has a title")
    if title == null:
        _tear_down(built)
        return
    assert_true(title.is_visible_in_tree(), "shown while it is lent")
    assert_eq(title.text, "Brush Presets", "naming the docker")
    var close := docker.hide_button
    assert_true(close.is_visible_in_tree(), "beside a close")
    assert_eq(close.tooltip_text, "Send this docker back where it was.", "which says it sends it home")

    close.pressed.emit()
    assert_false(dockers.layout_store.is_borrowed(section), "the close sends it home")
    assert_eq(docker.position, STORED_AT, "to the place the painter gave it")
    assert_true(docker.visible, "still open in its place, as the press found it")
    assert_false(docker.lent, "and no longer out")
    assert_eq(close.tooltip_text, "Hide this docker.", "so the close hides it again from here")

    assert_true(docker.toggle_at(Vector2(PRESSED_AT), dockers), "lent once more")
    assert_true(docker.toggle_at(Vector2(PRESSED_AT), dockers), "the second right press still sends it home")
    assert_false(dockers.layout_store.is_borrowed(section), "home")
    assert_true(docker.visible, "open where it was")
    _tear_down(built)


## A docker that was shut when the press lent it goes home shut on its close,
## which is the close it was.
func test_a_shut_docker_lent_and_closed_goes_home_shut() -> void:
    var built := _build(false)
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var dockers: MainDockers = built["dockers"]
    assert_true(docker.toggle_at(Vector2(PRESSED_AT), dockers), "the right press lends it")
    assert_true(docker.visible, "open beside the press")
    docker.hide_button.pressed.emit()
    assert_false(dockers.layout_store.is_borrowed(String(SaDockerIds.BRUSH_PRESETS)), "the close sends it home")
    assert_false(docker.visible, "shut, as the press found it")
    _tear_down(built)


## The right press suite's fixture, with the Window menu's rows appended, which is what
## wires a docker's close to the manager.
func _build(open: bool) -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, because the placement asks the parent for its window")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "PresetsLendTestHost"
    EventBus.add_child(host)

    var docker := DockerScript.new() as BrushPresetsDocker
    host.add_child(docker)
    docker.size = TEST_SIZE
    docker.position = STORED_AT
    docker.visible = open

    var registries := SaTestFixtures.make_menu_registries()
    registries.ui.register_docker(SaDockerIds.BRUSH_PRESETS, "Brush Presets", func() -> Window: return Window.new())
    registries.ui.set_docker_node(SaDockerIds.BRUSH_PRESETS, docker)
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var outside := Node.new()
    outside.add_child(MainDockers.new(registries.ui, store))
    store.save(true)
    assert_true(store.note_placement(docker), "the store holds where the painter left it")

    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    var dockers := outside.get_child(0) as MainDockers
    dockers.dockers_menu = bar.menus["Window"]
    dockers.append_menu_rows(bar.menus["Window"])
    return {
        "tree": tree, "host": host, "outside": outside, "bar": bar, "docker": docker, "dockers": dockers, "embedded": embedded
    }


## The manager first, because its summon watches the docker.
func _tear_down(built: Dictionary) -> void:
    (built["outside"] as Node).free()
    (built["host"] as Node).free()
    (built["bar"] as Node).free()
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])
