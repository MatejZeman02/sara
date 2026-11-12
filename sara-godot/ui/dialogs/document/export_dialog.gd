## File > Export: one dialog for PNG, JPG, EXR, TIFF and OpenRaster, rather
## than a native file dialog opened straight from the menu, which has no room for
## a format's options.
##
## The format picks the options row: JPG shows its quality slider, EXR its
## half/float check, and PNG and TIFF a depth row of their own. PNG's row is
## eight bits a channel or sixteen, which Godot's `Image.save_png` cannot offer
## and `SaPng16Writer` can, and TIFF's is sixteen unsigned or thirty-two float,
## which the TIFF writer takes as `bits`. The depth is remembered per format on
## this instance, so a painter who sets PNG to sixteen, looks at TIFF and comes
## back finds their choice where they left it.
##
## JPG also shows Transparent areas, the colour a file with no alpha lays the
## picture over, White, Black or any colour off its swatch.
##
## What the file will be is said in a Result block at the foot of the page, three
## short lines: the format and its depth, the gamut, and the size. Help is not
## part of the result and sits in muted type under what it explains. The
## sentence under the rolloff toggle says what a value outside 0 to 1 becomes,
## and it follows the depth: sixteen bits is the finer grid, not a way past the
## clip, and only the float formats keep a negative. The size is read-only: what
## the canvas already is, not a resample this dialog does not offer.
##
## A format whose depth clips also shows the rolloff check, so a file follows the
## view's tonemap rather than simply clipping a colour above 1. The check starts from the view's own answer, ticked where View >
## Tonemap Highlights is on and the format would otherwise clip, and unticked
## anywhere else, which is its default: a file written while the view
## rolls a highlight off should roll it off too. The painter can still untick
## it, and an unticked check clips. Its sentence names the operator the check runs, View >
## Tonemap Highlights, rather than asking a painter to remember that the two are
## the same thing.
##
## A file of eight bits a channel, JPG and PNG and OpenRaster at 8-bit, also
## shows a Dither check, because dithering is a choice and not the default.
## Unticked on the first opening and kept as the painter left it, the way the depth is. Ticked, the
## rounding to eight bits moves by a fixed pattern of up to half a step, so a
## faint edge or a long gradient does not band, and the Result's first line
## says the file is dithered. Sixteen bits and float never dither, and the row
## is not shown for them.
##
## OpenRaster keeps the layers, each one a PNG at PNG's depths and through the
## same rolloff, so it takes PNG's depth row and check. What the file cannot
## carry is said under the page before the painter confirms: the layers whose
## mode is written as normal, the groups whose mask or filters are left out,
## and the pass-through groups GIMP draws isolated.
##
## A flat format shows Include impasto lighting while the document has height: ticked on
## every opening, so the file shows the
## relief the view shows, lit by the same light, and a painter who wants the
## colour alone unticks it. OpenRaster writes colour only and never offers it,
## and its loss line says so, and the `.sad` keeps the raw height either way.
##
## The last format and its options are remembered on this instance, one
## dialog reused for the life of the File menu, the way `SaRadiusDialog`
## remembers a radius on `SaSelectMenu`.
@tool
class_name SaExportDialog
extends SaDialogWindow

signal exported(path: String, error: Error)

## The depth of a format's file in the words the Result's first line reads it in,
## keyed by the bits a format's depth row and `SaExport` take.
const DEPTH_WORDS := {8: "8 bits per channel", 16: "16 bits per channel", 32: "32-bit float"}
## Eight bits in the same words with the Dither check ticked, a whole phrase so
## a language can order it as it likes.
const DITHERED_WORDS := "8 bits per channel, dithered"
## The rows the format row shows for the formats whose registration names them,
## beside the depth row, which it shows for a format with depths.
const SWITCHED_ROWS: Array[StringName] = [SaImageFormat.ROW_QUALITY, SaImageFormat.ROW_FLATTEN, SaImageFormat.ROW_HALF]
const DEFAULT_QUALITY := 0.9

