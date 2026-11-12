## Everything the skeleton needs to know about a tool without knowing what it is.
##
## Data rather than strings the skeleton names, so a tool a module registers is
## treated like a built-in: whether it gets a brush ring, whether it paints,
## which quick key activates it and whether it appears in the embedded
## scratchpad are all read from here.
class_name SaToolDescriptor
extends RefCounted

## Stable identity. Persisted in settings, so it must not change casually.
var id: StringName

## Shown in the toolbox tooltip.
var display_name: String = ""

## Name resolved through SaUI.get_icon(), not a path.
var icon_name: String = ""

var category: StringName = &"general"

## The toolbox group this tool shares a button with, and empty for a button of
## its own. Two descriptors naming one group draw one button with a flyout
## listing both, so a module joins a built-in group by naming it. The base
## modules name two, `select` for the two marquees and `fill` for the fill and
## the gradient, and no other built-in tool shares a button. Only the default
## grouping reads it: a painter who dragged tools keeps theirs.
var toolbox_group: StringName = &""

## Painting tools are blocked mid-stroke when the tool changes with the mouse
## still down, and are the ones that may draw a software brush ring. Replaces
## a comparison against the brush's and the eraser's ids in two places.
var is_painting: bool = false

var wants_brush_cursor: bool = false

## Control.CURSOR_* for when the ring is not drawn.
var cursor_shape: int = Control.CURSOR_ARROW

## An optional picture to draw in place of `cursor_shape` while this tool is the
## active one, taking the shape's slot through `Input.set_custom_mouse_cursor`
## and given back on deactivate.
##
## A `Control.CursorShape` is one of Godot's stock arrows, so without this a
## descriptor could not ask for a picture and the eyedropper would settle for a
## crosshair. `cursor_shape` is still what a painter sees if this is null or
## fails to load, so a tool naming a picture is never worse off than one that
## does not.
var cursor_texture: Texture2D = null

## An outline to draw in place of the brush ring, answered rather than
## stored.
##
## The note is "brush circle cursor should copy the image mask shape if using an
## image", and the shape changes whenever the painter loads a tip or turns one,
## which is not a thing a descriptor registered at startup can hold. So this is
## a `Callable` taking nothing and answering a `PackedVector2Array`: a closed
## polyline in units of the ring's radius, already turned and narrowed, and
## empty for a tool or a tip that has no shape of its own.
##
## The overlay draws whatever comes back, scaled by the radius it was going to
## draw a circle at. That is what keeps it from learning what a brush is: the
## points are numbers, and the file that knows what they mean is the module's.
var cursor_outline: Callable = Callable()

## Where the point of `cursor_texture` is, as a fraction of its own size, not in
## pixels. The picture is resized to the cursor size the display asks for, and a
## hotspot in pixels would drift off the tip every time that number changed.
var cursor_hotspot: Vector2 = Vector2.ZERO

## InputMap action that permanently selects this tool ("tool_brush").
var activate_action: StringName = &""

## InputMap action that selects it only while held ("tool_pan_quick").
var quick_action: StringName = &""

## Higher wins when several quick actions are held. Replaces the _QUICK_TOOLS const.
var quick_priority: int = 0

## Whether the tool is offered on embedded surfaces such as the info docker's
## scratchpad. Replaces a duplicated six-tool registration block.
var available_in_embedded: bool = true

## Instantiated once per surface by the registry, so every surface gets its own
## tool instance while modules describe the tool only once.
var tool_script: Script = null

## Optional: settings shared across surfaces (a module may hand every surface's
## instance the same settings object so brush size follows the user around).
var shared_settings: Resource = null

## What the tool options bar and the canvas right-click menu offer while this
## tool is the permanent one, in this order. A tool that declares none shows
## an empty bar, which is honest for pan and zoom.
var options: Array[SaOptionSpec] = []

