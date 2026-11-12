## A filter's time: a number in seconds from nought that a scrubber sets and a
## play button moves, with the loop length it comes back round at.
##
## The stateless half of time on the canvas: a filter whose picture is a
## function of `t` alone, a noise that drifts or a hue that cycles, declares one
## in its `build` with [method declare] and reads it in `run` as
## `parameter(SaTimeRow.KEY)`. Nothing else is new. The time is a parameter of
## the filter's store like a slider's, so a record keeps it and `.sad` writes it,
## a preset holds it, and a change moves the record's revision and the chain
## redraws the record over the chunks the window reaches.
##
## **Two rows, both bound to the store.** The time row is a [SaValueControl], so
## the page binds it the way it binds a slider and a record or an undo shows in
## it, and it holds the play button and a [FactorSlider] that scrubs and reads
## the time inside its bar. The loop length is a plain `ui.slider` under it.
##
## **Playing is a hand moving the scrubber once a frame.** Each frame adds the
## frame's duration to the time, through the same write a drag makes, so the
## dialog reruns its preview and the attached record's panel writes the record
## through `replace_parameters`, the panel's one door. A frame past the loop
## length comes back round from nought. Pausing stops the frames and leaves the
## time where it stopped, which is what Bake and Flatten then take.
##
## A filter that writes its own `parameters()` keeps no store, so its time row
## would be bound to nothing. Declaring a time needs the store's values.
class_name SaTimeRow
extends RefCounted

## The parameter the time is kept under, the store's own name for it, so core
## reads a filter's time without naming this file.
const KEY: StringName = SaFilter.Store.TIME

## The parameter the loop length is kept under.
const LOOP: StringName = &"t_loop"

## The longest loop, and so the latest time, in seconds: an hour.
const LONGEST: float = 3600.0

## The shortest loop a painter can type, in seconds.
const SHORTEST: float = 0.1

## How far an arrow key or a notch of the wheel moves the time, in seconds.
const STEP: float = 0.1

## The decimals the time and the loop are read in.
const DECIMALS: int = 2


## Declares the time row and the loop row under it on *ui*, the time labelled
## *label* and the loop *loop* seconds long until a painter changes it. Answers
## the time row.
##
## The loop row is made after the time row, so the scrubber is handed a list it
## fills once the loop row exists. The scrubber is built at realize, by when the
## list holds it, and holds it weakly, because the page holds both rows.
static func declare(ui: SaDialog, label: String = "Time", loop: float = 10.0) -> SaPageRow:
    ui.parameter(KEY, 0.0, 0.0, LONGEST)
    var loop_rows: Array[WeakRef] = []
    var made := ui.custom(label, func(_rerun: Callable) -> Control: return Scrubber.new(loop_rows)).named(KEY)
    var loop_row := ui.slider("Loop", 1.0, 60.0, clampf(loop, SHORTEST, LONGEST), _loop_options()).named(LOOP)
    loop_row.custom_control.tooltip_text = SaPage.translated(
        "How many seconds play runs before the time comes back round to nought."
    )
    loop_rows.append(weakref(loop_row))
    return made


static func _loop_options() -> Dictionary:
    return {"hard_min": SHORTEST, "hard_max": LONGEST, "step": 0.01, "decimals": DECIMALS, "suffix": " s"}


