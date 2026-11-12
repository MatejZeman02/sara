## The network's weights sit in one buffer with every batch
## norm folded into its convolution.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The fixtures are made by `make_fixtures.py` beside this file and the table
## of the real weights by `make_reference.py`, both with PyTorch. The fixture's
## fold is read back from the buffer against the fold the script wrote. A zip
## and a pickle naming `posix system` are refused with no opcode run. The real
## weights, from the module's data folder or the path `SARA_U2NETP_PTH` names,
## are held to PyTorch's own fusion of every convolution, and without either
## the case says so and skips.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const FoldedWeights = preload("../folded_weights.gd")

const HERE := "res://modules/sara-background-removal/tests/"
## The environment variable that names a `u2netp.pth` outside the data folder.
const REAL_WEIGHTS_VARIABLE := "SARA_U2NETP_PTH"

## The largest difference a folded value may have from the reference's, as a
## share of the value's size, or of 1 when the value is smaller than 1. A sum
## of a convolution's values is held to the same share of the sum of those
## sizes, the most the values' own differences could add up to. The fold here
## runs in double precision and rounds once, PyTorch's in float32 step by step,
## so a value differs by a rounding or two, under 1.2e-7 of its size: 6.1e-5 in
## a bias of 1,361 in `stage2d.rebnconv1d`, which an absolute bound of 1e-6
## would have called wrong.
const VALUE_TOLERANCE := 1e-6

var _registries: SaRegistries = null
var _module: SaModule = null


func before_each() -> void:
    _registries = SaTestFixtures.make_menu_registries()
    _registries.build_context(func() -> SaEasel: return null, func() -> Array: return [], SaAppDrive.new())
    _module = SubjectModule.new()
    _module.register(_registries.context.for_module(_module.get_id()))


func after_each() -> void:
    if _module != null:
        _module.unregister(_registries.context)
    _module = null
    _registries = null


## The buffer's floats, read back from the GPU, or the values it was made of
## when there is no rendering device to hold it.
func _buffer_values(folded: FoldedWeights) -> PackedFloat32Array:
    var buffer := folded.upload()
    if buffer == null or not buffer.rid.is_valid():
        skip("no rendering device, so the fold is read from the values the buffer is made of")
        return folded.values
    return buffer.read().to_float32_array()


## A shape read from JSON, whose numbers are floats, as integers.
static func _ints(shape: Array) -> Array:
    var out: Array = []
    for each: Variant in shape:
        out.append(int(each))
    return out


func test_the_fixture_s_fold_is_the_one_its_script_wrote() -> void:
    var folded: FoldedWeights = _module.folded_weights(HERE + "fixture_legacy.pth")
    assert_eq(folded.error, "", "the fixture is read")
    assert_eq(folded.convolutions.size(), 1, "one convolution")
    assert_eq(folded.norms_folded, 1, "and its norm folded into it")
    var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HERE + "fixture_fold.json"))
    assert_eq(FoldedWeights.EPSILON, float(expected["epsilon"]), "the script folded at the module's epsilon")
    var convolution: FoldedWeights.Convolution = folded.named(expected["name"])
    assert_not_null(convolution, "the table names the convolution")
    if convolution == null:
        return
    assert_eq(
        [convolution.out_channels, convolution.in_channels, convolution.kernel_height, convolution.kernel_width],
        _ints(expected["shape"]),
        "with its shape"
    )
    assert_eq(convolution.norm, "stage1.rebnconvin.bn_s1", "and the norm folded into it")
    var uploads_before := FoldedWeights.uploads
    var read := _buffer_values(folded)
    var wanted: Array = (expected["weight"] as Array) + (expected["bias"] as Array)
    assert_eq(read.size(), wanted.size(), "the buffer holds the weights and the bias")
    var largest := 0.0
    for i: int in mini(read.size(), wanted.size()):
        largest = maxf(largest, absf(read[i] - float(wanted[i])) / maxf(1.0, absf(float(wanted[i]))))
    print(
        (
            "    the fixture's fold read from the buffer differs from the script's by at most %s of a value"
            % String.num_scientific(largest)
        )
    )
    assert_true(
        largest <= VALUE_TOLERANCE,
        (
            "the buffer is the script's fold within %s of each value, and differs by %s"
            % [String.num_scientific(VALUE_TOLERANCE), String.num_scientific(largest)]
        )
    )
    # gdlint:ignore=comparison-with-itself
    assert_true(folded.upload() == folded.upload(), "a second ask answers the same buffer")
    assert_true(_module.folded_weights(HERE + "fixture_legacy.pth") == folded, "and a second read of the file is the first")
    assert_true(FoldedWeights.uploads - uploads_before <= 1, "so the weights are uploaded once")