## The engine whose presets this tool takes, the id a settings script declares as
## `PRESET_ENGINE`. The presets docker lists every preset whatever tool is active
## and dims the ones of another engine against this. Empty takes the engine the
## settings the tool carries declares, and **a tool that declares one nowhere
## takes no presets**: the grid dims nothing against it and Save as... is dead,
## because a class name is not an engine.
var preset_engine: StringName = &""

## A right press on the canvas toggles a docker under the pointer under this
## tool rather than the context menu: Brush Presets or the pop-up palette, as
## the painter chose on Preferences > Brushes.
var opens_docker_on_right_click: bool = false

## The name [member opens_docker_on_right_click] had until the right click
## could open the pop-up palette as well. Kept as a second
## name for the same member, because a module in a repository of its own sets
## it, and a stranger's module setting a property that is gone fails at load.
var opens_presets_on_right_click: bool:
    get:
        return opens_docker_on_right_click
    set(val):
        opens_docker_on_right_click = val

## A Shift left drag on the canvas turns the view under this tool, see `ToolMachine._turn_with_left`.
var turns_view_on_shift_drag: bool = false

## The keys this tool reads on its own press, `KEY_SHIFT` and `KEY_ALT` for the
## selection tools, whose chord adds and subtracts. Held with this tool in the
## hand, such a key holds no quick tool, so Alt subtracts rather than putting the
## Eyedropper in the hand. Every other key of a quick action
## still holds it, Space's pan and Ctrl's pick among them.
var reads_keys: Array[int] = []

## Where a hand-back with nowhere to go lands, see `ToolMachine.fallback_tool_name`.
var is_fallback: bool = false

## A detour from painting, such as the Transform: its chord pressed while it is
## already the tool in hand goes back to the tool before it, through
## `ToolMachine.return_to_previous_tool`.
var is_detour: bool = false

## Writes [member ToolState.last_pressure], which the Info docker's Pressure row shows.
var reads_pressure: bool = false

## The tool that picks a colour off the canvas, which `SaPickHold` puts in the
## hand while a window waits for a pick. The base module sets it on its
## Eyedropper, and the skeleton names no module's tool, as with [member is_fallback].
var picks_colour: bool = false

## The tool that erases, which a pen button bound to Eraser while held puts in
## the hand, through [method ToolMachine.eraser_tool_name]. The stamp brush
## module sets it on its Eraser, and the skeleton names no module's tool, as
## with [member picks_colour].
var erases: bool = false

## The Brush: the tool whose button, key and count in the usage tally stand for
## every brush engine a module registers through
## [method SaContext.register_brush_engine], so a painter picks one Brush and
## chooses what it paints with by the preset. The stamp brush sets it on its
## brush, and the skeleton names no module's tool, as with [member is_fallback].
var takes_brush_engines: bool = false

## Set by the registry when a module registers this through
## [method SaContext.register_brush_engine]: an engine the Brush paints with,
## built by the tool machine like a tool and never offered as one. Modules never
## write this.
var is_brush_engine: bool = false

## A tool not ready for every painter. It stays registered and the tool machine
## builds it, so the door and a document that needs it still reach it, but the
## toolbox, the Tools menu and the search leave it out until Preferences'
## Show experimental tools is on.
var experimental: bool = false

## Set by the registry. Modules never write this.
var owner_module: StringName = &""


## Whether a painter is offered this tool: every tool but an experimental one,
## which waits for the setting.
func offered() -> bool:
    return not experimental or SaSettings.experimental_tools


static func create(tool_id: StringName, script: Script) -> SaToolDescriptor:
    var descriptor := SaToolDescriptor.new()
    descriptor.id = tool_id
    descriptor.tool_script = script
    descriptor.display_name = String(tool_id).capitalize()
    return descriptor


## Whether *descriptor*, which may be null, reads *key* on its own press.
static func reads_key(descriptor: SaToolDescriptor, key: int) -> bool:
    return descriptor != null and descriptor.reads_keys.has(key)


func is_valid() -> bool:
    return not String(id).is_empty() and tool_script != null
