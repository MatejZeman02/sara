## A filter with no class file: one pixel function on disk, and the dialog
## generated from its `uniform` lines.
##
## The shortest door: a module registers the file and the dialog is generated,
## so this is what a module hands to `ctx.register_filter`. There is
## no subclass to write and nothing to override: the title comes from the file
## name, the widgets come from the declarations, `run` is the wrapper's
## dispatch, and `problem` is the kernel's compile error. A student who wants
## more than that writes an `SaFilter` instead, which is the longer door and the
## same registration.
##
## **A widget per uniform, and the widget follows the type.** A scalar becomes
## an [SaSlider] over the bounds its `hint_range` declared, or the older range
## comment's, opening at the value the line declared and stepping by the hint's
## step when it gave one. An `int` with a `hint_enum` becomes a drop-down of its
## labels instead, and the kernel gets the picked entry's index, as in Godot. A
## `bool` becomes a checkbox. A `vec3` or a `vec4` tagged `source_color` becomes
## the dialog's colour swatch, and the kernel gets the very numbers the swatch
## shows, with none of Godot's conversion to linear light. A source with no hint
## on any line keeps the older rule, every `vec3` and `vec4` a swatch, because
## three or four floats between zero and one is what a student wrote for a
## colour before the tag, and a saved kernel keeps its swatch. Once a source
## hints anything it is read Godot's way, and an untagged vector keeps the
## value its line declared with no widget, as a `vec2` does.
## A `vec2` has no widget: it is a pair with no meaning this file can guess, and
## inventing one would be this file deciding something the source did not. It
## keeps the value the line declared, and the record says so.
##
## **A matrix is a grid of numbers.** `uniform float weights[9]` is a 3 by 3
## grid of number fields, `[25]` a 5 by 5 and `[49]` a 7 by 7, read row by row
## the way the kernel indexes `weights[row * 3 + column]`. The size is the
## length the line declared, so there is no size to pick. A field takes a number
## or a fraction such as `1/9`, and shows four decimals while it keeps every one
## it was given. The kernel is handed the numbers whole, and the dialect moves a
## matrix that does not fit the push constant into a buffer on its own.
##
## **The bounds are widened rather than the value clamped.** `SaSlider.make`
## clamps its default into the hard range, so a `uniform float gain = 4.0` with
## no range, whose parsed bounds are the parser's own 0 to 1, would open at 1
## and silently lose the student's four. The hard range is therefore stretched
## to cover the declared value, which leaves a ranged uniform whose default sits
## inside its range exactly on the range's numbers.
class_name SaPixelFilter
extends SaFilter

## The wrapper, preloaded by path for the reason its own file gives.
const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

## The most decimals a slider is written with, for a step such as a third that
## no count of decimals writes exactly.
const MOST_DECIMALS: int = 6

## The types that become a slider.
const SCALAR_TYPES: Array[String] = ["float", "int", "uint"]

## The dialect's reading of a `uniform` line, for the colour hint and the types
## that become a colour.
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

## How far a pixel function reads when a uniform says, see [member margin].
const PixelNeighbourhood := preload("res://core/custom-shader/dialect/sa_pixel_neighbourhood.gd")

## The decimals a matrix's field shows. The number it holds keeps all of them,
## so a ninth typed as `1/9` is a ninth in the kernel and 0.1111 on screen.
const MATRIX_DECIMALS: int = 4

## The pixel function this filter is, loaded and compiled at construction.
##
## Compiled here rather than lazily, so a file with a mistake in it is already
## known to be broken by the time the Filter menu asks [method problem] and the
## row is dimmed on the first fill rather than on the second.
var pixels: PixelFunction = null

## Uniform name -> the row that holds its value, as [method build] declared
## them. Empty until the dialog is built, and rebuilt whole on every build.
var widgets: Dictionary[String, SaPageRow] = {}

## How far past the run's rectangle [method run] reads, for a kernel whose
## `src` looks at a neighbourhood. Zero for a function that reads only `at`,
## which then runs in place, so a function that reads a neighbour declares how
## far or reads texels the run may already have written.
##
## A uniform whose line carries `hint_reach` sets it instead, run by run, so a
## blur pads by the radius its slider holds rather than by a number fixed at
## registration. Written on the line rather than handed here because the line is
## where the slider is declared, and a file registered with only its path, as a
## notebook's cell is, has nowhere else to say it. `sa_pixel_neighbourhood.gd`
## reads the hint.
var margin: int = 0

