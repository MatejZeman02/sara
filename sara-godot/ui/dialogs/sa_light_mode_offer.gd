## The offer of the settings for a weak GPU, made once: one sentence and two
## buttons, as a row at the top of the welcome window, or as a small question of
## its own when the welcome window does not open. It says the Performance page's
## own words, `SaPerformancePage.WEAK_GPU` and `USE_THEM`, rather than "a
## light mode", which a painter reads as a pale theme.
##
## **Whether to offer is two facts.** `SaWeakGpu` judges the device, and its
## class comment is the rule. `SaSettings.light_mode_offer` holds the answer,
## and either answer is kept, so a profile that has answered is never asked
## again. The Performance page is there either way, and both answers say where.
##
## **Use them presses the page's Use them**, which is
## `SaSettingsPerformance.apply_light`, the call the page's own button makes.
## The set is a preset and the offer does not turn anything on that the page
## could not turn off again.
##
## **Only a real start judges the device.** `SaBoot` hands [method at_start] to
## the end of the boot, and refuses it in a capture run, so a suite and every
## committed scenario meet no offer whatever GPU the gate lands on, the software
## rasteriser of a pixman compositor included. A scenario that wants it pretends
## a device through [method capture_offer].
@tool
class_name SaLightModeOffer
extends HBoxContainer

## The row's name, which the boot's window is searched for.
const NODE_NAME := "LightModeOffer"

## The question's window name, so a scenario finds it among other questions.
const DIALOG_NAME := "LightModeOfferQuestion"

## The one sentence, said on both surfaces. A question, because the two
## buttons under it answer one, and in the Performance page's words for the set.
const SENTENCE := "Your GPU may be slow for Sara. Use the settings for a weak GPU? They change no pixel of the picture."

var _text: Label


func _init() -> void:
    name = NODE_NAME
    _text = SaMake.label(self, "Sentence", tr(SENTENCE))
    _text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var on_tip := tr("Use lighter settings for the frame rate, half-size view, thumbnails, undo depth and filter preview.")
    SaMake.button(self, "LightModeOfferOn", tr(SaPerformancePage.USE_THEM), on_tip).pressed.connect(_press.bind(true))
    var later_tip := tr("Leave every setting as it is. You can change this later in Preferences > Performance.")
    SaMake.button(self, "LightModeOfferNotNow", tr("Not now"), later_tip).pressed.connect(_press.bind(false))
    refresh()


func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_TREE:
        var window := get_window()
        if window != null and not window.visibility_changed.is_connected(refresh):
            window.visibility_changed.connect(refresh)
        refresh()


## Shown while the offer is due, and taking no height otherwise.
func refresh() -> void:
    visible = due()


func _press(turn_on: bool) -> void:
    answer(turn_on)
    refresh()


## Whether the offer is made now: a device was judged weak and the profile has
## never answered.
static func due() -> bool:
    return SaWeakGpu.weak() and SaSettings.light_mode_offer.is_empty()


## Keeps the painter's answer, uses the settings for a weak GPU when *turn_on*,
## and says in the canvas corner what changed and where it can be changed back.
## The notice names the settings that moved in the Performance page's own
## words, and both answers name the page.
static func answer(turn_on: bool) -> void:
    if not turn_on:
        SaSettings.light_mode_offer = SaSettingsPerformance.OFFER_NOT_NOW
        SaMessage.notice(_tr("You can change this later in Preferences > Performance."))
        return
    SaSettings.light_mode_offer = SaSettingsPerformance.OFFER_TURNED_ON
    var moved := SaSettingsPerformance.apply_light(SaSettings)
    var said := SaPerformancePage.summary(
        moved, SaPerformancePage.WEAK_GPU_SET, "The settings for a weak GPU were already in use."
    )
    SaMessage.notice("%s %s" % [said, _tr("You can change any of them in Preferences > Performance.")])


