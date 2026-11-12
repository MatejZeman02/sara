## Export Effects as LUT: a group's, an adjustment layer's or a filtered
## layer's colour effects written as a `.cube` 3D table, the format DaVinci
## Resolve, Premiere, Photoshop, Krita, Nuke and OBS all read.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A table, because it carries the effects to other programs, a grader above
## all. It carries a colour change made pixel by pixel and nothing
## else, so a blur, a mask and painted pixels stay behind, and the dialog names
## each one before the file is written.
##
## The facade of the folder. The command and its row in the Layer menu and the
## Layers docker's More menu are here, the measurement is
## `effects_lut_scratch.gd` and the window `effects_lut_dialog.gd`. An instance
## is one export of one node: what it leaves out, the table at a size, and the
## file.
class_name SaEffectsLut
extends RefCounted

const Scratch = preload("res://ui/dockers/layers/lut/effects_lut_scratch.gd")
const DialogScript = preload("res://ui/dockers/layers/lut/effects_lut_dialog.gd")

## The command, and the row's id in `SaLayerMenuRows`.
const COMMAND := &"layer_export_lut"
## The sides offered, the three every reader takes, and the one picked first.
const SIZES: Array[int] = [17, 33, 65]
const DEFAULT_SIZE := 33
## What the window answers to in the tree, for a scenario's steps.
const DIALOG_NAME := "EffectsLutDialog"
const SENTENCE := (
    "Write the colour effects of the group or layer as a .cube table, which DaVinci Resolve, Premiere,"
    + " Photoshop and Krita read. Painted layers, masks and blurs stay behind, and the window names them."
)

## The node exported and its document.
var node: SaLayer = null
var document: SaDocument = null
## Whether the last table written changes with the place in the picture.
var moved: bool = false

var _scratch: Scratch = null


func _init(source: SaDocument, exported: SaLayer) -> void:
    document = source
    node = exported
    _scratch = Scratch.new(source, exported)


## Whether *layer* has effects to export: a group, an adjustment layer, or a
## layer with filters attached.
static func can_export(layer: SaLayer) -> bool:
    return layer != null and (layer.is_group or layer.is_adjustment() or not layer.filters.is_empty())


## One line for each thing the node holds that the table leaves out.
func left_out() -> PackedStringArray:
    return _scratch.left_out


## Whether anything kept changes a colour at all.
func carries_anything() -> bool:
    return _scratch.carries_anything()


## The table at *size* a side, red fastest, in the values Filter > Colour > LUT
## feeds a table.
func table(size: int) -> PackedFloat32Array:
    var entries := _scratch.bake(size)
    moved = _scratch.moved
    return entries


## Writes the table at *size* to *path* and answers the rows written, or 0 when
## the file could not be opened.
func write(path: String, size: int) -> int:
    var entries := table(size)
    if entries.is_empty():
        return 0
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return 0
    file.store_string(Scratch.cube_text(entries, size, str(node.name)))
    file.close()
    return floori(entries.size() / 3.0)


## The command on the Layer menu's row and in the Keyboard Shortcuts page, with
## no chord of its own. It acts on the active layer of the main canvas.
##
## The handler and `enabled` hold a bare context with only *ctx*'s easel
## provider, never *ctx* itself, which holds the command registry that holds
## the command, a ring that leaked every registration after the first.
## The provider asks the app for its easel on each call, so the command reads
## the main canvas as long as the app runs.
static func register(ctx: SaContext) -> void:
    var reach := SaContext.new(ctx.easel_provider)
    var command := SaCommandDescriptor.create(COMMAND, "Export the effects as a LUT", _open_in_tree.bind(reach))
    command.label = "Export Effects as LUT..."
    command.category = &"layer"
    command.sentence = SENTENCE
    command.enabled = func() -> bool: return _main_document(reach) != null and can_export(_main_document(reach).active_layer)
    ctx.register_command(command)


## Opens the window over *host* for *source*'s active layer, built on first use
## and kept under the main scene. Answers it, or null when there is nothing to
## export.
static func open_on(host: Node, source: SaDocument) -> Window:
    if host == null or source == null or not can_export(source.active_layer):
        return null
    var parent := host
    if host.is_inside_tree() and host.get_tree().current_scene != null:
        parent = host.get_tree().current_scene
    var dialog := parent.get_node_or_null(DIALOG_NAME) as Window
    if dialog == null:
        dialog = DialogScript.new()
        parent.add_child(dialog)
    dialog.call(&"open_for", SaEffectsLut.new(source, source.active_layer))
    return dialog


static func _open_in_tree(ctx: SaContext) -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.current_scene == null:
        return false
    return open_on(tree.current_scene, _main_document(ctx)) != null


static func _main_document(ctx: SaContext) -> SaDocument:
    var easel := ctx.get_easel() if ctx != null else null
    return easel.document if easel != null else null