## The entry's text, in the Filter menu and in the command list.
##
## Public and a constructor argument, because a filter with no class file has no
## `title()` to override and a private read back through one is the getter shape
## `tests/test_privates_rule.gd` counts. Written by this class alone, in `_init`.
var entry_title: String = ""

## The Filter menu's section the entry is listed in, empty for Other. A
## constructor argument for the reason [member entry_title] gives, so a built-in
## pixel function keeps the section its written class had.
var entry_family: StringName = &""


## The filter for the pixel function at *file_path*.
##
## *filter_title* names the menu entry, and defaults to the file's own name
## made readable, so `threshold.gmacs` is "Threshold" and `box_blur.gmacs` is
## "Box blur" with nothing declared at all. *filter_family* is the section,
## see [member entry_family].
##
## A file whose reach follows a uniform is never the point form, whatever
## *read_margin* says, since it reads its neighbours. Decided once, here, so a
## student who adds the hint to a file Sara has open restarts to have it pad.
func _init(file_path: String, filter_title: String = "", read_margin: int = 0, filter_family: StringName = &"") -> void:
    pixels = PixelFunction.new(file_path, "", true, read_margin == 0)
    if pixels.in_place and not PixelNeighbourhood.reaching(pixels.uniforms).is_empty():
        pixels = PixelFunction.new(file_path, "", true, false)
    pixels.compile()
    entry_title = filter_title if not filter_title.is_empty() else title_for(pixels.stem)
    margin = read_margin
    entry_family = filter_family


## `threshold` as "Threshold" and `box_blur` as "Box blur": the underscores are
## spaces and the first letter is a capital, which is how every other entry in
## the Filter menu is written.
static func title_for(stem: String) -> String:
    var words := stem.replace("_", " ").strip_edges()
    if words.is_empty():
        return "Filter"
    return words.substr(0, 1).to_upper() + words.substr(1)


func title() -> String:
    return entry_title


func family() -> StringName:
    return entry_family


## The first paragraph of the pixel function's own leading comment.
##
## A pixel filter has no class file to write a [method SaFilter.sentence] in, and
## the `.gmacs` it was made from already opens with a comment saying what it is,
## the way every shipped kernel does. So the sentence is that comment's first
## paragraph: the `#` lines at the top up to the first bare `#` or the first line
## of code, joined, with the licence line left out. A file with no leading comment
## answers empty, and the menu says who registered it instead.
##
## Read off the file on disk rather than kept, for the reason [method build]
## gives about the uniforms: a student who edits the comment expects the next
## registration to say what they wrote.
func sentence() -> String:
    return leading_sentence(FileAccess.get_file_as_string(pixels.path) if pixels != null else "")


## The first paragraph of *raw_text*'s leading comment, or empty. Static so a test
## can hand it text with no file behind it.
static func leading_sentence(raw_text: String) -> String:
    var words := PackedStringArray()
    for line in raw_text.replace("\r\n", "\n").split("\n"):
        var trimmed := line.strip_edges()
        if not trimmed.begins_with("#"):
            break
        var said := trimmed.substr(1).strip_edges()
        if said.is_empty():
            if not words.is_empty():
                break
            continue
        if said.begins_with("SPDX-License-Identifier"):
            continue
        words.append(said)
    return " ".join(words)


## Declares the preview, a widget per uniform, the time row when the function
## reads `t`, and the two buttons.
##
## Read from `pixels.uniforms` on every build rather than kept, because
## [method problem] rereads a file that has changed and a student who added a
## slider expects it on the next open.
func build(ui: SaDialog) -> void:
    widgets = {}
    ui.title(entry_title)
    ui.preview()
    var tagged := any_hinted(pixels.uniforms)
    for raw_field: Variant in pixels.uniforms:
        var field := SaTyped.strings(raw_field)
        var made := _widget_for(ui, field, tagged)
        if made != null:
            widgets[SaTyped.text_at(field, "name", "")] = made
    if pixels.reads_time:
        SaTimeRow.declare(ui)
    ui.apply_cancel()


