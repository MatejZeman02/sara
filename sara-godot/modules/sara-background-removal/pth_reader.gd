## Reads a state dictionary saved in the legacy format of PyTorch before 1.6,
## the format of `u2netp.pth`, without running anything the file says.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The legacy file is four pickles and then the raw storages. The first pickle
## is a magic number, the second the protocol version 1001, the third a
## dictionary that says the storages are little-endian, and the fourth the
## state dictionary, which names each tensor by a storage key. After them a
## fifth pickle lists the storage keys in the order their bytes follow, each a
## little-endian count of elements and then the elements.
##
## A pickle is a program, and a reader that ran it would run whatever a file
## put there, `os.system` as soon as `collections.OrderedDict`. This one is a
## machine of its own that knows twenty-odd opcodes and four globals, and it
## walks each pickle once to check every opcode and every global before it runs
## the first. A file that is a zip, or whose pickle names anything else, is
## refused with [member error] set and [member opcodes_run] still 0. Nothing
## here goes through `bytes_to_var`, and a `REDUCE` builds only an ordered
## dictionary or a tensor's record.
extends RefCounted

## The first pickle of every legacy file, protocol 2 and the magic number
## 0x1950a86a20f9469cfc6c, byte for byte.
const MAGIC := [0x80, 0x02, 0x8A, 0x0A, 0x6C, 0xFC, 0x9C, 0x46, 0xF9, 0x20, 0x6A, 0xA8, 0x50, 0x19, 0x2E]

## The protocol version the second pickle holds.
const PROTOCOL_VERSION := 1001

## The globals a state dictionary of float tensors names, and the bytes an
## element of each storage takes. 0 marks a global that is not a storage.
const GLOBALS: Dictionary[String, int] = {
    "collections OrderedDict": 0,
    "torch._utils _rebuild_tensor_v2": 0,
    "torch FloatStorage": 4,
    "torch LongStorage": 8,
}

## The sentence that says why the file was refused, empty when it was read.
var error: String = ""
## The state dictionary's tensors by name, in the file's order.
var tensors: Dictionary[String, Tensor] = {}
## The opcodes the machine ran. A refused pickle leaves this where the check
## found it, which for a refused state dictionary is 0.
var opcodes_run: int = 0

## Storages the state dictionary named, by key, and the float ones' values.
var _storages: Dictionary[String, Storage] = {}
var _bytes: PackedByteArray = PackedByteArray()
var _at: int = 0


## One tensor of the state dictionary: its name, shape and values, in the
## row-major order PyTorch keeps a contiguous tensor in.
class Tensor:
    extends RefCounted
    var storage: Storage
    var offset: int
    var shape: PackedInt64Array
    var stride: PackedInt64Array
    var values: PackedFloat32Array = PackedFloat32Array()

    func _init(from: Storage, start: int, dims: PackedInt64Array, steps: PackedInt64Array) -> void:
        storage = from
        offset = start
        shape = dims
        stride = steps

    func count() -> int:
        var n := 1
        for d: int in shape:
            n *= d
        return n

    func is_float() -> bool:
        return storage.element_bytes == 4

    ## Whether the strides are those of a row-major tensor of this shape.
    func is_contiguous() -> bool:
        var step := 1
        for i: int in range(shape.size() - 1, -1, -1):
            if shape[i] != 1 and stride[i] != step:
                return false
            step *= shape[i]
        return true


## A storage a tensor points into, named in the pickle by a persistent id.
class Storage:
    extends RefCounted
    var key: String
    var element_bytes: int
    var count: int
    var values: PackedFloat32Array = PackedFloat32Array()

    func _init(name: String, size: int, elements: int) -> void:
        key = name
        element_bytes = size
        count = elements


## A global the pickle named, which the machine never calls.
class Global:
    extends RefCounted
    var name: String

    func _init(called: String) -> void:
        name = called


