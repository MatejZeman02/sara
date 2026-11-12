## File > Export Frames...: a simulation's run written as numbered pictures,
## one image every so many steps and never a video.
##
## The page asks what a run needs: the format, one of the flat formats the
## export dialog offers at each of its depths, how many steps, and a picture
## every how many of them. Export... asks where, through the picker the export
## dialog uses, and the name chosen is the stem every picture's name is made
## from, `spread_0001.png`, `spread_0002.png` and on, the step each shows padded
## so the files sort. Each picture is written with the defaults the export
## dialog opens with: the highlights rolled off where View > Tonemap Highlights
## is on and the format would clip, the gamut mapping of Preferences, the relief
## baked where the view shows height, and a JPG at its default quality over
## white. OpenRaster is not offered, because a frame is the flat picture and
## OpenRaster keeps the layers.
##
## The run is [SaSimulation.Frames], in `core/layers/simulation`. This dialog
## drives it a frame of the app at a time from its own `_process`, says where
## it stands on the progress line, and Cancel stops it once the picture under
## way is written, so the layer stands at a step the folder holds. Closing the dialog
## while it runs cancels the same way. A run that writes every picture closes
## the dialog and says so in the corner, and one that stopped short stays open
## with the reason.
@tool
class_name SaSimulationFramesDialog
extends SaDialogWindow

## The node's name, which the follower and the scenario find it by.
const NODE_NAME := "ExportFramesDialog"
## The formats a frame is written in, each a registered format at one of its
## depths, whose registration says whether that depth keeps a value outside 0
## to 1. `bits` is what `SaExport` takes for the depth, and for EXR
## 16 is the half precision file and 32 the float one.
const FORMATS: Array[Dictionary] = [
    {"id": &"png8", "format": &"png", "bits": 8, "label": "PNG, 8 bits"},
    {"id": &"png16", "format": &"png", "bits": 16, "label": "PNG, 16 bits"},
    {"id": &"jpg", "format": &"jpg", "bits": 8, "label": "JPG"},
    {"id": &"exr32", "format": &"exr", "bits": 32, "label": "EXR, 32-bit float"},
    {"id": &"exr16", "format": &"exr", "bits": 16, "label": "EXR, 16-bit half"},
    {"id": &"tiff16", "format": &"tiff", "bits": 16, "label": "TIFF, 16-bit integer"},
    {"id": &"tiff32", "format": &"tiff", "bits": 32, "label": "TIFF, 32-bit float"},
]
const DEFAULT_STEPS := 10
const MOST_STEPS := 10000
const MOST_EVERY := 1000

## The format the next run writes, one of the ids of [constant FORMATS].
## Written by the format row.
var format_id: StringName = &"png8"
## The steps of the next run and a picture every how many. Written by their rows.
var steps: int = DEFAULT_STEPS
var every: int = 1
## The run under way, or the last one, null before the first.
var run: SaSimulation.Frames = null

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _layer: SaLayer = null
var _title: Label = null
var _format: SaChoiceButton = null
var _steps: FactorSlider = null
var _every: FactorSlider = null
var _result: Label = null
var _progress: Label = null
var _cancel: Button = null


