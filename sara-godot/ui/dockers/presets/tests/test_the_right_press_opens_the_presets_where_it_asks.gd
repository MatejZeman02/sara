## The brush's right press lends the Brush Presets docker beside the pointer and
## the second sends it home, with the layout untouched.
##
## The docker stays where the painter put it. The first right
## press hid a docker the painter had placed and the second showed it at the
## pointer, both through the Dockers menu's command, so the place was written
## over and the shipped layout forked under a name the painter never chose.
## `BrushPresetsDocker.toggle_at` borrows it through the summon a chord makes
## instead, which writes nothing, and sends it back on the second press.
##
## The right press does not go through `reveal`, so no case here is about the
## order inside it. The button's half of `reveal` is kept.
##
## A `MainDockers` is built here over a store on a scratch file and left out of
## the tree, the shape the summon suite uses, because the docker finds the
## manager through the main scene and no suite has one. Out of the tree, the
## summon's frame loop and the store's settle loop never run, so the leave and
## the compositor are not what these cases read. The running app's half is
## `scenarios/a-right-press-opens-the-presets-at-the-pointer-and-leaves-the-docker-where-it-was.json`.
extends "res://tests/test_framework.gd"

const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const Placement = preload("res://ui/dockers/presets/brush_presets_placement.gd")

const REQUIRES_GPU := true

static var scratch_layout_path: String = SaDataRoot.path("test_n63_presets_layout.cfg")

## Where the painter left the docker, and where the press lands. Small enough,
## with the size below, that neither the gap nor the clamp under the bar moves
## anything: the claim is about the borrow and not about the arithmetic.
const STORED_AT := Vector2i(700, 420)
const PRESSED_AT := Vector2i(160, 120)
const TEST_SIZE := Vector2i(200, 200)


func after_each() -> void:
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


## The core case: a docker the painter placed and left open comes to the
## press, and goes back to the place on the second, still open.
func test_a_placed_docker_comes_to_the_press_and_goes_back_to_its_place() -> void:
    var built := _build(true)
    if built.is_empty():
        return
    _read_both_presses(built, true)
    _tear_down(built)


## A shut docker opens beside the press and is shut again by the second, with
## the place the layout holds for it untouched.
func test_a_shut_docker_opens_beside_the_press_and_goes_home_shut() -> void:
    var built := _build(false)
    if built.is_empty():
        return
    _read_both_presses(built, false)
    _tear_down(built)


## The two presses and what each leaves, for a docker that started *was_open*.
func _read_both_presses(built: Dictionary, was_open: bool) -> void:
    var docker: BrushPresetsDocker = built["docker"]
    var dockers: MainDockers = built["dockers"]
    var store := dockers.layout_store
    var section := String(SaDockerIds.BRUSH_PRESETS)
    var on_disk := FileAccess.get_file_as_bytes(scratch_layout_path)
    var name_before := store.current_preset()
    var gap := SaUI.to_physical(Placement.POINTER_GAP)

    assert_true(docker.toggle_at(Vector2(PRESSED_AT), dockers), "the first press answers")
    assert_true(store.is_borrowed(section), "and lends the docker rather than moving it in the layout")
    assert_true(docker.visible, "which is open")
    assert_eq(docker.position, PRESSED_AT + Vector2i(gap, gap), "beside the press, down and right of it by the gap")
    assert_false(Rect2i(docker.position, docker.size).has_point(PRESSED_AT), "so the press is still canvas for the second")
    assert_eq(store.value_for(section, "position", Vector2i()), STORED_AT, "the layout still holds the painter's place")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "and its file is byte for byte what it was")
    assert_eq(store.current_preset(), name_before, "under the name it had")

    assert_true(docker.toggle_at(Vector2(PRESSED_AT), dockers), "the second press answers")
    assert_false(store.is_borrowed(section), "and sends it home")
    assert_eq(docker.position, STORED_AT, "to the place the painter put it")
    assert_eq(docker.visible, was_open, "open or shut as the first press found it")
    assert_eq(store.value_for(section, "position", Vector2i()), STORED_AT, "the layout's place untouched")
    assert_eq(FileAccess.get_file_as_bytes(scratch_layout_path), on_disk, "its file too")
    assert_eq(store.current_preset(), name_before, "and its name, which forked under the old press")


## The button passes no place at all, because a button has none to pass, and an
## open docker is left where the painter put it. `reveal` is the button's still.
func test_reveal_moves_nothing_when_it_is_open_or_when_it_is_asked_nothing() -> void:
    var built := _build(false)
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]

    assert_true(docker.reveal(), "the button opens it")
    assert_eq(docker.position, STORED_AT, "where the painter left it")
    assert_true(docker.reveal(Vector2(PRESSED_AT)), "a second reveal answers true")
    assert_eq(docker.position, STORED_AT, "and moves nothing, because the painter had placed it")

    _tear_down(built)


## A docker at the painter's place, open when *open*, registered with a docker
## manager over a store whose file was written from it, which is the layout a
## painter's session left behind. The docker is under an autoload because the
## runner calls this from its own `_ready` and a parent mid-`_ready` rejects
## `add_child`. The manager is not.
func _build(open: bool) -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, because the placement asks the parent for its window")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "N63PresetsBorrowTestHost"
    EventBus.add_child(host)

    var docker := DockerScript.new() as BrushPresetsDocker
    host.add_child(docker)
    docker.size = TEST_SIZE
    docker.position = STORED_AT
    # A `Window` is visible when it is built.
    docker.visible = open

    var registries := SaRegistries.new()
    registries.ui.register_docker(SaDockerIds.BRUSH_PRESETS, "Brush Presets", func() -> Window: return Window.new())
    registries.ui.set_docker_node(SaDockerIds.BRUSH_PRESETS, docker)
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var outside := Node.new()
    outside.add_child(MainDockers.new(registries.ui, store))
    store.save(true)
    assert_true(store.note_placement(docker), "the store holds where the painter left it")
    assert_eq(store.value_for(String(SaDockerIds.BRUSH_PRESETS), "position", Vector2i()), STORED_AT, "which is here")

    var dockers := outside.get_child(0) as MainDockers
    return {"tree": tree, "host": host, "outside": outside, "docker": docker, "dockers": dockers, "embedded": embedded}


## The manager first, because its summon watches the docker.
func _tear_down(built: Dictionary) -> void:
    (built["outside"] as Node).free()
    (built["host"] as Node).free()
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])
