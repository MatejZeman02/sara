## What a bound control drives, the door a module reaches the app's values,
## presets and filters through without naming the windows that show them: a
## value by the name its slider carries, a brush preset by its stored name, a
## filter by its registry key, and what a click on a control would bind.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## MIDI's bindings named the options bar, the layers' opacity,
## the preset chooser, the Filters docker and the note mode's hit test, so
## they could not leave `ui`. The app hands its own drive to the context as
## `SaContext.drive`, and a module's bindings ask that. This base answers that
## nothing can be moved, chosen or run, which is what a context built by a
## suite with no app holds.
##
## **A value** is read and written in its own units, and across the range a
## drag of its slider covers as a ratio from nought to one, geometric where the
## slider's drag is. A value that cannot be moved now answers NaN.
##
## **A target** is what a click binds, `{kind, target, label}`: *kind* is one of
## [constant DIAL], [constant PRESET] and [constant FILTER], *target* the name
## or key the binding keeps, and *label* the words a painter reads for it.
## A button's *target* is its made name, or the holder's name, a slash and its
## name where others carry the same name.
class_name SaControlDrive
extends RefCounted

## A value a slider names, which a knob or a fader moves.
const DIAL := "dial"

## A brush preset by its stored name, which a key or a pad chooses.
const PRESET := "preset"

## A filter by its registry key, whose command a key or a pad runs.
const FILTER := "filter"

## A button by the name it was made under, which a key, a pad or a control
## change past halfway presses as a click would.
const BUTTON := "button"


## Whether the value named *value_name* can be moved now.
func can_move(value_name: StringName) -> bool:
    return not is_nan(read(value_name))


## The ends a drag of the value's slider reaches, bottom then top, or two NaNs
## when it cannot be moved now.
func range_of(_value_name: StringName) -> Vector2:
    return Vector2(NAN, NAN)


## Where the value stands in its own units, or NaN when it cannot be moved now.
func read(_value_name: StringName) -> float:
    return NAN