## Records the generated kernel as a pass, with the widgets' values and the
## document's colour space, so the compositor previews it, Apply walks it over
## the layer, and an Attach or an adjustment layer of it runs in the chain as
## every built-in filter's does. With no [member margin] it is a point pass run
## in place, as every built-in point filter's is, and otherwise a neighbourhood
## pass of the margin.
##
## It once dispatched into `ctx.show`, which a preview and an Apply took and the
## chain could not: a record of a pixel function was skipped, as having no
## pass, and the dialog dimmed Layer. Nothing here touches a
## chunk and nothing reads a texel back. The pass reads as far as the reach
## uniform holds when one carries `hint_reach`, and [member margin] otherwise.
func run(ctx: SaFilterContext) -> void:
    if pixels.compute == null:
        SaProblems.report("SaPixelFilter", tr("%s has no compiled kernel to record.") % pixels.path.get_file())
        return
    var space: SaColorSpace = ctx.document.color_space if ctx.document != null else null
    var held := values()
    var params := pixels.pass_params(held, space)
    var buffers := pixels.carried(params)
    if pixels.in_place:
        ctx.point_pass(pixels.shader_name, pixels.stem, pixels.point_push(params), buffers, pixels.origin_slot())
        return
    var reaching := PixelNeighbourhood.reaching(pixels.uniforms)
    var reach := margin if reaching.is_empty() else PixelNeighbourhood.reach(reaching, held)
    ctx.neighbourhood_pass(pixels.shader_name, pixels.stem, params, reach, buffers)


## What each uniform is worth right now, as the kernel wants it, and `t`, the
## time the time row holds, when the function reads it.
##
## A uniform whose widget was never declared is absent, so the wrapper's `run`
## falls back to the value the line declared, which is what a `vec2` gets.
func values() -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {}
    if pixels.reads_time:
        out[PixelSource.TIME_FIELD] = maxf(SaTyped.real(parameter(SaFilter.Store.TIME), 0.0), 0.0)
    for raw_field: Variant in pixels.uniforms:
        var field := SaTyped.strings(raw_field)
        var field_name := SaTyped.text_at(field, "name", "")
        var found: Variant = widgets.get(field_name)
        var row: SaPageRow = found if found is SaPageRow else null
        if row == null:
            continue
        if SaTyped.int_at(field, "length", 0) != 0:
            out[field_name] = _matrix_of(row.read(), field["default"])
        else:
            out[field_name] = _value_of(SaTyped.text_at(field, "type", ""), row.read())
    return out


## Why this filter cannot run, or "" when it can.
##
## The file's own problems come first, because a file that declares a type the
## packer cannot measure was never compiled and glslang therefore said nothing
## about it. The reread is what makes a fixed file live again on the next open.
func problem() -> String:
    pixels.reload_if_changed()
    if not pixels.problems.is_empty():
        return String(pixels.problems[0])
    return pixels.first_error()


## Whether any of *fields* carries a hint, which is what tells a source written
## Godot's way from one written before the hints, whose vectors are all colours.
static func any_hinted(fields: Array) -> bool:
    for raw_field: Variant in fields:
        var field := SaTyped.strings(raw_field)
        var hints: Dictionary = field.get("hints", {})
        if not hints.is_empty():
            return true
    return false


## Whether *field* is a colour swatch, in a source whose lines are *tagged*
## when any of them carries a hint.
static func is_swatch(field: Dictionary[String, Variant], tagged: bool) -> bool:
    if not SaTyped.text_at(field, "type", "") in PixelSource.COLOUR_TYPES:
        return false
    if not tagged:
        return true
    var hints: Dictionary = field.get("hints", {})
    return hints.has(PixelSource.COLOUR_HINT)


