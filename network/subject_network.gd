## U²-NetP run as Sara's own kernels: the network of U-2-Net's model file, u2net.py,
## at `ac7e1c817`, its weights the folded buffer of `folded_weights.gd`, from a
## 320 by 320 input tensor in a buffer to the sigmoid of the fused output in
## another, with nothing read back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every layer is one of four kernels beside this file. `subject_convolve` is a
## 3×3 convolution at any dilation or a 1×1, with its bias and the ReLU fused,
## over one tensor or two read as their concatenation, and the residual add of
## an RSU block's last convolution. `subject_pool` is the 2×2 max pool rounding
## up, `subject_resample` the bilinear `F.upsample` with the corners unaligned,
## and `subject_sigmoid` the last step. The side outputs are concatenated by
## being written into the channels of one tensor that the fusing 1×1 reads.
##
## **The plan is made once**, when the chain is made: the steps in the order
## `U2NETP.forward` takes them, each tensor's size, and where each lives. A
## tensor is floats channel after channel and row after row, as PyTorch keeps
## it, at an offset in one of the pages, storage buffers each sized for the
## largest intermediate, 64 channels at 320 by 320, 25 MiB. A tensor takes the
## first gap that holds it in the first page that has one from the step that
## writes it, and gives the gap back after the last step that reads it, so the
## pages hold what is alive at once and no more. One page per tensor would be
## 255 of them, and one buffer for all would ask a device for more than the
## 128 MiB some give a storage buffer.
##
## **A run is one compute list**, every step recorded with a barrier before it
## and submitted together, so the network is a single submission and the
## picture never leaves the card.
extends RefCounted

const FoldedWeights := preload("../folded_weights.gd")

## The side of the input and of the mask.
const SIZE := 320
## The input's channels.
const INPUT_CHANNELS := 3
## The floats of a page, the largest intermediate.
const PAGE_FLOATS := 64 * SIZE * SIZE
## Invocations along a workgroup's x, as every kernel here declares them.
const LANES := 64
## The output channels one invocation of the convolution works, its CHANNELS.
const CONVOLUTION_CHANNELS := 8
## No kernel here reads an image, so the variant is the same at any format.
const FORMAT := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## Why the chain cannot run, empty when it can.
var error: String = ""
## The input tensor, 3 × 320 × 320 floats, which the caller fills.
var input: SaCompute.Buffer = null
## The mask, 320 × 320 floats, the sigmoid as the network gives it.
var output: SaCompute.Buffer = null
## The pages the intermediates live in.
var pages: Array[SaCompute.Buffer] = []
## Every step, in the order a run dispatches them.
var steps: Array[Step] = []
## Steps of each kind, by kernel name, which a suite holds to the network's
## own count.
var counts: Dictionary[String, int] = {}
## Concatenations, read as two inputs or written into channels of one tensor.
var concatenations: int = 0
## Runs submitted, which a suite reads.
var runs: int = 0

## The folded weights the chain reads.
var weights: FoldedWeights = null
var _weights_buffer: SaCompute.Buffer = null
var _kernels: Dictionary[String, SaCompute] = {}
var _tensors: Array[Tensor] = []


## One tensor of the plan: its size, and where it lives once placed.
class Tensor:
    extends RefCounted
    var channels: int
    var height: int
    var width: int
    ## The index of the page it lives in, -1 for the input and -2 for the
    ## output, which have buffers of their own.
    var page: int = -1
    ## Where it starts, in floats.
    var at: int = 0
    ## The steps that write it first and read it last.
    var born: int = -1
    var dies: int = -1

    func _init(planes: int, tall: int, wide: int) -> void:
        channels = planes
        height = tall
        width = wide

    func floats() -> int:
        return channels * height * width


## One dispatch: the kernel, the tensors it binds by name, its params and its
## groups. A param naming a tensor's place is filled in once the tensors are
## placed.
class Step:
    extends RefCounted
    var kernel: String
    ## Binding name to the tensor bound there, or to null for the weights.
    var bindings: Dictionary[String, Tensor] = {}
    ## Param name to the tensor whose offset it takes, plus a channel offset.
    var places: Dictionary[String, Array] = {}
    var params: Dictionary[String, int] = {}
    var groups: Vector2i

    func _init(called: String, wide: int, tall: int) -> void:
        kernel = called
        groups = Vector2i(wide, tall)


