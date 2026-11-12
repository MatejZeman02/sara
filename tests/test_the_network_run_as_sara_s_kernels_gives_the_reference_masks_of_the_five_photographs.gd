## The network run as Sara's kernels gives the reference masks
## of the five photographs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The reference inputs and masks are made by `make_masks.py` beside this file
## with U-2-Net's own code: each photograph through the reference's
## preparation, and the sigmoid of the fused output as the network gives it.
## Each case feeds the kept input through Sara's kernels and reads the mask
## back, which a suite may, and holds it to the reference's. The weights come
## from the module's data folder or the path `SARA_U2NETP_PTH` names, and
## without either every case says so and skips.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const SubjectNetwork = preload("../network/subject_network.gd")

const REQUIRES_GPU := true
const HERE := "res://modules/sara-background-removal/tests/"
## The environment variable that names a `u2netp.pth` outside the data folder.
const REAL_WEIGHTS_VARIABLE := "SARA_U2NETP_PTH"
const PHOTOGRAPHS: Array[String] = ["p1", "p2", "p3", "p4", "p5"]
## `ToTensorLab(flag=0)`'s ImageNet mean and deviation, channel by channel.
const MEAN: Array[float] = [0.485, 0.456, 0.406]
const DEVIATION: Array[float] = [0.229, 0.224, 0.225]

## The most Sara's mask may differ from the reference's at any texel: the
## 1 in 255 between the reference's own CPU and GPU runs.
const MASK_TOLERANCE := 1.0 / 255.0
## the share of the bicycle's texels between 0.05 and 0.95, read on the
## stretched mask resized to the photograph, and how far Sara's share at 320
## may sit from it, and from the reference's own share at 320.
const BICYCLE_SOFT := 0.187
const BICYCLE_SOFT_BOUND := 0.005
const BICYCLE_SOFT_AGAINST_THE_REFERENCE := 0.001
## The most a mask of a picture with no subject may reach, far under the 1 a
## stretch to the full range would give it.
const GREY_HIGHEST := 0.01
## The spec's bound on a forward pass, and how many passes are timed after how
## many warm-up passes.
const PASS_BOUND_MS := 200.0
const TIMED_PASSES := 20
const WARM_UP_PASSES := 3

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


## The chain over the real weights, or null with the case skipped.
func _network() -> SubjectNetwork:
    var path := OS.get_environment(REAL_WEIGHTS_VARIABLE)
    if path.is_empty() or not FileAccess.file_exists(path):
        path = _module.weights_path()
    if not FileAccess.file_exists(path):
        skip("no u2netp.pth in the module's data folder and %s names none" % REAL_WEIGHTS_VARIABLE)
        return null
    if GlobalShaderCompiler.get_rd() == null:
        skip("no rendering device to run the kernels on")
        return null
    var network: SubjectNetwork = _module.subject_network(path)
    assert_eq(network.error, "", "the chain is made over the real weights")
    return network if network.error.is_empty() else null


## The kept picture *name*: its tensor as `ToTensorLab(flag=0)` makes it of
## the rescaled picture, and the reference's mask.
func _reference(name: String) -> Dictionary:
    var packed := FileAccess.get_file_as_bytes(HERE + "reference_%s.bin" % name)
    var bytes := packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
    var plane := SubjectNetwork.SIZE * SubjectNetwork.SIZE
    var picture := bytes.slice(0, 3 * plane)
    var largest := 0.0
    for value: int in picture:
        largest = maxf(largest, value / 255.0)
    var tensor := PackedFloat32Array()
    tensor.resize(3 * plane)
    for channel: int in 3:
        for at: int in plane:
            var scaled: float = picture[channel * plane + at] / 255.0 / largest
            tensor[channel * plane + at] = (scaled - MEAN[channel]) / DEVIATION[channel]
    var mask := PackedFloat32Array()
    mask.resize(plane)
    for at: int in plane:
        mask[at] = bytes.decode_u16(3 * plane + 2 * at) / 65535.0
    return {"input": tensor, "mask": mask}


## Sara's mask of the kept picture *name*.
func _run(network: SubjectNetwork, input: PackedFloat32Array) -> PackedFloat32Array:
    network.input.update(input.to_byte_array())
    assert_true(network.run(), "the chain runs, and says: %s" % network.error)
    return network.output.read().to_float32_array()


static func _largest_difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
    var largest := 0.0
    for at: int in mini(a.size(), b.size()):
        largest = maxf(largest, absf(a[at] - b[at]))
    return largest


static func _soft_share(mask: PackedFloat32Array) -> float:
    var soft := 0
    for value: float in mask:
        soft += 1 if value > 0.05 and value < 0.95 else 0
    return float(soft) / maxf(1.0, mask.size())