## The three rows the page binds, one property each. The format dropdown, the
## quality slider and the half check are the page's, and this dialog reads what
## they wrote.
var format: StringName = &"png"
var quality: float = DEFAULT_QUALITY
var half: bool = false
## What a JPG's transparent areas become, a colour as the picker holds it.
## White by default, the paper a picture with no background is usually seen on.
var flatten: Color = Color.WHITE

## The declared rows, realized once into `ExportPage`.
var page: SaPage = null

var _canvas: SaCanvas = null
## The two rows the page does not bind, and their controls under the names the
## suites reach them by.
var _depth_row: SaPageRow
var _rolloff_row: SaPageRow
var _depth_option: SaChoiceButton
## Whether a value outside 0 to 1 is rolled off rather than clipped, shown only
## where `_can_rolloff` says the format's depth would otherwise clip.
var _rolloff_check: CheckButton
## The Result block, one label a line: the format and its depth, the gamut the
## file will be named for, said and not offered, and the size.
var _format_label: Label
var _gamut_label: Label
var _size_label: Label
## The muted sentence under the rolloff toggle, what a value outside 0 to 1 becomes.
var _note_label: Label
## The muted line under the gamut, where to change it, shown only when there is
## something to say.
var _gamut_help_label: Label
## What a layered file of this document cannot carry, shown only for such a
## format and only when there is something to say.
var _loss_label: Label
## The format row, whose list and rules follow the format registry.
var _format_row: SaPageRow
## The registry the format row was filled from, heard for a format coming and
## going while the dialog lives.
var _registry: SaImageFormatRegistry = null

## The depth the painter last chose, per format, so the row is where they left it
## when they come back to a format. Written by the row's own press and by nothing
## else, and a format with no entry is at the default its registration names.
var _depths: Dictionary = {}
## One choice for every format, because it is the same operator wherever it
## shows, rather than a depth's own setting the way `_depths` is. Its row is not
## bound, because the rolloff suite reads this member by its private name: the
## row's handler writes it, which keeps the writer inside this class.
var _rolloff: bool = false
## Whether a flat export lights the relief into the file, shown only where
## `_can_bake_relief` says there is a relief to bake. Unbound for the rolloff's
## reason, and written by its row's handler and by `open_for`.
var _bake_relief: bool = false
var _relief_row: SaPageRow
var _relief_check: CheckButton
## The Transparent areas row's swatch, which White and Black set as well, so it
## always shows the colour the file will be laid over.
var _flatten_swatch: ColorPickerButton
## Whether an eight-bit file is rounded through the dither, shown only where
## `_can_dither` says the file is eight bits. Off until the painter ticks it,
## and kept across openings, so `open_for` leaves it alone. Unbound for the
## rolloff's reason, and written by its row's handler alone.
var _dither: bool = false
var _dither_row: SaPageRow
var _dither_check: CheckButton


