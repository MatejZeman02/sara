## The background removal module: the Select Subject tool, whose click selects
## the subject of the picture with U²-NetP, a small network run on Sara's
## kernels, and the Object Selection tool beside it, whose dragged box selects
## the object inside it with the same network on the same weights.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A repository of its own, `sara-background-removal`, which Sara takes as a
## submodule, outside the base modules, so a Sara without it still has the
## wand, Colour Range and the quick mask, and has no Select Subject tool since
## nothing of the skeleton names this folder.
##
## **It ships no weights.** Choosing the tool, from the toolbox, the Tools
## menu, the search or a chord a painter bound to [constant COMMAND], with no
## weights file in the module's data folder opens `weights_dialog.gd`, which
## says where the file comes from, its size and what is known of its licence,
## and downloads it on the painter's Accept. Cancel puts the tool in hand
## before back in hand. The file is kept only when its SHA-256 is [constant
## WEIGHTS_SHA256]. Once it is kept the tool opens no dialog and asks the
## network nothing again. Two arguments after the `--` of Sara's command line
## point the download elsewhere, for a suite or a mirror:
## `--background-removal-source=<url>` and `--background-removal-sha256=<hex>`.
extends SaModule

const WeightsDialog := preload("weights_dialog.gd")
const FoldedWeights := preload("folded_weights.gd")
const PthReader := preload("pth_reader.gd")
const SubjectNetwork := preload("network/subject_network.gd")
const SelectSubjectTool := preload("select_subject_tool.gd")
const ObjectSelectionTool := preload("object_selection_tool.gd")
const SubjectSelection := preload("selection/subject_selection.gd")

## The tool's id, which the toolbox and the tool machine know it by.
const TOOL := &"select_subject"
## The command that puts the tool in hand, which a painter binds a chord to on
## the Keyboard Shortcuts page. No chord of its own, since a row in the shipped
## shortcuts would be a row in a file that is not this module's.
const COMMAND := &"pick_select_subject"
const ICON := "res://modules/sara-background-removal/icons/select_subject.svg"
## The toolbox's Preferences category, and the tool's row in it, which a fresh
## toolbox orders by: right after the Magic Wand's, as Krita and Photoshop keep
## their subject selection beside the wand. A painter's own order keeps theirs
## and gets the row at its end.
const TOOLBOX := "ToolBoxDocker"
const TOOLBOX_ROW := "Select Subject Tool"
const TOOLBOX_ANCHOR := "Magic Wand Tool"
## The Object Selection tool's id, its command, its icon and its toolbox row,
## which stands right after Select Subject's.
const BOX_TOOL := &"object_selection"
const BOX_COMMAND := &"pick_object_selection"
const BOX_ICON := "res://modules/sara-background-removal/icons/object_selection.svg"
const BOX_TOOLBOX_ROW := "Object Selection Tool"

## The weights of U²-NetP as the U-2-Net authors trained them, the file their
## README links on Google Drive, at commit `ac7e1c817` of `xuebinqin/U-2-Net`.
const WEIGHTS_SOURCE := "https://drive.google.com/uc?export=download&id=1rbSTGKAE-MTxBYHd-51l2hMOQPT_7EPy"
const WEIGHTS_SHA256 := "e7567cde013fb64813973ce6e1ecc25a80c05c3ca7adbc5a54f3c3d90991b854"
const WEIGHTS_BYTES := 4683258
## The file's name in the module's data folder, the name its authors gave it.
const WEIGHTS_FILE := "u2netp.pth"
## The source named for the painter.
const WEIGHTS_WHERE := "the authors' own Google Drive link in the U-2-Net README, github.com/xuebinqin/U-2-Net"

## The arguments after the `--` that point the download elsewhere.
const SOURCE_ARGUMENT := "--background-removal-source="
const SHA256_ARGUMENT := "--background-removal-sha256="

