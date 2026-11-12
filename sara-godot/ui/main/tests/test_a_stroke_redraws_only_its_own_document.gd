## A stroke redraws only its own document. Two easels, the
## way two tabs will hold them, each under a canvas item of its own as the
## canvas holds it in the app, and the status line and the Minimap on the
## first, which is the one in front.
##
## Under `ui` because the status line and the Minimap are two of its subjects,
## and the easel is a `core` class a suite here may name.
extends "res://tests/test_framework.gd"

## Chunks and outputs are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _host: Node = null
var _first: SaSurface = null
var _second: SaSurface = null
var _first_holder: Control = null
var _second_holder: Control = null
var _embedded: bool = false


func before_each() -> void:
    _host = Node.new()
    _host.name = "U278Host"
    EventBus.add_child(_host)
    _first = Fixtures.make_surface(Vector2i(512, 256))
    _first.id = &"first"
    _second = Fixtures.make_surface(Vector2i(256, 512))
    _second.id = &"second"
    _first_holder = _hold(_first)
    _second_holder = _hold(_second)
    _embedded = (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows


func after_each() -> void:
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    Fixtures.teardown(_first)
    Fixtures.teardown(_second)
    _host.free()
    _host = null
    _first = null
    _second = null
    _first_holder = null
    _second_holder = null


## *surface*'s easel under a Control of its own, the place `SaCanvas` gives it.
func _hold(surface: SaSurface) -> Control:
    var holder := Control.new()
    holder.name = "Holder%s" % String(surface.id).capitalize()
    _host.add_child(holder)
    holder.add_child(surface.easel)
    return holder


func _frames(count: int) -> void:
    for _frame: int in count:
        await (Engine.get_main_loop() as SceneTree).process_frame


## *space* at the depth *document* already has, so its output stays the format
## the easel allocated.
func _space_for(document: SaDocument, space: SaColorSpace) -> SaColorSpace:
    return space.with_depth(document.color_space.depth)


func test_a_changed_chunk_in_the_first_composites_the_first_alone() -> void:
    await _frames(3)
    var first_before := _first.easel.composite_count
    var second_before := _second.easel.composite_count

    _first.get_document().invalidate_chunks([Vector2i.ZERO])
    await _frames(2)

    assert_eq(_first.easel.composite_count, first_before + 1, "The first easel composites its changed chunk once")
    assert_eq(_second.easel.composite_count, second_before, "and the second makes no pass at all")

    # The request a fold or a load sends when it marks no chunk: it names its
    # document, so only that document's easel is asked.
    _second.get_document().composite_requested.emit()
    assert_true(_second.easel.needs_composite, "A document's own request reaches its easel")
    assert_false(_first.easel.needs_composite, "and not the other one")


func test_a_hidden_easel_composites_once_when_it_is_shown() -> void:
    await _frames(3)
    _second_holder.hide()
    var before := _second.easel.composite_count
    assert_false(_second.easel.is_shown(), "An easel under a hidden canvas item is not shown")
    assert_true(_first.easel.is_shown(), "and one under a shown one is")

    _second.get_document().invalidate_chunks([Vector2i.ZERO])
    await _frames(3)
    assert_eq(_second.easel.composite_count, before, "A hidden easel with a changed chunk composites nothing")

    _second_holder.show()
    await _frames(1)
    assert_eq(_second.easel.composite_count, before + 1, "and composites once on the frame it is shown")
    await _frames(2)
    assert_eq(_second.easel.composite_count, before + 1, "and not again while nothing changes")


func test_a_space_change_behind_the_first_leaves_the_status_line_on_the_first() -> void:
    var line := SaStatusLine.new(func() -> SaSurface: return _first)
    _host.add_child(line)
    line.refresh()
    var first_space := SaStatusLine.space_text(_first.get_document().color_space)
    assert_eq(line.space_label.text, first_space, "The line names the first document's space")

    var second_document := _second.get_document()
    second_document.color_space = _space_for(second_document, SaColorSpace.linear_srgb())
    assert_false(line._queued, "The second document's change asks the line for no reading")
    line.refresh()
    assert_eq(line.space_label.text, first_space, "and the line keeps the first's space")

    var first_document := _first.get_document()
    first_document.color_space = _space_for(first_document, SaColorSpace.linear_srgb())
    assert_true(line._queued, "The first document's own change asks for one")
    line.refresh()
    assert_eq(line.space_label.text, SaStatusLine.space_text(first_document.color_space), "and the line reads its new space")


func test_a_space_change_behind_the_first_leaves_the_minimap_on_the_first() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = true
    var canvas := SaCanvas.new()
    canvas.easel = _first.easel
    canvas.material = ShaderMaterial.new()
    var docker := MinimapDocker.new()
    docker.view_transforms = registries.view_transforms
    docker.target_canvas = canvas
    _host.add_child(docker)
    docker.toggle_proof()
    # The copy of the canvas material is made, so the flag reads clean.
    docker._sync_material()
    assert_false(docker._material_dirty, "The Minimap's copy of the first canvas's material is up to date")

    var second_document := _second.get_document()
    second_document.color_space = _space_for(second_document, SaColorSpace.linear_srgb())
    assert_false(docker._material_dirty, "The second document's change leaves the copy as it is")

    var first_document := _first.get_document()
    first_document.color_space = _space_for(first_document, SaColorSpace.linear_srgb())
    assert_true(docker._material_dirty, "and the first document's own change asks for a new one")
    canvas.easel = null
    canvas.free()