func _init(folded: FoldedWeights) -> void:
    weights = folded
    if not folded.error.is_empty():
        error = folded.error
        return
    if GlobalShaderCompiler.get_rd() == null:
        error = "There is no rendering device to run the network on."
        return
    var given := Tensor.new(INPUT_CHANNELS, SIZE, SIZE)
    _forward(given)
    if not error.is_empty():
        steps.clear()
        return
    _place()
    _weights_buffer = folded.upload()
    for each: Step in steps:
        if not _kernels.has(each.kernel):
            _kernels[each.kernel] = SaCompute.new(each.kernel)


## Runs the network on what [member input] holds, into [member output], as
## one submission. Answers false when the chain cannot run.
func run() -> bool:
    if not error.is_empty() or _weights_buffer == null:
        return false
    var recorded: Array[SaCompute.Recorded] = []
    for each: Step in steps:
        var compute: SaCompute = _kernels[each.kernel]
        for binding: String in each.bindings:
            compute.set_storage(binding, _rid_of(each.bindings[binding]))
        compute.set_params(each.params)
        var one := compute.record(each.kernel, FORMAT, each.groups.x, each.groups.y, 1, true)
        if one == null:
            error = "The kernel %s could not be recorded." % each.kernel
            return false
        recorded.append(one)
    SaCompute.submit(recorded, "subject_network")
    runs += 1
    return true


func _rid_of(tensor: Tensor) -> RID:
    if tensor == null:
        return _weights_buffer.rid
    if tensor.page == -1:
        return input.rid
    if tensor.page == -2:
        return output.rid
    return pages[tensor.page].rid


# --- The network, as U2NETP.forward writes it -------------------------------


func _forward(x: Tensor) -> void:
    var hx1 := _rsu("stage1", [x], 7)
    var hx2 := _rsu("stage2", [_pool(hx1)], 6)
    var hx3 := _rsu("stage3", [_pool(hx2)], 5)
    var hx4 := _rsu("stage4", [_pool(hx3)], 4)
    var hx5 := _rsu_f("stage5", [_pool(hx4)])
    var hx6 := _rsu_f("stage6", [_pool(hx5)])
    if not error.is_empty():
        return
    var sides := _tensor(6, SIZE, SIZE)
    _side("side6", hx6, sides, 5)
    var hx5d := _rsu_f("stage5d", _concatenated(_resample(hx6, hx5), hx5))
    _side("side5", hx5d, sides, 4)
    var hx4d := _rsu("stage4d", _concatenated(_resample(hx5d, hx4), hx4), 4)
    _side("side4", hx4d, sides, 3)
    var hx3d := _rsu("stage3d", _concatenated(_resample(hx4d, hx3), hx3), 5)
    _side("side3", hx3d, sides, 2)
    var hx2d := _rsu("stage2d", _concatenated(_resample(hx3d, hx2), hx2), 6)
    _side("side2", hx2d, sides, 1)
    var hx1d := _rsu("stage1d", _concatenated(_resample(hx2d, hx1), hx1), 7)
    _side("side1", hx1d, sides, 0)
    if not error.is_empty():
        return
    # The six side outputs are one tensor's channels, so the fusing 1×1 reads
    # their concatenation without a step of its own.
    concatenations += 1
    var fused := _convolve("outconv", [sides], false)
    if fused == null:
        return
    var mask := Tensor.new(1, SIZE, SIZE)
    mask.page = -2
    var step := _step("subject_sigmoid", SIZE * SIZE, 1)
    step.bindings = {"source": fused, "target": mask}
    step.places = {"source_at": [fused, 0], "target_at": [mask, 0]}
    step.params = {"count": SIZE * SIZE}
    _read(fused)
    _write(mask)