## The dialog, while it exists.
var dialog: WeightsDialog = null
## The tool machine whose choice of the tool opened the dialog, which Cancel
## hands back to the tool before.
var _chooser: Variant = null
## The last line the command said in the corner, which a suite reads.
var said: String = ""
var _ctx: SaContext = null
## The weights read and folded, kept for the session once read, with the path
## they were read from.
var _folded: FoldedWeights = null
var _folded_from: String = ""
## The network's chain over those weights, made once for them.
var _network: SubjectNetwork = null
## The run that makes the network's mask the selection, made once a session.
var selector: SubjectSelection = SubjectSelection.new()
## Whether a click is running, while the cursor shows it is busy.
var busy: bool = false
## A click that waited on the weights, run once the dialog keeps them.
var _waiting: Callable = Callable()
## Where the tool's dialog downloads from and the hash it keeps, empty for the
## command line's or the authors'.
var _source: String = ""
var _sha256: String = ""


## The loader makes the module with neither. A suite names its own server and
## the hash of the bytes it serves, so choosing the tool asks that server.
func _init(source: String = "", sha256: String = "") -> void:
    _source = source
    _sha256 = sha256


func get_id() -> StringName:
    return &"background_removal"


func get_name() -> String:
    return "Background removal"


func register(ctx: SaContext) -> void:
    _ctx = ctx
    var tool := SaToolDescriptor.create(TOOL, SelectSubjectTool)
    tool.display_name = "Select Subject"
    tool.icon_name = ICON
    tool.category = &"select"
    # With the Magic Wand, which is where painters coming from other programs
    # look for the subject and object selections, so W steps through them.
    tool.toolbox_group = &"wand"
    tool.cursor_shape = Control.CURSOR_CROSS
    tool.is_detour = true
    tool.reads_keys = [KEY_SHIFT, KEY_ALT]
    tool.shared_settings = SelectSubjectTool.Click.new(click)
    tool.options = [merged_option()]
    ctx.register_tool(tool)
    var box := SaToolDescriptor.create(BOX_TOOL, ObjectSelectionTool)
    box.display_name = "Object Selection"
    box.icon_name = BOX_ICON
    box.category = &"select"
    # Under the Magic Wand's button with Select Subject, so W steps through
    # all three.
    box.toolbox_group = &"wand"
    box.cursor_shape = Control.CURSOR_CROSS
    box.reads_keys = [KEY_SHIFT, KEY_ALT]
    box.shared_settings = tool.shared_settings
    box.options = [merged_option()]
    ctx.register_tool(box)
    SaInHand.Settings.place_element(TOOLBOX, TOOLBOX_ROW, TOOLBOX_ROW, false, TOOLBOX_ANCHOR)
    SaInHand.Settings.place_element(TOOLBOX, BOX_TOOLBOX_ROW, BOX_TOOLBOX_ROW, false, TOOLBOX_ROW)
    var surfaces := SaContext.new(Callable(), ctx.surface_provider)
    var pick := SaCommandDescriptor.create(COMMAND, "Select subject", _pick.bind(surfaces, TOOL))
    pick.label = "Select Subject"
    pick.category = &"select"
    pick.sentence = "Put the Select Subject tool in hand, whose click selects the subject of the picture."
    ctx.register_command(pick)
    var pick_box := SaCommandDescriptor.create(BOX_COMMAND, "Object selection", _pick.bind(surfaces, BOX_TOOL))
    pick_box.label = "Object Selection"
    pick_box.category = &"select"
    pick_box.sentence = "Put the Object Selection tool in hand, whose dragged box selects the object inside it."
    ctx.register_command(pick_box)
    if not EventBus.tool_picked.is_connected(_on_tool_picked):
        EventBus.tool_picked.connect(_on_tool_picked)


