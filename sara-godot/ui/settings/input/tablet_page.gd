## Preferences > Tablet: every row about the pen, in the order a painter sets
## one up. Which driver reads it, how hard it presses, what its buttons do, and
## the pointer and the ring it moves over the panels and the canvas.
##
## The driver, Sara's own pointer and the cursor lead are here rather than on
## the Workspace page, because a painter setting up a pen opens this page and
## should find all of what a pen needs.
##
## The calibration is a spanning custom row with no label of its own, and it
## draws its strip, its maximum and its curve as three rows of the row shape,
## so a search for pressure finds the page and lands on them. The strip and its
## controls are `SaTabletCalibration`'s own, beside the sweep.
##
## Below it, what each of the pen's buttons does: a choice row a
## button, over the one table `SaSettings.pen_buttons` stores, which the tool
## machine reads at every press. The rows bind through `SaPageBinding` because
## a button is a key of that table and not a property of its own, and the writer
## hands the settings a new table so the setter runs and the profile is written.
class_name SaTabletPage
extends SaSettingsPage

## The tablet driver row's key, named rather than taken from its label so the
## change handler can match it before the page has keyed anything.
const DRIVER_ROW := &"tablet_driver"

## The Middle row's Wayland hint while a pen module reads the pen from the
## kernel, in place of the one that says the upper's release in the air is never
## heard, which the kernel hears. The kernel is the module's business, so the
## sentence says what the painter gets and not where it comes from.
const MIDDLE_HINT_WITH_THE_KERNEL := (
    "The barrel's upper button. On Wayland, press it while the pen hovers: a touch with it held then counts "
    + "as the button, and a touch after you let it go counts as the tip. The mouse's wheel press has the row below."
)

## The tablet driver row's model, the running engine's unless a suite handed
## one in.
var _driver: SaTabletDriver = null

## The tablet driver row, kept so its "In use here" can be said again after a
## switch and whenever the page is shown.
var _driver_row: SaPageRow = null

## The Cursor lead row, kept so its last sentence can follow the ring while the
## page is open. The setting, Sara's own pointer and the device moving the
## pointer each change whether the ring leads, so a sentence written once when
## the page is declared reads "Not leading here." under Auto, On and Off alike
## while the ring leads under On.
var _lead_row: SaPageRow = null

## Sara's own pointer row, kept for the same reason as the lead row: its last
## sentence says who draws the pointer here, and otherwise reads the answer the
## run began with after a pick, a driver switch and Preferences opened again,
## while the lead row below follows the pick.
var _pointer_row: SaPageRow = null

## The Middle row, kept so its hint says again what the pen module does
## whenever the page is shown. The module looks for the pen on a thread of its
## own, and finds it, or finds it may not read it, after the page was declared.
var _middle_row: SaPageRow = null


## *driver* stands in for the running engine's drivers, which is how a suite on
## a machine with no tablet offers the list Windows would. Set before `super()`,
## because the base class declares the page in its `_init`.
func _init(driver: SaTabletDriver = null) -> void:
    _driver = driver
    super()


func _ready() -> void:
    super()
    visibility_changed.connect(_on_page_shown)


## Each part opens its own section off *ui* rather than being handed one, so
## the page names `SaPage`, the door of `ui/page`, and no file behind it.
func build(ui: SaPage) -> void:
    _declare_driver_row(ui)

    var pressure := ui.section("Pen pressure")
    var calibration := SaTabletCalibration.new(true)
    calibration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pressure.custom("", calibration).named(&"calibration")

    _declare_buttons(ui)
    _declare_pointer_rows(ui)
    ui.row_changed.connect(_on_row_changed)


## Which driver reads the pen, offered from the drivers the running engine
## names. The row holds its own value rather than binding a preference, because
## a change has two places to go, the live driver and the profile, and
## `SaTabletDriver.choose` writes both.
func _declare_driver_row(ui: SaPage) -> void:
    var rows := ui.section("Driver")
    if _driver == null:
        _driver = SaTabletDriver.new(
            SaTabletDriver.engine_names(),
            DisplayServer.tablet_get_current_driver(),
            DisplayServer.tablet_set_current_driver,
            DisplayServer.tablet_get_current_driver
        )
    _driver_row = rows.choice("Tablet driver", _driver.choices()).named(DRIVER_ROW)
    _driver_row.value = _driver.current
    _driver_row.node("TabletDriverMode").explain(_driver_explanation())


