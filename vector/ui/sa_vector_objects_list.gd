## The objects list, a row of the Tool Options docker while the Shape tool or
## the Object tool is the active one: the active vector layer's objects, top
## first as the Layers docker lists layers, each with its eye, its lock and its
## name, and under them the picked objects' fill and stroke.
##
## The vector page's second question was answered so: the objects live here
## and the Layers docker shows a vector layer as one row with no child rows.
##
## A click on a name picks that object on the canvas, Ctrl or Shift on it adds
## to the pick. Raise and Lower move the picked objects in the drawing order,
## and the two colour buttons give them the painter's pair, the fill the
## background and the stroke the foreground, as a new object takes them. Every
## change is one undo step through the drawn layer's door, so the history
## keeps the objects' JSON and no pixel.
##
## The row is a `Kind.CUSTOM` row, built by [method build] and pointed at the
## active tool by [method bind]. It reads the document through that tool, and
## shows the list again when the layer, its recipe's count of edits or the pick
## changed, which an undo, a drag on the canvas or a door step all move.
@tool
extends VBoxContainer

const VectorSettings := preload("res://modules/sara-base-modules/vector/tools/sa_vector_settings.gd")
const VectorRecipe := preload("res://modules/sara-base-modules/vector/sa_vector_recipe.gd")
const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")

## The steps the list's buttons record.
const SHOW_TITLE := "Show Object"
const HIDE_TITLE := "Hide Object"
const LOCK_TITLE := "Lock Object"
const UNLOCK_TITLE := "Unlock Object"
const ORDER_TITLE := "Reorder Objects"
const FILL_TITLE := "Fill Objects"
const STROKE_TITLE := "Stroke Objects"

## The swatch's side, in logical pixels.
const SWATCH := 18

## The tool the list reads the document and the pick through.
var listing: ToolState = null

## What the rows were last built from: the layer, its edits and the pick.
var _shown: Array = []
var _rows: VBoxContainer = null
var _empty: Label = null
var _fill: ColorRect = null
var _stroke: ColorRect = null
var _picked_box: VBoxContainer = null


## The row's widget, the factory `SaOptionSpec.build_control` asks for.
static func build(_spec: SaOptionSpec, _write: Callable) -> Control:
    var script: GDScript = load("res://modules/sara-base-modules/vector/ui/sa_vector_objects_list.gd")
    var list: Control = script.new()
    list.name = "VectorObjects"
    return list


## Points *control* at *value*, the active tool, the door `bind_value` asks for.
static func bind(control: Control, value: Variant) -> void:
    if control != null and "listing" in control:
        control.set("listing", value as ToolState)


func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _empty = Label.new()
    _empty.text = tr("The active layer holds no objects. Drag with the Shape tool to draw one on a new vector layer.")
    _empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(_empty)
    _rows = VBoxContainer.new()
    _rows.name = "Rows"
    add_child(_rows)
    _picked_box = VBoxContainer.new()
    add_child(_picked_box)
    var order := HBoxContainer.new()
    _picked_box.add_child(order)
    _button(order, tr("Raise"), tr("Moves the picked objects up the drawing order."), _reorder.bind(1))
    _button(order, tr("Lower"), tr("Moves the picked objects down the drawing order."), _reorder.bind(-1))
    var fill_row := HBoxContainer.new()
    _picked_box.add_child(fill_row)
    _fill = _swatch(fill_row)
    _button(fill_row, tr("Fill with Background"), tr("Fills the picked objects with the background colour."), _paint.bind(true))
    var stroke_row := HBoxContainer.new()
    _picked_box.add_child(stroke_row)
    _stroke = _swatch(stroke_row)
    _button(
        stroke_row, tr("Stroke with Foreground"), tr("Strokes the picked objects in the foreground colour."), _paint.bind(false)
    )


func _process(_delta: float) -> void:
    var recipe := _recipe()
    var picked := _settings().picked if _settings() != null else PackedStringArray()
    var now := [recipe, recipe.edits if recipe != null else -1, picked]
    if now != _shown:
        _shown = now
        _show(recipe, picked)


