## The Stats docker's quantizer: a switch that puts the Shape Check view on the
## canvas and takes it off, and a slider over how many steps of lightness the
## view snaps to.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A view mode on the canvas, with its level slider on the docker.** The
## quantizer is the Shape Check mode's Levels half, so the switch here is one
## more door to the mode the View menu's row and Ctrl+Shift+Q already open,
## and the slider moves `SaSettings.shape_check_level_count`, the count the
## view's shader reads.
##
## **The switch shows whichever door turned the view.** It holds no value of
## its own: it reads the view transform registry's mode, and the registry's
## `changed` is passed on as this part's [signal changed], which the page
## listens to as it listens to any target that has one. So Ctrl+Shift+Q or the
## View menu moves the switch as a press on it does. The slider writes the
## setting and listens to its `changed`, so a count a profile or the `prefs`
## step sets moves it too.
##
## **Neither waits for the compute switch.** The view reduces nothing, so the
## part leaves [member SaStatsPart.reduction] null, the service never hears of
## it, and both controls work with the docker's switch off.
##
## **The registry is found, not handed**, as the Display page finds its own:
## the docker makes every part with no arguments and is itself built with no
## registries. A suite hands one to [method _init] instead.
extends SaStatsPart

## Emitted when the view moved, through any door, so the page reads the switch
## again.
signal changed

## The mode the switch puts on, the Shape Check view `skeleton_module.gd`
## registers.
const MODE := &"shape_check"

## What the two rows say under their titles. Short, because the docker is a
## column under three hundred pixels wide and the sentence wraps beside the
## control.
const SWITCH_SENTENCE := "The canvas in flat steps of lightness, as Ctrl+Shift+Q shows it."
const LEVELS_SENTENCE := "How many steps the lightness snaps to."

## The slider's width before the docker gives it more, the widest count it
## shows with room to drag, so the row stays inside the docker's 300 pixels.
const LEVELS_WIDTH := 56

## What the slider says on hover, the part a short sentence leaves out.
const LEVELS_HOVER := (
    "From two, light against dark, to eleven. The Shape check row in Preferences > Canvas and colour (F3)"
    + " picks whether the view snaps the lightness, averages the canvas into blocks, or does both."
)

## Whether the Shape Check view is on the canvas, the switch's binding. Read off
## the registry every time, so it is true however the view went on. Off puts
## back the ordinary view only when the Shape Check view is the one showing, so
## a write of off never takes away a mode another door put on.
var showing: bool:
    get:
        var registry := _registry()
        return registry != null and registry.mode == MODE
    set(value):
        var registry := _registry()
        if registry == null:
            return
        if value:
            registry.set_mode(MODE)
        elif registry.mode == MODE:
            registry.set_mode(SaViewTransformRegistry.NORMAL)

## The view transforms the switch reads and moves, handed in or found, and null
## while there is no main scene to find them in.
var _view_transforms: SaViewTransformRegistry = null

## The slider over the count, once the page is declared. A node held by a part
## counts no reference, and the docker frees it with the page.
var _levels: FactorSlider = null


## *view_transforms* is the registry to read and move, for a suite. The docker
## makes the part with none, and it finds the application's.
func _init(view_transforms: SaViewTransformRegistry = null) -> void:
    _view_transforms = view_transforms
    _listen()


## A section of its own under the docker's switch and line: the switch, then the
## slider.
func declare(page: SaPage) -> void:
    _registry()
    var rows := page.section("Quantizer")
    rows.toggle("Shape Check", self, ^"showing").named(&"quantizer").node("QuantizerSwitch").explain(SWITCH_SENTENCE)
    # Sara's own slider, made by `SaMake` so the `control` step finds it by its
    # name and moves it as a drag does. A box around it, because the page
    # draws a bare `FactorSlider` with no title beside it, its caption inside
    # the bar instead, and "Levels: 11" inside the bar beside the title column
    # asked the docker 408 wide where its layouts give it 300. So the title
    # stands where the switch's does, and the bar holds the number alone.
    _levels = SaMake.slider(
        null,
        "QuantizerLevels",
        float(SaInHand.Settings.MIN_SHAPE_LEVELS),
        float(SaInHand.Settings.MAX_SHAPE_LEVELS),
        1.0,
        float(SaInHand.Settings.read(&"shape_check_level_count"))
    )
    _levels.decimal_places = 0
    # Both, because the slider set its minimum from the default width when it
    # was made and reads `preferred_width` again only when its value moves.
    _levels.preferred_width = SaUI.px(LEVELS_WIDTH)
    _levels.custom_minimum_size.x = SaUI.px(LEVELS_WIDTH)
    _levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _levels.tooltip_text = SaPage.translated(LEVELS_HOVER)
    _levels.value_changed.connect(_levels_moved)
    var box := SaMake.row(null, "QuantizerLevelsBox")
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(_levels)
    var levels := rows.custom("Levels", box).named(&"quantizer_levels").explain(LEVELS_SENTENCE)
    # Bound for the dump, which reads a row's value through its binding. The
    # writes go through the slider's own signal below, because the page moves
    # only the controls it drew itself.
    levels.target = SaInHand.Settings.row_target()
    levels.property = ^"shape_check_level_count"
    if not SaInHand.Settings.changed().is_connected(_setting_moved):
        SaInHand.Settings.changed().connect(_setting_moved)


## The registry, finding it the first time there is a main scene to find it in.
func _registry() -> SaViewTransformRegistry:
    if _view_transforms == null:
        _view_transforms = _found()
        _listen()
    return _view_transforms


## Passes the registry's `changed` on as this part's. A signal holds no
## reference to the part, so the registry keeps nothing alive.
func _listen() -> void:
    if _view_transforms != null and not _view_transforms.changed.is_connected(_view_moved):
        _view_transforms.changed.connect(_view_moved)


func _view_moved() -> void:
    changed.emit()


## A drag or a step moved the slider: the count is the whole number it shows.
func _levels_moved(moved: float) -> void:
    SaInHand.Settings.write(&"shape_check_level_count", roundi(moved))


## A count set anywhere else, a profile or the `prefs` step, moves the slider
## without a write back.
func _setting_moved(property: StringName) -> void:
    if property == &"shape_check_level_count" and is_instance_valid(_levels):
        _levels.set_value_no_signal(float(SaInHand.Settings.read(&"shape_check_level_count")))


## The application's view transforms, read off the main scene by name as
## the Display page reads them, or null when there is no main scene.
static func _found() -> SaViewTransformRegistry:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null:
        return null
    var registries := main_node.get(&"registries") as SaRegistries
    return registries.view_transforms if registries != null else null