## Every argument is what the dialog would have been left holding by a painter,
## and they are constructor arguments because `ui/dialogs/document/tests/test_export_dialog.gd` needs
## a dialog already in that state, and a private is written by its own class
## only, so something set from outside arrives here. Every default is the ordinary case, because the application builds the
## dialog once with no arguments at all and `open_for` names the canvas each time
## it is shown.
##
## *starting_depths* is `{format: bits}` for the depths a painter would have
## already chosen, empty for the ordinary case, and a format the dialog has no
## depth row for is dropped rather than stored. *starting_rolloff* is
## [member _rolloff]'s until the dialog is opened, false for the ordinary case:
## `open_for` is what gives the check its start from the view, and the argument
## is how a caller that is not the File menu sets a state before that, and
## *starting_relief* is [member _bake_relief]'s the same way,
## *starting_flatten* is [member flatten]'s and *starting_dither* is
## [member _dither]'s.
func _init(
    canvas: SaCanvas = null,
    format_id: StringName = &"png",
    starting_quality: float = DEFAULT_QUALITY,
    starting_half: bool = false,
    starting_depths: Dictionary = {},
    starting_rolloff: bool = false,
    starting_relief: bool = false,
    starting_flatten: Color = Color.WHITE,
    starting_dither: bool = false
) -> void:
    _canvas = canvas
    format = format_id
    quality = starting_quality
    half = starting_half
    flatten = starting_flatten
    _rolloff = starting_rolloff
    _bake_relief = starting_relief
    _dither = starting_dither
    for format_id_key: Variant in starting_depths:
        var offered := _formats().find(StringName(format_id_key))
        if offered != null and not offered.depths.is_empty():
            _depths[format_id_key] = int(starting_depths[format_id_key])
    # Wide enough for the page's label column. The height is measured, not
    # reasoned: the running app grows a 520 by 400 window to 426 to hold the
    # page, the format note and the gamut line, so the size is that plus room
    # for a line a distro's font wraps further.
    _init_dialog("ExportDialog", tr("Export"), Vector2i(520, 460), Vector2i(460, 440))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)

    # The rows scroll when the host is shorter than they are, so the buttons stay
    # on it, as they do in New Document.
    var rows_view := SaMake.scroll(column, "RowsScroll")
    rows_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    rows_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rows_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = rows_view
    var rows := SaMake.column(rows_view, "ExportPage")
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page = SaPage.new(_declare)
    page.declare_rows()
    page.realize(rows)
    page.row_changed.connect(_on_row_changed)
    _depth_row = page.row(&"depth")
    _rolloff_row = page.row(&"rolloff")
    _depth_option = _depth_row.control as SaChoiceButton
    _rolloff_check = _rolloff_row.control as CheckButton
    _relief_row = page.row(&"relief")
    _relief_check = _relief_row.control as CheckButton
    _dither_row = page.row(&"dither")
    _dither_check = _dither_row.control as CheckButton

    var buttons := SaMake.row(column, "Buttons", SaTheme.GAP)
    buttons.alignment = BoxContainer.ALIGNMENT_END
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size.x = float(SaUI.px(90))
    cancel_button.pressed.connect(hide)
    default_button = SaMake.button(buttons, "ExportButton", tr("Export..."))
    default_button.custom_minimum_size.x = float(SaUI.px(90))
    default_button.pressed.connect(_on_export_pressed)
    _listen(_formats())
    _sync_options()


## The page: the format, then the one row each format has of its own, then the
## rolloff with its sentence under it, then the Result. The quality slider is
## JPG's, the half check EXR's and the depth row PNG's and TIFF's, which their
## registrations name and the format row's rules say. The rolloff row follows
## the depth as well as the format, which no rule of one row can say, so
## `_sync_options` shows it.
##
## The sentences and the Result's lines are custom rows with no title, labels
## `_sync_options` rewrites as a row moves.
##
## The depth row, the dither row and the rolloff row are not bound. The depth
## is kept per format in `_depths` and its list is refilled when the format
## moves, and the dither and the rolloff are the private members their headers
## explain. The quality row is
## custom, for the reason `_quality_slider` gives, and writes `quality` itself,
## and so is Transparent areas, for the reason `_flatten_row` gives, which
## writes `flatten`.
func _declare(ui: SaPage) -> void:
    var rows := ui.section("")
    var format_row := rows.choice("Format", _format_choices(), self, ^"format").named(&"format").node("FormatOption")
    format_row.hide_rules = _format_rules()
    # Kept as declared, so a page that declares again hands over its new row.
    _format_row = format_row
    rows.custom("Quality", _quality_slider()).named(&"quality")
    rows.custom("Transparent areas", _flatten_row()).named(&"flatten").explain(tr("A JPG holds no transparency."))
    rows.toggle("Half precision (16-bit)", self, ^"half").named(&"half").node("HalfCheck")
    var depth := rows.choice("Bit depth", _format().depths).named(&"depth").node("DepthOption")
    depth.value = _depth()
    var dither := rows.toggle("Dither").named(&"dither").node("DitherCheck").explain(
        tr("Hides banding in smooth gradients and faint edges with a fine noise, the same in every export.")
    )
    dither.value = _dither
    var rolloff := rows.toggle("Roll off highlights instead of clipping").named(&"rolloff").node("RolloffCheck")
    rolloff.value = _rolloff
    _note_label = _bare(rows.custom, "FormatNote", &"note", true)
    var relief := rows.toggle("Include impasto lighting").named(&"relief").node("ReliefCheck")
    relief.value = _bake_relief
    var result := ui.section(tr("Result"))
    _format_label = _bare(result.custom, "FormatLine", &"format_line", false)
    # Said and not offered: changing the gamut is the Image menu's job, and a
    # second place to choose it would be a second answer to what the picture's
    # numbers mean.
    _gamut_label = _bare(result.custom, "GamutLine", &"gamut_line", false)
    _gamut_help_label = _bare(result.custom, "GamutHelp", &"gamut_help", true)
    _size_label = _bare(result.custom, "SizeLine", &"size_line", false)
    _loss_label = _bare(result.custom, "LossLine", &"loss", true)


