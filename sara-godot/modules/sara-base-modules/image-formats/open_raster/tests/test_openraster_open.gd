## An OpenRaster file opens as a document with its layers and
## groups.
##
## Three fixtures under `tests/data/openraster/`. `sara_own.ora` is one Sara wrote with
## [SaExportOra]. `krita_like.ora` and `gimp_like.ora` are written by
## `make_ora_fixtures.py` beside them, the way Krita and GIMP write the format,
## and every number the suite expects below is a number that script wrote. Each
## is opened by [SaOraReader] and read back as layer facts and as texels out of
## the chunks.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SARA_OWN := "res://tests/data/openraster/sara_own.ora"
const KRITA := "res://tests/data/openraster/krita_like.ora"
const GIMP := "res://tests/data/openraster/gimp_like.ora"
const NOT_A_ZIP := "res://tests/data/import_gradient.png"

## One eight-bit step, the most an eight-bit sample can be off by once a
## float has been rounded into it on the way out.
const BYTE := 1.0 / 255.0

var _problems: Array[String] = []
var _easel: SaEasel

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))
    _problems.clear()
    _easel = SaEasel.create_default(Vector2i(128, 128))


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    _easel.free()
    _easel = null


func _open(path: String, depth: int = -1) -> SaOraReader:
    var reader := SaOraReader.new(ProjectSettings.globalize_path(path), depth)
    assert_eq(reader.open_into(_easel.document), OK, "%s opens" % path.get_file())
    return reader


## The document's layers and groups bottom first, as their names.
func _names() -> Array[String]:
    var out: Array[String] = []
    for child in _easel.document.get_children():
        if child is SaLayer:
            out.append(str(child.name))
    return out


func _layer(layer_name: String) -> SaLayer:
    return _easel.document.get_node(layer_name) as SaLayer


## The texel at document pixel (*x*, *y*), transparent where no chunk is.
func _texel(layer: SaLayer, x: int, y: int) -> Color:
    var side := SaChunk.SIZE
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / side, y / side))
    if texture == null:
        return Color(0, 0, 0, 0)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(texture).get_pixel(x % side, y % side)


func _near(got: Color, want: Color, tolerance: float, what: String) -> void:
    assert_almost_eq(got.r, want.r, tolerance, "%s: red" % what)
    assert_almost_eq(got.g, want.g, tolerance, "%s: green" % what)
    assert_almost_eq(got.b, want.b, tolerance, "%s: blue" % what)
    assert_almost_eq(got.a, want.a, tolerance, "%s: alpha" % what)


# --- Sara's own file ----------------------------------------------------------


func test_sara_own_file_opens_with_its_stack() -> void:
    var reader := _open(SARA_OWN)
    var doc := _easel.document
    assert_eq(doc.canvas_size, Vector2i(96, 64), "The document is the image's size")
    var order := ["Background", "Layer 1", "Paint", "Multiply", "Group", "Hidden"]
    assert_eq(_names(), order, "bottom first, a group over its members")
    var group := _layer("Group")
    assert_true(group.is_group, "A nested stack is a group")
    assert_true(group.isolated, "isolated as the file says")
    assert_almost_eq(group.opacity, 0.5, 1e-4, "at its opacity")
    assert_eq(_layer("Multiply").group, group, "and holds its member")
    assert_eq(_layer("Multiply").blend_mode, &"multiply", "whose mode comes back from its operator")
    assert_false(_layer("Hidden").visible, "A hidden layer opens hidden")
    assert_eq(doc.active_layer, _layer("Paint"), "The selected layer is active")
    assert_true(reader.fallen_back.is_empty() and reader.left_out.is_empty(), "Nothing of Sara's own is dropped")
    assert_true(_problems.is_empty(), "and nothing is said")


func test_sara_own_file_carries_its_texels() -> void:
    _open(SARA_OWN)
    _near(_texel(_layer("Paint"), 10, 10), Color(0.8, 0.2, 0.4, 1.0), BYTE, "Paint")
    _near(_texel(_layer("Multiply"), 95, 63), Color(0.6, 0.4, 0.8, 0.5), BYTE, "Multiply, straight alpha")
    _near(_texel(_layer("Hidden"), 0, 0), Color(0.2, 0.2, 0.8, 1.0), BYTE, "Hidden")
    assert_eq(_texel(_layer("Layer 1"), 50, 50).a, 0.0, "The empty layer is empty")


func test_an_open_leaves_nothing_to_undo() -> void:
    _open(SARA_OWN)
    assert_false(_easel.document.undo_redo.has_undo(), "An open is not an edit to take back")
    assert_true(_easel.document.modified, "and the file is not a .sad, so Save asks where")


# --- The way Krita writes it --------------------------------------------------


