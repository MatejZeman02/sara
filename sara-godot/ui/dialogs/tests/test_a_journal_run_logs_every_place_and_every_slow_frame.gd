## A journal run of Sara logs every place it goes and every slow frame, for a
## session that hunts freezes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The trail knows the places and prints a line only where something stalled, so
## a session with no stall says nothing of what the painter did. With `SaTrail.journal` on, each of a preset
## applied, a dialog shown and hidden, a menu opened, a command run and the
## focus leaving and coming back is one line with its time, and a frame over
## `SLOW_S` is one line, marked when a focus change fell in it. Off, none of
## them prints. The lines are read out of the run's own log, and the watch is out of the tree, so its frames come on the
## suite's clock and its focus by `notification`.
##
## Here and not under `core/app/tests`, because the dialog is `SaDialogWindow`,
## which `core` never names.
##
## `@tool` because the probe dialog below extends `SaDialogWindow`, which is a
## tool script, the reason `test_ui_font.gd` gives for its probe docker.
@tool
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## A settings resource a preset can be saved from and applied onto.
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## Never the real preset folder.
static var scratch_dir: String = SaDataRoot.path("test_journal_presets")

var _watch: SaTrail.Watch = null
var _host: Node = null
var _kept_journal: bool = false
var _kept_embedding: bool = true
var _clock: int = 0
var _from: int = 0


## A dialog of nothing but its shell, which is what enters the trail.
class ProbeDialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("JournalProbeDialog", "Journal Probe", Vector2i(320, 200), Vector2i(240, 160))


func before_each() -> void:
    _kept_journal = SaTrail.journal
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A Window added without embedding maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "JournalTestHost"
    EventBus.add_child(_host)
    _watch = SaTrail.Watch.new()
    _clock = _watch._beat_usec
    ScratchFolder.clear(scratch_dir)
    _from = _log_text().length()


func after_each() -> void:
    SaTrail.journal = _kept_journal
    if _watch != null:
        _watch.free()
        _watch = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    ScratchFolder.clear(scratch_dir)


## A whole session in small: a preset picked, a dialog opened and closed, a
## menu opened, a command run, the focus out and in with a slow frame across it,
## and a slow frame of Sara's own. One line each, in order, each with a time.
func test_the_journal_prints_a_line_for_each_thing_the_painter_did() -> void:
    SaTrail.journal = true
    _sitting()
    var lines := _lines()
    var expected := PackedStringArray(
        [
            "went to the Journal suite",
            "the preset Journal Wide applied in",
            "entered the dialog Journal Probe",
            "the window Journal Probe (SaDialogWindow) shown",
            "left the dialog Journal Probe after",
            "the window Journal Probe (SaDialogWindow) hidden",
            "the menu JournalMenu (PopupMenu) shown",
            "the menu JournalMenu (PopupMenu) hidden",
            "entered the command probe",
            "left the command probe after",
            "the focus left Sara",
            "the focus came back to Sara",
            "a frame took 3200 ms, a focus change fell in it, at the Journal suite",
            "a frame took 250 ms, at the Journal suite",
        ]
    )
    assert_eq(lines.size(), expected.size(), "One line for each, and no others: %s" % "\n".join(lines))
    var times: Array[int] = []
    for index in mini(lines.size(), expected.size()):
        var parts := lines[index].split(" ms, ", true, 1)
        assert_true(parts.size() == 2 and parts[0].is_valid_int(), "Line %d opens with its time: %s" % [index, lines[index]])
        if parts.size() == 2:
            times.append(parts[0].to_int())
            assert_true(parts[1].begins_with(expected[index]), "Line %d reads '%s': %s" % [index, expected[index], parts[1]])
    for index in range(1, times.size()):
        assert_true(times[index] >= times[index - 1], "The times run forward")


## Off, the same session prints no journal line at all.
func test_with_the_journal_off_none_of_them_prints() -> void:
    SaTrail.journal = false
    _sitting()
    assert_eq(_lines(), PackedStringArray(), "No journal line with the journal off")


## A dialog freed while it shows gives its place back, and the journal says so
## once.
func test_a_ticket_given_back_twice_prints_once() -> void:
    SaTrail.journal = true
    var ticket := SaTrail.enter("the Journal place")
    SaTrail.give_back(ticket)
    SaTrail.give_back(ticket)
    var lines := _lines()
    assert_eq(lines.size(), 2, "One line in and one out: %s" % "\n".join(lines))


func _sitting() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaTrail.follow_windows(tree)
    SaTrail.note("the Journal suite")

    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var settings := BrushSettingsScript.new()
    store.save_preset("Journal Wide", settings)
    store.apply_preset("Journal Wide", BrushSettingsScript.new())

    var dialog := ProbeDialog.new()
    _host.add_child(dialog)
    dialog.popup_centered()
    dialog.hide()

    var menu := PopupMenu.new()
    menu.name = "JournalMenu"
    menu.add_item("One")
    _host.add_child(menu)
    menu.popup()
    menu.hide()

    var commands := SaCommandRegistry.new()
    var descriptor := SaCommandDescriptor.new()
    descriptor.id = &"probe"
    descriptor.title = "Journal probe"
    descriptor.handler = func() -> bool: return true
    commands.register(descriptor, &"probe")
    commands.execute(&"probe")

    _frames(5, 16)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    _frames(1, 3200)
    _frames(5, 16)
    _frames(1, 250)
    _frames(5, 16)


func _frames(count: int, ms: int) -> void:
    for _i in count:
        _clock += ms * 1000
        _watch.frame_came(_clock, _watch._seen_motions)


## The journal lines printed since the test began, each after its opening.
func _lines() -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.JOURNAL):
            out.append(trimmed.substr(SaTrail.JOURNAL.length()).strip_edges())
    return out


func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""