func _init(bytes: PackedByteArray, label: String = "the file") -> void:
    _bytes = bytes
    error = _read(label)
    _bytes = PackedByteArray()
    if not error.is_empty():
        tensors.clear()


func _read(label: String) -> String:
    if _bytes.is_empty():
        return "%s is empty or could not be read." % label
    if _bytes.size() >= 2 and _bytes[0] == 0x50 and _bytes[1] == 0x4B:
        return "%s is a zip, PyTorch's format since 1.6, and not the legacy format of the U²-NetP weights." % label
    if _bytes.size() < MAGIC.size() or _bytes.slice(0, MAGIC.size()) != PackedByteArray(MAGIC):
        return "%s does not begin with the magic number of PyTorch's legacy format." % label
    # Every pickle is checked before the first opcode of any runs, so a file
    # refused for its fourth pickle has run nothing of its second.
    _at = MAGIC.size()
    for _pickle_index: int in 4:
        var refused := _check(label)
        if not refused.is_empty():
            return refused
    _at = MAGIC.size()
    var version: Variant = _run(label)
    if not error.is_empty():
        return error
    if typeof(version) != TYPE_INT or int(version) != PROTOCOL_VERSION:
        return "%s has protocol version %s, not %d." % [label, str(version), PROTOCOL_VERSION]
    var system: Variant = _run(label)
    if not error.is_empty():
        return error
    if not (system is Dictionary) or (system as Dictionary).get("little_endian") != true:
        return "%s was not saved little-endian." % label
    var state: Variant = _run(label)
    if not error.is_empty():
        return error
    if not (state is Dictionary):
        return "%s holds no state dictionary." % label
    var keys: Variant = _run(label)
    if not error.is_empty():
        return error
    if not (keys is Array):
        return "%s lists no storages after its state dictionary." % label
    for key: Variant in keys:
        var said := _storage(str(key), label)
        if not said.is_empty():
            return said
    for name: Variant in state:
        var tensor: Variant = (state as Dictionary)[name]
        if not (tensor is Tensor):
            return "%s holds %s, which is not a tensor." % [label, str(name)]
        var said := _resolve(tensor as Tensor, str(name), label)
        if not said.is_empty():
            return said
        tensors[str(name)] = tensor
    return ""


## Reads one storage's count and elements, at the place the list says.
func _storage(key: String, label: String) -> String:
    if not _storages.has(key):
        return "%s lists a storage %s its state dictionary never named." % [label, key]
    if _at + 8 > _bytes.size():
        return "%s ends before storage %s." % [label, key]
    var storage: Storage = _storages[key]
    var count := _bytes.decode_s64(_at)
    _at += 8
    var length := count * storage.element_bytes
    if count < 0 or count != storage.count or _at + length > _bytes.size():
        return "%s has storage %s of %d elements where %d were named." % [label, key, count, storage.count]
    if storage.element_bytes == 4:
        storage.values = _bytes.slice(_at, _at + length).to_float32_array()
    _at += length
    return ""


func _resolve(tensor: Tensor, name: String, label: String) -> String:
    if tensor.shape.size() != tensor.stride.size() or not tensor.is_contiguous():
        return "%s holds %s, a tensor that is not contiguous." % [label, name]
    if tensor.offset < 0 or tensor.offset + tensor.count() > tensor.storage.count:
        return "%s holds %s, which runs past its storage." % [label, name]
    if tensor.is_float():
        tensor.values = tensor.storage.values.slice(tensor.offset, tensor.offset + tensor.count())
    return ""


## Walks the pickle at the reading place without running an opcode, moves
## the reading place past it, and answers why it is refused, or empty.
func _check(label: String) -> String:
    var at := _at
    while at < _bytes.size():
        var op := _bytes[at]
        at += 1
        var length := _argument_length(op, at)
        if length < 0:
            return (
                "%s holds pickle opcode 0x%02x, which a state dictionary of float tensors never needs, at byte %d."
                % [label, op, at - 1]
            )
        if op == 0x63:
            var global := _global_at(at)
            if not GLOBALS.has(global):
                return "%s names the global %s, which a state dictionary of float tensors never names." % [label, global]
        if op == 0x80 and _bytes[at] != 2:
            return "%s is pickled with protocol %d, not 2." % [label, _bytes[at]]
        at += length
        if at > _bytes.size():
            return "%s ends inside a pickle." % label
        if op == 0x2E:
            _at = at
            return ""
    return "%s ends inside a pickle." % label