func test_krita_file_opens_with_its_stack() -> void:
    var reader := _open(KRITA)
    var doc := _easel.document
    assert_eq(doc.canvas_size, Vector2i(64, 48), "The document is the image's size")
    assert_almost_eq(doc.dpi, 300.0, 1e-4, "at its resolution")
    assert_eq(_names(), ["Background", "Xor", "Hidden", "Group", "Sixteen"], "bottom first, the missing layer left out")
    var group := _layer("Group")
    assert_true(group.is_group and group.isolated, "The nested stack is an isolated group")
    assert_almost_eq(group.opacity, 0.5, 1e-4, "at half opacity")
    assert_eq(_layer("Xor").group, group, "holding Xor")
    assert_eq(_layer("Hidden").group, group, "and Hidden")
    assert_eq(_layer("Sixteen").group, null, "and nothing above it")
    assert_false(_layer("Hidden").visible, "Hidden opens hidden")
    assert_eq(_layer("Hidden").blend_mode, &"multiply", "in multiply")
    assert_eq(_layer("Xor").blend_mode, &"normal", "An operator Sara has no mode for opens as normal")
    assert_almost_eq(_layer("Xor").opacity, 0.75, 1e-4, "at its own opacity")
    assert_eq(doc.active_layer, _layer("Sixteen"), "The selected layer is active")
    assert_eq(reader.fallen_back, PackedStringArray(["Xor"]), "The fallen-back layer is named")
    assert_eq(reader.left_out, PackedStringArray(["Missing"]), "and so is the one left out")
    assert_eq(_problems.size(), 2, "Each is said once, in a line of its own")
    assert_true(_problems.size() == 2 and "Xor" in _problems[0] and "Missing" in _problems[1], "naming the layers")


func test_krita_file_places_layers_at_their_offsets() -> void:
    _open(KRITA)
    var green := Color(0.0, 200.0 / 255.0, 0.0, 1.0)
    var xor := _layer("Xor")
    _near(_texel(xor, 2, 2), green, BYTE, "Xor starts at the group's offset")
    _near(_texel(xor, 5, 5), green, BYTE, "and is four pixels wide")
    assert_eq(_texel(xor, 1, 1).a, 0.0, "Nothing before it")
    assert_eq(_texel(xor, 6, 6).a, 0.0, "and nothing after it")
    _near(_texel(_layer("Hidden"), 12, 12), Color(200.0 / 255.0, 0.0, 0.0, 1.0), BYTE, "Hidden at its offset plus the group's")
    assert_eq(_texel(_layer("Hidden"), 11, 11).a, 0.0, "and not before it")
    var ground := Color(230.0 / 255.0, 220.0 / 255.0, 200.0 / 255.0, 1.0)
    _near(_texel(_layer("Background"), 63, 47), ground, BYTE, "An RGB layer is opaque")
    assert_eq(_layer("Sixteen").chunks.size(), 1, "A small layer allocates the one chunk it covers")


## 0x1234 is 4660 of 65535. Read at eight bits it would be 18 of 255, which is
## 0.07059 against 0.07111, a difference fifty times the tolerance here.
func test_a_sixteen_bit_layer_keeps_sixteen_bits() -> void:
    _open(KRITA, SaColorSpace.Depth.F16)
    assert_eq(_easel.document.color_space.depth, SaColorSpace.Depth.F32, "A sixteen-bit layer asks for full floats over a half")
    var got := _texel(_layer("Sixteen"), 40, 4)
    var want := Color(0x1234 / 65535.0, 0x8001 / 65535.0, 0xFEDC / 65535.0, 1.0)
    _near(got, want, 1e-6, "Sixteen at its offset")
    assert_eq(_texel(_layer("Sixteen"), 39, 4).a, 0.0, "and not before it")


# --- The way GIMP writes it ---------------------------------------------------


func test_gimp_file_opens_without_thumbnail_or_merged_image() -> void:
    var reader := _open(GIMP)
    var doc := _easel.document
    assert_eq(doc.canvas_size, Vector2i(40, 30), "The document is the image's size")
    assert_almost_eq(doc.dpi, SaDocument.DEFAULT_DPI, 1e-4, "at the default resolution when none is named")
    assert_eq(_names(), ["Plain", "Screen"], "bottom first")
    assert_eq(_layer("Plain").blend_mode, &"normal", "A layer without an operator is normal")
    assert_eq(_layer("Screen").blend_mode, &"screen", "and screen is screen")
    _near(_texel(_layer("Screen"), 20, 10), Color(0.0, 0.0, 1.0, 128.0 / 255.0), BYTE, "Screen at its offset")
    assert_eq(_texel(_layer("Screen"), 19, 9).a, 0.0, "and not before it")
    _near(_texel(_layer("Plain"), 0, 0), Color(1.0, 1.0, 0.0, 1.0), BYTE, "Plain")
    assert_eq(doc.active_layer, _layer("Plain"), "With nothing selected the first layer read is active")
    assert_true(reader.fallen_back.is_empty() and reader.left_out.is_empty(), "Nothing is dropped")
    assert_true(_problems.is_empty(), "and nothing is said")


# --- The edges ----------------------------------------------------------------


func test_every_operator_the_writer_names_comes_back() -> void:
    for mode: StringName in SaExportOra.COMPOSITE_OPS:
        assert_eq(SaOraReader.mode_for(SaExportOra.composite_op(mode)), mode, "%s survives the round trip" % mode)
    assert_eq(SaOraReader.mode_for("svg:xor"), &"", "and an operator Sara lacks answers nothing")


func test_a_file_that_is_not_a_zip_is_refused_and_leaves_the_document() -> void:
    var before := _names()
    var reader := SaOraReader.new(ProjectSettings.globalize_path(NOT_A_ZIP))
    assert_true(reader.open_into(_easel.document) != OK, "A PNG called anything is not OpenRaster")
    assert_eq(_names(), before, "and the document is untouched")
    assert_eq(_problems.size(), 1, "with one line saying why")


func test_the_open_dialog_and_the_drop_know_the_extension() -> void:
    var formats := SaImageImport.formats()
    assert_true(formats.layered_named("/a/b/picture.ORA") != null, "The extension is read whatever its case")
    assert_false(SaImageImport.is_image_path("picture.ora"), "and an .ora is not a picture to import as one layer")
    assert_true("*.ora" in formats.layered_filters()[0], "The dialog's line names it")