## The time row's control: the play button and the scrubber beside it, holding
## the time as the number the page binds.
##
## A box laid over the whole control does the layout, and the control asks for
## the box's size, so the row sizes as a slider row does.
class Scrubber:
    extends SaValueControl

    const NODE_NAME := "TimeScrubber"

    ## Whether the frames are moving the time.
    var playing: bool = false

    ## How many frames have moved it since the last play, which is what a dump
    ## and a suite count.
    var frames: int = 0

    var play_button: PlayButton = null
    var slider: FactorSlider = null

    var _box: HBoxContainer = null
    var _loop_rows: Array[WeakRef] = []

    func _init(loop_rows: Array[WeakRef]) -> void:
        super(0.0, 0.0, LONGEST, STEP)
        _loop_rows = loop_rows
        name = NODE_NAME
        tooltip_text = SaPage.translated(
            "Seconds from nought. Play moves the time on by each frame and brings it back round at the loop length."
        )
        _box = SaMake.row(self, "TimeBox", SaTheme.GAP)
        _box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _box.mouse_filter = Control.MOUSE_FILTER_PASS
        _box.minimum_size_changed.connect(update_minimum_size)
        play_button = PlayButton.new()
        play_button.toggled.connect(_play_toggled)
        _box.add_child(play_button)
        slider = SaMake.slider(_box, "TimeSlider", 0.0, LONGEST, 0.01, 0.0)
        slider.decimal_places = DECIMALS
        slider.suffix = " s"
        slider.tooltip_text = SaPage.translated("Drag to scrub the time.")
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slider.value_changed.connect(move_to)
        var loop_row := _loop_row()
        if loop_row != null:
            loop_row.changed.connect(_loop_moved)
        _fit_loop()
        set_process(false)

    ## The loop length the loop row holds, or the scrubber's end when the row is
    ## gone.
    func loop_length() -> float:
        var loop_row := _loop_row()
        if loop_row == null:
            return high
        return clampf(SaTyped.real(loop_row.read(), high), SHORTEST, LONGEST)

    ## Starts or stops the frames moving the time, as the button does.
    func play(on: bool) -> void:
        play_button.button_pressed = on

    ## One frame of *seconds*: while playing, the time moves on by them and
    ## comes back round from nought past the loop length, and paused it holds.
    ## What `_process` calls with the frame's duration, and a suite with a
    ## duration of its own in place of a frame.
    func advance(seconds: float) -> void:
        if not playing:
            return
        _fit_loop()
        var next := value + seconds
        if next >= high:
            next = fposmod(next, high)
        frames += 1
        move_to(next)

    func move_to(wanted: float) -> void:
        super(wanted)
        slider.set_value_no_signal(value)

    ## A record, a preset or an undo shows its time, and the loop it was saved
    ## with, without saying so.
    func show_value(shown: float) -> void:
        _fit_loop()
        super(shown)
        slider.set_value_no_signal(value)

    func describe() -> Dictionary:
        var out := super()
        out["playing"] = playing
        out["frames"] = frames
        out["loop"] = high
        return out

    func _process(delta: float) -> void:
        advance(delta)

    func _get_minimum_size() -> Vector2:
        return _box.get_combined_minimum_size() if _box != null else Vector2.ZERO

    ## The row sets a control it does not know to shrink, and a scrubber wants
    ## the whole control column a slider has.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_PARENTED:
            size_flags_horizontal = Control.SIZE_EXPAND_FILL

    ## The scrubber ends at the loop length, and a time past it reads full.
    func _fit_loop() -> void:
        high = loop_length()
        slider.max_value = high

    func _loop_row() -> SaPageRow:
        return null if _loop_rows.is_empty() else _loop_rows[0].get_ref() as SaPageRow

    ## The loop row moved: the scrubber ends at the new length, and a time past
    ## it comes in to the end, so what the slider shows is what the record holds.
    func _loop_moved(_length: Variant) -> void:
        _fit_loop()
        move_to(value)

    func _play_toggled(on: bool) -> void:
        playing = on
        if on:
            frames = 0
        set_process(on)
        play_button.queue_redraw()

    ## The button the scrubber plays and pauses with, a toggle that draws a
    ## triangle while it is up and two bars while it is down. Drawn rather than
    ## written, because the interface fonts have no glyph for either.
    class PlayButton:
        extends Button

        const NODE_NAME := "TimePlay"

        ## How much of the button's shorter side the glyph spans.
        const GLYPH: float = 0.42

        func _init() -> void:
            name = NODE_NAME
            toggle_mode = true
            focus_mode = Control.FOCUS_NONE
            custom_minimum_size = Vector2(float(SaUI.px(30)), 0.0)
            SaTheme.make_toggle(self)
            # The walker reads and moves a toggle, so a scenario can say play.
            set_meta(SaMake.KIND_META, SaMake.Kind.TOGGLE)
            tooltip_text = SaPage.translated("Play the filter's time.")
            toggled.connect(
                func(on: bool) -> void:
                    tooltip_text = SaPage.translated("Pause the filter's time." if on else "Play the filter's time.")
            )

        func _draw() -> void:
            var side := minf(size.x, size.y) * GLYPH
            var middle := size / 2.0
            var ink := get_theme_color("font_pressed_color" if button_pressed else "font_color", "Button")
            if button_pressed:
                var bar := Vector2(side * 0.32, side)
                draw_rect(Rect2(middle - Vector2(side * 0.42, side / 2.0), bar), ink)
                draw_rect(Rect2(middle + Vector2(side * 0.1, -side / 2.0), bar), ink)
                return
            var left := middle.x - side * 0.4
            draw_colored_polygon(
                PackedVector2Array(
                    [
                        Vector2(left, middle.y - side / 2.0),
                        Vector2(left + side * 0.9, middle.y),
                        Vector2(left, middle.y + side / 2.0),
                    ]
                ),
                ink
            )
