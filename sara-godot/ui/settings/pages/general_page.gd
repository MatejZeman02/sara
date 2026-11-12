## Preferences > Interface, its last part: the pen's door, how deep the undo
## history goes, the advanced options, and what shows while Sara starts.
##
## **The first page holds what a painter changes in their first sessions, the
## most used first**, and no system path as the first thing. The Interface page
## is three parts drawn as one, and its rows read down in this order, each for
## the reason beside it:
##
## - **I'm coming from** (`SaComingFromRow`), first because one press of it
##   sets the shortcuts, the theme, the layout and the picker a painter from
##   Krita or Photoshop would otherwise hunt through four pages for.
## - **UI scale** and **Font size** (`SaWorkspacePage`), because a painter on a
##   laptop at scale 2, or one who needs larger text, meets them before
##   anything else, and they are the settings new painters ask about most.
## - **Interface font**, in the same section, since the face is read with the
##   size and Atkinson Hyperlegible is there for the same eyes.
## - **Colour theme** (`SaColorThemesPage.ThemeChoice`), the one choice most
##   painters make, which otherwise sits at the top of a 47 row editor.
## - **Pen pressure**, a door and not a row: the Pen and tablet page is about
##   the pen and keeps every control of it, so its ceiling stays there and this
##   line says where the ceiling is now, because a painter looks for the
##   calibration under Edit first.
## - **Undo steps**, the one row of the undo budget, which a painting ran into
##   159 steps deep.
## - **Advanced options**, the one switch behind a Preferences row the painters
##   pressed, four times, though from the Tool Options docker, whose own check
##   is the same switch, so it comes after the undo depth that has no other.
## - **Show the welcome window**, then **Show the last session while Sara
##   starts**: the first is the window a painter turned off and then could not
##   find again, the second a picture at boot.
##
## The settings folder was the first row here, and is at the foot of Files,
## where a painter who means to move it looks among the files. Dockers inside
## the main window went to Layouts and dockers, beside the layouts it moves.
class_name SaGeneralPage
extends SaSettingsPage

## What Calibrate the pen… calls, the window's way to Pen and tablet at its
## calibration, or nothing for a page built with no window, which dims it.
var _open_pen: Callable = Callable()

var _pen_row: SaPageRow = null


## *open_pen* is set before `super()`, because the base class declares the page
## in its `_init`.
func _init(open_pen: Callable = Callable()) -> void:
    _open_pen = open_pen
    super()
    (_pen_row.control as Button).disabled = not _open_pen.is_valid()


func build(ui: SaPage) -> void:
    var pen := ui.section("Pen")
    _pen_row = pen.action("Pen pressure", _on_calibrate_pressed).button("Calibrate the pen...").named(&"calibrate_pen")
    _pen_row.node("CalibratePenButton").explain(pen_sentence())

    var history := ui.section("Undo history")
    (
        history
        . slider(
            "Undo steps", SaSettingsValues.MIN_HISTORY_DEPTH, SaSettingsValues.MAX_HISTORY_DEPTH, SaSettings, ^"history_depth"
        )
        . named(&"history_depth")
        . step(1.0)
        . decimals(0)
        . node("HistoryDepthSlider")
        . explain(
            tr(
                (
                    "How many steps that cover the whole canvas, a fill, a gradient or a crop, Ctrl+Z can walk back. "
                    + "The history is bounded by memory rather than by steps, so ordinary dabs go far deeper than this "
                    + "and only the expensive ones are counted. The Info docker's History rows say what it is holding."
                )
            )
        )
    )
    (
        history
        . toggle("Layer visibility in the undo history", SaSettings, ^"visibility_in_history")
        . named(&"visibility_in_history")
        . explain(
            tr(
                (
                    "On, showing or hiding a layer is a step Ctrl+Z takes back. Off, the eye leaves the history alone "
                    + "and only marks the document changed, as Photoshop does."
                )
            )
        )
    )

    var tools := ui.section("Tool options")
    # A switch like every other row on the page, and not the check box it was.
    var advanced := CheckButton.new()
    advanced.name = "AdvancedOptionsCheck"
    advanced.button_pressed = SaSettings.advanced_options
    # `SaMake` has no switch, and the walker reads a control by the kind it was
    # made as, so the dump's `preferences_check` goes on reading this one.
    advanced.set_meta(SaMake.KIND_META, SaMake.Kind.TOGGLE)
    advanced.toggled.connect(func(pressed: bool) -> void: SaSettings.advanced_options = pressed)
    # The docker's own check writes the same setting while this page is open, so
    # the box follows it rather than showing the state the page was built with.
    EventBus.advanced_options_changed.connect(advanced.set_pressed_no_signal)
    tools.custom("Advanced options", advanced).named(&"advanced").explain(
        tr(
            (
                "Show the tool options a tool marks as advanced. Off by default, so the Tool Options docker "
                + "carries what a painter reaches for and not everything a tool can be told. The Advanced "
                + "check at the top of the Tool Options docker is the same switch."
            )
        )
    )

    tools.toggle("Show experimental tools", SaSettings, ^"experimental_tools").named(&"experimental_tools").explain(
        tr(
            (
                "Offer the tools and layer kinds that are not ready for every painter yet, the vector shapes among "
                + "them. Off by default. A document that already holds such a layer opens and shows it either way."
            )
        )
    )

    var start := ui.section("Starting")
    # The welcome window's own switch hides it for good, and turning it back on
    # would take finding a window that does not open. Bound to the setting, so a
    # press on that switch shows here while the page is open.
    start.toggle("Show the welcome window", SaSettings, ^"welcome_at_start").named(&"welcome_at_start").explain(
        tr(
            (
                "The window with the recent pictures, News and Quick settings, opened when Sara starts with no "
                + "document to open. The Show this at start switch on the window itself is this same setting."
            )
        )
    )
    start.toggle("Show the last session while Sara starts", SaSettings, ^"show_last_session").named(&"show_last_session").explain(
        tr(
            (
                "While Sara starts, its window is covered by a blurred picture of the last session with a line "
                + "that says what is loading. When off, the cover shows a stock picture and a quit writes no picture "
                + "of the painting to the settings folder."
            )
        )
    )


## What the pen's line says: where full pressure is now, then where the button
## goes. The page is built again on every open, so the ceiling read here is the
## one Pen and tablet last stored. It speaks of the ceiling alone, because the
## pressure curve beside it is a second calibration that can be set while the
## ceiling is not.
func pen_sentence() -> String:
    var now := tr("Full pressure is the pen's maximum reading until you calibrate it.")
    if SaSettings.tablet_max_pressure < SaTablet.DEFAULT_MAX_PRESSURE:
        now = tr("Full pressure at %.2f of what the pen can send.") % SaSettings.tablet_max_pressure
    return (
        now
        + " "
        + tr(
            (
                "Calibrate the pen... opens Preferences > Pen and tablet at the strip that measures it, "
                + "beside the pressure curve, the driver and the pen's buttons."
            )
        )
    )


func _on_calibrate_pressed() -> void:
    if _open_pen.is_valid():
        _open_pen.call()
