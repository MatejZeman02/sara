## Filter > Colour > LUT, a `.cube` file as a colour lookup table.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A 3D LUT loader for `.cube` files, so a grade made in another program
## applies in Sara. The dialog has one button that opens
## the picker on `.cube` files and a line that names the file loaded, or says
## why a file was refused. Every output texel reads only its own input texel, so
## this is a point filter: the kernel is `lut.gmacs` and keeps the contract on
## `SaPointPass`, with the table in a storage buffer at binding 2.
##
## The table maps the document's encoded RGB view, the values a painter sees,
## which is what a grade made in another program is written for, and an Oklab
## document is taken to that view first and back after. The lookup is
## trilinear, and a value outside the file's domain keeps the distance it lay
## beyond the edge, so nothing clamps (hard rule 5).
##
## The record carries the table, so a document saved with the filter attached
## reopens with the same look when the file has gone: the entries as float32
## bytes in base64 under `table`, with the file's `size`, its `domain` and its
## `name`. A 33 sided table is about 575 kilobytes of text and a 65 sided one
## about 4.4 megabytes, which is why nothing larger is read.
class_name SaLutFilter
extends SaFilter

const SHADER := "sara-base-modules/lut"
const KERNEL := "lut"

## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 0
## The binding the kernel reads the table at.
const TABLE_BINDING := 2
## The sides a table may have. Two is the least a trilinear lookup can mix.
const SIZE_MIN := 2
const SIZE_MAX := 65
## The floats before the entries in the buffer: the domain's low then high end.
const DOMAIN_FLOATS := 6

const DEFAULTS := {"table": "", "size": 0, "domain": [0.0, 0.0, 0.0, 1.0, 1.0, 1.0], "name": ""}

## The tables made so far, by the record's own text, newest last, so a rerun on
## every slider frame binds one buffer and a record that comes back finds its
## own. A few only: each is up to a few megabytes of VRAM.
const KEPT := 4
var _buffers: Dictionary[String, SaCompute.Buffer] = {}
var _identity: SaCompute.Buffer = null


func title() -> String:
    return "LUT"


## Listed under Colour, beside Colour Lookup.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Grade the picture with a colour lookup table from a .cube file."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.parameter_value(&"table", DEFAULTS["table"])
    ui.parameter_value(&"size", DEFAULTS["size"])
    ui.parameter_value(&"domain", DEFAULTS["domain"])
    ui.parameter_value(&"name", DEFAULTS["name"])
    ui.custom("", _make_panel).named(&"table_file")


func run(ctx: SaFilterContext) -> void:
    var values := parameters()
    var buffer := _buffer_for(values)
    if buffer == null:
        return
    var space := ctx.document.color_space if ctx.document != null else null
    var size := float(maxi(int(values.get("size", 0)), SIZE_MIN)) if _has_table(values) else float(SIZE_MIN)
    ctx.point_pass(SHADER, KERNEL, push_for(size, space), {TABLE_BINDING: buffer}, ORIGIN_SLOT)


## The 108-byte push constant `lut.gmacs` reads, for a table of *size* entries a
## side on a document stored in *space*: the region's origin, which the runner
## writes at [constant ORIGIN_SLOT], the size, a spare, then the colour space
## tail exactly as `SaColorSpacePushConstant` writes it.
static func push_for(size: float, space: SaColorSpace) -> PackedFloat32Array:
    var push := PackedFloat32Array([0.0, 0.0, size, 0.0])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push


## The values a record keeps for *cube*, what [method Cube.parse] answered, and
## the file name *name* it came from.
static func values_for(cube: Cube, name: String) -> Dictionary:
    var floats := PackedFloat32Array(cube.domain_min)
    floats.append_array(cube.domain_max)
    var domain: Array = []
    for value in floats:
        domain.append(value)
    return {"table": Marshalls.raw_to_base64(cube.entries.to_byte_array()), "size": cube.size, "domain": domain, "name": name}


