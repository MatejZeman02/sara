## The hold on a summoned docker ends when the field being typed
## into gives the edit up.
##
## The reported fault is that the Recorder did not disappear after its text was
## edited and Enter or another button was pressed. The hold a summon keeps is
## "while a field inside it holds focus", which is the right rule but could not
## see the end of an edit: the engine keeps the keyboard
## on a `LineEdit` after Enter, so the field whose edit was over went on holding
## the docker for good.
##
## **The group's first step is to see it on Linux, and it is seen.** A capture of
## the running app reads the Recorder's `Folder` field as the focused control of
## its docker on the frame Enter was pressed and every frame after, with the
## docker still borrowed a dwell past the pointer's leaving: nothing about the
## keyboard changes at Enter.
##
## What the engine does give is the submission, so `DockerSummon.EditWatch` reads
## the field's own `text_submitted` and `text_changed`. Escape, a click on a
## button and a click on the canvas all move the keyboard instead and never reach
## that watch, which the first cases read off the rule rather than off a `Window`:
## a `Window` outside a tree cannot be given the focus, so the delivery itself is
## the scenario named for the unit.
extends "res://tests/test_framework.gd"

## The store's file, and the last case puts a real window in the tree.
const REQUIRES_GPU := true

static var scratch_layout_path: String = SaDataRoot.path("test_w3_summon_layout.cfg")
const SECTION: String = "RecorderDocker"
const HOME := Vector2i(1500, 120)
const SIZE := Vector2i(320, 400)
const POINT := Vector2i(700, 500)
## Far enough from the rectangle this suite draws to be past any reach.
const AWAY := Vector2(100, 100)
const REACH: float = 57.6
const DWELL: int = 1000

var _dwell_before: Variant = null
var _was_embedding: bool = false
var _host: Node = null


func before_each() -> void:
    # The default is named rather than left to the two-argument form: a profile
    # that has never held the key makes that form log an engine error, and this
    # suite is not one of the ones asserting a refusal.
    _dwell_before = SaSettings.module_preference(
        SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, SaDockerBorrow.DEFAULT_DWELL_MS
    )
    SaDockerBorrow.new().dwell_ms = DWELL
    # Only the last case needs either of these, and both are cheap.
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Node.new()
    _host.name = "W3SummonTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.set_module_preference(SaDockerBorrow.MODULE_ID, SaDockerBorrow.DWELL_KEY, _dwell_before)
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


## The engine's rule the fault came from, and the one thing this unit changes:
## Enter ends the edit without moving the keyboard.
func test_enter_ends_the_edit_and_the_next_keystroke_starts_it_again() -> void:
    var watch := DockerSummon.EditWatch.new()
    var field := LineEdit.new()

    assert_true(watch.holds(field), "a field that has just taken the keyboard is being typed into")
    field.text_submitted.emit("a path")
    assert_false(watch.holds(field), "Enter ends the edit, whatever the keyboard still says")
    field.text_changed.emit("a path/")
    assert_true(watch.holds(field), "and the next keystroke starts it again")
    field.text_submitted.emit("a path/")
    assert_false(watch.holds(field), "so a second Enter ends it a second time")

    field.free()


## The other three answers the keyboard gives, which `EditWatch` is right to
## refuse: a button a painter clicked keeps the focus and is not typed into, and
## a `TextEdit` has no submission to announce because Enter is a newline in it.
func test_only_a_field_is_being_typed_into() -> void:
    var watch := DockerSummon.EditWatch.new()
    var button := Button.new()
    var area := TextEdit.new()

    assert_false(watch.holds(button), "a button that took the focus is not a field being typed into")
    assert_false(watch.holds(null), "and a docker with no focus owner has nobody typing in it")
    assert_true(watch.holds(area), "a text area is a field while it has the keyboard")

    area.text_changed.emit()
    assert_true(watch.holds(area), "and its own text changing is not the end of anything")

    button.free()
    area.free()


## The whole of it on a real window with a real focus owner: the summon holds the
## docker while the field is typed into, and sends it back a dwell after Enter.
##
## The window is embedded, which is what makes a `Window` in this suite's tree
## legal at all: without it `add_child` maps a real OS window and the run blocks
## until the watchdog. The focus is asked for and then asserted, because a case
## about a focus owner that quietly has none would read as a pass.
func test_the_summon_holds_then_sends_back_the_recorder() -> void:
    var win := Window.new()
    win.name = SECTION
    win.position = HOME
    win.size = SIZE
    _host.add_child(win)
    var field := LineEdit.new()
    field.name = "Folder"
    win.add_child(field)
    win.show()
    win.grab_focus()
    field.grab_focus()
    assert_true(win.has_focus(), "the docker took the focus")
    assert_eq(win.gui_get_focus_owner(), field, "and its Folder field owns the keyboard")

    var store := _store_with(win)
    var summon := DockerSummon.new(store)
    assert_true(summon.summon(win, SECTION, POINT, 10000), "the chord summons the docker")
    assert_false(summon.step(SECTION, AWAY, REACH, 10100), "the pointer past the reach starts the dwell")
    assert_false(summon.step(SECTION, AWAY, REACH, 60000), "and the field being typed into holds the docker")

    field.text_submitted.emit("a path")
    assert_true(win.gui_get_focus_owner() == field, "the keyboard is still on the field after Enter, which is the fault")
    assert_false(summon.step(SECTION, AWAY, REACH, 60100), "the edit is over, so the dwell starts")
    assert_false(summon.step(SECTION, AWAY, REACH, 60900), "and it is a full wait from there")
    assert_true(summon.step(SECTION, AWAY, REACH, 61100), "after which the docker goes back")

    assert_false(store.is_borrowed(SECTION), "nothing is borrowed after the leave")
    assert_eq(win.position, HOME, "and the docker is where the painter left it")

    summon.free()
    store.free()


## A store with the one docker and the file written once from it, which is the
## layout a painter's session left behind. `DockerSummon` reaches the borrowed
## node through the store's own address book, so the docker has to be in it.
func _store_with(win: Window) -> DockerLayoutStore:
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": win, "id": SECTION, "name": "Recorder"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    return store
