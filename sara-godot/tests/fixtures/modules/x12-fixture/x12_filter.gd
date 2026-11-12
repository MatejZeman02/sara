## A fixture filter: the three things a filter may bring beside `build` and `run`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every one of the three is spelled so that the default would not do, because a
## fixture that lands on the default spelling proves nothing about the door. The
## title slugs to `x12_fixture_tint`, so the command the registry would derive
## carries the module's hyphen and the title twice over. The chord is a key no
## built-in command answers to, so a suite that opens this filter by it and one
## that opens it from the menu are telling two things apart.
##
## It is written the way the box blur is written, because that is the shape every
## door is measured against, and it hands over a widget the closed set
## of six has no member for.
extends SaFilter

## The command and the InputMap action this filter asks for by name, which is
## the whole of the third declaration: a filter whose command has already
## shipped under a name of its own says so here and keeps every chord a painter
## has rebound to it.
const DECLARED_COMMAND := &"filter_x12_fixture_tint"

## Ctrl+Shift+O. Free in the shipped Krita and Photoshop maps, and the suite
## checks it against every command the skeleton registers rather than trusting
## that sentence. The first draft declared Ctrl+Shift+Y, which
## `view_minimap_proof` already answers to: the filter never opened, because the
## dispatcher reached the minimap's command first, and it took the scenario to
## say so. Ctrl+Shift+J belongs to Layer via Cut, as in
## Photoshop and Krita.
const DECLARED_KEY := KEY_O


## The widget the filter hands over instead of one of the six: a bar of its own
## with the one method a capture door needs.
##
## Inner rather than a sibling file, which is the rules of structure's answer for
## a small helper, and it is what a student writes when the closed set has no
## widget for what they mean.
class StopsBar:
    extends HSlider

    ## How many times the harness moved this through its door, so a suite can
    ## say the door was reached rather than that a number happened to change.
    var moved: int = 0

    ## `{"stop": 3}` sets the bar, which is this widget's own word for what it
    ## holds. An unknown key is ignored rather than refused, because the step
    ## that reaches here carries the name the row was found by as well, and a
    ## widget that refused it would make every scenario spell the same call two
    ## ways.
    func capture_option_edit(spec: Dictionary) -> String:
        moved += 1
        if spec.has("stop"):
            set_value_no_signal(float(spec["stop"]))
        return "SaCapture: x12 stops bar is %s" % JSON.stringify({"stop": value, "moved": moved})


var amount: SaSlider = null
var bar: StopsBar = null


func title() -> String:
    return "Fixture Tint"


func action_name() -> StringName:
    return DECLARED_COMMAND


func chord() -> Array[InputEvent]:
    var event := InputEventKey.new()
    event.keycode = DECLARED_KEY
    event.ctrl_pressed = true
    event.shift_pressed = true
    return [event]


func build(ui: SaDialog) -> void:
    ui.title("Fixture Tint")
    ui.preview()
    amount = ui.slider("Amount", 1, 10, 4)
    ui.custom("Stops", _make_bar)
    ui.apply_cancel()


## What `ui.custom` calls once, when the dialog is realized.
##
## It is handed the dialog's own "ask for a rerun" call and wires it to the bar,
## which is the half a widget the page cannot read has to do for itself: the
## page has no binding to write, so a control that changes what the filter reads
## is the one that has to say so.
func _make_bar(rerun: Callable) -> Control:
    bar = StopsBar.new()
    bar.name = "StopsBar"
    bar.min_value = 0.0
    bar.max_value = 8.0
    bar.step = 1.0
    bar.value = 2.0
    bar.value_changed.connect(func(_moved: float) -> void: rerun.call())
    return bar


func run(ctx: SaFilterContext) -> void:
    # The layer as it stands. The shortest run whose result a scenario can see,
    # and the one that keeps this fixture out of the kernel manifest.
    ctx.show(ctx.layer_pixels(0))