## The widget one `uniform` line earns, or null for a type with none.
func _widget_for(ui: SaDialog, field: Dictionary[String, Variant], tagged: bool) -> SaPageRow:
    var type_name := SaTyped.text_at(field, "type", "")
    var label := title_for(SaTyped.text_at(field, "name", ""))
    if SaTyped.int_at(field, "length", 0) != 0:
        return _grid_for(ui, field)
    if is_swatch(field, tagged):
        return ui.color(label, _colour_of(field["default"]))
    if type_name == "bool":
        var ticked: bool = field["default"] == true
        return ui.checkbox(label, ticked)
    var choices: PackedStringArray = field.get("choices", PackedStringArray())
    if type_name == "int" and not choices.is_empty():
        return ui.dropdown(label, Array(choices), SaTyped.int_at(field, "default", 0))
    if not type_name in SCALAR_TYPES:
        return null
    var declared := SaTyped.float_at(field, "default", 0.0)
    var low := SaTyped.float_at(field, "minimum", 0.0)
    var high := SaTyped.float_at(field, "maximum", 0.0)
    var step := SaTyped.float_at(field, "step", 0.0)
    var options := {"hard_min": minf(low, declared), "hard_max": maxf(high, declared)}
    var hints: Dictionary = field.get("hints", {})
    if hints.has(PixelNeighbourhood.REACH_HINT):
        # The reach's own most, so a radius can be typed past where the drag
        # stops, as far as the gather may pad.
        options["hard_max"] = maxf(maxf(high, declared), float(PixelNeighbourhood.ceiling(field)))
    if type_name != "float":
        # A count of anything is whole, whatever the range was written as, and
        # a slider that offered a radius of 3.47 would be offering something
        # the kernel cannot hold. A step the hint gave is whole too.
        options["step"] = maxf(roundf(step), 1.0)
        options["decimals"] = 0
    elif step > 0.0:
        # As many decimals as the step is written with, so a step of 0.05
        # reads 0.35 rather than 0.3 and a step of 0.5 does not read 0.50.
        options["step"] = step
        options["decimals"] = _decimals_of(step)
    return ui.slider(label, low, high, declared, options)


## The row a matrix uniform earns: a [MatrixGrid] of its numbers, built when
## the dialog is realized like every custom control, and kept in the filter's
## store when the dialog keeps one, so a preset and a record carry the matrix
## the way they carry a slider.
func _grid_for(ui: SaDialog, field: Dictionary[String, Variant]) -> SaPageRow:
    var key := StringName(SaTyped.text_at(field, "name", ""))
    var opening := _matrix_of(field["default"], field["default"])
    ui.parameter_value(key, opening)
    # The row is made by the call the builder is handed to, so the builder
    # reaches it through this, weakly, because the row owns the grid it builds.
    var made_by: Array[WeakRef] = []
    var made := ui.custom(title_for(String(key)), func(_rerun: Callable) -> Control: return MatrixGrid.new(made_by[0]))
    made.named(key)
    made.value = opening
    if store.has(key):
        made.target = store
        made.property = NodePath(String(key))
    made_by.append(weakref(made))
    return made


## *held* as the numbers a matrix hands the kernel, or *declared* when it is not
## a list of as many numbers, which a record from another version of the file
## can be.
static func _matrix_of(held: Variant, declared: Variant) -> Array:
    var wanted: Array = declared if declared is Array else []
    var given: Array = held if held is Array else []
    var kept: Array = given if given.size() == wanted.size() else wanted
    var out: Array = []
    for number: Variant in kept:
        out.append(SaTyped.real(number))
    return out


## The fewest decimals that write *step* exactly, up to MOST_DECIMALS.
##
## Not `step_decimals()`, which answers where the first digit after the point
## that is not nought sits, so a step of 0.25 read one decimal and the slider
## showed 0.3 for a value of 0.25.
static func _decimals_of(step: float) -> int:
    var places := 0
    while places < MOST_DECIMALS:
        var shifted := step * pow(10.0, places)
        if is_equal_approx(shifted, roundf(shifted)):
            break
        places += 1
    return places


## A declared vector default as the colour the swatch opens on. Alpha is one
## for a `vec3`, which has none to declare.
static func _colour_of(declared: Variant) -> Color:
    if declared is Vector4:
        var four: Vector4 = declared
        return Color(four.x, four.y, four.z, four.w)
    if declared is Vector3:
        var three: Vector3 = declared
        return Color(three.x, three.y, three.z, 1.0)
    return Color.WHITE


## A widget's value as the type its `uniform` line declared.
##
## `SaPushConstants` packs a `Color` as four floats, which is a `vec4` and one float
## too many for a `vec3`, so the swatch of a three-float uniform is narrowed
## here rather than left for the packer to refuse.
static func _value_of(type_name: String, held: Variant) -> Variant:
    if type_name == "vec3" and held is Color:
        var color: Color = held
        return Vector3(color.r, color.g, color.b)
    if type_name == "bool":
        return held == true
    if type_name in ["int", "uint"]:
        return roundi(SaTyped.real(held))
    if type_name == "float":
        return SaTyped.real(held)
    return held