## The bytes the argument of *op* at *at* takes, or -1 for an opcode the
## machine does not know.
func _argument_length(op: int, at: int) -> int:
    match op:
        0x28, 0x74, 0x85, 0x86, 0x87, 0x29, 0x7D, 0x5D, 0x61, 0x65, 0x73, 0x75, 0x4E, 0x88, 0x89, 0x51, 0x52, 0x62, 0x2E:
            return 0
        0x80, 0x4B, 0x71, 0x68:
            return 1
        0x4D:
            return 2
        0x4A, 0x72, 0x6A:
            return 4
        0x58:
            return 4 + int(_bytes.decode_u32(at)) if at + 4 <= _bytes.size() else 4
        0x63:
            var end := at
            for _line: int in 2:
                end = _bytes.find(0x0A, end)
                if end < 0:
                    return _bytes.size()
                end += 1
            return end - at
    return -1


## The global at *at*, as "module name".
func _global_at(at: int) -> String:
    var first := _bytes.find(0x0A, at)
    var second := _bytes.find(0x0A, first + 1) if first >= 0 else -1
    if second < 0:
        return "?"
    return _bytes.slice(at, first).get_string_from_utf8() + " " + _bytes.slice(first + 1, second).get_string_from_utf8()


## Runs a pickle [method _check] passed.
func _run(label: String) -> Variant:
    var stack: Array = []
    var marks: PackedInt64Array = PackedInt64Array()
    var memo: Dictionary[int, Variant] = {}
    while true:
        var op := _bytes[_at]
        _at += 1
        opcodes_run += 1
        match op:
            0x80:
                _at += 1
            0x2E:
                return (
                    stack.pop_back()
                    if stack.size() == 1
                    else _fail("%s leaves %d values where a pickle leaves one." % [label, stack.size()])
                )
            0x4B:
                stack.append(int(_bytes[_at]))
                _at += 1
            0x4D:
                stack.append(int(_bytes.decode_u16(_at)))
                _at += 2
            0x4A:
                stack.append(int(_bytes.decode_s32(_at)))
                _at += 4
            0x58:
                var length := int(_bytes.decode_u32(_at))
                stack.append(_bytes.slice(_at + 4, _at + 4 + length).get_string_from_utf8())
                _at += 4 + length
            0x71, 0x72:
                var slot := int(_bytes[_at]) if op == 0x71 else int(_bytes.decode_u32(_at))
                _at += 1 if op == 0x71 else 4
                if stack.is_empty():
                    return _fail("%s puts an empty stack in its memo." % label)
                memo[slot] = stack.back()
            0x68, 0x6A:
                var slot := int(_bytes[_at]) if op == 0x68 else int(_bytes.decode_u32(_at))
                _at += 1 if op == 0x68 else 4
                if not memo.has(slot):
                    return _fail("%s gets memo %d, which it never put." % [label, slot])
                stack.append(memo[slot])
            0x28:
                marks.append(stack.size())
            0x74:
                if marks.is_empty():
                    return _fail("%s closes a tuple it never opened." % label)
                var start := int(marks[marks.size() - 1])
                marks.remove_at(marks.size() - 1)
                var items := stack.slice(start)
                stack.resize(start)
                stack.append(items)
            0x85, 0x86, 0x87:
                var n := op - 0x84
                if stack.size() < n:
                    return _fail("%s makes a tuple of values it does not have." % label)
                var items := stack.slice(stack.size() - n)
                stack.resize(stack.size() - n)
                stack.append(items)
            0x29:
                stack.append([])
            0x7D:
                stack.append({})
            0x5D:
                stack.append([])
            0x4E:
                stack.append(null)
            0x88:
                stack.append(true)
            0x89:
                stack.append(false)
            0x63:
                var global := _global_at(_at)
                _at += _argument_length(op, _at)
                stack.append(Global.new(global))
            0x61, 0x65, 0x73, 0x75:
                var said := _fill(op, stack, marks, label)
                if not said.is_empty():
                    return _fail(said)
            0x51:
                if stack.is_empty():
                    return _fail("%s has a persistent id with no value." % label)
                var storage := _named_storage(stack.pop_back(), label)
                if storage == null:
                    return null
                stack.append(storage)
            0x52:
                if stack.size() < 2:
                    return _fail("%s calls with no arguments." % label)
                var arguments: Variant = stack.pop_back()
                var called: Variant = stack.pop_back()
                var made: Variant = _reduce(called, arguments, label)
                if not error.is_empty():
                    return null
                stack.append(made)
            0x62:
                if stack.size() < 2 or not (stack[stack.size() - 2] is Dictionary):
                    return _fail("%s builds something that is not its ordered dictionary." % label)
                # The state is the dictionary's `_metadata`, the versions of
                # the modules that saved it, which the fold has no use for.
                stack.pop_back()
    return null