## The driver row's sentence, ending on the driver the engine is using now.
func _driver_explanation() -> String:
    return (
        tr(
            (
                "Which driver reads the pen. Windows starts on WinTab, and Windows Ink is the fallback "
                + "for a tablet that ships no WinTab driver. Applies at once and at every launch."
            )
        )
        + (" " + _wintab_failed_sentence() if _driver.wintab_failed() else "")
        + " "
        + tr("In use here: %s.") % _driver.label_of(_driver.in_use())
    )


## Why the row reads another driver than the WinTab the profile asked for.
func _wintab_failed_sentence() -> String:
    return tr(
        (
            "WinTab failed to start, as it does while the tablet's own service is stopped, "
            + "so Windows Ink reads the pen for this session."
        )
    )


## Says the driver in use again, on the row's fields and on its line, so a
## switch to Windows Ink does not go on reading "In use here: WinTab" until a
## relaunch.
func _refresh_driver_row() -> void:
    if _driver_row != null and _driver != null:
        _driver_row.retitle(_driver_row.label, _driver_explanation())


## A row a button, each with the hint `SaSettingsPenButtons` gives it on this
## display server, saying which button of a usual pen arrives as the one the
## row is named for. The names stay the driver's, because that is all Sara sees
## of a pen, and the hint is where a painter holding one reads which to press.
func _declare_buttons(ui: SaPage) -> void:
    var rows := ui.section("Pen buttons")
    var table := SaPageBinding.new(
        func(button: StringName) -> Variant: return SaSettings.pen_buttons.get(String(button)),
        func(button: StringName, action: Variant) -> void:
            var bound := SaSettings.pen_buttons.duplicate()
            bound[String(button)] = String(action)
            SaSettings.pen_buttons = bound
    )
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        var id := String(button["id"])
        var row := rows.choice(button["label"], SaSettingsPenButtons.ACTIONS, table, NodePath(id))
        row.named(StringName("pen_" + id)).explain(button_hint(button, _wayland(), pen_source()))
        if id == "middle":
            _middle_row = row
            # The wheel press, beside the pen's Middle row and apart from it, on
            # the setting itself rather than on the table above. A middle press
            # follows this row unless a pen made it, so the pen's upper button
            # can hold the eraser while the wheel still pans.
            var wheel := rows.choice("Mouse middle button", SaSettingsPenButtons.ACTIONS, SaSettings, ^"mouse_middle")
            wheel.named(&"mouse_middle").explain(
                tr(
                    (
                        "The mouse's wheel press. A pen's upper button follows the Middle row above, and Sara tells the two "
                        + "apart by whether a pen moved the pointer last."
                    )
                )
            )
    (
        rows
        . note(
            tr(
                (
                    "A pen's buttons reach Sara as the mouse buttons its tablet's driver reports, so each hint says "
                    + "what most pens send rather than what every pen does. The eraser end is not a button: turned "
                    + "over, the pen erases with the brush in hand."
                )
            )
        )
        . named(&"pen_buttons_note")
    )


## What the row of *button* says. Its hint from `SaSettingsPenButtons`, and
## under *wayland* the Middle row also says what the pen module does with the
## upper button there: while *source* reads the pen from the kernel, the hint
## that says the upper's release is never heard gives way to one that says it
## is, and while it reads nothing, the source's own sentence says why and how
## to turn it on. With no pen module loaded the hint is as it was.
static func button_hint(button: Dictionary, wayland: bool, source: SaPenSource) -> String:
    var hint := SaSettingsPenButtons.hint(button, wayland)
    if not wayland or String(button["id"]) != "middle" or source == null:
        return hint
    if source.reads():
        hint = TranslationServer.translate(MIDDLE_HINT_WITH_THE_KERNEL)
    var said := source.said()
    return hint if said.is_empty() else hint + " " + said


## The pen source on the door, when a main scene holds the registries. The
## lookup `display_page.gd` makes, because a settings page is built by the
## Preferences window and is handed no registries.
static func pen_source() -> SaPenSource:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.registries
    return registries.pens.source() if registries != null else null


static func _wayland() -> bool:
    return DisplayServer.get_name() == "Wayland"


## Says the Middle row's hint again, for what the pen module found since.
func _refresh_middle_row() -> void:
    if _middle_row == null:
        return
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        if String(button["id"]) == "middle":
            _middle_row.retitle(_middle_row.label, button_hint(button, _wayland(), pen_source()))