## A label the page draws bare at the end of a section, for `_sync_options` to
## rewrite as a row moves. *custom* is the section's own `custom`. One of the
## Result's lines at the dialog's own size, or help in muted type, the smaller
## and dimmer face a page's own explanation is drawn in.
func _bare(custom: Callable, node_name: String, key: StringName, muted: bool) -> Label:
    var label := SaSettingsRows.hint_label("") if muted else SaMake.label(null, node_name)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.name = node_name
    (custom.call("", label) as SaPageRow).named(key)
    return label


## JPG's quality, a `FactorSlider` rather than the page's slider row, which is
## why its row is custom. That slider is typed into as well as dragged, and reads
## two decimals, which the page's `HSlider` and its readout do not offer. The
## caption goes inside the bar, the way the options bar's sliders carry theirs,
## because the page draws no title beside a `FactorSlider`.
func _quality_slider() -> FactorSlider:
    var slider := FactorSlider.new()
    slider.name = "QualitySlider"
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.01
    slider.decimal_places = 2
    # A colon after the caption, as every slider caption in the tree has.
    slider.prefix = tr("Quality") + ": "
    slider.value = quality
    slider.value_changed.connect(func(value: float) -> void: quality = value)
    return slider


## JPG's Transparent areas: White and Black, the two a painter asks for most,
## and a swatch for any other, which the two buttons set as well. Custom
## because the page's colour row is a swatch alone. The swatch edits no alpha,
## because the colour is what a file with no alpha is laid over.
func _flatten_row() -> HBoxContainer:
    var box := SaMake.row(null, "FlattenRow", SaTheme.GAP)
    var white := SaMake.button(box, "FlattenWhite", tr("White"))
    white.pressed.connect(_flatten_on.bind(Color.WHITE))
    var black := SaMake.button(box, "FlattenBlack", tr("Black"))
    black.pressed.connect(_flatten_on.bind(Color.BLACK))
    _flatten_swatch = ColorPickerButton.new()
    _flatten_swatch.name = "FlattenSwatch"
    _flatten_swatch.edit_alpha = false
    _flatten_swatch.color = flatten
    _flatten_swatch.tooltip_text = tr("Pick any other colour to lay the picture over.")
    _flatten_swatch.custom_minimum_size = Vector2(SaUI.px(64), SaUI.px(SaUI.BASE_BTN_H))
    _flatten_swatch.color_changed.connect(func(picked: Color) -> void: flatten = picked)
    box.add_child(_flatten_swatch)
    return box


## White or Black pressed: the colour, and the swatch showing it.
func _flatten_on(picked: Color) -> void:
    flatten = picked
    _flatten_swatch.color = picked


## Opens the dialog for *canvas*, at the format and options it was last on, with
## the rolloff check starting where the view is: ticked while Tonemap Highlights
## is on and this format would otherwise clip, unticked anywhere else.
##
## The start is derived here rather than in `_init` because the File menu builds
## the dialog once and shows it for the rest of the session, so a default read
## at construction would be the tonemapper of the moment the app booted. A
## painter who turns Tonemap Highlights on and then opens Export gets the check
## ticked, and one who turns it off gets it unticked.
func open_for(canvas: SaCanvas) -> void:
    _canvas = canvas
    _rolloff = _rolloff_from_the_view()
    _rolloff_row.value = _rolloff
    _bake_relief = SaRelief.shows_height(canvas.document)
    _relief_row.value = _bake_relief
    _sync_options()
    popup_centered()