func _init(registries: SaRegistries = null) -> void:
    _registries = registries
    _init_dialog(NODE_NAME, tr("Export Frames"), Vector2i(440, 300), Vector2i(380, 260))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    _title = SaMake.label(column, "ExportFramesTitle")
    _title.text_overrun_behavior = SaTheme.TEXT_CUT
    var format_row := SaMake.row(column, "ExportFramesFormatRow")
    SaMake.label(format_row, "ExportFramesFormatLabel", tr("Format"))
    var choices: Array = FORMATS.map(func(each: Dictionary) -> Dictionary: return {"id": each["id"], "label": each["label"]})
    _format = SaMake.choice(format_row, "ExportFramesFormat", choices)
    _format.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _format.select_value(format_id)
    _format.choice_picked.connect(_format_picked)
    _steps = SaMake.slider(column, "ExportFramesSteps", 1.0, float(MOST_STEPS), 1.0, float(steps))
    _steps.prefix = "%s: " % tr("Steps")
    _every = SaMake.slider(column, "ExportFramesEvery", 1.0, float(MOST_EVERY), 1.0, float(every))
    _every.prefix = "%s " % tr("A picture every")
    for slider: FactorSlider in [_steps, _every]:
        slider.decimal_places = 0
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _steps.value_changed.connect(_steps_moved)
    _every.value_changed.connect(_every_moved)
    _result = SaMake.label(column, "ExportFramesResult")
    _result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _progress = SaMake.label(column, "ExportFramesProgress")
    _progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(_progress, "text_muted")
    var buttons := pinned_buttons(column)
    _cancel = SaMake.button(buttons, "ExportFramesCancel", tr("Cancel"), tr("Stop once the picture under way is written"))
    _cancel.custom_minimum_size.x = float(SaUI.px(90))
    _cancel.pressed.connect(_cancel_pressed)
    default_button = SaMake.button(
        buttons, "ExportFramesButton", tr("Export..."), tr("Choose the name the pictures are numbered from")
    )
    default_button.custom_minimum_size.x = float(SaUI.px(90))
    default_button.pressed.connect(_export_pressed)
    visibility_changed.connect(_cancel_when_closed)
    _sync()


## Opens on *easel*'s document, whose simulated layer the run steps, as
## [method SaSimulation.simulated_layer] picks it.
func open_for(easel: SaEasel) -> void:
    _easel = easel
    _layer = SaSimulation.simulated_layer(easel.document if easel != null else null)
    _sync()
    popup_centered()


## Whether a run is under way.
func running() -> bool:
    return run != null and not run.finished


## The run's share of this frame, then the lines again.
func _process(_delta: float) -> void:
    if Engine.is_editor_hint() or not running():
        return
    if not run.advance():
        _ended()
    _sync()


## Starts a run named from *path*. A name with no extension takes the format's,
## and one with another format's has it changed, so every picture says what it
## is in the format the row chose.
func start(path: String) -> void:
    if running() or not _carries() or _easel == null:
        return
    var chosen := _chosen()
    var named := SaExportDialog.format_for(path, &"")
    if named != chosen["format"]:
        path = path.get_basename() if not named.is_empty() else path
        path += _registered().suffix
    var easel := _easel
    var writer := func(file: String) -> Error: return _write(easel, file)
    var rules := _registries.simulation_rules if _registries != null else null
    run = SaSimulation.Frames.new(easel.document, _layer, rules, path, steps, every, writer)
    if not running():
        _ended()
    _sync()


## The picture of the step the run just took, in the chosen format. The step
## was taken this frame, so what it marked is composited first, as Copy Merged
## does, because the export's own flush takes only what the window held back.
func _write(easel: SaEasel, path: String) -> Error:
    var format := _registered()
    if format == null:
        return ERR_INVALID_PARAMETER
    var bits: int = _chosen()["bits"]
    var keeps := not format.clips(bits)
    var options := SaImageFormat.Write.new()
    options.depth = bits
    options.quality = SaExportDialog.DEFAULT_QUALITY
    options.half = format.rows.has(SaImageFormat.ROW_HALF) and bits == 16
    options.rolloff = SaSettings.tonemap_highlights and not keeps
    options.mapping = SaGamutMapping.for_export(SaSettings.gamut_mapping, keeps)
    options.relief = format.rows.has(SaImageFormat.ROW_RELIEF) and SaRelief.shows_height(easel.document)
    easel.process_pending_composite()
    return format.write_picture(easel, path, options)


## The registered format the chosen entry writes, whose own sentences say
## whether its depth keeps a value outside 0 to 1.
func _registered() -> SaImageFormat:
    return SaImageImport.formats().find(_chosen()["format"])