## The Pointer section, the pointer Sara draws for a pen and the ring that
## leads it.
##
## Whether Sara draws its own pointer over the panels is built from
## `SaCursorPolicy.CURSOR_MODES` rather than from a list written here, so the
## row and the policy cannot come to name different things. Its hint says what
## the choice resolves to on this machine right now, because the default is the
## one setting whose meaning depends on the display driver and a row reading
## "Only where the system does not draw one" tells a painter nothing about
## whether it is currently doing so. Both is a debugging choice and is offered
## only under Advanced options, by [method pointer_modes].
##
## Whether the brush ring leads the pointer is built from
## `SaCursorPrediction.LEAD_MODES`, for the same reason. Its hint ends on what
## the ring does on this machine right now, the way the pointer row's does, and
## [method refresh_lead_row] says it again whenever that changes, and
## [method refresh_pointer_row] does the same for the pointer row.
func _declare_pointer_rows(ui: SaPage) -> void:
    var rows := ui.section("Pointer")
    var modes: Array = []
    for mode: Dictionary in pointer_modes():
        modes.append({"id": String(mode["id"]), "label": tr(String(mode["label"]))})
    _pointer_row = rows.choice("Sara's own pointer", modes, SaSettings, ^"software_cursor")
    _pointer_row.node("SoftwarePointerMode").explain(_pointer_explanation())

    var leads: Array = []
    for mode: Dictionary in SaCursorPrediction.LEAD_MODES:
        leads.append({"id": String(mode["id"]), "label": tr(String(mode["label"]))})
    # Keyed by the row's old title, Cursor lead, which suites and scenarios name,
    # and found by it too.
    _lead_row = rows.choice("Cursor prediction", leads, SaSettings, ^"cursor_lead").named(&"cursor_lead")
    _lead_row.node("CursorLeadMode").words("cursor lead").explain(_lead_explanation())


## The pointer modes the row offers. Both draws two pointers to show the lag
## between them, which is for whoever is measuring it and not for a painter, so
## it is offered while Advanced options is on and to a profile already set to it,
## which would otherwise open on a row naming a choice it does not list. The page
## is built afresh each time it opens, so the switch on General is read here.
static func pointer_modes() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for mode: Dictionary in SaCursorPolicy.CURSOR_MODES:
        var debugging := String(mode["id"]) == "both"
        if not debugging or SaSettings.advanced_options or SaSettings.software_cursor == "both":
            out.append(mode)
    return out


## The pointer row's sentence, ending on who draws the pointer here now.
func _pointer_explanation() -> String:
    return (
        tr(
            (
                "Some drivers give the mouse a pointer and the pen none, so a tablet has nothing to aim "
                + "with over the panels. Sara can draw one in its place. "
            )
        )
        + _drawn_by()
    )


## Who draws the pointer here now, the sentence the pointer row ends on.
func _drawn_by() -> String:
    if SaCursorPolicy.software_pointer_mode_active():
        return tr("Sara is drawing it here.")
    return tr("The system is drawing it here.")


## The lead row's sentence, ending on whether the ring leads here now.
##
## Asked of `SaCursorPrediction.lead_enabled`, the one question
## `CursorOverlay.drawn_centre` asks before it moves the ring off the pointer,
## so the hint and the ring cannot answer differently. Under Auto the answer
## turns on the device, and a painter reads this page with whichever one reached
## it: a mouse there is told what a pen would get, because a mouse that reached
## Preferences reading "Not leading here." while the pen leads on the canvas is
## told the wrong thing. Under Never there is no ring to lead at all,
## `SaCursorRing.cursor_ring_radius_at` answers none for every point, so the
## hint says that rather than a lead nobody can see.
func _lead_explanation() -> String:
    var verdict := tr("Not active on this system.")
    if SaSettings.software_cursor == "never":
        verdict = tr("No brush outline is drawn while Sara's own pointer is set to Never.")
    elif SaCursorPrediction.lead_enabled():
        verdict = tr("Active on this system.")
    elif a_pen_would_lead():
        verdict = tr("Not active for the mouse on this system. A pen would use it.")
    return (
        tr(
            (
                "Draws the brush outline where the pen will be a frame later, learned from recorded strokes. "
                + "Auto predicts a pen whose pointer Sara draws: every pen on Wayland, and any pen "
                + "with Sara's own pointer on Always or Both. "
            )
        )
        + verdict
    )


## Whether Auto would lead if a pen moved the pointer rather than the mouse
## that does, with everything else as it is here.
static func a_pen_would_lead() -> bool:
    if SaSettings.cursor_lead != "auto" or SaCursorPolicy.pointer_is_tablet:
        return false
    return SaCursorPrediction.auto_lead_on(true, SaCursorPolicy.sara_draws_the_pen())


## Says the pointer row's sentence again when who draws the pointer has
## changed, from the frame [method refresh_lead_row] is asked in. The pick is
## this row's own, but Auto turns on the display driver as well, and asking
## every frame is the one spelling that follows all of them.
func refresh_pointer_row() -> void:
    if _pointer_row == null:
        return
    var now := _pointer_explanation()
    if now != _pointer_row.explanation:
        _pointer_row.retitle(_pointer_row.label, now)


