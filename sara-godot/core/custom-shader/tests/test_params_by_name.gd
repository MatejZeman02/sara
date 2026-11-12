## The params block and the bindings packed and found by their declared names.
##
## The two sides of a kernel call used to be matched by eye. A push constant was
## a positional float array whose order lived in a comment, and a binding was a
## slot number the caller counted off the preamble. A field inserted into the
## GLSL block, or a binding renumbered, changed neither side of the GDScript and
## produced a wrong picture rather than an error.
##
## The packer is pure, so the whole of it is provable here against the layouts
## `sa_kernel_source.gd` parses, with no RenderingDevice anywhere in the suite.
##
## The two subjects moved and the cases did not: `sa_params.gd`
## was cut into `sa_push_constants.gd`, which packs a block, and
## `sa_binding_slots.gd`, which finds a slot by name. Every case below is the one
## it was, under the name that now owns it. The one case that needs a GPU, a probe bound by name and dispatched,
## is in `test_storage_formats.gd` beside the probe it borrows.
extends "res://tests/test_framework.gd"

const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const PushConstants := preload("res://core/custom-shader/sa_push_constants.gd")
const BindingSlots := preload("res://core/custom-shader/sa_binding_slots.gd")
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")

## The block the unit was specified against: a vec2, a float and a pad, which is
## sixteen bytes and the shape half of Sara's kernels declare.
const BLOCK := """
layout( push_constant, std430 ) uniform Params {
    vec2 origin;
    float opacity;
    float pad;
} params;
"""

## A block whose fields are not all four bytes wide, so the alignment std430
## demands is exercised rather than assumed away.
const WIDE_BLOCK := """
layout( push_constant, std430 ) uniform Params {
    float amount;
    vec4 tint;
    int steps;
    float weights[3];
} params;
"""

## The three binding kinds under names a caller would actually write, with the
## numbers out of order so a lookup that returns the position in the dictionary
## rather than the declared binding is caught.
const PREAMBLE := """
layout( SA_STORAGE_FORMAT, set = 0, binding = 2 ) uniform image2D canvas;
layout( set = 0, binding = 0 ) uniform sampler2D tip;
layout( std430, set = 0, binding = 1 ) buffer Table { float values[]; } curve;
"""


func _layout() -> Array:
    return KernelSource.extract_push_constant_layout(BLOCK)


func _wide_layout() -> Array:
    return KernelSource.extract_push_constant_layout(WIDE_BLOCK)


func _bindings() -> Dictionary:
    return Bindings.extract_layout(PREAMBLE)


## The dialect's own block, transpiled rather than hand-written, so the pad
## under test is the one the dialect actually writes and not an imitation of it.
func _padded_layout() -> Array:
    return KernelSource.extract_push_constant_layout(Dialect.transpile("params:\n    float sigma\n    int radius\n"))


# ---------------------------------------------------------------------------
# The packing
# ---------------------------------------------------------------------------


## The layout is the compiler's, not the test's. If this drifts, every offset
## below is measuring the wrong thing.
func test_the_block_parses_into_the_four_declared_fields() -> void:
    var layout := _layout()
    assert_eq(layout.size(), 4, "Three fields and the closing entry")
    assert_eq(String(layout[0]["name"]), "origin", "origin first")
    assert_eq(int(layout[1]["offset"]), 8, "opacity after the vec2")
    assert_eq(int(layout[2]["offset"]), 12, "and the pad after it")
    assert_eq(int(layout[3]["offset"]), 16, "so the block is sixteen bytes")


func test_a_dictionary_packs_into_the_declared_offsets() -> void:
    var bytes := PushConstants.pack(_layout(), {"origin": Vector2(3.0, 4.0), "opacity": 0.5, "pad": 0.0})

    assert_eq(bytes.size(), 16, "The block is sixteen bytes")
    assert_almost_eq(bytes.decode_float(0), 3.0, 1e-6, "origin.x at the start")
    assert_almost_eq(bytes.decode_float(4), 4.0, 1e-6, "origin.y beside it")
    assert_almost_eq(bytes.decode_float(8), 0.5, 1e-6, "and opacity at the offset the block declares")


## The Dictionary is written in a different order from the block, because the
## whole point is that the caller no longer keeps the order.
func test_the_declaration_orders_the_bytes_and_not_the_dictionary() -> void:
    var jumbled := PushConstants.pack(_layout(), {"pad": 0.0, "opacity": 0.5, "origin": Vector2(3.0, 4.0)})
    var in_order := PushConstants.pack(_layout(), {"origin": Vector2(3.0, 4.0), "opacity": 0.5, "pad": 0.0})

    assert_eq(jumbled, in_order, "The same block either way round")