## RSU-L, the block of `RSU7` to `RSU4`: a U of *levels* convolutions down,
## pooled between them, a dilated one at the bottom, and back up, each step
## up reading the one before resampled to the size of the step down it pairs
## with, and the last adding the block's first.
func _rsu(prefix: String, x: Array, levels: int) -> Tensor:
    var hxin := _convolve(prefix + ".rebnconvin", x)
    var down: Array[Tensor] = []
    var hx := hxin
    for k: int in range(1, levels):
        var h := _convolve("%s.rebnconv%d" % [prefix, k], [hx])
        if h == null:
            return null
        down.append(h)
        hx = _pool(h) if k < levels - 1 else h
    var up := _convolve("%s.rebnconv%d" % [prefix, levels], [down.back()], true, 2)
    for k: int in range(levels - 1, 0, -1):
        if up == null:
            return null
        var skip := down[k - 1]
        var resized := up if up.height == skip.height and up.width == skip.width else _resample(up, skip)
        up = _convolve("%s.rebnconv%dd" % [prefix, k], [resized, skip], true, 1, hxin if k == 1 else null)
    return up


## RSU-4F, dilations of 1, 2, 4 and 8 in place of pools.
func _rsu_f(prefix: String, x: Array) -> Tensor:
    var hxin := _convolve(prefix + ".rebnconvin", x)
    var hx1 := _convolve(prefix + ".rebnconv1", [hxin])
    var hx2 := _convolve(prefix + ".rebnconv2", [hx1], true, 2)
    var hx3 := _convolve(prefix + ".rebnconv3", [hx2], true, 4)
    var hx4 := _convolve(prefix + ".rebnconv4", [hx3], true, 8)
    var hx3d := _convolve(prefix + ".rebnconv3d", [hx4, hx3], true, 4)
    var hx2d := _convolve(prefix + ".rebnconv2d", [hx3d, hx2], true, 2)
    return _convolve(prefix + ".rebnconv1d", [hx2d, hx1], true, 1, hxin)


## Both tensors, which the next convolution reads as their concatenation.
func _concatenated(first: Tensor, then: Tensor) -> Array[Tensor]:
    return [first, then]


## A side output: its 3×3 to one channel, resampled into channel *channel* of
## *sides*, or written there when it is already full size.
func _side(name: String, from: Tensor, sides: Tensor, channel: int) -> void:
    if from == null:
        error = "The side output %s has no input." % name
        return
    if from.height == SIZE and from.width == SIZE:
        _convolve(name, [from], false, 1, null, sides, channel)
        return
    var small := _convolve(name, [from], false)
    if small != null:
        _resample(small, sides, sides, channel)


func _convolve(
    name: String,
    inputs: Array,
    relu: bool = true,
    dilation: int = 1,
    residual: Tensor = null,
    into: Tensor = null,
    channel: int = 0
) -> Tensor:
    var layer := weights.named(name) if weights.named(name) != null else weights.named(name + ".conv_s1")
    var source: Tensor = inputs[0] if not inputs.is_empty() else null
    if layer == null or source == null:
        if error.is_empty():
            error = "The network has no convolution %s, or nothing to run it on." % name
        return null
    var second: Tensor = inputs[1] if inputs.size() > 1 else null
    var channels := source.channels + (second.channels if second != null else 0)
    if layer.in_channels != channels or layer.kernel_height != layer.kernel_width:
        error = "The convolution %s takes %d channels and is given %d." % [name, layer.in_channels, channels]
        return null
    if second != null:
        concatenations += 1
    var out := into if into != null else _tensor(layer.out_channels, source.height, source.width)
    var step := _step("subject_convolve", source.height * source.width, ceili(float(layer.out_channels) / CONVOLUTION_CHANNELS))
    step.bindings = {
        "source": source,
        "second": second if second != null else source,
        "residual": residual if residual != null else source,
        "target": out,
        "weights": null,
    }
    step.places = {"source_at": [source, 0], "target_at": [out, channel * source.height * source.width]}
    if second != null:
        step.places["second_at"] = [second, 0]
    if residual != null:
        step.places["residual_at"] = [residual, 0]
    step.params = {
        "source_channels": source.channels,
        "second_at": 0,
        "second_channels": second.channels if second != null else 0,
        "height": source.height,
        "width": source.width,
        "target_channels": layer.out_channels,
        "taps": layer.kernel_height,
        "dilation": dilation,
        "weights_at": layer.weights,
        "bias_at": layer.bias,
        "relu": 1 if relu else 0,
        "residual_at": -1,
    }
    for read: Tensor in [source, second, residual]:
        if read != null:
            _read(read)
    _write(out)
    return out


