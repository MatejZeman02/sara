## The door's two pixel writers, `write_pixels` and `kernel`,
## refuse a layer a painter could not paint, as the path step does.
##
## A locked layer, a group and a generated layer are each refused by both steps
## with the reason, and the refusal adds no chunk, no layer and no history step.
## The kernel also refuses a written layer whose format is not the read layer's,
## because its result is made in the read layer's format and copied texel for
## texel. A plain layer is written by both, so each refusal is the kind's.
##
## The step table hands `write_pixels` and `kernel` to `SaScenarioPixels.write`
## and `SaKernelDriver.kernel`, which pass the main canvas's document on to
## `write_from` and `run_on`. The suite calls those two on a document of its
## own, because a suite has no main canvas.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const KernelDriver := preload("res://harness/sa_kernel_driver.gd")

## Needs a RenderingDevice, because both writes upload into chunks.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)

## A kernel that copies its source, so a landed write is the paint it read.
const COPY := """kernel copy

image src: readonly
image dst

def copy():
    image_store(dst, pixel, image_load(src, pixel))
"""

const RED := Color(1.0, 0.0, 0.0, 1.0)

## The three kinds a painter cannot paint, by the word each refusal names.
const KINDS := {"Locked": "locked", "Group": "group", "Generated": "generator"}


## Each kind refuses the pixel write by its own reason and keeps nothing of it,
## and the plain layer takes the same write.
func test_write_pixels_refuses_what_a_painter_cannot_paint() -> void:
    var easel := _easel()
    var doc := easel.document
    var folder := _folder()
    _save(folder.path_join("red.npy"), Vector2i(16, 16), RED)
    for kind: String in KINDS:
        var layer := _layer_named(doc, kind)
        var steps := doc.undo_redo.get_history_count()
        var count := _count(doc)
        var answer := PixelDriver.write_from(doc, {"layer": kind, "rect": [8, 8, 16, 16], "file": "red.npy"}, folder)
        var said := String(answer.get("error", ""))
        assert_true(said.contains(KINDS[kind]), "the write into %s is refused by its kind: %s" % [kind, answer])
        assert_true(layer.chunks.is_empty(), "and %s holds no chunk" % kind)
        assert_eq(_count(doc), count, "and no layer was added for %s" % kind)
        assert_eq(doc.undo_redo.get_history_count(), steps, "and no step was recorded for %s" % kind)

    var plain := _layer_named(doc, "Plain")
    var steps_before := doc.undo_redo.get_history_count()
    var landed := PixelDriver.write_from(doc, {"layer": "Plain", "rect": [8, 8, 16, 16], "file": "red.npy"}, folder)
    assert_false(landed.has("error"), "the plain layer takes the write: %s" % landed)
    assert_false(plain.chunks.is_empty(), "and holds its chunk")
    assert_eq(doc.undo_redo.get_history_count(), steps_before + 1, "as one step")
    easel.free()
    _clear(folder)


## Each kind refuses a kernel written into it, by its own reason and with
## nothing kept, and the plain layer takes the same run.
func test_a_kernel_refuses_what_a_painter_cannot_paint() -> void:
    var easel := _easel()
    var doc := easel.document
    var driver := KernelDriver.new(null)
    for kind: String in KINDS:
        var layer := _layer_named(doc, kind)
        var steps := doc.undo_redo.get_history_count()
        var count := _count(doc)
        var verdict := driver.run_on(doc, _run_into(kind))
        assert_false(bool(verdict["ok"]), "the kernel into %s is refused: %s" % [kind, verdict])
        var said := String(verdict.get("error", ""))
        assert_true(said.contains(KINDS[kind]), "by its kind: %s" % said)
        assert_true(layer.chunks.is_empty(), "and %s holds no chunk" % kind)
        assert_eq(_count(doc), count, "and no layer was added for %s" % kind)
        assert_eq(doc.undo_redo.get_history_count(), steps, "and no step was recorded for %s" % kind)

    var plain := _layer_named(doc, "Plain")
    var steps_before := doc.undo_redo.get_history_count()
    var landed := driver.run_on(doc, _run_into("Plain"))
    assert_true(bool(landed["ok"]), "the plain layer takes the run: %s" % [landed])
    assert_false(plain.chunks.is_empty(), "and holds its chunk")
    assert_eq(doc.undo_redo.get_history_count(), steps_before + 1, "as one step")
    easel.free()


## A written layer stored in half floats is refused when the read layer is
## full floats, before a chunk or a step is made.
func test_a_kernel_refuses_a_layer_of_another_format() -> void:
    var easel := _easel()
    var doc := easel.document
    var half := SaLayerOps.new(doc).add(&"")
    half.name = "Half"
    half.schema = SaFieldSpec.default_schema(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
    var steps := doc.undo_redo.get_history_count()
    var verdict := KernelDriver.new(null).run_on(doc, _run_into("Half"))
    assert_false(bool(verdict["ok"]), "the run into another format is refused: %s" % [verdict])
    assert_true(String(verdict.get("error", "")).contains("format"), "by the format: %s" % [verdict])
    assert_true(half.chunks.is_empty(), "and the layer holds no chunk")
    assert_eq(doc.undo_redo.get_history_count(), steps, "and no step was recorded")
    easel.free()


## A document with a painted read layer, a plain one, and one of each kind.
func _easel() -> SaEasel:
    var easel := SaEasel.create_default(SIZE)
    var doc := easel.document
    var read := doc.active_layer
    read.name = "Read"
    read.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    var ops := SaLayerOps.new(doc)
    for name: String in ["Plain", "Locked", "Group", "Generated"]:
        var layer := ops.add(&"")
        layer.name = name
    _layer_named(doc, "Locked").is_locked = true
    _layer_named(doc, "Group").is_group = true
    var generated := _layer_named(doc, "Generated")
    generated.generator = "background"
    generated.generator_params = {"color": Color(0.5, 0.5, 0.5, 1.0)}
    return easel


func _run_into(name: String) -> Dictionary:
    return {"source": COPY, "name": "copy", "layer": "Read", "into": name, "rect": [8, 8, 16, 16]}


func _layer_named(doc: SaDocument, name: String) -> SaLayer:
    return KernelDriver.layer_of(doc, name)


func _count(doc: SaDocument) -> int:
    return SaLayerOps.new(doc).layers().size()


func _folder() -> String:
    var folder := SaDataRoot.path("d14-door-writes-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    return folder


func _clear(folder: String) -> void:
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)


func _save(path: String, size: Vector2i, color: Color) -> void:
    var floats := PackedFloat32Array()
    for _i in size.x * size.y:
        floats.append_array([color.r, color.g, color.b, color.a])
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(size))
    file.store_buffer(floats.to_byte_array())
    file.close()