## What the check starts at: the view's own tonemapper, where the format and
## depth the dialog is on would otherwise clip. EXR and the 32-bit TIFF hold
## every value, so the check starts unticked for both whatever the view is set
## to, and `_can_rolloff` is the same question the row's visibility asks.
##
## The painter's own unticking is not lost: this runs once per opening, and the
## check they leave is what `_export_to` reads.
func _rolloff_from_the_view() -> bool:
    return SaSettings.tonemap_highlights and _can_rolloff()


## A row moved. The format refills the depth row and moves every line under the
## page, the depth moves the rolloff row and the lines, and the rolloff moves the
## note. The three bound rows wrote their property already, so only the two
## unbound ones are written here.
func _on_row_changed(key: StringName, value: Variant) -> void:
    match key:
        &"depth":
            _depths[format] = int(value)
        &"rolloff":
            _rolloff = bool(value)
        &"relief":
            _bake_relief = bool(value)
        &"dither":
            _dither = bool(value)
    _sync_options()


## The depth row for the format the dialog is on, the rolloff row where the
## format and depth would otherwise clip, the sentence under it and the Result's
## lines. The quality, half and depth rows follow the format by the rules
## `_declare` gave them, so this touches none of them but the depth row's list.
##
## The rolloff row is hidden and so is its check, because a check inside a
## hidden line still answers `visible` and the rolloff suite asks the check.
func _sync_options() -> void:
    _sync_depth_row()
    var offered := _can_rolloff()
    _rolloff_row.line.visible = offered
    _rolloff_check.visible = offered
    var bakes := _can_bake_relief()
    _relief_row.line.visible = bakes
    _relief_check.visible = bakes
    var dithers := _can_dither()
    _dither_row.line.visible = dithers
    _dither_check.visible = dithers
    _note_label.text = tr(_note_text()) + _mapping_text()
    _format_label.text = _format_text()
    _gamut_label.text = _gamut_text()
    _gamut_help_label.text = _gamut_help()
    _gamut_help_label.visible = not _gamut_help_label.text.is_empty()
    _size_label.text = _size_text()
    _loss_label.text = _loss_text()
    _loss_label.visible = not _loss_label.text.is_empty()


## Refills the depth row with the format's own two entries, marked where this
## format was left. A format with no depth keeps the list it had under a hidden
## row, which is what the row always did.
func _sync_depth_row() -> void:
    var choices: Array = _format().depths
    # The list is already in the `{"id", "label"}` shape a declared row keeps.
    if not choices.is_empty() and _depth_row.choices != choices:
        _depth_row.choices = choices
        _depth_option.set_choices(choices)
    _depth_row.value = _depth()
    page.refresh()


## Whether the page shows the row called *key*, which is what the state dump
## and the suites ask rather than the control: a rule hides the row's line and
## leaves the control inside it as it was.
func shows(key: StringName) -> bool:
    var line := page.row(key).line
    return line != null and line.visible


## The depth the file will be written at, which is what the painter last chose
## for this format and the format's own default until they do.
func _depth() -> int:
    return int(_depths.get(format, _format().default_depth))


## Whether the format and depth the dialog is on would otherwise clip a value
## outside 0 to 1, which is what the rolloff check offers an alternative to. EXR
## and the 32-bit TIFF never clip, so the check has nothing to do for either and
## stays hidden.
func _can_rolloff() -> bool:
    return _format().clips(_depth())


## Whether the file is eight bits a channel, which is what the Dither check is
## offered for, in a format whose registration offers it: JPG always, and PNG
## and OpenRaster at 8-bit.
func _can_dither() -> bool:
    return _format().rows.has(SaImageFormat.ROW_DITHER) and _depth() == 8


