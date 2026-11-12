## The solid colour a smart layer's contents are shown over while Edit Smart
## Layer Contents is open, in place of the checkerboard, so the contents read
## against a colour that is not carried anywhere with them.
##
## **Never part of the picture.** A rectangle of the canvas drawn behind the
## composite over the checkerboard, as the checkerboard is, and no layer in the
## document's tree and no chunk, so a merge, a save, an export and the save's
## preview never meet it. It is a 2D rectangle the canvas draws each frame,
## with no compute pass, so it dispatches nothing over the canvas.
##
## **A neutral grey**, the colour Select > Color Range shows its picked colours
## over, `SaColorRange.NEUTRAL_BACKDROP`, held here so `render` names no
## selection code.
##
## **Its colour turns clear when the view closes**, rather than the rectangle
## being hidden, because the canvas hides and shows the rectangles behind it
## itself while it draws at half size.
class_name SaContentsBackdrop
extends ColorRect

const NODE_NAME := "ContentsBackdrop"
## The grey drawn behind the contents, 0.5 on every channel.
const COLOR := Color(0.5, 0.5, 0.5, 1.0)

var _canvas: SaCanvas = null


## The canvas is a constructor argument, because a private member is set from
## outside its class that way only, defaulted so that `.new()` still works as
## Godot expects.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas


## Puts the backdrop behind *canvas*'s composite, once however often it is
## asked, and answers it.
static func attach_to(canvas: SaCanvas) -> SaContentsBackdrop:
    if canvas == null:
        return null
    var found := canvas.get_node_or_null(NODE_NAME) as SaContentsBackdrop
    if found != null:
        return found
    var backdrop := SaContentsBackdrop.new(canvas)
    backdrop.name = NODE_NAME
    canvas.add_child(backdrop)
    return backdrop


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    show_behind_parent = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    color = Color(COLOR, 0.0)


func _process(_delta: float) -> void:
    var wanted := COLOR if shows() else Color(COLOR, 0.0)
    if color != wanted:
        color = wanted


## Whether the document under the canvas has a smart layer's contents open.
func shows() -> bool:
    return _canvas != null and SaLocalView.contents_of(_canvas.document) != null
