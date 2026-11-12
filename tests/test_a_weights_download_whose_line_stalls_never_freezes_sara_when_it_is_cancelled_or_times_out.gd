## A weights download whose line stalls never freezes Sara
## when it is cancelled or times out.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The suites' server sends part of the weights and then stops sending with the
## connection left open, as a Wi-Fi that drops leaves it. Cancel then has to
## return at once and keep nothing, and a short timeout has to end the
## download with no long frame between the stall and the end. A watchdog
## thread closes the server's side after WATCHDOG seconds, so that a download
## which waits on the line makes the suite fail rather than hang.
extends "res://tests/test_framework.gd"

const SubjectModule = preload("../module.gd")
const WeightsServer = preload("weights_server.gd")
const WeightsDownload = preload("../weights_download.gd")
const Base = preload("test_select_subject_asks_once_to_download_the_model_s_weights_and_then_keeps_them.gd")

## The size of the real weights, so the stall falls part way as it would.
const BYTES := 4683258
## The seconds before the watchdog closes the server's side.
const WATCHDOG := 5.0
## The longest Cancel and any frame may take.
const PROMPT_MSEC := 100

var _registries: SaRegistries = null
var _module: SaModule = null
var _server: Node = null
var _watchdog: Thread = null
## Set when the test is over, so the watchdog stops waiting.
var _over: bool = false


func _frames(count: int) -> void:
    for _frame: int in count:
        await (Engine.get_main_loop() as SceneTree).process_frame


func before_each() -> void:
    _over = false
    _registries = SaTestFixtures.make_menu_registries()
    _registries.build_context(func() -> SaEasel: return null, func() -> Array: return [], SaAppDrive.new())
    _module = SubjectModule.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    _forget_weights()
    # The runner's root is busy with its children until the first frame, and
    # the server and the dialog join the tree.
    await _frames(1)
    _server = WeightsServer.new(Base.made_bytes(BYTES))
    (Engine.get_main_loop() as SceneTree).root.add_child(_server)


func after_each() -> void:
    _over = true
    if _watchdog != null:
        _watchdog.wait_to_finish()
    _watchdog = null
    if _server != null and is_instance_valid(_server):
        _server.queue_free()
    _server = null
    _forget_weights()
    _module.unregister(_registries.context)
    _module = null
    _registries = null


func _forget_weights() -> void:
    var path: String = _module.weights_path()
    for each: String in [path, path + ".part"]:
        if FileAccess.file_exists(each):
            DirAccess.remove_absolute(each)


## Runs on the watchdog's thread. The server's own frames have stopped, so
## nothing else touches its connections while this closes them.
func _close_later() -> void:
    var until := Time.get_ticks_msec() + int(WATCHDOG * 1000.0)
    while Time.get_ticks_msec() < until:
        if _over:
            return
        OS.delay_msec(20)
    print("the watchdog closes the stalled connection")
    for each: Dictionary in _server._open:
        (each["peer"] as StreamPeerTCP).disconnect_from_host()


## Waits until *download* has some of the bytes, then stops the server sending
## with the connection left open, and starts the watchdog.
func _stall(download: WeightsDownload) -> void:
    for _frame: int in 600:
        await _frames(1)
        if download.progress > 0.05:
            break
    _server.set_process(false)
    assert_true(download.progress > 0.0 and download.progress < 1.0, "the download stalls part way, at %.3f" % download.progress)
    assert_eq(download.outcome, WeightsDownload.Outcome.RUNNING, "the stalled download still runs")
    await _frames(10)
    _watchdog = Thread.new()
    _watchdog.start(_close_later)


func test_cancel_of_a_stalled_download_returns_at_once_and_keeps_nothing() -> void:
    var dialog: Window = _module.open_dialog(_server.url(), "0".repeat(64))
    dialog.accept()
    var download: WeightsDownload = dialog.download
    await _stall(download)
    var began := Time.get_ticks_msec()
    dialog.cancel()
    var took := Time.get_ticks_msec() - began
    print("Cancel returned after %d ms" % took)
    assert_true(took <= PROMPT_MSEC, "Cancel returns within %d ms, it took %d ms" % [PROMPT_MSEC, took])
    assert_eq(download.outcome, WeightsDownload.Outcome.CANCELLED, "the download ended cancelled")
    assert_false(FileAccess.file_exists(download.part_path()), "no .part file is kept")
    assert_false(FileAccess.file_exists(download.target), "no weights are kept")


func test_a_stalled_download_times_out_with_no_long_frame() -> void:
    var download := WeightsDownload.new(_server.url(), _module.weights_path(), "0".repeat(64), BYTES, 1.0)
    (Engine.get_main_loop() as SceneTree).root.add_child(download)
    var lines: Array[String] = []
    download.finished.connect(func(_kept: bool, line: String) -> void: lines.append(line))
    download.start()
    await _stall(download)
    var longest := 0
    var last := Time.get_ticks_msec()
    for _frame: int in 1200:
        await _frames(1)
        var now := Time.get_ticks_msec()
        longest = maxi(longest, now - last)
        last = now
        if download.outcome != WeightsDownload.Outcome.RUNNING:
            break
    print(
        "the timeout ended the download %s, the longest frame %d ms" % [WeightsDownload.Outcome.keys()[download.outcome], longest]
    )
    assert_eq(download.outcome, WeightsDownload.Outcome.FAILED, "the timeout ends the download failed")
    assert_true(
        longest <= PROMPT_MSEC,
        "no frame from the stall to the end lasts over %d ms, the longest took %d ms" % [PROMPT_MSEC, longest]
    )
    assert_eq(
        lines, [download.failure_line(HTTPRequest.RESULT_TIMEOUT)] as Array[String], "the dialog's line is the timeout's sentence"
    )
    assert_false(FileAccess.file_exists(download.part_path()), "no .part file is kept")
    download.queue_free()