## std430 aligns a vec4 to sixteen, so `amount` leaves twelve bytes of gap
## behind it. Those bytes are the packer's to leave at zero, and a packer that
## wrote fields end to end would put the tint where the gap is.
func test_a_gap_std430_demands_is_left_at_zero() -> void:
    var values := {"amount": 1.0, "tint": Color(0.25, 0.5, 0.75, 1.0), "steps": 7, "weights": [1.0, 2.0, 3.0]}
    var bytes := PushConstants.pack(_wide_layout(), values)

    assert_almost_eq(bytes.decode_float(0), 1.0, 1e-6, "amount at the start")
    assert_almost_eq(bytes.decode_float(4), 0.0, 1e-6, "then the gap the vec4 alignment left")
    assert_almost_eq(bytes.decode_float(16), 0.25, 1e-6, "and the tint on its sixteen-byte boundary")


func test_an_int_is_written_as_an_int_and_an_array_run_by_run() -> void:
    var values := {"amount": 1.0, "tint": Color(0, 0, 0, 0), "steps": 7, "weights": [1.0, 2.0, 3.0]}
    var bytes := PushConstants.pack(_wide_layout(), values)

    assert_eq(bytes.decode_s32(32), 7, "steps is four bytes of integer, not a float that looks like seven")
    assert_almost_eq(bytes.decode_float(36), 1.0, 1e-6, "the array starts after it")
    assert_almost_eq(bytes.decode_float(44), 3.0, 1e-6, "with a stride of four, which is what float[] has")


## The packing half: the stride the layout measures is the stride written.
##
## A `vec3[]` is the one array whose entries are not written end to end, because
## std430 aligns each of them to sixteen. A packer that wrote them tightly would
## put the second entry twelve bytes in, which is inside the first entry's
## padding, and the kernel would read the first entry's z as the second entry's
## x. Nothing refuses it, the picture is merely wrong, which is the failure this
## whole file exists to end.
func test_a_vec3_array_is_packed_on_the_stride_std430_gives_it() -> void:
    var block := "layout( push_constant, std430 ) uniform Params { vec3 tint[3]; float opacity; } params;"
    var layout := KernelSource.extract_push_constant_layout(block)
    var tint: Array = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]

    var bytes := PushConstants.pack(layout, {"tint": tint, "opacity": 0.5})

    assert_almost_eq(bytes.decode_float(0), 1.0, 1e-6, "The first entry opens the block")
    assert_almost_eq(bytes.decode_float(8), 3.0, 1e-6, "with its three components four bytes apart")
    assert_almost_eq(bytes.decode_float(12), 0.0, 1e-6, "then the four bytes std430 pads each entry with")
    assert_almost_eq(bytes.decode_float(16), 4.0, 1e-6, "and the second entry sixteen bytes in, not twelve")
    assert_almost_eq(bytes.decode_float(32), 7.0, 1e-6, "the third at thirty-two")
    assert_almost_eq(bytes.decode_float(48), 0.5, 1e-6, "and opacity after the whole run")


## The block is sent at the size it declares and not one byte more.
##
## This asserted sixteen until a run of a twelve-byte block against a GPU and
## Vulkan answered "this compute pipeline requires (8) bytes of push constant
## data, supplied: (16)". std430 rounds the offsets *inside* a block up to
## sixteen, which `test_a_gap_std430_demands_is_left_at_zero` covers, and it does
## not round the block itself.
func test_the_block_is_sent_at_the_size_it_declares() -> void:
    var short_block := "layout( push_constant, std430 ) uniform Params { vec2 origin; float opacity; } params;"
    var layout := KernelSource.extract_push_constant_layout(short_block)
    assert_eq(int(layout[-1]["offset"]), 12, "Three floats is twelve bytes declared")

    var bytes := PushConstants.pack(layout, {"origin": Vector2(1.0, 2.0), "opacity": 1.0})
    assert_eq(bytes.size(), 12, "and twelve sent")
    assert_almost_eq(bytes.decode_float(8), 1.0, 1e-6, "with opacity as the last word of it")


# ---------------------------------------------------------------------------
# The refusal and the report
# ---------------------------------------------------------------------------


