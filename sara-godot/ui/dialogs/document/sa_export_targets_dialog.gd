## File > Export Target: the files the document in front is exported to on
## every save, each with its path and a Remove on one line and the options
## File > Export offers a PNG on the line under it: the depth, Impasto
## lighting, Dither at eight bits and Roll off highlights. Add Target... under
## them asks for a PNG's name, and a new target starts where the export dialog
## starts.
##
## What a row changes is the document's at once, through `SaExportTargets`, and
## the document counts as changed, because the targets are saved in its `.sad`.
## Each file is written as File > Export writes it with the same options,
## after each Save.
@tool
class_name SaExportTargetsDialog
extends SaDialogWindow

## The depth row of every target, a PNG's two.
const DEPTHS: Array = [{"id": 8, "label": "8-bit"}, {"id": 16, "label": "16-bit"}]

## The document the rows are about, set by [method open_for] alone.
var _document: SaDocument = null
## The rows, rebuilt whenever a target comes or goes.
var _rows: VBoxContainer = null
## The line saying there is none yet, or where the paths are read from.
var _note: Label = null


func _init() -> void:
    _init_dialog("ExportTargetsDialog", tr("Export Target"), Vector2i(620, 300), Vector2i(500, 220))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    var view := SaMake.scroll(column, "RowsScroll")
    view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scrolling_body = view
    _rows = SaMake.column(view, "Targets", SaTheme.GAP)
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _note = SaMake.label(column, "NoteLabel")
    _note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(_note, "text_muted")
    var buttons := SaMake.row(column, "Buttons", SaTheme.GAP)
    buttons.alignment = BoxContainer.ALIGNMENT_END
    var add := SaMake.button(buttons, "AddButton", tr("Add Target..."), tr("Name a PNG every save writes"))
    add.pressed.connect(_on_add_pressed)
    var done := SaMake.button(buttons, "DoneButton", tr("Done"))
    done.custom_minimum_size.x = float(SaUI.px(90))
    done.pressed.connect(hide)
    default_button = done


## Shows *document*'s targets and opens.
func open_for(document: SaDocument) -> void:
    _document = document
    _rebuild()
    popup_centered()


## Names *path* a target of the document at *depth*, `.png` put after a name
## with no extension. The picker answers here, and so does a suite.
func add_target(path: String, depth: int = 8) -> void:
    if _document == null or path.is_empty():
        return
    var at := path if path.get_extension().to_lower() == "png" else path + ".png"
    var targets := SaExportTargets.of(_document)
    targets.append(SaExportTargets.Target.new(at, &"png", depth, true, false, SaExportTargets.starting_rolloff()))
    _keep(targets)


func _on_add_pressed() -> void:
    SaFilePicker.open(self, SaFilePicker.Mode.SAVE_FILE, PackedStringArray([tr("*.png ; PNG Image")]), add_target)


func _keep(targets: Array[SaExportTargets.Target]) -> void:
    SaExportTargets.name_all(_document, targets)
    _document.modified = true
    _rebuild()


func _remove(index: int) -> void:
    var targets := SaExportTargets.of(_document)
    targets.remove_at(index)
    _keep(targets)


## The target at *index* with its option called *key* at *value*, which a
## row's control answers here and a suite does too.
func set_option(index: int, key: StringName, value: Variant) -> void:
    var targets := SaExportTargets.of(_document)
    if index < 0 or index >= targets.size():
        return
    targets[index] = targets[index].changed(key, value)
    _keep(targets)


func _rebuild() -> void:
    for child in _rows.get_children():
        _rows.remove_child(child)
        child.queue_free()
    var targets := SaExportTargets.of(_document)
    for index in targets.size():
        var target := targets[index]
        var block := SaMake.column(_rows, "Target%d" % index, SaTheme.GAP)
        var row := SaMake.row(block, "PathRow", SaTheme.GAP)
        var path := SaMake.label(row, "PathLabel", target.path)
        path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        path.clip_text = true
        path.tooltip_text = target.path
        var remove := SaMake.button(row, "RemoveButton", tr("Remove"))
        remove.pressed.connect(_remove.bind(index))
        var options := SaMake.row(block, "OptionsRow", SaTheme.GAP)
        var depth := SaMake.choice(options, "DepthChoice", DEPTHS)
        depth.select_value(target.depth)
        depth.choice_picked.connect(func(picked: Variant) -> void: set_option(index, &"depth", picked))
        _option(options, index, "ReliefCheck", tr("Impasto lighting"), &"relief", target.relief).tooltip_text = tr(
            "Lights the paper's tooth and the impasto into the file, as the view shows them."
        )
        # Sixteen bits never dither, so the check is not offered there, as in
        # File > Export.
        _option(options, index, "DitherCheck", tr("Dither"), &"dither", target.dither).visible = target.depth == 8
        _option(options, index, "RolloffCheck", tr("Roll off highlights"), &"rolloff", target.rolloff)
    if targets.is_empty():
        _note.text = tr("No target yet. A target is a PNG written by every Save, as Export writes it.")
    elif _document.file_path.is_empty():
        _note.text = tr("Each path is kept beside the .sad from its first save on.")
    else:
        _note.text = tr("Each path is kept from the folder of %s, so the two can move together.") % _document.file_path.get_file()


## One option's check on *row*, ticked at *value*, which sets *key* of the
## target at *index*.
func _option(row: HBoxContainer, index: int, node_name: String, text: String, key: StringName, value: bool) -> CheckBox:
    var check := SaMake.check_box(row, node_name, text, value)
    check.toggled.connect(func(on: bool) -> void: set_option(index, key, on))
    return check


## The rows' paths, in order, which a suite reads.
func shown_paths() -> PackedStringArray:
    var out := PackedStringArray()
    for target in SaExportTargets.of(_document):
        out.append(target.path)
    return out