func test_a_zip_is_refused_and_nothing_of_it_runs() -> void:
    var folded: FoldedWeights = _module.folded_weights(HERE + "fixture_zip.pth")
    assert_true(folded.error.contains("is a zip"), "the zip is refused with a message, which reads: %s" % folded.error)
    assert_eq(folded.convolutions.size(), 0, "and folds nothing")
    assert_null(folded.upload(), "and uploads nothing")
    var reader := FoldedWeights.PthReader.new(FileAccess.get_file_as_bytes(HERE + "fixture_zip.pth"), "fixture_zip.pth")
    assert_eq(reader.opcodes_run, 0, "and the reader runs no opcode of it")


func test_a_pickle_naming_a_global_it_does_not_expect_is_refused_and_nothing_of_it_runs() -> void:
    var folded: FoldedWeights = _module.folded_weights(HERE + "fixture_global.pth")
    assert_true(
        folded.error.contains("names the global posix system"),
        "the file is refused naming the global, and reads: %s" % folded.error
    )
    assert_eq(folded.convolutions.size(), 0, "and folds nothing")
    var reader := FoldedWeights.PthReader.new(FileAccess.get_file_as_bytes(HERE + "fixture_global.pth"), "fixture_global.pth")
    assert_eq(reader.opcodes_run, 0, "and the reader runs no opcode of any of its pickles")
    assert_eq(reader.tensors.size(), 0, "and keeps no tensor")


func test_the_real_weights_are_119_convolutions_equal_to_pytorch_s_fusion() -> void:
    var path := OS.get_environment(REAL_WEIGHTS_VARIABLE)
    if path.is_empty() or not FileAccess.file_exists(path):
        path = _module.weights_path()
    if not FileAccess.file_exists(path):
        skip("no u2netp.pth in the module's data folder and %s names none" % REAL_WEIGHTS_VARIABLE)
        return
    var folded: FoldedWeights = _module.folded_weights(path)
    assert_eq(folded.error, "", "the real weights are read")
    var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HERE + "u2netp_folded.json"))
    var rows: Array = table["convolutions"]
    assert_eq(folded.convolutions.size(), 119, "the table holds 119 convolutions")
    assert_eq(folded.norms_folded, 112, "with 112 norms folded into them")
    var norms := 0
    for each: FoldedWeights.Convolution in folded.convolutions:
        norms += 1 if each.name.contains(".bn") else 0
    assert_eq(norms, 0, "and no norm of its own")
    var read := _buffer_values(folded)
    assert_eq(read.size(), folded.values.size(), "the buffer holds every value")
    var largest_value := 0.0
    var largest_sum := 0.0
    var shapes_wrong := 0
    for i: int in mini(rows.size(), folded.convolutions.size()):
        var row: Dictionary = rows[i]
        var convolution := folded.convolutions[i]
        if (
            convolution.name != row["name"]
            or (
                [convolution.out_channels, convolution.in_channels, convolution.kernel_height, convolution.kernel_width]
                != _ints(row["shape"])
            )
        ):
            shapes_wrong += 1
            continue
        for part: String in ["weight", "bias"]:
            var start := convolution.weights if part == "weight" else convolution.bias
            var count := convolution.weight_count() if part == "weight" else convolution.out_channels
            var sum := 0.0
            var sizes := 0.0
            for j: int in range(start, start + count):
                sum += read[j]
                sizes += maxf(1.0, absf(read[j]))
            var expected: Dictionary = row[part]
            largest_sum = maxf(largest_sum, absf(sum - float(expected["sum"])) / sizes)
            for end: Array in [[start, "first"], [start + count - 1, "last"]]:
                var want := float(expected[end[1]])
                largest_value = maxf(largest_value, absf(read[end[0]] - want) / maxf(1.0, absf(want)))
    print(
        (
            # gdlint:ignore=max-line-length
            "    the real weights' fold differs from PyTorch's by at most %s of a first or last value and %s of a sum, each as a share of its size"
            % [String.num_scientific(largest_value), String.num_scientific(largest_sum)]
        )
    )
    assert_eq(shapes_wrong, 0, "every convolution has the reference's name and shape, in its order")
    assert_true(
        largest_value <= VALUE_TOLERANCE,
        (
            "every first and last value within %s of its size, the largest off by %s"
            % [String.num_scientific(VALUE_TOLERANCE), String.num_scientific(largest_value)]
        )
    )
    assert_true(
        largest_sum <= VALUE_TOLERANCE,
        (
            "every sum within %s of its values' sizes, the largest off by %s"
            % [String.num_scientific(VALUE_TOLERANCE), String.num_scientific(largest_sum)]
        )
    )