## A `params:` block in the dialect ends with the fields std430 needs to
## reach the boundary, written by the compiler because the maintainers' decision
## takes the writing of one off the student. To the parsed layout they read like
## any other field, so the packer asked the caller for them, refused every call
## that sensibly left them out, and the dispatch then failed for a push constant
## that was never set. A pad is the compiler's on both sides or on neither.
##
## The last assertion is the line that keeps this from overreaching: a field the
## author named `pad`, which half of Sara's kernels declare, is theirs and is
## still required.
func test_a_pad_the_compiler_wrote_is_not_the_callers_to_supply() -> void:
    var layout := _padded_layout()
    var values := {"sigma": 2.0, "radius": 5}

    assert_eq(int(layout[-1]["offset"]), 16, "The block the dialect wrote is sixteen bytes, pad included")
    assert_eq(PushConstants.complaint(layout, values), "", "and the two fields a kernel author declared are the whole of it")

    var bytes := PushConstants.pack(layout, values)
    assert_eq(bytes.size(), 16, "Packed at the size the block declares, which is what the pipeline demands")
    assert_almost_eq(bytes.decode_float(0), 2.0, 1e-6, "sigma at its offset")
    assert_eq(bytes.decode_s32(4), 5, "radius at its own")
    assert_eq(bytes.decode_float(8), 0.0, "and the pad left at the zero the resize gave it")
    assert_eq(bytes.decode_float(12), 0.0, "both words of it")

    var wrote_one: Dictionary = values.duplicate()
    wrote_one["_pad_0"] = 0.0
    assert_true(
        "declares no field named '_pad_0'" in PushConstants.complaint(layout, wrote_one),
        "A caller who writes one is told the block has no such field, the way any other unknown name is"
    )
    assert_true(
        "no value was given for 'pad'" in PushConstants.complaint(_layout(), {"origin": Vector2.ZERO, "opacity": 1.0}),
        "A field a kernel author called pad is theirs, and is still asked for"
    )


func test_nothing_is_wrong_with_a_complete_dictionary() -> void:
    var complaint := PushConstants.complaint(_layout(), {"origin": Vector2.ZERO, "opacity": 1.0, "pad": 0.0})
    assert_eq(complaint, "", "A block filled field for field has no complaint")


## The typo case. Packing around it would send a block the caller does not think
## it sent, and the misspelling is the one word worth printing.
func test_an_unknown_name_is_refused_and_named() -> void:
    var complaint := PushConstants.complaint(_layout(), {"origin": Vector2.ZERO, "opacty": 1.0, "pad": 0.0})

    assert_true("'opacty'" in complaint, "The name the caller wrote is in the message")
    assert_true("'opacity'" in complaint, "and so are the names it could have meant")
    assert_true(PushConstants.pack(_layout(), {"opacty": 1.0}).is_empty(), "and nothing is packed")


## The forgotten case. Zero is not a safe guess for an opacity, so it is refused
## rather than filled in, and the field is named because "the push constant is
## the wrong size" sends you reading the block instead.
func test_a_missing_field_is_reported_by_name() -> void:
    var complaint := PushConstants.complaint(_layout(), {"origin": Vector2.ZERO, "pad": 0.0})

    assert_true("'opacity'" in complaint, "The field left out is named")
    assert_false("'origin'" in complaint, "and the ones that were given are not")


func test_a_shader_with_no_block_says_so_rather_than_packing_nothing() -> void:
    var complaint := PushConstants.complaint([], {"opacity": 1.0})

    assert_false(complaint.is_empty(), "A library takes no push constant, and set_params on one is a mistake")
    assert_true(PushConstants.pack([], {"opacity": 1.0}).is_empty(), "so nothing is packed")


# ---------------------------------------------------------------------------
# The bindings by name
# ---------------------------------------------------------------------------


func test_each_kind_is_found_by_the_name_the_kernel_gave_it() -> void:
    var layout := _bindings()

    assert_eq(BindingSlots.slot_of(layout, "canvas", "image"), 2, "The image is at the binding it declares")
    assert_eq(BindingSlots.slot_of(layout, "tip", "sampler"), 0, "the sampler at its own")
    assert_eq(BindingSlots.slot_of(layout, "curve", "buffer"), 1, "and the buffer at its own")
    assert_eq(BindingSlots.slot_of(layout, "Table", "buffer"), 1, "which answers to its block name too")


## A buffer bound where a sampler was declared is the refusal SaCompute already
## makes by slot. Asking for the kind as well makes it a lookup that fails
## rather than a bind that is caught afterwards.
func test_a_name_of_the_wrong_kind_is_not_found() -> void:
    var layout := _bindings()

    assert_eq(BindingSlots.slot_of(layout, "canvas", "sampler"), -1, "The image is no sampler")
    assert_eq(BindingSlots.slot_of(layout, "curve", "image"), -1, "nor is the buffer an image")
    assert_eq(BindingSlots.slot_of(layout, "mask", "image"), -1, "and a name nothing declares is nowhere")


func test_the_names_of_a_kind_are_listed_for_an_error_that_has_to_suggest_one() -> void:
    var layout := _bindings()

    assert_eq(BindingSlots.declared_names(layout, "image"), "'canvas'", "One image, named")
    assert_eq(BindingSlots.declared_names(layout, "sampler"), "'tip'", "one sampler")
    assert_eq(BindingSlots.declared_names(layout, "buffer"), "'curve'", "and one buffer")