## The grid a matrix uniform draws: a number field per entry, as many to a row as
## the matrix is wide, in the order the kernel reads them.
##
## Inner, because it is this file's widget and nothing else draws one. It writes
## the row it was built for, which is what asks the dialog for a rerun and what a
## bound row hands on to the filter's store.
class MatrixGrid:
    extends GridContainer

    ## What a field is measured against, the widest number it shows.
    const WIDEST := "-00.0000"

    ## The row this grid writes, weakly, because the row owns the grid.
    var _row: WeakRef = null

    ## The numbers the fields stand for, row by row, every decimal kept.
    var numbers: Array = []

    func _init(row_ref: WeakRef) -> void:
        name = "MatrixGrid"
        _row = row_ref
        var held: Object = row_ref.get_ref()
        var row := held as SaPageRow
        numbers = SaTyped.list(row.read() if row != null else []).duplicate()
        columns = maxi(roundi(sqrt(float(numbers.size()))), 1)
        for at in numbers.size():
            var entry := LineEdit.new()
            entry.name = "Entry%d" % at
            entry.text = shown(SaTyped.real(numbers[at]))
            entry.alignment = HORIZONTAL_ALIGNMENT_RIGHT
            entry.select_all_on_focus = true
            entry.text_submitted.connect(_typed.bind(at))
            entry.focus_exited.connect(_left.bind(at))
            add_child(entry)

    ## *value* as a field shows it, a whole number without the `.0` the
    ## engine writes after one, so a weight of two reads `2`.
    static func shown(value: float) -> String:
        var text := String.num(value, MATRIX_DECIMALS).trim_suffix(".0")
        return "0" if text == "-0" else text

    ## *text* as the number a field means, a plain number or a fraction such as
    ## `1/9`, or null when it is neither.
    static func number_in(text: String) -> Variant:
        var written := text.strip_edges()
        if written.is_valid_float():
            return written.to_float()
        var halves := written.split("/")
        if halves.size() != 2:
            return null
        var top := halves[0].strip_edges()
        var bottom := halves[1].strip_edges()
        if not top.is_valid_float() or not bottom.is_valid_float() or is_zero_approx(bottom.to_float()):
            return null
        return top.to_float() / bottom.to_float()

    ## What a field holds once the painter has said so, by Enter or by leaving it.
    ## Text that is no number puts the last number back, and text that is what
    ## the field already showed changes nothing, so leaving a field that shows a
    ## rounded ninth does not round the ninth.
    func _typed(text: String, at: int) -> void:
        var entry := get_child(at) as LineEdit
        var was := SaTyped.real(numbers[at])
        var said: Variant = number_in(text)
        if said == null or text.strip_edges() == shown(was):
            entry.text = shown(was)
            return
        var number: float = said
        numbers[at] = number
        entry.text = shown(number)
        var held: Object = _row.get_ref()
        var row := held as SaPageRow
        if row != null:
            row.write(numbers.duplicate())

    func _left(at: int) -> void:
        _typed((get_child(at) as LineEdit).text, at)

    ## The `filter` step's door, since the grid is a custom row:
    ## `{"entry": 5, "text": "1/9"}` types into the sixth field, counted row by
    ## row from nought, and presses Enter the way a hand would.
    func capture_option_edit(spec: Dictionary) -> String:
        var at := SaTyped.whole(spec.get("entry", -1), -1)
        if at < 0 or at >= get_child_count():
            return "SaCapture: the grid has no entry %d, it has %d" % [at, get_child_count()]
        var entry := get_child(at) as LineEdit
        entry.text = str(spec.get("text", ""))
        entry.text_submitted.emit(entry.text)
        return "entry %d -> %s" % [at, entry.text]

    ## Every field as wide as the widest number it shows, measured again when the
    ## theme changes, since the font follows the interface scale.
    func _notification(what: int) -> void:
        if what != NOTIFICATION_THEME_CHANGED:
            return
        for entry: Node in get_children():
            var field := entry as LineEdit
            var font := field.get_theme_font(&"font")
            var font_size := field.get_theme_font_size(&"font_size")
            var width := font.get_string_size(WIDEST, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
            var style := field.get_theme_stylebox(&"normal")
            field.custom_minimum_size.x = ceilf(width + (style.get_minimum_size().x if style != null else 0.0))
