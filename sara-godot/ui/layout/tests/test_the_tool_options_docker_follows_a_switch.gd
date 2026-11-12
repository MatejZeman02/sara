## The tool options docker follows a tool switch without the layout file.
##
## A switch to another tool files the window's size under the tool it was
## showing and reads the size of the tool it moves to, without opening and
## parsing the layout file for each, writing it back only if something moved,
## or finding the store with a search of the whole tree every time. The store keeps the variant sizes it read,
## writes one only when it
## moved, and the docker holds the store it found.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StoreScript := preload("res://ui/layout/docker_layout_store.gd")

## The docker builds its rows against a tool machine, which needs a
## RenderingDevice.
const REQUIRES_GPU := true

static var scratch_layout: String = SaDataRoot.path("test_c5_layout.cfg")
const SECTION: String = "ToolOptionsDocker"
const OPENED_AT: Vector2i = Vector2i(320, 420)

var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _store: DockerLayoutStore = null
var _docker: ToolOptionsDocker = null


## A window that answers `layout_variant` the way the docker does, for the
## store's half on its own.
class VariantWindow:
    extends Window

    var variant: String = ""

    func layout_variant() -> String:
        return variant


func before_each() -> void:
    DirAccess.remove_absolute(scratch_layout)


func after_each() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    if _surface != null or _machine != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _store = null
    _docker = null
    DirAccess.remove_absolute(scratch_layout)


## Twenty switches between the brush and the eraser in a profile that has
## sized both open the layout file once, for the first, and write it never.
func test_twenty_switches_in_a_sized_profile_read_the_file_once() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, SaDockerVariantSizes.VARIANT_PREFIX + "brush", OPENED_AT)
    cfg.set_value(SECTION, SaDockerVariantSizes.VARIANT_PREFIX + "eraser", OPENED_AT)
    assert_eq(cfg.save(scratch_layout), OK, "A profile that has sized both tools")
    _build()
    var at := _docker.size
    for index in 20:
        _machine.set_active_tool(&"eraser" if index % 2 == 0 else &"brush")
    assert_eq(_docker.shown_tool_id(), &"brush", "The docker ends on the brush")
    assert_eq(_store._variants.loads, 1, "Twenty switches open the layout file once")
    assert_eq(_store._variants.saves, 0, "and write it never, since no size moved")
    assert_eq(_docker.size, at, "and the docker is the size it was")
    assert_eq(_docker._store, _store, "The docker holds the store it found")


## In a fresh profile each tool is filed once, the first time the docker leaves
## it, and after that a switch touches the file no more.
func test_a_fresh_profile_files_each_tool_once() -> void:
    _build()
    _machine.set_active_tool(&"eraser")
    _machine.set_active_tool(&"brush")
    _machine.set_active_tool(&"eraser")
    var loads := _store._variants.loads
    var saves := _store._variants.saves
    assert_eq(saves, 2, "The brush and the eraser are filed once each")
    for index in 17:
        _machine.set_active_tool(&"brush" if index % 2 == 0 else &"eraser")
    assert_eq(_store._variants.loads, loads, "Seventeen switches after them open the file no more")
    assert_eq(_store._variants.saves, saves, "and write it no more")


## A size dragged under one tool is that tool's when it is chosen again, and
## after a restart, which is a second store reading the same file.
func test_a_dragged_size_comes_back_with_its_tool_and_after_a_restart() -> void:
    _build()
    _machine.set_active_tool(&"eraser")
    var brush_size := _docker.size
    var dragged := brush_size + Vector2i(40, 120)
    _docker.size = dragged
    # The handler the drag handle's `docker_layout_changed` reaches, called
    # rather than emitted, because the signal also sets a static on every
    # docker window that says a painter sized one, and a suite after this one
    # would open its dockers as if a painter had.
    _docker._on_painter_changed_the_layout()
    var dragged_filed := _docker.size
    _machine.set_active_tool(&"brush")
    assert_eq(_docker.size, brush_size, "The brush has its own size back")
    _machine.set_active_tool(&"eraser")
    assert_eq(_docker.size, dragged_filed, "and the eraser has the size dragged under it")

    var reader: DockerLayoutStore = StoreScript.new()
    reader.path = scratch_layout
    assert_eq(reader.variant_size(_docker, SECTION, "eraser"), dragged_filed, "A restart reads the eraser's size")
    assert_eq(reader.variant_size(_docker, SECTION, "brush"), brush_size, "and the brush's")
    reader.free()


## The store is held from the first search that finds it and forgotten when it
## leaves the tree, and found again once it is back.
func test_the_store_is_held_and_forgotten_when_it_leaves() -> void:
    _build()
    _machine.set_active_tool(&"eraser")
    assert_eq(_docker._store, _store, "The first switch finds the store and holds it")
    _host.remove_child(_store)
    assert_null(_docker._store, "The store left the tree, and the docker let go of it")
    _host.add_child(_store)
    _machine.set_active_tool(&"brush")
    assert_eq(_docker._store, _store, "The next switch finds it again")
    _store.free()


## A size the scale does not divide back to the stored number is still the
## stored size. At 1.25 a stored 397 opens at 496, which divides to 396, and
## writing that lost a pixel on every switch.
func test_a_restored_size_at_a_fractional_scale_is_not_written_back() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, SaDockerVariantSizes.VARIANT_PREFIX + "brush", Vector2i(301, 397))
    assert_eq(cfg.save(scratch_layout), OK, "A stored size that 1.25 does not divide back")
    var store: DockerLayoutStore = StoreScript.new()
    store.path = scratch_layout
    var window := VariantWindow.new()
    window.min_size = Vector2i(160, 120)
    window.set_meta(SaUI.EXTRA_SCALE_META, 1.25)
    window.size = store.variant_size(window, SECTION, "brush")
    store.save_variant_size(window, SECTION, "brush")
    assert_eq(store._variants.saves, 0, "The size a restore gave is not written back")
    var back := ConfigFile.new()
    back.load(scratch_layout)
    assert_eq(back.get_value(SECTION, SaDockerVariantSizes.VARIANT_PREFIX + "brush"), Vector2i(301, 397), "The file says 397")
    window.free()
    store.free()


## A store under Main's name and a tool options docker over a bound machine,
## both in the tree, with the brush shown.
func _build() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _store = StoreScript.new()
    _store.name = "DockerLayoutStore"
    _store.path = scratch_layout
    _host.add_child(_store)
    _docker = ToolOptionsDocker.new()
    _docker.name = SECTION
    _docker.target_tool_machine = _machine
    _host.add_child(_docker)
    _docker.size = OPENED_AT
    _machine.set_active_tool(&"brush")
    _docker.follow_tool_size()