## The end of a real boot: judges the device and makes the offer where it
## belongs. *welcome* is the window `SaBoot` opened, or null, and *refused* is
## a capture run or a door session, which are never offered anything.
static func at_start(host: Node, welcome: Window, refused: bool) -> void:
    if refused or not is_instance_valid(host) or SaDeviceFloor.summary() != "met":
        return
    SaWeakGpu.read_running()
    if not due():
        return
    if welcome != null and is_instance_valid(welcome) and welcome.visible:
        var row := welcome.find_child(NODE_NAME, true, false) as SaLightModeOffer
        if row != null:
            row.refresh()
            return
    ask_alone(host)


## The question of its own, for a start with no welcome window. Closed without
## a button it answers Not now, because a window put away is a no, and a
## painter who closes it at every start should not meet it at every start.
static func ask_alone(host: Node) -> SaMessage:
    var labels := PackedStringArray([_tr(SaPerformancePage.USE_THEM), _tr("Not now")])
    var dialog := SaMessage.confirm(
        host, _tr(SaPerformancePage.WEAK_GPU), _tr(SENTENCE), labels, func(index: int) -> void: answer(index == 0), 1, 1
    )
    dialog.name = DIALOG_NAME
    return dialog


## `tr` for a static function, which has no object to ask.
static func _tr(text: String) -> String:
    return String(TranslationServer.translate(text))


## Drives the light mode offer: `{"light_offer": {...}}`. `fake` pretends a
## device, one of `SaWeakGpu.TYPE_NAMES`' words, with `memory_gib` of memory.
## `unasked` clears the kept answer. `dialog` asks the question of its own.
## `press`, `"on"` or `"not_now"`, presses a button of whichever surface is up,
## the question first. Answers the device judged, the running device beside it
## so a record names the real one, the kept answer, both surfaces and the five
## settings it writes.
static func capture_offer(tree: SceneTree, spec: Variant) -> String:
    var asked: Dictionary = spec if spec is Dictionary else {}
    if asked.has("fake"):
        SaWeakGpu.fake(String(asked["fake"]), int(float(asked.get("memory_gib", 8)) * 1024.0 * 1024.0 * 1024.0))
    if asked.get("unasked", false):
        SaSettings.light_mode_offer = ""
    var row := tree.root.find_child(NODE_NAME, true, false) as SaLightModeOffer
    if row != null:
        row.refresh()
    if asked.get("dialog", false):
        ask_alone(tree.current_scene if tree.current_scene != null else tree.root)
    var dialog := _live_question(tree)
    if asked.has("press"):
        var index := 0 if String(asked["press"]) == "on" else 1
        if dialog != null:
            dialog.buttons[index].pressed.emit()
        elif row != null and row.is_visible_in_tree():
            var button_name := "LightModeOfferOn" if index == 0 else "LightModeOfferNotNow"
            (row.get_node(button_name) as Button).pressed.emit()
        dialog = _live_question(tree)
    var running := SaWeakGpu.running()
    var report := {
        "device": SaWeakGpu.state(),
        "running": "%s, %s" % [running["name"], SaWeakGpu.reason(int(running["type"]), int(running["memory"]))],
        "answer": SaSettings.light_mode_offer,
        "due": due(),
        "row_shown": row != null and row.is_visible_in_tree(),
        "row_size": [row.size.x, row.size.y] if row != null else [],
        "sentence_lines": row._text.get_line_count() if row != null else 0,
        "question_shown": dialog != null,
        "painting_frame_rate": SaSettings.painting_frame_rate,
        "half_size_view_while_moving": SaSettings.half_size_view_while_moving,
        "thumbnails_while_painting": SaSettings.thumbnails_while_painting,
        "history_depth": SaSettings.history_depth,
    }
    return "SaCapture: light_offer %s" % JSON.stringify(report)


static func _live_question(tree: SceneTree) -> SaMessage:
    var found := tree.root.find_child(DIALOG_NAME, true, false) as SaMessage
    return found if found != null and found.visible and not found.is_queued_for_deletion() else null