func _show(recipe: VectorRecipe, picked: PackedStringArray) -> void:
    for row in _rows.get_children():
        _rows.remove_child(row)
        row.queue_free()
    var objects: Array[VectorObject] = recipe.objects if recipe != null else ([] as Array[VectorObject])
    _empty.visible = objects.is_empty()
    for i in range(objects.size() - 1, -1, -1):
        _rows.add_child(_row(objects[i], picked.has(objects[i].id)))
    var first: VectorObject = recipe.find(picked[0]) if recipe != null and not picked.is_empty() else null
    _picked_box.visible = first != null
    if first != null:
        _fill.color = first.fill if first.filled else Color(0, 0, 0, 0)
        _stroke.color = first.stroke if first.stroke_width > 0.0 else Color(0, 0, 0, 0)


func _row(object: VectorObject, is_picked: bool) -> Control:
    var row := HBoxContainer.new()
    row.name = "Object %s" % object.id
    var eye := CheckBox.new()
    eye.button_pressed = object.visible
    eye.tooltip_text = tr("Shows or hides the object.")
    eye.toggled.connect(_flag.bind(object.id, "visible"))
    row.add_child(eye)
    var lock := CheckBox.new()
    lock.button_pressed = object.locked
    lock.tooltip_text = tr("Locks the object, so a press on the canvas passes over it.")
    lock.toggled.connect(_flag.bind(object.id, "locked"))
    row.add_child(lock)
    var pick := Button.new()
    pick.text = object.name
    pick.toggle_mode = true
    pick.button_pressed = is_picked
    pick.flat = not is_picked
    pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
    pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pick.clip_text = true
    pick.pressed.connect(_pick.bind(object.id))
    row.add_child(pick)
    return row


func _pick(object_id: String) -> void:
    var settings := _settings()
    if settings == null:
        return
    var adding := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT)
    var picks := settings.picked.duplicate() if adding else PackedStringArray()
    if picks.has(object_id):
        picks.remove_at(picks.find(object_id))
    else:
        picks.append(object_id)
    settings.picked = picks


func _flag(on: bool, object_id: String, key: String) -> void:
    var title := tr(SHOW_TITLE) if on else tr(HIDE_TITLE)
    if key == "locked":
        title = tr(LOCK_TITLE) if on else tr(UNLOCK_TITLE)
    _edit(title, func(recipe: VectorRecipe) -> void: recipe.restyle(object_id, {key: on}))


func _reorder(places: int) -> void:
    var settings := _settings()
    if settings == null:
        return
    var picks := settings.picked.duplicate()
    _edit(
        tr(ORDER_TITLE),
        func(recipe: VectorRecipe) -> void:
            for object_id in picks:
                recipe.reorder(object_id, places)
    )


func _paint(filling: bool) -> void:
    var settings := _settings()
    if settings == null:
        return
    var picks := settings.picked.duplicate()
    var colour: Color = SaInHand.Pair.background() if filling else SaInHand.Pair.foreground()
    var values := (
        {"fill": [colour.r, colour.g, colour.b, colour.a]} if filling else {"stroke": [colour.r, colour.g, colour.b, colour.a]}
    )
    if not filling:
        values["stroke_width"] = settings.stroke_width
    _edit(
        tr(FILL_TITLE) if filling else tr(STROKE_TITLE),
        func(recipe: VectorRecipe) -> void:
            for object_id in picks:
                recipe.restyle(object_id, values)
    )


func _edit(title: String, change: Callable) -> void:
    var doc := listing.document() if listing != null else null
    var layer := doc.active_layer if doc != null else null
    if VectorSettings.recipe_of(layer) == null:
        return
    SaDrawnLayer.edit(layer, title, change)


func _recipe() -> VectorRecipe:
    var doc := listing.document() if listing != null else null
    return VectorSettings.recipe_of(doc.active_layer) if doc != null else null


func _settings() -> VectorSettings:
    return listing.get("settings") as VectorSettings if listing != null else null


static func _button(row: Control, label: String, hint: String, press: Callable) -> void:
    var button := Button.new()
    button.text = label
    button.tooltip_text = hint
    button.pressed.connect(press)
    row.add_child(button)


static func _swatch(row: Control) -> ColorRect:
    var swatch := ColorRect.new()
    swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
    swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(swatch)
    return swatch
