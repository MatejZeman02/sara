## Opening the seasons file holds no frame for more than a
## second, at 1,945 blobs too.
##
## The fill no longer builds the fold whole when its last chunk is in, which
## held one frame for 1.2 s on the winter seasons file, and it marks each
## step's chunks once and below no layer, after every layer's refold, where it
## marked each layer named and spent 4 s of the fill in the stale spread. Both
## hold only while what the steps marked is enough: the picture a frame draws
## from it after the last step is the one a whole open draws.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and an open writes them.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Three chunks by two.
const SIZE := Vector2i(768, 512)
const PAINTED := 6
## The layer active when the file is saved, so the open has caches below and
## above it for the steps to fold again.
const ACTIVE := 2

var _surfaces: Array[SaSurface] = []
var _machines: Array[ToolMachine] = []
var _paths: Array[String] = []


func after_each() -> void:
    for index in _surfaces.size():
        Fixtures.teardown(_surfaces[index], _machines[index])
    _surfaces.clear()
    _machines.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    _surfaces.append(surface)
    _machines.append(Fixtures.make_bound_machine(surface))
    return surface


## A file of [constant PAINTED] layers over the background, each a colour of
## its own at part cover over a chunk of its own and the one beside it, so the
## composite reads every layer and the caches each bake a different part.
func _saved() -> String:
    var document := _surface().get_document()
    var made: Array[SaLayer] = []
    for i in PAINTED:
        var layer := SaLayerOps.new(document).add(&"")
        layer.name = "Painted %d" % i
        made.append(layer)
        var positions := SaLayer.grid_positions(SIZE)
        for grid_pos: Vector2i in [positions[i % positions.size()], positions[(i + 1) % positions.size()]]:
            layer.get_or_create_chunk(grid_pos).clear(_colour(i))
    document.set_active_layer(made[ACTIVE])
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_%d.sad" % _paths.size()))
    _paths.append(path)
    assert_eq(SaExport.save_sad(document, path), OK, "The file is written")
    return path


static func _colour(i: int) -> Color:
    return Color(0.1 + 0.12 * i, 0.9 - 0.1 * i, 0.3 + 0.05 * i, 0.4 + 0.08 * i)


static func _opening(document: SaDocument, path: String) -> SaSadOpening:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    return SaSadOpening.new(document, file, path)


static func _picture(surface: SaSurface) -> PackedByteArray:
    return SaExport.get_texture_image_float(surface.easel.output).get_data()


func test_the_picture_drawn_from_what_the_steps_marked_is_the_whole_open_s() -> void:
    var path := _saved()
    var whole := _surface()
    assert_eq(SaExport.load_sad(whole.get_document(), path), OK, "The file opens in one call")
    Bench.composite(whole.easel)

    var surface := _surface()
    var document := surface.get_document()
    var opening := _opening(document, path)
    opening.defer_chunks()
    var reads := 0
    while not opening.step(0) and reads < 1000:
        reads += 1
    assert_true(reads < 1000, "The stack is read within a thousand steps")
    assert_eq(opening.land(), OK, "The stack lands with its chunks to come")
    var said := "with the saved active layer, so caches stand below and above it"
    assert_eq(document.active_layer.name, "Painted %d" % ACTIVE, said)
    Bench.composite(surface.easel)
    opening.begin_filling(Rect2i(Vector2i.ZERO, SIZE))
    var steps := 0
    # A step of no time brings one chunk, and a frame draws after each.
    while not opening.fill(0) and steps < 10000:
        steps += 1
        surface.easel.process_pending_composite()
    opening.finish_filling()
    assert_true(steps > 1, "The chunks came over %d steps" % steps)
    assert_null(SaSadOpening.still_filling(document), "and the open is done")
    surface.easel.process_pending_composite()
    assert_true(_picture(surface) == _picture(whole), "The picture drawn from what the steps marked is the whole open's")