## Says the lead row's sentence again when what the ring does has changed.
##
## Asked every frame the page is on screen rather than on the row's own change,
## because two of the three things that move the answer are not on this row:
## Sara's own pointer is the row above, and the device is whichever one the
## painter picked up. Comparing the sentence costs a string, and only while
## Preferences shows this page.
func refresh_lead_row() -> void:
    if _lead_row == null:
        return
    var now := _lead_explanation()
    if now != _lead_row.explanation:
        _lead_row.retitle(_lead_row.label, now)


## One frame of the page on screen: the pointer's sentence follows the pick and
## the lead's follows the ring. A page off screen stops asking until it is shown
## again.
func _process(_delta: float) -> void:
    if not is_visible_in_tree():
        set_process(false)
        return
    refresh_pointer_row()
    refresh_lead_row()


## The page is shown again, by its category or by Preferences opening, and the
## driver and the lead may have changed since it was drawn.
func _on_page_shown() -> void:
    set_process(is_visible_in_tree())
    if is_visible_in_tree():
        _refresh_driver_row()
        _refresh_middle_row()
        refresh_pointer_row()
        refresh_lead_row()


## A pick on the driver row switches the live driver and the profile, and says
## the driver in use again.
func _on_row_changed(key: StringName, value: Variant) -> void:
    if key == DRIVER_ROW and _driver != null:
        _driver.choose(String(value))
        _refresh_driver_row()


## `{"workspace": {"lead": true}}`: every row of the cursor lead dropdown, which
## is selected, and whether the ring leads on this machine.
##
## Read off the built control rather than off `SaCursorPrediction.LEAD_MODES`,
## for the reason the pointer report gives: the constant is what the rule
## resolves and the dropdown is what a painter can reach.
##
## The line carries no prefix of its own: the capture that prints it adds one,
## so this file names the harness nowhere at all.
func lead_report() -> String:
    var opt := find_child("CursorLeadMode", true, false) as SaChoiceButton
    if opt == null:
        return "the Tablet page has no cursor lead row"
    var rows := opt.choice_labels()
    var out := PackedStringArray()
    (
        out
        . append(
            (
                "cursor lead '%s', %d row(s), the ring %s leading here, tablet=%s driver=%s"
                % [
                    SaSettings.cursor_lead,
                    rows.size(),
                    "is" if SaCursorPrediction.lead_enabled() else "is not",
                    str(SaCursorPolicy.pointer_is_tablet),
                    DisplayServer.get_name(),
                ]
            )
        )
    )
    for i in rows.size():
        var id: String = String(SaCursorPrediction.LEAD_MODES[i]["id"]) if i < SaCursorPrediction.LEAD_MODES.size() else "?"
        var here: bool = String(opt.selected_value()) == id
        out.append("  %d '%s' = %s%s" % [i, id, rows[i], " <- selected" if here else ""])
    # The hint as the row holds it now, so a scenario reads the sentence the
    # painter reads beside the verdict above rather than trusting the two agree.
    if _lead_row != null:
        out.append("  hint: %s" % _lead_row.explanation)
    return "\n".join(out)


## `{"workspace": {"pointer": true}}`: every row of the pointer dropdown in the
## order it offers them, which is the one thing a scenario can prove about a
## debugging mode nobody can photograph.
##
## Read off the built control rather than off `SaCursorPolicy.CURSOR_MODES`,
## because a list and a row agreeing is exactly the claim: the constant is what
## the policy resolves and the dropdown is what a painter can reach, which is
## Both only under Advanced options.
##
## The line carries no prefix of its own, for the reason the lead report gives.
func pointer_report() -> String:
    var opt := find_child("SoftwarePointerMode", true, false) as SaChoiceButton
    if opt == null:
        return "the Tablet page has no pointer row"
    var rows := opt.choice_labels()
    var out := PackedStringArray()
    out.append(
        (
            "pointer mode '%s', %d row(s), Sara %s drawing it here"
            % [SaSettings.software_cursor, rows.size(), "is" if SaCursorPolicy.software_pointer_mode_active() else "is not"]
        )
    )
    var ids := opt.choice_values()
    for i in rows.size():
        var id: String = String(ids[i]) if i < ids.size() else "?"
        var here: bool = String(opt.selected_value()) == id
        out.append("  %d '%s' = %s%s" % [i, id, rows[i], " <- selected" if here else ""])
    return "\n".join(out)