## Whether the export offers to bake the relief: a flat format, over a document
## the view shows height in. OpenRaster writes colour only and never offers it.
func _can_bake_relief() -> bool:
    return _format().rows.has(SaImageFormat.ROW_RELIEF) and SaRelief.shows_height(_document())


## The gamut mapping this export is written under: the painter's preference for
## a file that narrows, and clip for EXR and the 32-bit TIFF, which keep every
## value and are never mapped. `_can_rolloff` is already the question of whether
## the file narrows, so the two cannot disagree.
func _mapping() -> String:
    return SaGamutMapping.for_export(SaSettings.gamut_mapping, not _can_rolloff())


## What the note under the rolloff toggle adds when the file is mapped, so the
## dialog says what the preference will do to this file. The row is on the
## Canvas and colour page.
func _mapping_text() -> String:
    if _mapping() != SaGamutMapping.OKLAB:
        return ""
    var said := tr(
        "An out-of-gamut colour keeps its hue and gives up chroma before anything is clipped (Preferences > Canvas and colour)."
    )
    return " " + said


## The depth sentence for the format and depth the dialog is on, falling back to
## the format's own when the depth changes nothing about clipping, and to the
## rolled sentences throughout when the check is on and the format has one.
func _note_text() -> String:
    return _format().note_at(_depth(), _rolloff)


## The document the dialog exports, or null before it has a canvas.
func _document() -> SaDocument:
    return _canvas.document if _canvas != null else null


## The colour space of that document, or null before it has one.
func _space() -> SaColorSpace:
    var document := _document()
    return document.color_space if document != null else null


## The Result's first line, in the words the format's registration gives it. JPG
## is always eight bits and EXR's depth is its half switch.
func _format_text() -> String:
    var shown := _format()
    var halved := shown.rows.has(SaImageFormat.ROW_HALF) and half
    return tr(shown.result_line) % [shown.label, tr("16-bit float") if halved else _depth_words(_depth())]


## *bits* in the Result's words, naming the dither where the file is eight
## bits and the check is ticked, which is the one place the Result says it.
func _depth_words(bits: int) -> String:
    if bits == 8 and _dither and _can_dither():
        return tr(DITHERED_WORDS)
    return tr(DEPTH_WORDS.get(bits, DEPTH_WORDS[32]))


## The Result's gamut line, over the document the dialog exports and what the
## file will say about it. A format of linear light, EXR, names no gamut and is
## written in linear sRGB from any document's, so its line says what it is
## converted from instead.
func _gamut_text() -> String:
    var space := _space()
    if space == null:
        return ""
    if _format().linear:
        var source := space.gamut().display_name if space.is_specified else tr("an unspecified gamut taken as sRGB")
        return tr("Written as linear sRGB, from %s") % source
    if not space.is_specified:
        return tr("Gamut: unspecified, not named in the file")
    var gamut_name := space.gamut().display_name
    if SaExportGamut.gamut_named(space) == null:
        return tr("Gamut: %s, not named in the file") % gamut_name
    return tr("Gamut: %s, named in the file") % gamut_name


## The help under the gamut line: where to change it, or why the file cannot name it.
func _gamut_help() -> String:
    var space := _space()
    if space == null or not space.is_specified or _format().linear:
        return ""
    if SaExportGamut.gamut_named(space) == null:
        return tr("Sara has no profile for it.")
    return tr("Image > Gamut changes it.")


## The Result's size line: what the canvas is, and empty before there is one.
func _size_text() -> String:
    if _canvas == null:
        return ""
    var pixels := _canvas.canvas_size
    return tr("Size: %s × %s px") % [pixels.x, pixels.y]


## What a layered format, OpenRaster, loses of the document the dialog exports,
## in the words the painter reads before confirming, or empty for a flat format
## and for a document it loses nothing of: the writer's own sentences, which the
## format's registration hands over, and the impasto.
func _loss_text() -> String:
    var document := _document()
    var shown := _format()
    if not shown.losses.is_valid() or document == null:
        return ""
    var said: PackedStringArray = shown.losses.call(document)
    if SaRelief.shows_height(document) and not shown.relief_loss.is_empty():
        said.append(tr(shown.relief_loss))
    return " ".join(said)