## The storage buffer's floats for a record's *values*: the domain, then the
## entries. Empty when the record holds no table.
static func buffer_floats(values: Dictionary) -> PackedFloat32Array:
    if not _has_table(values):
        return PackedFloat32Array()
    var domain: Array = values.get("domain", DEFAULTS["domain"])
    var out := PackedFloat32Array()
    for index in DOMAIN_FLOATS:
        out.append(float(domain[index]) if index < domain.size() else float(DEFAULTS["domain"][index]))
    var entries := Marshalls.base64_to_raw(String(values.get("table", ""))).to_float32_array()
    var wanted := 3 * int(pow(float(int(values.get("size", 0))), 3.0))
    if entries.size() != wanted:
        return PackedFloat32Array()
    out.append_array(entries)
    return out


## The identity table of two entries a side, in the buffer's own layout, which
## the filter binds before any file is loaded so that it changes nothing.
static func identity_floats() -> PackedFloat32Array:
    var out := PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
    for b in 2:
        for g in 2:
            for r in 2:
                out.append_array(PackedFloat32Array([float(r), float(g), float(b)]))
    return out


static func _has_table(values: Dictionary) -> bool:
    return int(values.get("size", 0)) >= SIZE_MIN and not String(values.get("table", "")).is_empty()


func _buffer_for(values: Dictionary) -> SaCompute.Buffer:
    var floats := buffer_floats(values)
    if floats.is_empty():
        if _identity == null:
            _identity = SaCompute.Buffer.new(identity_floats().to_byte_array())
        return _identity if _identity.rid.is_valid() else null
    var key := "%s:%d" % [String(values["table"]).sha1_text(), int(values["size"])]
    if _buffers.has(key):
        return _buffers[key]
    var made := SaCompute.Buffer.new(floats.to_byte_array())
    if not made.rid.is_valid():
        return null
    if _buffers.size() >= KEPT:
        _buffers.erase(_buffers.keys()[0])
    _buffers[key] = made
    return made


## What `ui.custom` calls: the button and the line under it.
func _make_panel(rerun: Callable) -> Control:
    var panel := LutPanel.new(self)
    panel.loaded.connect(rerun)
    return panel


## The dialog's one row, a button that opens the picker on `.cube` files and
## the line that names what was loaded or why a file was refused.
class LutPanel:
    extends VBoxContainer

    signal loaded

    var _filter: SaLutFilter = null
    var _button: Button = null
    var _line: Label = null

    func _init(filter: SaLutFilter) -> void:
        _filter = filter
        name = "LutPanel"
        _button = SaMake.button(
            self, "LutLoad", tr("Load .cube file..."), tr("Pick a .cube file and keep its table in this filter.")
        )
        _button.pressed.connect(_ask)
        _line = SaMake.label(self, "LutLine")
        _line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _line.custom_minimum_size.x = 240.0
        _say()
        _filter.store.changed.connect(_say)

    ## The picker, over this button, on the format's one extension.
    func _ask() -> void:
        var filters := PackedStringArray(["*.cube ; Colour lookup table"])
        SaFilePicker.open(_button, SaFilePicker.Mode.OPEN_FILE, filters, load_file, "Load a .cube file")

    ## Reads *path* and, when it parses, keeps its table in the record. A file
    ## that does not is refused with a line naming it and what was wrong, and
    ## the record keeps what it had.
    func load_file(path: String) -> void:
        var cube := SaLutFilter.Cube.parse(FileAccess.get_file_as_string(path))
        var file := path.get_file()
        if cube.problem != "":
            SaProblems.refuse("SaLutFilter", tr("%s: %s") % [file, cube.problem])
            _say("%s: %s" % [file, cube.problem])
            return
        var kept := SaLutFilter.values_for(cube, file)
        for key: String in kept:
            _filter.write_parameter(StringName(key), kept[key])
        _say()
        loaded.emit()

    func _say(text: String = "") -> void:
        if _line == null:
            return
        if not text.is_empty():
            _line.text = text
            return
        var kept := String(_filter.parameter(&"name"))
        var side := int(_filter.parameter(&"size"))
        _line.text = (
            tr_n("%s, %d a side", "%s, %d a side", side) % [kept, side] if not kept.is_empty() else tr("No table loaded.")
        )