func unregister(_context: SaContext) -> void:
    SaInHand.Settings.remove_element(TOOLBOX, TOOLBOX_ROW)
    SaInHand.Settings.remove_element(TOOLBOX, BOX_TOOLBOX_ROW)
    if EventBus.tool_picked.is_connected(_on_tool_picked):
        EventBus.tool_picked.disconnect(_on_tool_picked)
    if dialog != null and is_instance_valid(dialog):
        dialog.queue_free()
    dialog = null
    _chooser = null


## The wand's Merged, under the wand's key, so the two tools read one switch.
static func merged_option() -> SaOptionSpec:
    var merged := SaOptionSpec.make(&"sample_merged", "Sample merged", SaOptionSpec.Kind.BOOL)
    merged.on_tool = true
    merged.bar = true
    merged.bar_hidden = true
    merged.tooltip = "Read every layer as shown, rather than the active layer alone."
    return merged


## Where the weights are kept, in the module's data folder.
func weights_path() -> String:
    return _ctx.module_data_dir().path_join(WEIGHTS_FILE) if _ctx != null else ""


## Whether the weights are kept.
func has_weights() -> bool:
    return not weights_path().is_empty() and FileAccess.file_exists(weights_path())


## The weights read from *path*, by default the kept file, every batch norm
## folded into its convolution. Read once a session: a second ask for the
## same file answers the same object, whose buffer is uploaded once. A file
## that is refused answers an object whose `error` says why.
func folded_weights(path: String = "") -> FoldedWeights:
    var from := path if not path.is_empty() else weights_path()
    if _folded == null or _folded_from != from:
        _folded = FoldedWeights.new(PthReader.new(FileAccess.get_file_as_bytes(from), from.get_file()))
        _folded_from = from
    return _folded


## U²-NetP as Sara's kernels over the weights read from *path*, by default
## the kept file. Made once for a set of weights, so its plan and its pages
## are built once a session. Its `error` says why it cannot run.
func subject_network(path: String = "") -> SubjectNetwork:
    var folded := folded_weights(path)
    if _network == null or _network.weights != folded:
        _network = SubjectNetwork.new(folded)
    return _network


## A click of either tool on *surface*'s canvas, in *press_mode*, a
## `SaSelection.Mode`, reading the merged picture when *merged*, inside *box*
## when it has an area and over the whole picture otherwise. The cursor
## shows the run is busy from the frame before it starts until it ends. With
## no weights kept it opens the dialog, and the click runs once the dialog
## keeps them.
func click(
    press_mode: int = SaSelection.Mode.REPLACE, merged: bool = true, surface: SaSurface = null, box: Rect2i = Rect2i()
) -> void:
    if not has_weights():
        var opened := open_dialog()
        if opened != null:
            _waiting = click.bind(press_mode, merged, surface, box)
            opened.kept.connect(_run_waiting.unbind(1), CONNECT_ONE_SHOT)
        return
    if busy:
        return
    busy = true
    var shape := DisplayServer.cursor_get_shape()
    DisplayServer.cursor_set_shape(DisplayServer.CURSOR_BUSY)
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        # Two frames, so the busy cursor is on the screen before the run holds
        # the main thread.
        await tree.process_frame
        await tree.process_frame
    select_subject(press_mode, merged, surface, box)
    DisplayServer.cursor_set_shape(shape)
    busy = false


## Selects the subject of *surface*'s picture, or of the active surface's when
## none is named, in *press_mode*, as one undo step, reading the merged picture
## when *merged* and the active layer alone otherwise, as the wand does. A
## *box* with an area, in document pixels, selects the object inside it alone,
## Object Selection's run. Answers whether the selection was reached. Public so
## a suite and a capture step run it in one call.
func select_subject(
    press_mode: int = SaSelection.Mode.REPLACE, merged: bool = true, surface: SaSurface = null, box: Rect2i = Rect2i()
) -> bool:
    var network := subject_network()
    if not network.error.is_empty():
        _say(TranslationServer.translate("Select Subject could not run: %s") % network.error)
        return false
    var on := surface if surface != null else _surface_in_hand()
    var document: SaDocument = on.get_document() if on != null else null
    if document == null:
        _say(TranslationServer.translate("There is no picture to select the subject of."))
        return false
    var picture: SaTexture = null
    if merged and on.easel != null:
        # The network reads the whole canvas, so the picture is composited
        # everywhere first, as the wand's flood has it.
        on.easel.catch_up()
        on.easel.flush()
        picture = on.easel.output
    var done := selector.select(document, network, press_mode, picture, box)
    if not done:
        _say(TranslationServer.translate("Select Subject could not run: %s") % selector.error)
    return done