func _fill(op: int, stack: Array, marks: PackedInt64Array, label: String) -> String:
    var start := stack.size() - (1 if op == 0x61 else 2)
    if op == 0x65 or op == 0x75:
        if marks.is_empty():
            return "%s fills a container with no mark." % label
        start = int(marks[marks.size() - 1])
        marks.remove_at(marks.size() - 1)
    if start < 1:
        return "%s fills a container it does not have." % label
    var items := stack.slice(start)
    stack.resize(start)
    var into: Variant = stack.back()
    if op == 0x61 or op == 0x65:
        if not (into is Array):
            return "%s appends to something that is not a list." % label
        (into as Array).append_array(items)
        return ""
    if not (into is Dictionary) or items.size() % 2 != 0:
        return "%s sets items in something that is not a dictionary." % label
    for i: int in range(0, items.size(), 2):
        (into as Dictionary)[items[i]] = items[i + 1]
    return ""


## The storage a persistent id names, `('storage', type, key, location, count,
## view)`, made once per key.
func _named_storage(id: Variant, label: String) -> Storage:
    if not (id is Array) or (id as Array).size() < 5 or (id as Array)[0] != "storage" or not ((id as Array)[1] is Global):
        _fail("%s has a persistent id that is not a storage." % label)
        return null
    var kind: String = ((id as Array)[1] as Global).name
    if GLOBALS.get(kind, 0) == 0:
        _fail("%s has a storage of type %s." % [label, kind])
        return null
    var key := str((id as Array)[2])
    if not _storages.has(key):
        _storages[key] = Storage.new(key, GLOBALS[kind], int((id as Array)[4]))
    return _storages[key]


## What `REDUCE` makes of *called* and *arguments*: an ordered dictionary or a
## tensor's record, and nothing else.
func _reduce(called: Variant, arguments: Variant, label: String) -> Variant:
    if not (called is Global) or not (arguments is Array):
        return _fail("%s calls something that is not a global." % label)
    var name: String = (called as Global).name
    var given: Array = arguments
    if name == "collections OrderedDict" and given.is_empty():
        return {}
    if (
        name == "torch._utils _rebuild_tensor_v2"
        and given.size() >= 4
        and given[0] is Storage
        and given[2] is Array
        and given[3] is Array
    ):
        return Tensor.new(given[0], int(given[1]), PackedInt64Array(given[2]), PackedInt64Array(given[3]))
    return _fail("%s calls %s in a way a state dictionary never does." % [label, name])


func _fail(line: String) -> Variant:
    if error.is_empty():
        error = line
    return null