func _chosen() -> Dictionary:
    for each: Dictionary in FORMATS:
        if each["id"] == format_id:
            return each
    return FORMATS[0]


func _export_pressed() -> void:
    if running() or not _carries():
        return
    var filters := PackedStringArray([_registered().save_filter])
    SaFilePicker.open(self, SaFilePicker.Mode.SAVE_FILE, filters, start, "", Callable(), "export")


## Cancel stops a run once its picture is written, and closes the dialog when
## nothing runs.
func _cancel_pressed() -> void:
    if running():
        run.cancel()
        _sync()
        return
    hide()


func _cancel_when_closed() -> void:
    if not visible and running():
        run.cancel()


## A run that wrote every picture closes the dialog and says so in the corner.
## One cancelled or stopped short stays, its line saying where it stood.
func _ended() -> void:
    if not run.wrote_all():
        return
    SaMessage.notice(_progress_text())
    hide()


func _format_picked(value: Variant) -> void:
    format_id = StringName(value)
    _sync()


func _steps_moved(moved: float) -> void:
    steps = clampi(roundi(moved), 1, MOST_STEPS)
    _sync()


func _every_moved(moved: float) -> void:
    every = clampi(roundi(moved), 1, MOST_EVERY)
    _sync()


## The title, the result and the progress line, and which buttons take a press.
func _sync() -> void:
    _title.text = _title_text()
    _every.suffix = " %s" % (tr("step") if every == 1 else tr("steps"))
    _result.text = _result_text()
    _progress.text = _progress_text()
    _progress.visible = not _progress.text.is_empty()
    default_button.disabled = running() or not _carries()
    _cancel.text = tr("Stop") if running() else tr("Cancel")


## The layer the dialog opened on, null once it is gone with its document.
func _alive() -> SaLayer:
    return _layer if is_instance_valid(_layer) else null


## Whether the layer the dialog opened on still carries a simulation.
func _carries() -> bool:
    return SaSimulation.record_of(_alive()) != null


func _title_text() -> String:
    var record := SaSimulation.record_of(_alive())
    if record == null:
        return tr("No layer of this document carries a simulation.")
    var found: SaSimulation.Rule = _registries.simulation_rules.find(record.rule) if _registries != null else null
    var rule_label: String = tr(found.label) if found != null else String(record.rule)
    return tr_n("%s on %s, at step %d", "%s on %s, at step %d", record.steps) % [rule_label, _layer.name, record.steps]


## How many pictures the rows ask for and the steps they show, from where the
## layer stands now.
func _result_text() -> String:
    var record := SaSimulation.record_of(_alive())
    var at: int = record.steps if record != null else 0
    var each := clampi(every, 1, steps)
    var pictures := floori(float(steps) / float(each))
    var said: String = (
        tr_n("One picture, of step %d.", "One picture, of step %d.", pictures)
        if pictures == 1
        else tr_n("%d picture, of steps %d to %d.", "%d pictures, of steps %d to %d.", pictures)
    )
    var line := said % [at + each] if pictures == 1 else said % [pictures, at + each, at + pictures * each]
    return "%s %s" % [line, _chosen()["label"]]


func _progress_text() -> String:
    return run.said() if run != null else ""


## What the dialog asks and what its last run wrote, for the state dump: the
## rows, the lines, every picture read back from the disk by the helper the
## suite reads them with, its name and size, and the step the layer stands at.
func report() -> Dictionary:
    var out := {
        "visible": visible,
        "format": String(format_id),
        "format_label": _format.text,
        "steps": steps,
        "every": every,
        "steps_row": _steps.value,
        "every_row": _every.value,
        "title": _title.text,
        "result": _result.text,
        "progress": _progress.text,
        "running": running(),
        "export_enabled": not default_button.disabled,
    }
    if run != null:
        out.merge(run.describe())
        var record := SaSimulation.record_of(_alive())
        out["layer_step"] = record.steps if record != null else -1
    return out