func _run_waiting() -> void:
    var waiting := _waiting
    _waiting = Callable()
    if waiting.is_valid():
        waiting.call()


## The main canvas's surface, else the first.
func _surface_in_hand() -> SaSurface:
    if _ctx == null:
        return null
    var found: SaSurface = null
    for surface: SaSurface in _ctx.list_surfaces():
        if not surface.is_embedded:
            return surface
        found = surface if found == null else found
    return found


## The tool was chosen on some surface's machine. With no weights kept the
## dialog opens at once, and its Cancel hands that machine back the tool before.
func _on_tool_picked(tool_name: String) -> void:
    if not StringName(tool_name) in [TOOL, BOX_TOOL] or has_weights():
        return
    if dialog != null and is_instance_valid(dialog) and dialog.visible:
        return
    _chooser = _machine_holding_the_tool(StringName(tool_name))
    var opened := open_dialog()
    if opened != null:
        opened.cancelled.connect(_hand_back)


## The machine whose permanent tool is *tool*, the main canvas's first.
func _machine_holding_the_tool(tool: StringName) -> Variant:
    if _ctx == null:
        return null
    var found: Variant = null
    for surface: SaSurface in _ctx.list_surfaces():
        var machine: Variant = surface.tool_machine
        if machine == null or machine.default_tool_name != tool:
            continue
        if not surface.is_embedded:
            return machine
        found = machine if found == null else found
    return found


func _hand_back() -> void:
    if _chooser != null and is_instance_valid(_chooser) and _chooser.default_tool_name in [TOOL, BOX_TOOL]:
        _chooser.return_to_previous_tool()
    _chooser = null


## A command's handler: puts *tool* in the main canvas's hand, as the
## toolbox's button does. Declines when no machine took the tool.
static func _pick(surfaces: SaContext, tool: StringName) -> bool:
    for surface: SaSurface in surfaces.list_surfaces():
        var machine: Variant = surface.tool_machine
        if surface.is_embedded or machine == null or not machine.registered_tools.has(tool):
            continue
        machine.set_active_tool(tool)
        return true
    return false


## Opens the download's dialog, built on first use. Public so a suite and a
## capture step open it without a press.
func open_dialog(source: String = "", sha256: String = "") -> WeightsDialog:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or _ctx == null:
        return null
    if dialog != null and is_instance_valid(dialog):
        dialog.queue_free()
    var from := (
        source if not source.is_empty() else _source if not _source.is_empty() else argument(SOURCE_ARGUMENT, WEIGHTS_SOURCE)
    )
    var digest := (
        sha256 if not sha256.is_empty() else _sha256 if not _sha256.is_empty() else argument(SHA256_ARGUMENT, WEIGHTS_SHA256)
    )
    dialog = WeightsDialog.new(from, weights_path(), digest, WEIGHTS_BYTES, WEIGHTS_WHERE)
    dialog.kept.connect(_say)
    var host: Node = tree.current_scene if tree.current_scene != null else tree.root
    host.add_child(dialog)
    dialog.popup_centered()
    return dialog


func _say(line: String) -> void:
    said = line
    EventBus.corner_notice.emit(line)


## The value of the argument after the `--` that starts with *prefix*, or
## *fallback*.
static func argument(prefix: String, fallback: String) -> String:
    for given: String in OS.get_cmdline_user_args():
        if given.begins_with(prefix):
            return given.substr(prefix.length())
    return fallback
