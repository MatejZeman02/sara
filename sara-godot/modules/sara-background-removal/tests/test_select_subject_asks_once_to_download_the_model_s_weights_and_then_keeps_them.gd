## Select Subject asks once to download the model's weights
## and then keeps them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A local server stands in for Google Drive and logs what it is asked. The
## right bytes are kept with their SHA-256 and the bar moved before the end,
## and the command asks nothing a second time. Bytes of another hash are not
## kept and the dialog names the mismatch. Cancel asks the server nothing. The
## Select menu is read from a bar built detached, as the tutorials module's
## suite reads Help's, and now holds no Select Subject row.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const WeightsServer = preload("weights_server.gd")
const WeightsDownload = preload("../weights_download.gd")

## The frames a download of the test's bytes is given, far more than it needs.
const PATIENCE := 1200

var _registries: SaRegistries = null
var _module: SaModule = null
var _server: Node = null


func before_each() -> void:
    _registries = SaTestFixtures.make_menu_registries()
    _registries.build_context(func() -> SaEasel: return null, func() -> Array: return [], SaAppDrive.new())
    _module = SubjectModule.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    _forget_weights()
    # The runner's root is busy with its children until the first frame, and
    # the server and the dialog join the tree.
    await (Engine.get_main_loop() as SceneTree).process_frame


func after_each() -> void:
    if _server != null and is_instance_valid(_server):
        _server.queue_free()
    _server = null
    if _module != null:
        _forget_weights()
        _module.unregister(_registries.context)
        _module = null
    _registries = null


func _forget_weights() -> void:
    var path: String = _module.weights_path()
    for each: String in [path, path + ".part"]:
        if FileAccess.file_exists(each):
            DirAccess.remove_absolute(each)


