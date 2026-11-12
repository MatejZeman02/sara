## U²-NetP's weights as the network's kernels read them: every batch norm
## folded into the convolution before it, and every convolution's weights and
## bias in one storage buffer with a table of where each starts.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A norm after a convolution is, at inference, one scale and one shift per
## output channel, so it costs no kernel of its own once it is folded in when
## the weights are loaded. For output channel o, with the norm's weight g,
## bias β, running mean μ and running variance σ²:
##
##     s[o]  = g[o] / sqrt(σ²[o] + ε)
##     W'[o] = W[o] · s[o]
##     b'[o] = (b[o] − μ[o]) · s[o] + β[o]
##
## worked in double precision and rounded to float once. A convolution with no
## norm after it, a side output or the fusing 1×1, keeps its own weights.
##
## The buffer is floats, convolution after convolution in the state
## dictionary's order, each its weights in PyTorch's own order, output channel,
## input channel, row and column, and then its bias. [member convolutions] says
## where each starts, counted in floats. The upload is once: [method upload]
## answers the same buffer however often it is asked.
extends RefCounted

const PthReader := preload("pth_reader.gd")

## The norms' epsilon. U-2-Net's `model/u2net.py` at `ac7e1c817` builds
## every norm as `nn.BatchNorm2d(out_ch)` in `REBNCONV`, with no epsilon of its
## own, so it is PyTorch's default, the 1e-5 of `BatchNorm2d`'s signature.
const EPSILON := 1e-5

## Buffers made by [method upload] in this session, over every set of weights,
## which a suite reads to know a second ask made none.
static var uploads: int = 0

## Why the weights could not be folded, empty when they were.
var error: String = ""
## Every convolution, in the state dictionary's order.
var convolutions: Array[Convolution] = []
## The norms folded, each into the convolution before it.
var norms_folded: int = 0
## The buffer's contents.
var values: PackedFloat32Array = PackedFloat32Array()

var _buffer: SaCompute.Buffer = null


## One convolution's place in the buffer and its shape.
class Convolution:
    extends RefCounted
    ## Its name in the state dictionary, without `.weight`.
    var name: String
    var out_channels: int
    var in_channels: int
    var kernel_height: int
    var kernel_width: int
    ## Where its weights start in the buffer, in floats.
    var weights: int
    ## Where its bias starts, in floats, `out_channels` of them.
    var bias: int
    ## The name of the norm folded into it, empty when it had none.
    var norm: String

    func _init(called: String, shape: PackedInt64Array, at: int, folded: String) -> void:
        name = called
        out_channels = shape[0]
        in_channels = shape[1]
        kernel_height = shape[2]
        kernel_width = shape[3]
        weights = at
        bias = at + weight_count()
        norm = folded

    func weight_count() -> int:
        return out_channels * in_channels * kernel_height * kernel_width


func _init(reader: PthReader) -> void:
    error = reader.error if not reader.error.is_empty() else _fold(reader.tensors)
    if not error.is_empty():
        convolutions.clear()
        values = PackedFloat32Array()


## The buffer, made the first time it is asked for and the same buffer after.
## Null when the weights were refused or there is no rendering device.
func upload() -> SaCompute.Buffer:
    if _buffer == null and error.is_empty() and not values.is_empty():
        _buffer = SaCompute.Buffer.new(values.to_byte_array())
        uploads += 1
    return _buffer


## The convolution named *name*, or null.
func named(name: String) -> Convolution:
    for each: Convolution in convolutions:
        if each.name == name:
            return each
    return null


func _fold(tensors: Dictionary[String, PthReader.Tensor]) -> String:
    var pending: Array[Dictionary] = []
    for name: String in tensors:
        var tensor: PthReader.Tensor = tensors[name]
        if not name.ends_with(".weight"):
            continue
        var prefix := name.trim_suffix(".weight")
        if tensor.shape.size() == 4:
            if not tensor.is_float():
                return "%s is not a float tensor." % name
            var bias: PthReader.Tensor = tensors.get(prefix + ".bias")
            if bias != null and bias.count() != tensor.shape[0]:
                return "%s has a bias of %d values for %d output channels." % [prefix, bias.count(), tensor.shape[0]]
            pending.append({"name": prefix, "weight": tensor, "bias": bias, "norm": ""})
        elif tensors.has(prefix + ".running_var"):
            var said := _fold_norm(pending, prefix, tensors)
            if not said.is_empty():
                return said
    if pending.is_empty():
        return "The file holds no convolution."
    var total := 0
    for each: Dictionary in pending:
        total += (each["weight"] as PthReader.Tensor).count() + (each["weight"] as PthReader.Tensor).shape[0]
    values.resize(total)
    var at := 0
    for each: Dictionary in pending:
        var weight: PthReader.Tensor = each["weight"]
        var convolution := Convolution.new(each["name"], weight.shape, at, each["norm"])
        _write(convolution, weight, each)
        convolutions.append(convolution)
        at = convolution.bias + convolution.out_channels
    return ""


## Marks the convolution before the norm *prefix* as folded with it, keeping
## the norm's scale and shift per output channel.
func _fold_norm(pending: Array[Dictionary], prefix: String, tensors: Dictionary[String, PthReader.Tensor]) -> String:
    if pending.is_empty() or not (pending.back()["norm"] as String).is_empty():
        return "The norm %s follows no convolution of its own." % prefix
    var before: Dictionary = pending.back()
    var channels: int = (before["weight"] as PthReader.Tensor).shape[0]
    var parts: Array[PackedFloat32Array] = []
    for part: String in ["weight", "bias", "running_mean", "running_var"]:
        var tensor: PthReader.Tensor = tensors.get(prefix + "." + part)
        if tensor == null or not tensor.is_float() or tensor.count() != channels:
            return "The norm %s has no %s of %d values for %s." % [prefix, part, channels, before["name"]]
        parts.append(tensor.values)
    var scale := PackedFloat64Array()
    var shift := PackedFloat64Array()
    scale.resize(channels)
    shift.resize(channels)
    for o: int in channels:
        scale[o] = parts[0][o] / sqrt(float(parts[3][o]) + EPSILON)
        shift[o] = parts[1][o] - parts[2][o] * scale[o]
    before["norm"] = prefix
    before["scale"] = scale
    before["shift"] = shift
    norms_folded += 1
    return ""


## Writes one convolution's folded weights and bias at its place.
func _write(convolution: Convolution, weight: PthReader.Tensor, pending: Dictionary) -> void:
    var source := weight.values
    var bias: PthReader.Tensor = pending["bias"]
    var per_channel := convolution.in_channels * convolution.kernel_height * convolution.kernel_width
    var folded := not convolution.norm.is_empty()
    var scale: PackedFloat64Array = pending.get("scale", PackedFloat64Array())
    var shift: PackedFloat64Array = pending.get("shift", PackedFloat64Array())
    for o: int in convolution.out_channels:
        var s: float = scale[o] if folded else 1.0
        var start := o * per_channel
        for i: int in range(start, start + per_channel):
            values[convolution.weights + i] = source[i] * s
        var b: float = bias.values[o] if bias != null else 0.0
        values[convolution.bias + o] = b * s + shift[o] if folded else b