func _on_export_pressed() -> void:
    if _canvas == null:
        return
    SaFilePicker.open(
        self, SaFilePicker.Mode.SAVE_FILE, PackedStringArray([tr(_format().save_filter)]), _export_to, "", Callable(), "export"
    )


## The format the extension of *path* names, case ignored, or *fallback* for a
## name with no extension or one no format answers to.
static func format_for(path: String, fallback: StringName) -> StringName:
    var named := _formats().exported_named(path)
    return named.id if named != null else fallback


## The file the painter picked, written in the format its name says rather than
## the one the dropdown was left on, so a file named `.exr` is never a TIFF
## inside. A name whose extension is another format's moves the dropdown
## to it first, so the rows and the Result read that format's, and the notice
## says why. A name no format answers to keeps the dropdown's and takes its
## extension, so the file says what it is.
func _export_to(path: String) -> void:
    var named := format_for(path, &"")
    var moved := not named.is_empty() and named != format
    if named.is_empty():
        path += _format().suffix
    elif moved:
        format = named
        _sync_options()
    var options := SaImageFormat.Write.new()
    options.depth = _depth()
    options.quality = quality
    options.half = half
    options.rolloff = _rolloff and _can_rolloff()
    options.mapping = _mapping()
    options.relief = _bake_relief and _can_bake_relief()
    options.flatten = flatten
    options.dither = _dither and _can_dither()
    # A PNG is written over frames, so the window draws on while the file is
    # read and encoded, and the rest at once. Either way the dialog
    # hears how it went through `_exported`.
    _format().write_picture_in_turns(_canvas.easel, path, options, _exported.bind(path, moved, _format().label))


## How an export the dialog asked for went: the notice when the extension chose
## the format, the signal, and the dialog put away once the file is whole.
func _exported(error: Error, path: String, moved: bool, label: String) -> void:
    if moved and error == OK:
        SaMessage.notice(tr("Exported as %s, chosen from the file extension.") % label)
    exported.emit(path, error)
    if error == OK:
        hide()


## The File menu's sentence for Export..., built from the registered formats so
## a format a module adds is named there too. Which formats keep a value outside 0 to 1 is
## the dialog's to say, in the note under each format's rows, and not the
## menu's, so the hover stays two short sentences.
static func menu_sentence() -> String:
    var formats := _formats().exported()
    var layers := formats.filter(func(each: SaImageFormat) -> bool: return each.keeps_layers)
    var sentence := TranslationServer.translate("Save a copy as %s.") % _listed(formats, false)
    if not layers.is_empty():
        var layered := TranslationServer.translate(
            (
                "%s keeps the layers, the others flatten them."
                if layers.size() == 1
                else "%s keep the layers, the others flatten them."
            )
        )
        sentence += " " + layered % _listed(layers, true)
    return sentence


## The hint beside the Author row of Preferences, built from the formats whose
## writer names the author.
static func author_sentence() -> String:
    var naming := _formats().exported().filter(func(each: SaImageFormat) -> bool: return each.names_author)
    return (
        TranslationServer.translate("The author name written into %s files. Leave empty to write none.") % _listed(naming, false)
    )


## The labels of *formats*, in the order given, joined by commas and "and", or
## by "or" where *both* is false.
static func _listed(formats: Array, both: bool) -> String:
    var labels: Array[String] = []
    for each: SaImageFormat in formats:
        labels.append(each.label)
    return _joined(labels, both)


## The ids of the formats Export writes, in the order the format row lists
## them, which is the order they registered in.
static func format_ids() -> Array[StringName]:
    var ids: Array[StringName] = []
    for each in _formats().exported():
        ids.append(each.id)
    return ids


## The format registry the dialog reads, the app's or the skeleton's own.
static func _formats() -> SaImageFormatRegistry:
    return SaImageFormatRegistry.shared()