## What a `.cube` file says, read once. The text format's lines are `TITLE`,
## `DOMAIN_MIN` and `DOMAIN_MAX` with three numbers, `LUT_3D_INPUT_RANGE` with
## two, `LUT_3D_SIZE` with one, comments from a `#`, and then size cubed rows
## of three numbers, red running fastest. A file that does not read has its
## reason in [member problem], with the line it was found on when there is one.
class Cube:
    extends RefCounted

    var size: int = 0
    var domain_min: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
    var domain_max: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
    var entries: PackedFloat32Array = PackedFloat32Array()
    var title: String = ""
    var problem: String = ""

    static func parse(text: String) -> Cube:
        var cube := Cube.new()
        var line_no := 0
        for raw in text.split("\n"):
            line_no += 1
            var line := raw.strip_edges()
            if line.is_empty() or line.begins_with("#"):
                continue
            var words := line.split(" ", false) if not line.contains("\t") else line.replace("\t", " ").split(" ", false)
            var said := cube._read_line(line, words)
            if said != "":
                cube.problem = "line %d, %s" % [line_no, said]
                return cube
        cube._finish()
        return cube

    ## Reads one line, answers what is wrong with it or "".
    func _read_line(line: String, words: PackedStringArray) -> String:
        var head := words[0]
        if head == "TITLE":
            title = line.substr(5).strip_edges().trim_prefix('"').trim_suffix('"')
            return ""
        if head == "LUT_1D_SIZE" or head == "LUT_1D_INPUT_RANGE":
            return "this is a 1D table and only 3D tables are read"
        if head == "LUT_3D_SIZE":
            if words.size() != 2 or not words[1].is_valid_int():
                return "LUT_3D_SIZE wants one whole number"
            var asked := words[1].to_int()
            if asked < SaLutFilter.SIZE_MIN or asked > SaLutFilter.SIZE_MAX:
                return "a table of %d a side is outside %d to %d" % [asked, SaLutFilter.SIZE_MIN, SaLutFilter.SIZE_MAX]
            size = asked
            return ""
        if head == "LUT_3D_INPUT_RANGE":
            var pair := _numbers(words, 1)
            if pair.size() != 2:
                return "LUT_3D_INPUT_RANGE wants two numbers"
            if pair[1] <= pair[0]:
                return "LUT_3D_INPUT_RANGE high is not above low"
            domain_min = PackedFloat32Array([pair[0], pair[0], pair[0]])
            domain_max = PackedFloat32Array([pair[1], pair[1], pair[1]])
            return ""
        if head == "DOMAIN_MIN" or head == "DOMAIN_MAX":
            var triple := _numbers(words, 1)
            if triple.size() != 3:
                return "%s wants three numbers" % head
            if head == "DOMAIN_MIN":
                domain_min = triple
            else:
                domain_max = triple
            return ""
        if head.begins_with("LUT_") or head.begins_with("DOMAIN_"):
            return "the keyword %s is not one this reads" % head
        if size == 0:
            return "a row of numbers comes before LUT_3D_SIZE"
        var row := _numbers(words, 0)
        if row.size() != 3:
            return "a row wants three numbers"
        entries.append_array(row)
        return ""

    func _finish() -> void:
        if size == 0:
            problem = "there is no LUT_3D_SIZE line"
            return
        var wanted := size * size * size
        if entries.size() != 3 * wanted:
            problem = "a table of %d a side holds %d rows and this has %d" % [size, wanted, floori(entries.size() / 3.0)]
            return
        for axis in 3:
            if domain_max[axis] <= domain_min[axis]:
                problem = "DOMAIN_MAX is not above DOMAIN_MIN"
                return

    ## *words* from *from* on as numbers, or fewer than they are when one is not.
    static func _numbers(words: PackedStringArray, from: int) -> PackedFloat32Array:
        var out := PackedFloat32Array()
        for index in range(from, words.size()):
            if not words[index].is_valid_float():
                return PackedFloat32Array()
            out.append(words[index].to_float())
        return out
