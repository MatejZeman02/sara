## The dialog Select Subject opens while the model's weights are not kept:
## where the file comes from, its size, what is known of its licence, and a
## button that downloads it and one that does not.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Accept starts a `WeightsDownload` under this window, and the bar under the
## sentences follows its bytes. The download ending says in the line below the
## bar how it ended, and when the file was kept the dialog closes and hands the
## line to the command. Cancel before Accept sends nothing to the network,
## and Cancel during a download stops it and keeps nothing.
@tool
extends SaDialogWindow

## The end of a download that kept the file, with the line to say of it.
signal kept(line: String)
## Cancel, the × or Escape: the dialog closed without keeping the file.
signal cancelled

const WeightsDownload := preload("weights_download.gd")

## What the window is called, and what a driver finds it by.
const NODE_NAME := "SubjectWeightsDialog"

const OPENING_SIZE := Vector2i(520, 400)
const FLOOR := Vector2i(360, 300)

## The download running or last run, or null before Accept.
var download: WeightsDownload = null
var accept_button: Button = null
var cancel_button: Button = null
var bar: ProgressBar = null
## The line that says how the download is going, and how it ended.
var status: Label = null

var _source: String = ""
var _target: String = ""
var _sha256: String = ""
var _bytes: int = 0


## *source* is where the file is asked for, *target* where it is kept, *sha256*
## what it must hash to and *bytes* its size. *where_from* names the source in
## words for the painter.
func _init(source: String = "", target: String = "", sha256: String = "", bytes: int = 0, where_from: String = "") -> void:
    _init_dialog(NODE_NAME, tr("Download the subject model"), OPENING_SIZE, FLOOR)
    _source = source
    _target = target
    _sha256 = sha256
    _bytes = bytes
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SaTheme.GAP)
    var lines := [
        [
            "Intro",
            tr(
                # gdlint:ignore=max-line-length
                "Select Subject needs the weights of U²-NetP, a small network that finds the subject of a picture. Sara does not carry them. Accept downloads them once and keeps them for every later use."
            )
        ],
        ["Source", tr("Source: %s.") % where_from],
        ["Size", tr("Size: %s bytes, %.1f MB.") % [grouped(bytes), bytes / 1.0e6]],
        [
            "Licence",
            tr(
                # gdlint:ignore=max-line-length
                "Licence: the U-2-Net code is Apache 2.0. The weights have no licence statement of their own. The model was trained on DUTS-TR, whose owners reserve all rights. So Sara cannot say the weights may be copied, and you are fetching them from their authors."
            )
        ],
    ]
    for each: Array in lines:
        var line := SaMake.label(column, "Weights%s" % each[0], each[1])
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        line.custom_minimum_size.x = 300
    bar = ProgressBar.new()
    bar.name = "WeightsProgress"
    bar.min_value = 0.0
    bar.max_value = 1.0
    bar.step = 0.0
    bar.visible = false
    column.add_child(bar)
    status = SaMake.label(column, "WeightsStatus", "")
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var buttons := pinned_buttons(column)
    cancel_button = SaMake.button(buttons, "WeightsCancel", tr("Cancel"))
    accept_button = SaMake.button(buttons, "WeightsAccept", tr("Accept and download"))
    cancel_button.pressed.connect(cancel)
    accept_button.pressed.connect(accept)
    # The × and Escape close as Cancel does, so the tool chosen hands back.
    close_requested.connect(cancel)


## Accept: starts the download, unless one is running.
func accept() -> void:
    if download != null and download.outcome == WeightsDownload.Outcome.RUNNING:
        return
    if download != null:
        download.queue_free()
    download = WeightsDownload.new(_source, _target, _sha256, _bytes)
    download.finished.connect(_on_finished)
    add_child(download)
    bar.value = 0.0
    bar.visible = true
    accept_button.disabled = true
    status.text = tr("Downloading...")
    download.start()


## Cancel: stops a download that runs and closes the dialog. Before Accept it
## sends nothing.
func cancel() -> void:
    if download != null and download.outcome == WeightsDownload.Outcome.RUNNING:
        download.cancel()
    hide()
    cancelled.emit()


func _process(_delta: float) -> void:
    if download != null and download.outcome == WeightsDownload.Outcome.RUNNING:
        bar.value = download.progress


func _on_finished(was_kept: bool, line: String) -> void:
    status.text = line
    accept_button.disabled = false
    if was_kept:
        bar.value = 1.0
        hide()
        kept.emit(line)
        return
    accept_button.text = tr("Try again")


## *count* with a comma between each group of three digits, 4,683,258.
static func grouped(count: int) -> String:
    var digits := str(count)
    var out := ""
    while digits.length() > 3:
        out = "," + digits.right(3) + out
        digits = digits.left(digits.length() - 3)
    return digits + out