## The format the dialog is on, or the first Export writes when it is on one
## that has gone. With every format gone, as when the modules are put down at
## quit, an empty description of the id stands in, which writes nothing.
func _format() -> SaImageFormat:
    var registry := _registry if _registry != null else _formats()
    var shown := registry.find(format)
    if shown == null or not shown.writes():
        var writers := registry.exported()
        shown = writers[0] if not writers.is_empty() else SaImageFormat.new(format, String(format))
    return shown


## The format row's entries, every format Export writes in registration order.
func _format_choices() -> Array:
    var registry := _registry if _registry != null else _formats()
    return registry.exported().map(func(each: SaImageFormat) -> Dictionary: return {"id": each.id, "label": each.label})


## The format row's rules: each switched row for the formats that name it, and
## the depth row for the formats with depths.
func _format_rules() -> Array[Dictionary]:
    var registry := _registry if _registry != null else _formats()
    var rules: Array[Dictionary] = []
    for key: StringName in SWITCHED_ROWS:
        var ids := registry.exported().filter(func(each: SaImageFormat) -> bool: return each.rows.has(key))
        rules.append({"key": key, "values": ids.map(func(each: SaImageFormat) -> StringName: return each.id)})
    var deep := registry.exported().filter(func(each: SaImageFormat) -> bool: return not each.depths.is_empty())
    rules.append({"key": &"depth", "values": deep.map(func(each: SaImageFormat) -> StringName: return each.id)})
    return rules


## Hears *registry*, so a format a module registers or takes away while the
## dialog lives is in its list or out of it the next time it is read.
func _listen(registry: SaImageFormatRegistry) -> void:
    if _registry == registry:
        return
    if _registry != null and _registry.changed.is_connected(_on_formats_changed):
        _registry.changed.disconnect(_on_formats_changed)
    _registry = registry
    _registry.changed.connect(_on_formats_changed)
    _on_formats_changed()


## A format came or went: the format row's list and rules again, and the first
## format when the one the dialog was on has gone.
func _on_formats_changed() -> void:
    if _format_row == null or _registry.exported().is_empty():
        return
    var choices := _format_choices()
    _format_row.choices = choices
    _format_row.hide_rules = _format_rules()
    (_format_row.control as SaChoiceButton).set_choices(choices)
    format = _format().id
    _sync_options()


## "A", "A and B", or "A, B and C", and "or" in place of "and" where *both* is
## false. The last two are joined by a whole pattern a language can translate,
## rather than by an English word between them.
static func _joined(words: Array[String], both: bool) -> String:
    if words.size() < 2:
        return "".join(words)
    var pattern := TranslationServer.translate("%s and %s" if both else "%s or %s")
    return pattern % [", ".join(words.slice(0, -1)), words[-1]]


## What the dialog is asking for, for the state dump: the format, the depth the
## row is on and the words it and the note read. The depth row's own mark is a
## few texels in a picture and its label is not, so a scenario that picks the
## second row proves nothing the dump cannot say, and this says it in the words
## the file will be written with.
static func capture_state(root: Window) -> Dictionary:
    var dialog := root.find_child("ExportDialog", true, false) as SaExportDialog
    if dialog == null or not dialog.visible:
        return {}
    return {
        "format": String(dialog.format),
        "depth": dialog._depth(),
        "depth_row": dialog.shows(&"depth"),
        "depth_label": dialog._depth_option.text,
        "depth_rows": dialog._depth_option.choice_labels(),
        "rolloff_row": dialog.shows(&"rolloff"),
        "rolloff": dialog._rolloff,
        "relief_row": dialog.shows(&"relief"),
        "relief": dialog._bake_relief,
        "dither_row": dialog.shows(&"dither"),
        "dither": dialog._dither,
        "flatten_row": dialog.shows(&"flatten"),
        "flatten": "#" + dialog.flatten.to_html(false),
        "gamut_mapping": dialog._mapping(),
        "format_line": dialog._format_label.text,
        "gamut": dialog._gamut_label.text,
        "gamut_help": dialog._gamut_help_label.text if dialog._gamut_help_label.visible else "",
        "size": dialog._size_label.text,
        "note": dialog._note_label.text,
        "losses": dialog._loss_label.text,
    }
