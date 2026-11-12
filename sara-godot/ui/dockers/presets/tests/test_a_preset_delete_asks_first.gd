## Delete asks before it deletes, and only the answer deletes.
##
## There is a Confirm dialog on the delete click for safety.
## `delete_preset` removes the file and no undo entry goes anywhere near a
## preset, so without the question the press would be the last chance to change
## your mind.
##
## Driven through the docker's own handler with a real bar and a real store, in
## the tree, because the question is a `Window` and the host it is added to is
## `get_tree().root`. What a painter sees is
## `scenarios/delete-asks-first.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_b6_delete_asks")


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)


func test_cancel_leaves_the_preset_where_it_was() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    assert_not_null(ToolOptionsPresets.in_tree(docker), "The docker found the bar")
    assert_eq(ToolOptionsPresets.in_tree(docker).selected_preset, "Doomed", "and the preset is loaded")
    docker._on_delete_pressed()
    var question := SaMessage.live_dialog(built["tree"])
    assert_not_null(question, "Pressing Delete puts a question up rather than deleting")
    if question != null:
        assert_eq(question.title, "Delete preset", "titled for what it is about to do")
        assert_true(question.text_label.text.contains("Doomed"), "and it names the preset: %s" % question.text_label.text)
        assert_eq(question.buttons.size(), 2, "Cancel and Delete")
        assert_eq(question.buttons[0].text, "Cancel", "Cancel first, so the safe answer is the default")
        assert_eq(question.buttons[1].text, "Delete", "and Delete second")
        assert_true(bar.preset_names().has("Doomed"), "and the preset is still there while the question is up")
        question.buttons[0].pressed.emit()

    assert_true(bar.preset_names().has("Doomed"), "Cancel leaves it exactly where it was")
    assert_eq(bar.selected_preset_name(), "Doomed", "and still loaded")
    _tear_down(built)


func test_delete_deletes() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    docker._on_delete_pressed()
    var question := SaMessage.live_dialog(built["tree"])
    assert_not_null(question, "The question is up again")
    if question != null:
        question.buttons[1].pressed.emit()

    assert_false(bar.preset_names().has("Doomed"), "Answering Delete is what deletes")
    assert_eq(bar.selected_preset_name(), "", "and nothing is loaded afterwards")
    _tear_down(built)


## With no bar to ask there is nothing loaded, so nothing is asked either: a
## question about a preset that does not exist is worse than no question.
func test_a_docker_with_nothing_loaded_asks_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var host := Node.new()
    host.name = "B6NoBarHost"
    var docker := DockerScript.new()
    host.add_child(docker)

    docker._on_delete_pressed()
    assert_null(SaMessage.live_dialog(tree), "No bar, no preset, no question")

    host.free()


## A docker, a bar with a store of its own, and one preset saved and loaded.
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, for the window the question opens in")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "B6DeleteTestHost"
    EventBus.add_child(host)

    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()
    bar.save_current_as_preset("Doomed")
    bar.load_preset("Doomed")

    var docker := DockerScript.new()
    host.add_child(docker)
    docker.show()
    docker.rebind()

    return {
        "tree": tree, "host": host, "bar": bar, "docker": docker, "surface": surface, "machine": machine, "embedded": embedded
    }


func _tear_down(built: Dictionary) -> void:
    var tree: SceneTree = built["tree"]
    # The question frees itself on the answer, and it does so deferred, so it is
    # still in the tree when the assertions above run and gone a frame later.
    var left := SaMessage.live_dialog(tree)
    if left != null:
        left.queue_free()
    (built["host"] as Node).free()
    Fixtures.teardown(built["surface"], built["machine"])
    tree.root.gui_embed_subwindows = bool(built["embedded"])