## Bytes no file of the authors has, the same each run.
static func made_bytes(count: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(count)
    for i: int in count:
        out[i] = (i * 31 + (i >> 8)) & 0xFF
    return out


static func sha256_of(bytes: PackedByteArray) -> String:
    var hashing := HashingContext.new()
    hashing.start(HashingContext.HASH_SHA256)
    hashing.update(bytes)
    return hashing.finish().hex_encode()


func _serve(bytes: PackedByteArray) -> void:
    _server = WeightsServer.new(bytes)
    (Engine.get_main_loop() as SceneTree).root.add_child(_server)


## Waits for the download in *dialog* to end, and answers the largest the bar
## read while it ran.
func _wait_for(dialog: Window) -> float:
    var tree := Engine.get_main_loop() as SceneTree
    var highest := 0.0
    for _frame: int in PATIENCE:
        await tree.process_frame
        var download: WeightsDownload = dialog.download
        if download == null or download.outcome != WeightsDownload.Outcome.RUNNING:
            break
        highest = maxf(highest, dialog.bar.value)
    return highest


func _frames(count: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for _frame: int in count:
        await tree.process_frame


## Select Subject is a tool and not a Select row, so the menu
## with the module holds what it holds without it.
func test_the_select_menu_carries_no_select_subject_row() -> void:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(_registries.commands)
    var select := bar.menu("Select") as SaSelectMenu
    select.populate()
    var labels: PackedStringArray = select.popup.row_labels()
    assert_false(labels.has("Select Subject"), "Select lists no Select Subject row: %s" % [labels])
    assert_true(labels.has("Colour Range..."), "and keeps Colour Range: %s" % [labels])
    bar.free()


func test_the_right_bytes_are_kept_and_asked_for_once() -> void:
    var bytes := made_bytes(400000)
    _serve(bytes)
    assert_true(_server.port > 0, "the server has a port")
    var dialog: Window = _module.open_dialog(_server.url(), sha256_of(bytes))
    assert_not_null(dialog, "the first use opens the dialog")
    if dialog == null:
        return
    dialog.accept()
    var highest: float = await _wait_for(dialog)
    var path: String = _module.weights_path()
    assert_true(FileAccess.file_exists(path), "the file is kept in the module's data folder, %s: %s" % [path, dialog.status.text])
    assert_eq(FileAccess.get_sha256(path), sha256_of(bytes), "with the bytes served")
    assert_false(FileAccess.file_exists(path + ".part"), "and no part file beside it")
    assert_true(highest > 0.0, "the bar rose above 0 before the end, to %.3f" % highest)
    assert_true(dialog.download.progress_before_end > 0.0, "and the download measured %.3f" % dialog.download.progress_before_end)
    assert_false(dialog.visible, "the dialog closed once the file was kept")
    assert_eq(_server.requests.size(), 1, "one request: %s" % [_server.requests])
    _module.click()
    await _frames(30)
    assert_eq(_server.requests.size(), 1, "a second use asks the server nothing: %s" % [_server.requests])
    assert_false(dialog.visible, "and opens no dialog")
    # The served bytes are no model file, so the click runs the
    # network on them and says why it cannot.
    assert_true(_module.said.begins_with("Select Subject could not run: "), "it runs on the weights kept: %s" % _module.said)


func test_bytes_of_another_hash_are_not_kept() -> void:
    _serve(made_bytes(200000))
    var dialog: Window = _module.open_dialog(_server.url(), SubjectModule.WEIGHTS_SHA256)
    dialog.accept()
    await _wait_for(dialog)
    var path: String = _module.weights_path()
    assert_false(FileAccess.file_exists(path), "no file is kept")
    assert_false(FileAccess.file_exists(path + ".part"), "and no part file")
    assert_eq(dialog.download.outcome, WeightsDownload.Outcome.MISMATCH, "the download ended on the hash")
    assert_true(
        dialog.status.text.contains("did not match what Sara expects"), "the dialog names the mismatch: %s" % dialog.status.text
    )
    assert_true(dialog.status.text.contains("Nothing was stored"), "and that nothing was stored")


func test_cancel_asks_the_server_nothing() -> void:
    _serve(made_bytes(1000))
    var dialog: Window = _module.open_dialog(_server.url(), SubjectModule.WEIGHTS_SHA256)
    dialog.cancel()
    await _frames(30)
    assert_eq(_server.requests.size(), 0, "the server's log is empty: %s" % [_server.requests])
    assert_false(dialog.visible, "the dialog closed")
    assert_false(FileAccess.file_exists(_module.weights_path()), "and nothing is kept")


func test_a_server_that_is_not_there_keeps_nothing() -> void:
    var dialog: Window = _module.open_dialog("http://127.0.0.1:9/u2netp.pth", SubjectModule.WEIGHTS_SHA256)
    dialog.accept()
    await _wait_for(dialog)
    assert_eq(dialog.download.outcome, WeightsDownload.Outcome.FAILED, "the download failed: %s" % dialog.status.text)
    assert_true(dialog.status.text.contains("Nothing was stored"), "and says nothing was stored: %s" % dialog.status.text)
    assert_false(FileAccess.file_exists(_module.weights_path()), "nothing is kept")


func test_the_dialog_names_source_size_and_licence() -> void:
    var dialog: Window = _module.open_dialog("http://127.0.0.1:9/none", SubjectModule.WEIGHTS_SHA256)
    var text := ""
    for each: String in ["Source", "Size", "Licence"]:
        text += (dialog.find_child("Weights%s" % each, true, false) as Label).text + "\n"
    assert_true(text.contains("Google Drive link in the U-2-Net README"), "the source: %s" % text)
    assert_true(text.contains("4,683,258 bytes"), "the size, from the constant: %s" % text)
    for clause: String in [
        "Apache 2.0", "no licence statement of their own", "DUTS-TR", "reserve all rights", "fetching them from their authors"
    ]:
        assert_true(text.contains(clause), "the licence says %s" % clause)
    assert_not_null(dialog.find_child("WeightsAccept", true, false), "an Accept button")
    assert_not_null(dialog.find_child("WeightsCancel", true, false), "and a Cancel button")
    dialog.cancel()