func _pool(source: Tensor) -> Tensor:
    if source == null:
        return null
    var out := _tensor(source.channels, ceili(source.height / 2.0), ceili(source.width / 2.0))
    var step := _step("subject_pool", out.height * out.width, source.channels)
    step.bindings = {"source": source, "target": out}
    step.places = {"source_at": [source, 0], "target_at": [out, 0]}
    step.params = {"channels": source.channels, "height": source.height, "width": source.width}
    _read(source)
    _write(out)
    return out


## *source* resampled to the size of *like*, into a new tensor, or into channel
## *channel* of *into*.
func _resample(source: Tensor, like: Tensor, into: Tensor = null, channel: int = 0) -> Tensor:
    if source == null or like == null:
        return null
    var out := into if into != null else _tensor(source.channels, like.height, like.width)
    var step := _step("subject_resample", like.height * like.width, source.channels)
    step.bindings = {"source": source, "target": out}
    step.places = {"source_at": [source, 0], "target_at": [out, channel * like.height * like.width]}
    step.params = {
        "channels": source.channels,
        "source_height": source.height,
        "source_width": source.width,
        "target_height": like.height,
        "target_width": like.width,
    }
    _read(source)
    _write(out)
    return out


func _tensor(channels: int, height: int, width: int) -> Tensor:
    var made := Tensor.new(channels, height, width)
    made.page = 0
    _tensors.append(made)
    return made


func _step(kernel: String, texels: int, channel_groups: int) -> Step:
    var made := Step.new(kernel, ceili(float(texels) / LANES), channel_groups)
    steps.append(made)
    counts[kernel] = counts.get(kernel, 0) + 1
    return made


func _read(tensor: Tensor) -> void:
    tensor.dies = steps.size() - 1


func _write(tensor: Tensor) -> void:
    if tensor.born < 0:
        tensor.born = steps.size() - 1
    tensor.dies = maxi(tensor.dies, steps.size() - 1)


# --- Where each tensor lives ------------------------------------------------


## Places every tensor in the pages by the steps that write and read it, makes
## the pages and the two buffers of the ends, and writes each step's offsets.
func _place() -> void:
    var born_at: Dictionary[int, Array] = {}
    for each: Tensor in _tensors:
        if not born_at.has(each.born):
            born_at[each.born] = []
        born_at[each.born].append(each)
    var live: Array[Array] = []
    for index: int in steps.size():
        for each: Tensor in born_at.get(index, []):
            _take(each, live)
        for page: Array in live:
            page.assign(page.filter(func(held: Tensor) -> bool: return held.dies > index))
    for page: Array in live:
        pages.append(SaCompute.Buffer.new(_zeros(PAGE_FLOATS)))
    input = SaCompute.Buffer.new(_zeros(INPUT_CHANNELS * SIZE * SIZE))
    output = SaCompute.Buffer.new(_zeros(SIZE * SIZE))
    for each: Step in steps:
        for param: String in each.places:
            var place: Array = each.places[param]
            each.params[param] = (place[0] as Tensor).at + int(place[1])


## Puts *tensor* in the first gap of the first page that holds it, opening a
## page when none does. *live* holds each page's tensors, ordered by offset.
func _take(tensor: Tensor, live: Array[Array]) -> void:
    for index: int in live.size():
        var start := _gap(live[index], tensor.floats())
        if start >= 0:
            _put(tensor, live[index], index, start)
            return
    live.append([])
    _put(tensor, live.back(), live.size() - 1, 0)


## Where the first gap of *page* that holds *floats* starts, or -1.
static func _gap(page: Array, floats: int) -> int:
    var start := 0
    for held: Tensor in page:
        if held.at - start >= floats:
            return start
        start = held.at + held.floats()
    return start if PAGE_FLOATS - start >= floats else -1


static func _put(tensor: Tensor, page: Array, index: int, start: int) -> void:
    tensor.page = index
    tensor.at = start
    page.append(tensor)
    page.sort_custom(func(a: Tensor, b: Tensor) -> bool: return a.at < b.at)


static func _zeros(floats: int) -> PackedByteArray:
    var bytes := PackedByteArray()
    bytes.resize(floats * 4)
    return bytes
