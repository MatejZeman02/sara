## The list beside the right click menu's Colour row: No Colour and Photoshop's
## seven, each with a swatch of its hue, the active layer's ticked. A choice
## emits `chosen` with the colour's row id, and the actions give that colour to
## every picked row as one step through `SaLayerColorTag`.
@tool
class_name SaLayerColorList
extends SaChoicePopup

## Prefixed, so a colour's row id is never the id of a row of the menu it
## opens beside. No Colour is the prefix alone.
const PREFIX := "layer_color_"

## The swatch's side before the UI scale.
const SWATCH := 12


func _init() -> void:
    super(false)
    name = "LayerColorList"


## The eight rows, *held* ticked.
func fill(held: StringName) -> void:
    clear()
    for id: StringName in SaLayerColorTag.IDS:
        var key := row_id(id)
        add_row(key, tr(SaLayerColorTag.words(id)), true, id == held)
        if not id.is_empty():
            label_button(key).icon = _swatch(SaLayerColorTag.hue(id))


## The row id of the colour *id*.
static func row_id(id: StringName) -> StringName:
    return StringName(PREFIX + String(id))


## The colour a row id stands for, and null for an id that is no colour's row.
static func color_of(key: StringName) -> Variant:
    var text := String(key)
    var id := StringName(text.substr(PREFIX.length()))
    if not text.begins_with(PREFIX) or not SaLayerColorTag.IDS.has(id):
        return null
    return id


static func _swatch(hue: Color) -> ImageTexture:
    var side := SaUI.px(SWATCH)
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
    image.fill(hue)
    return ImageTexture.create_from_image(image)
