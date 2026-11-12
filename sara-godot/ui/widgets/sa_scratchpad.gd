## A small second painting surface: its own document, view, tool machine and a
## Clear button, in a control anything can put anywhere.
##
## Kept with nothing showing it yet, rather than deleted, because the preset
## editor wants a place to try a brush without touching the painting, and the
## Info docker, a panel of numbers, is no place for it.
##
## This surface is why "the canvas" is never safely singular. It owns a
## document of its own, so every canvas lookup in the tree has to say which one
## it means, and a tool is instantiated per surface rather than shared.
@tool
extends VBoxContainer

class_name SaScratchpad

## The edge of the painting area, in logical pixels. Square, and the document
## is the same size, so the whole of it is on screen at zoom 1.
const EDGE: int = 256

var canvas: SaCanvas
var clear_button: Button
var tool_machine: ToolMachine
var surface: SaSurface


func _init() -> void:
    name = "Scratchpad"

    canvas = SaCanvas.new()
    canvas.name = "Canvas"
    canvas.custom_minimum_size = Vector2(EDGE, EDGE)
    canvas.canvas_size = Vector2i(EDGE, EDGE)
    add_child(canvas)
    canvas.unique_name_in_owner = true

    tool_machine = preload("res://tools/tool_machine.gd").new()
    tool_machine.name = "ToolMachine"
    canvas.add_child(tool_machine)
    tool_machine.unique_name_in_owner = true

    clear_button = SaMake.button(self, "ClearButton", tr("Clear", "clear the scratchpad"))
    clear_button.unique_name_in_owner = true


func _ready() -> void:
    canvas.canvas_size = Vector2i(EDGE, EDGE)
    clear_button.pressed.connect(clear)
    canvas.gui_input.connect(_on_canvas_gui_input)


## Throws the scratch painting away. Not undoable, because a scratchpad that
## charges the painting's history for a doodle is the wrong trade.
func clear() -> void:
    if canvas.document == null:
        return
    canvas.document.clear_layer()
    if canvas.document.stroke_layer != null:
        canvas.document.stroke_layer.chunks.clear()
    canvas.document.invalidate_all_allocated_chunks()
    canvas.request_composite()


func _on_canvas_gui_input(event: InputEvent) -> void:
    if tool_machine != null:
        tool_machine.handle_input(event)


## Builds this surface and instantiates its tools. An embedded surface takes
## only descriptors marked available_in_embedded, which is what keeps the tool
## list here from being a second hand-written copy of the main canvas's.
func bind_tools(registry: SaToolRegistry, roles: SaRoleRegistry = null, pens: SaPenRegistry = null) -> void:
    if canvas == null or canvas.ensure_easel() == null:
        return
    if surface == null:
        surface = SaSurface.create(&"scratchpad", canvas.easel, SaCanvasView.for_canvas(canvas))
        surface.is_embedded = true
    tool_machine.bind(surface, registry, roles, pens)