## Sets the value to *value* in its own units. True when there was a value to
## set. *merge* says whether a value that is an undo step folds into the step
## the last write opened.
func write(_value_name: StringName, _value: float, _merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
    return false


## Where the value stands across its range, nought at the bottom and one at the
## top, or NaN when it cannot be moved now.
func read_ratio(_value_name: StringName) -> float:
    return NAN


## Sets the value *ratio* of the way across its range. True when there was a
## value to set. *merge* as [method write].
func write_ratio(_value_name: StringName, _ratio: float, _merge: UndoRedo.MergeMode = UndoRedo.MERGE_ENDS) -> bool:
    return false


## Whether a brush preset is stored under *preset*.
func has_preset(_preset: String) -> bool:
    return false


## Chooses the brush preset stored under *preset*, as a press on its cell does.
## True when it was chosen.
func choose_preset(_preset: String) -> bool:
    return false


## Whether a filter is registered under *key*.
func has_filter(_key: StringName) -> bool:
    return false


## Runs the command of the filter registered under *key*, the one its menu row
## runs, which opens its dialog. True when it ran.
func run_filter(_key: StringName) -> bool:
    return false


## Presses the button *target* names as a click on it does: a toggle toggles,
## any other emits `pressed`, and a disabled one does nothing. True when it was
## pressed. This base presses nothing.
func press_button(_target: String) -> bool:
    return false


## What a click on *control* would bind, walking up from it to the first
## control that names something, or empty when none does.
func target_of(_control: Control) -> Dictionary:
    return {}


## What a press in *window* at *point* would bind, the control drawn under the
## point asked as [method target_of] is.
func target_at(_window: Window, _point: Vector2) -> Dictionary:
    return {}


## The control called *control_name* that the app's widget maker made, under
## *under* or under the whole window when *under* is null, or null when there
## is none. One shown on screen wins over one that is not. The door a module
## finds a control of the main window through, a lesson's step among them, and
## the one the harness's walker reads. This base finds nothing.
func find_control(_control_name: String, _under: Node = null) -> Control:
    return null


## Shows the closed docker that holds *control*, the way its row in the Window
## menu does, so a press recorded on a control a layout has since put away
## reaches it again. True when *control* is shown after. This base shows
## nothing.
func bring_out(_control: Control) -> bool:
    return false


## The name a scenario's step aims at for a press in *window* at *point*: the
## made control drawn under the point, or the nearest made control holding it,
## that [method find_control] finds again by that name. Empty where none is,
## the canvas among those places. What a lesson's recording writes for a press
## on a control, so the step survives a change of layout. This base names
## nothing.
func control_name_at(_window: Window, _point: Vector2) -> String:
    return ""


## What a scenario's click aims at for a press in *window* at *point*, as the
## step writes it: `{"control": name}` for a control its name alone finds, and
## `{"control": name, "in": holder}` for one whose name others carry too, a
## menu's row among them, *holder* the node above it the lookup goes under.
## Empty where no control is named. This base asks [method control_name_at].
func control_aim_at(window: Window, point: Vector2) -> Dictionary:
    var control_name := control_name_at(window, point)
    return {} if control_name.is_empty() else {"control": control_name}


## Whether a press in *window* at *point* lands on the front document's canvas,
## with no docker or bar drawn over it there. This base has no canvas.
func is_canvas_at(_window: Window, _point: Vector2) -> bool:
    return false


## The document pixel under *point* of the main window, through the front
## canvas's pan, zoom, rotation and mirror as they stand now, which is the walk
## a scenario's stroke in document space takes the other way. Two NaNs where
## there is no canvas, which is all this base answers.
func document_point(_point: Vector2) -> Vector2:
    return Vector2(NAN, NAN)


## The id of the tool in the main canvas's hand, empty when there is none.
func active_tool() -> StringName:
    return &""


## Saves a copy of *document* to *path* in Sara's own format, in the
## background, leaving the document's own file and path as they were. *then*
## is called with the save's error once it has ended. False when nothing was
## started, which is all this base answers.
func save_copy(_document: SaDocument, _path: String, _then: Callable) -> bool:
    return false


## The point of the main window, in its logical units, over the document pixel
## *point*, through the front canvas's pan, zoom, rotation and mirror as they
## stand now: [method document_point] walked the other way, which a lesson's
## stroke is replayed along. Two NaNs where there is no canvas, which is all
## this base answers.
func window_point(_point: Vector2) -> Vector2:
    return Vector2(NAN, NAN)


## Whether *document* is the one whose tab is in front, the one a press on
## the main window's canvas and [method window_point] reach. False where no
## document is shown, which is all this base answers.
func is_front(_document: SaDocument) -> bool:
    return false


## Opens the `.sad` at *path* as a document of its own, in a tab of its own
## brought to the front, untitled and with no history, so a Save never writes
## over the file it came from. *then* is called with the error and the
## document once it is in, a frame or many later. False when nothing was
## started, which is all this base answers.
func open_copy(_path: String, _then: Callable) -> bool:
    return false


## Puts the `.sad` at *path* into *document* in place of what it holds, its
## tab kept and its history cleared, since nothing in it is then the painter's
## to take back. *then* is called with the error once it is in. False when
## nothing was started, which is all this base answers.
func load_copy(_document: SaDocument, _path: String, _then: Callable) -> bool:
    return false


## The whole of *document*'s picture as the composite holds it, an `RGBAF`
## image of the stored numbers at the document's size, read back once and never
## inside a stroke. Null where no document is shown, which is all this base
## answers.
func picture(_document: SaDocument) -> Image:
    return null


## The picture of the `.sad` at *path*, as [method picture] reads a document's,
## opened off screen and let go again. Null for a file that does not open,
## which is all this base answers.
func picture_of(_path: String) -> Image:
    return null