func test_the_chain_is_the_network_s_layers() -> void:
    var network := _network()
    if network == null:
        return
    assert_eq(network.counts.get("subject_convolve", 0), 119, "119 convolutions, each with its norm folded in")
    assert_eq(network.counts.get("subject_pool", 0), 33, "33 max pools")
    assert_eq(network.counts.get("subject_resample", 0), 38, "38 bilinear resamplings")
    assert_eq(network.concatenations, 51, "51 concatenations, none a step of its own")
    assert_eq(network.counts.get("subject_sigmoid", 0), 1, "and the one sigmoid of the fused output")
    var largest := 0
    for page: SaCompute.Buffer in network.pages:
        largest = maxi(largest, page.size)
    print("    %d steps, the intermediates in %d pages of %d bytes" % [network.steps.size(), network.pages.size(), largest])
    assert_eq(largest, SubjectNetwork.PAGE_FLOATS * 4, "every page is the largest intermediate's size, 64 channels at 320 by 320")


func test_each_photograph_s_mask_is_the_reference_s() -> void:
    var network := _network()
    if network == null:
        return
    for name: String in PHOTOGRAPHS:
        var made := _reference(name)
        var mask := _run(network, made["input"])
        var largest := _largest_difference(mask, made["mask"])
        print("    %s, Sara's mask differs from the reference's by at most %s" % [name, String.num_scientific(largest)])
        assert_true(
            largest <= MASK_TOLERANCE,
            (
                "%s is within %s of the reference at every texel, and differs by %s"
                % [name, String.num_scientific(MASK_TOLERANCE), String.num_scientific(largest)]
            )
        )


func test_the_bicycle_s_mask_is_as_patchy_as_the_reference_s() -> void:
    var network := _network()
    if network == null:
        return
    var made := _reference("p4")
    var mask := _run(network, made["input"])
    var share := _soft_share(mask)
    var theirs := _soft_share(made["mask"])
    var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HERE + "reference_masks.json"))
    var stretched := float(table["pictures"]["p4"]["soft_stretched_full_size"])
    assert_true(
        absf(stretched - BICYCLE_SOFT) <= BICYCLE_SOFT_AGAINST_THE_REFERENCE,
        (
            "the reference's mask, stretched and resized as the table read it, is the table's %.3f, at %.4f"
            % [BICYCLE_SOFT, stretched]
        )
    )
    print(
        (
            ("    the bicycle's share between 0.05 and 0.95 is %.4f in Sara's mask and %.4f in the reference's" % [share, theirs])
            + ", against the table's %.3f" % BICYCLE_SOFT
        )
    )
    assert_true(
        absf(share - BICYCLE_SOFT) <= BICYCLE_SOFT_BOUND,
        "the bicycle is as patchy as the table found it, within %.3f of %.3f, at %.4f" % [BICYCLE_SOFT_BOUND, BICYCLE_SOFT, share]
    )
    assert_true(
        absf(share - theirs) <= BICYCLE_SOFT_AGAINST_THE_REFERENCE,
        "and within %.3f of the reference's own share at 320, %.4f, at %.4f" % [BICYCLE_SOFT_AGAINST_THE_REFERENCE, theirs, share]
    )


func test_a_flat_grey_comes_out_as_the_sigmoid_gives_it_and_unstretched() -> void:
    var network := _network()
    if network == null:
        return
    var made := _reference("grey")
    var mask := _run(network, made["input"])
    var largest := _largest_difference(mask, made["mask"])
    var highest := 0.0
    var lowest := 1.0
    for value: float in mask:
        highest = maxf(highest, value)
        lowest = minf(lowest, value)
    print(
        (
            "    the flat grey's mask runs from %s to %s and differs from the reference's by at most %s"
            % [String.num_scientific(lowest), String.num_scientific(highest), String.num_scientific(largest)]
        )
    )
    assert_true(
        largest <= MASK_TOLERANCE,
        (
            "the grey's mask is the reference's within %s, and differs by %s"
            % [String.num_scientific(MASK_TOLERANCE), String.num_scientific(largest)]
        )
    )
    assert_true(
        highest < GREY_HIGHEST,
        (
            "and no texel reaches %s, the highest %s, so nothing stretched it to the full range"
            % [GREY_HIGHEST, String.num_scientific(highest)]
        )
    )


func test_a_forward_pass_takes_under_200_milliseconds() -> void:
    var network := _network()
    if network == null:
        return
    var made := _reference("p3")
    network.input.update((made["input"] as PackedFloat32Array).to_byte_array())
    var times: Array[float] = []
    for pass_index: int in WARM_UP_PASSES + TIMED_PASSES:
        var started := Time.get_ticks_usec()
        if not network.run():
            assert_true(false, "the chain runs, and says: %s" % network.error)
            return
        # A read of one float waits for the list, so the time is the pass's.
        network.output.read(0, 4)
        if pass_index >= WARM_UP_PASSES:
            times.append((Time.get_ticks_usec() - started) / 1000.0)
    times.sort()
    var middle: int = TIMED_PASSES >> 1
    var median := (times[middle - 1] + times[middle]) / 2.0
    print(
        (
            "    the median of %d forward passes after %d warm-up passes is %.2f ms, from %.2f to %.2f, on %s"
            % [TIMED_PASSES, WARM_UP_PASSES, median, times[0], times[-1], RenderingServer.get_video_adapter_name()]
        )
    )
    assert_true(median < PASS_BOUND_MS, "a pass takes under %d ms, the median %.2f ms" % [PASS_BOUND_MS, median])
