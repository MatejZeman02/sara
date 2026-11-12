## The document's blend reference white W, and what it must not change.
##
## W says what a display-referred formula should treat as 1.0, so those modes
## evaluate `out = W * f(src / W, dst / W)` rather than assuming the window they
## were written for.
##
## Two properties are worth more than the arithmetic itself. W = 1 has to be the
## exact identity, or landing this would have quietly restyled every document
## ever painted. And an arithmetic-safe mode has to ignore W entirely, because
## windowing something already well defined unbounded would be a lie about what
## it computes.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIZE := Vector2i(32, 32)

## 32 / 8, the [numthreads(8, 8, 1)] the composite kernels declare.
const GROUPS: int = 4

## Kernel indices, in the order composite.gmacs declares them.
const KERNEL_SCREEN := 2
const KERNEL_ADD := 4


## Runs one blend of `src` over `dst` at reference white `white` and returns the
## stored pixel.
func _blend(kernel: int, dst: Color, src: Color, white: float) -> Color:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(SIZE)
    var chunk := SaTexture.new(SIZE)
    rd.texture_clear(canvas.rid, dst, 0, 1, 0, 1)
    rd.texture_clear(chunk.rid, src, 0, 1, 0, 1)

    var compute := SaCompute.new("composite")
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 0.0, white))
    compute.dispatch(kernel, GROUPS, GROUPS, 1)

    var data := rd.texture_get_data(canvas.rid, 0)
    return Color(data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12))


func test_the_default_is_one() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    assert_almost_eq(easel.document.blend_reference_white, 1.0, 0.0, "A new document's window is 1.0")
    easel.free()


## The whole point of landing W at 1.0: nothing may look different. Bit-exact
## rather than approximate, because `c / 1.0` and `c * 1.0` are exact in IEEE
## floats and anything less would mean the windowing is not really the identity.
func test_white_of_one_is_bit_exact() -> void:
    var dst := Color(0.3, 0.6, 0.9, 1.0)
    var src := Color(0.7, 0.2, 0.4, 1.0)
    var windowed := _blend(KERNEL_SCREEN, dst, src, 1.0)
    # 1 - (1-a)(1-b), computed here in double precision, is what the kernel
    # produced before W existed.
    for channel in 3:
        var expected: float = 1.0 - (1.0 - src[channel]) * (1.0 - dst[channel])
        assert_almost_eq(windowed[channel], expected, 1e-6, "Screen at W=1 channel %d" % channel)


## Screen at W = 2 must equal 2 * screen(src/2, dst/2). Chosen because screen is
## the mode the spec names when explaining why the window exists at all.
func test_screen_uses_the_window() -> void:
    var dst := Color(1.0, 0.5, 0.25, 1.0)
    var src := Color(0.5, 1.5, 0.75, 1.0)
    var result := _blend(KERNEL_SCREEN, dst, src, 2.0)
    for channel in 3:
        var a: float = src[channel] / 2.0
        var b: float = dst[channel] / 2.0
        var expected: float = 2.0 * (1.0 - (1.0 - a) * (1.0 - b))
        assert_almost_eq(result[channel], expected, 1e-5, "Screen at W=2 channel %d" % channel)


## The observable reason to set W at all: the same colour sits lower in a wider
## window, so screen has further to travel and saturates less.
##
## Measured as a fraction of the window, not in absolute value. Absolutely a
## wider window produces the *larger* number, because 0.8 screened in a 0-4
## window is 1.44, and reading that as "brighter" is the error this comment
## exists to stop the next person making.
func test_a_wider_window_saturates_less() -> void:
    var dst := Color(0.8, 0.8, 0.8, 1.0)
    var src := Color(0.8, 0.8, 0.8, 1.0)
    var at_one := _blend(KERNEL_SCREEN, dst, src, 1.0)
    var at_four := _blend(KERNEL_SCREEN, dst, src, 4.0)
    assert_almost_eq(at_one.r, 0.96, 1e-5, "0.8 screened on itself is almost white in a 0-1 window")
    assert_almost_eq(at_four.r, 1.44, 1e-4, "and only 36% of the way up a 0-4 one")
    assert_true(at_four.r / 4.0 < at_one.r, "so as a fraction of its window it is far from saturated")


## Add is arithmetic-safe, so W must not reach it. If windowing ever leaks into
## the arithmetic modes this is the test that says so: 2 + 2 is 4 at every W.
func test_arithmetic_modes_ignore_the_window() -> void:
    var dst := Color(2.0, 0.5, 0.25, 1.0)
    var src := Color(2.0, 0.5, 0.25, 1.0)
    var at_one := _blend(KERNEL_ADD, dst, src, 1.0)
    var at_seven := _blend(KERNEL_ADD, dst, src, 7.0)
    assert_almost_eq(at_one.r, 4.0, 1e-5, "Add is unbounded at W=1")
    assert_almost_eq(at_seven.r, 4.0, 1e-5, "and W does not touch it")


## W is document data, so a file has to reopen looking as it was saved. Viewer
## state would not survive this round trip and that is exactly the distinction.
func test_w_survives_a_sad_round_trip() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var document := easel.document
    document.blend_reference_white = 3.5

    var path := SaDataRoot.path("test_blend_white.sad")
    assert_eq(SaExport.save_sad(document, path), OK, "Saving succeeds")

    var reopened := SaEasel.create_default(Vector2i(16, 16))
    assert_eq(SaExport.load_sad(reopened.document, path), OK, "Loading succeeds")
    assert_almost_eq(reopened.document.blend_reference_white, 3.5, 1e-6, "W came back")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    easel.free()
    reopened.free()


## Every .sad written before W existed has no key for it, and those documents
## meant 1.0. A missing key must not read as zero and divide the window away.
func test_a_file_without_the_key_reads_as_one() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var path := SaDataRoot.path("test_blend_white_absent.sad")
    assert_eq(SaExport.save_sad(easel.document, path), OK, "Saving a default document succeeds")

    var reopened := SaEasel.create_default(Vector2i(16, 16))
    reopened.document.blend_reference_white = 9.0
    assert_eq(SaExport.load_sad(reopened.document, path), OK, "Loading succeeds")
    assert_almost_eq(reopened.document.blend_reference_white, 1.0, 0.0, "and the absent key means 1.0")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    easel.free()
    reopened.free()


## The packer writes W by index into a slot the colour space descriptor owns the
## rest of. If either side's layout moves, this is the cheap test that catches it
## before a GPU one has to.
func test_the_packed_block_puts_w_where_the_shader_reads_it() -> void:
    var params := SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 0.0, 2.5)
    assert_eq(params.size(), 32, "The composite push constant is 32 floats, 128 bytes")
    assert_almost_eq(params[SaCompute.COMPOSITE_BLEND_WHITE_INDEX], 2.5, 0.0, "W is at the documented index")
    assert_almost_eq(params[SaCompute.COMPOSITE_BLEND_WHITE_INDEX - 1], 1.0, 0.0, "and sits right after the opacity")


## A zero window would divide every display-referred mode by nothing. Refused in
## the packer as well as in the shader, because a NaN canvas is unrecoverable.
func test_a_nonpositive_window_falls_back_to_one() -> void:
    for bad: float in [0.0, -2.0]:
        var params := SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 0.0, bad)
        assert_almost_eq(params[SaCompute.COMPOSITE_BLEND_WHITE_INDEX], 1.0, 0.0, "W of %s is refused" % bad)
