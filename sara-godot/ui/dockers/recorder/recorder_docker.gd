## The Recorder docker: see where the timelapse writes, start and stop it, see
## what it has written, and hand the frames to ffmpeg.
##
## Registered through `SaUIRegistry` like every built-in, hidden until the
## Dockers menu shows it. The docker owns an `SaRecorder` and points it at the
## main canvas, which it finds the way the capture harness does: the live
## canvas in the root window.
##
## The folder is the path row the Preferences pages draw, the path trimmed from
## its start with the whole of it in the tooltip, and a Choose button. It was a
## bare text field whose path was cut at the end, where the folder's own name
## is. Settle and Cap sit under a fold, because a painter sets them once, and
## each carries the title and the sentence the Timelapse page declares for it.
##
## The status line says what the recorder did as a painter would count it. A
## count goes through the plural forms, a size reads KB under a megabyte, the
## start says how long after a change a frame comes, and Make Video watches the
## ffmpeg it started until it ends and then says whether the file is there. Every
## path on the line is the real one, never one only Godot can read.
@tool
class_name RecorderDocker
extends DockerWindow

const DockerColumnScroll := preload("res://ui/dockers/docker_column_scroll.gd")

## The fold header's arrows, the icons the brush editor's Presets header and a
## group's row in the Layers docker draw. They were "▶" and "▼" in the text,
## which Atkinson Hyperlegible and IBM Plex Sans have no glyph for.
const FOLDED_ARROW: String = "chevron_right"
const OPEN_ARROW: String = "chevron_down"
## How often Make Video asks whether its ffmpeg still runs.
const VIDEO_POLL_SECONDS: float = 0.5
const BYTES_PER_KB: int = 1024
const BYTES_PER_MB: int = 1048576

var recorder: SaRecorder = null
## Reads Record, and Stop while a recording runs, since it is the one control
## that does both.
var record_button: Button = null
var video_button: Button = null
var status: Label = null
## The folder's path row, as `SaPathRow.make` answers it.
var folder: Control = null
## The header that opens and shuts `fold`, and the box holding Settle and Cap.
var fold_button: Button = null
var fold: VBoxContainer = null
var settle: SpinBox = null
var cap: SpinBox = null
## Whether the process with a pid still runs, `OS.is_process_running` unless a
## suite stands in for the ffmpeg.
var process_alive: Callable = func(pid: int) -> bool: return OS.is_process_running(pid)
## Asks *process_alive* every `VIDEO_POLL_SECONDS` while a video is being made.
var video_timer: Timer = null
## The ffmpeg Make Video started and the file it writes, -1 and "" when none.
var video_pid: int = -1
var video_path: String = ""


func _init() -> void:
    _init_docker(SaDockerIds.RECORDER, "Recorder", Vector2i(300, 270), Vector2i(220, 200))

    recorder = SaRecorder.new()
    add_child(recorder)
    recorder.frame_written.connect(_on_frame_written)
    recorder.stopped.connect(_on_stopped)
    video_timer = Timer.new()
    video_timer.name = "VideoTimer"
    video_timer.wait_time = VIDEO_POLL_SECONDS
    video_timer.timeout.connect(poll_video)
    add_child(video_timer)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Recorder")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(null, "MarginContainer", SaUI.BASE_MARGIN)
    # Scrolled rather than the window floored at the column's height: the row
    # that opens the folder was under the resize grip at the docker's own
    # default size.
    DockerColumnScroll.wrap(vbox, margin)

    # The theme's gap between groups and a tight one inside the folder's, so the
    # rows fit the docker's own size with the fold shut and nothing scrolls.
    var column := SaMake.column(margin, "Column", SaTheme.GAP)

    recorder.directory = _folder_or_default(SaSettings.recorder_directory)
    recorder.settle_seconds = SaSettings.recorder_settle_seconds
    recorder.cap_bytes = SaSettings.recorder_cap_bytes

    var folder_group := SaMake.column(column, "FolderGroup", SaTheme.GAP_TIGHT)
    SaMake.label(folder_group, "FolderTitle", tr("Folder"))
    folder = SaPathRow.make(_on_folder_chosen, column)
    folder.name = "Folder"
    folder_group.add_child(folder)
    SaPathRow.show(folder, ProjectSettings.globalize_path(recorder.directory))

    # One row, so Make Video sits beside Record at the docker's own size rather
    # than below the status, where it was cut off. A turning row, so a
    # language whose two words do not fit side by side puts Make Video under
    # Record rather than past the docker's edge.
    var buttons := SaMake.turning_row(column, "Buttons", SaTheme.GAP)
    record_button = SaMake.button(buttons, "RecordButton", tr("Record"))
    record_button.toggle_mode = true
    SaTheme.make_toggle(record_button)
    record_button.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    record_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    record_button.toggled.connect(_on_record_toggled)

    video_button = SaMake.button(buttons, "VideoButton", tr("Make Video"))
    video_button.custom_minimum_size = Vector2(0, SaUI.px(SaUI.BASE_BTN_H))
    video_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    video_button.pressed.connect(_on_video_pressed)

    # Out of sight until there is something to say. "Not recording." said what
    # the button's Record already does, and its line was the one the rows went
    # past the docker's own height by.
    status = SaMake.label(column, "Status")
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status.visible = false

    _build_fold(column)
    SaSettings.changed.connect(_on_setting_changed)


## Pause before frame and Size limit, the settle time and the cap, under a
## Timing and size limit header that opens them, shut to begin with. Each row
## takes its title and its sentence from the Timelapse page, read off a page
## built for it and freed, the way the settings search reads every page, so the
## docker and Preferences cannot come to say two things about one number.
func _build_fold(column: VBoxContainer) -> void:
    fold_button = SaMake.button(column, "FoldButton")
    fold_button.flat = true
    fold_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    # The arrow as tall as the line and no taller, so the header is the height
    # it was as text and the shut fold still fits the docker's own size.
    fold_button.expand_icon = true
    # A header longer than the docker is wide wraps rather than widening it.
    fold_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    fold_button.pressed.connect(func() -> void: open_fold(not fold.visible))
    fold = SaMake.column(column, "Fold", SaTheme.GAP_TIGHT)

    var page := SaRecorderPage.new()
    settle = _fold_row(page.page.row(&"settle"), "Settle", 0.5, 30.0, 0.5, recorder.settle_seconds)
    settle.value_changed.connect(
        func(value: float) -> void:
            recorder.settle_seconds = value
            SaSettings.recorder_settle_seconds = value
    )
    @warning_ignore("integer_division")
    cap = _fold_row(page.page.row(&"cap"), "Cap", 1, 100000, 1, recorder.cap_bytes / 1048576)
    cap.value_changed.connect(
        func(value: float) -> void:
            recorder.cap_bytes = int(value) * 1048576
            SaSettings.recorder_cap_bytes = recorder.cap_bytes
    )
    page.free()
    open_fold(false)


## One row of the fold: the page row's title beside a number box, and its
## explanation under both in the dimmed hint the pages draw.
##
## The box carries the unit the page's readout does, since the title it shares
## has none, and is the number field a page draws, which is as wide as
## "100000 MB".
func _fold_row(declared: SaPageRow, node_name: String, low: float, high: float, step: float, value: float) -> SpinBox:
    var line := SaMake.row(fold, node_name + "Row", SaTheme.GAP)
    var heading := SaMake.label(line, "Title", SaPage.translated(declared.label))
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var spin := SaPage.NumberField.new()
    spin.min_value = low
    spin.max_value = high
    spin.step = step
    spin.value = value
    spin.suffix = declared.suffix.strip_edges(true, false)
    spin.name = node_name
    spin.set_meta(SaMake.KIND_META, SaMake.Kind.SPIN)
    line.add_child(spin)
    var hint := SaSettingsRows.hint_label(SaPage.translated(declared.explanation))
    hint.name = node_name + "Hint"
    fold.add_child(hint)
    spin.tooltip_text = hint.text
    return spin


## Opens or shuts the fold, the header's arrow saying which.
func open_fold(open: bool) -> void:
    fold.visible = open
    fold_button.icon = SaUI.get_icon(OPEN_ARROW if open else FOLDED_ARROW)
    fold_button.text = tr("Timing and size limit")


## The folder the picker chose, or "" from Use Default, which is the recorder's
## own folder rather than an empty path a recording would then start in.
func _on_folder_chosen(picked: String) -> void:
    SaSettings.recorder_directory = _folder_or_default(picked)


## Keeps the recorder and the rows on what Preferences holds, so a folder, a
## settle time or a cap set on the Timelapse page is the one the next recording
## uses, and one the docker set shows there.
func _on_setting_changed(property: StringName) -> void:
    match property:
        &"recorder_directory":
            recorder.directory = _folder_or_default(SaSettings.recorder_directory)
            SaPathRow.show(folder, ProjectSettings.globalize_path(recorder.directory))
        &"recorder_settle_seconds":
            recorder.settle_seconds = SaSettings.recorder_settle_seconds
            settle.set_value_no_signal(recorder.settle_seconds)
        &"recorder_cap_bytes":
            recorder.cap_bytes = SaSettings.recorder_cap_bytes
            @warning_ignore("integer_division")
            cap.set_value_no_signal(recorder.cap_bytes / 1048576)


static func _folder_or_default(path: String) -> String:
    return path if not path.is_empty() else SaRecorder.default_directory()


## Listens for the document in front for as long as the docker is in the tree.
func _enter_tree() -> void:
    if not EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.connect(_on_front_changed)


func _ready() -> void:
    _setup_docker_ready()
    # Checked once, here rather than per click: a system without ffmpeg gets a
    # button that says so instead of one that fails.
    if not SaRecorder.ffmpeg_available():
        video_button.disabled = true
        video_button.tooltip_text = tr("ffmpeg was not found on this system. Install it to turn the frames into a video.")
    _bind_main_canvas.call_deferred()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.RECORDER)


## The front document's canvas, deferred because the dockers are built before
## the main canvas has a document. Pressing Record asks again, so a recording
## starts on the document in front and not on one an earlier recording bound.
func _bind_main_canvas() -> void:
    if not is_inside_tree():
        return
    _bind(SaCanvasView.front_canvas())


## Points the recorder at *canvas* when it is another with a document.
func _bind(canvas: SaCanvas) -> void:
    if canvas != null and canvas.document != null and canvas != recorder._canvas:
        recorder.bind_canvas(canvas)


## The recorder follows the document the painter brought forward. A recording
## carries on into the new document: its frames go to the same folder under the
## one count the recorder keeps, so a frame never overwrites an earlier one and
## the video shows both documents in the order they were painted.
func _on_front_changed(surface: SaSurface) -> void:
    _bind(SaCanvasView.canvas_of(surface))


func _on_record_toggled(pressed: bool) -> void:
    if pressed:
        _bind_main_canvas()
        if recorder.start():
            _say(tr("Recording: %s. %s") % [frames_text(recorder.frame_count), _settle_text()])
            _show_recording(true)
        else:
            record_button.set_pressed_no_signal(false)
    else:
        recorder.stop()


## The button's word follows the recording, whichever way it ended: a press, or
## the cap reached.
func _show_recording(on: bool) -> void:
    record_button.text = tr("Stop") if on else tr("Record")


## "A frame is taken 2 seconds after each change.", the seconds the recorder
## waits, since nothing is written while the painter is still at work.
func _settle_text() -> String:
    var seconds := recorder.settle_seconds
    # The plural form wants a count, and only exactly one second is singular.
    var form := 1 if is_equal_approx(seconds, 1.0) else 2
    var line := tr_n("A frame is taken %s second after each change.", "A frame is taken %s seconds after each change.", form)
    # A whole number of seconds without its ".0", which `String.num` keeps.
    var shown := str(roundi(seconds)) if is_equal_approx(seconds, roundf(seconds)) else String.num(seconds, 2)
    return line % shown


## *count* frames as a count reads, "1 frame" or "2 frames".
static func frames_text(count: int) -> String:
    return TranslationServer.translate_plural("%d frame", "%d frames", count) % count


## *bytes* in KB under a megabyte and in MB from one up, so a 37 KB frame does
## not read 0.0 MB. Anything written is at least 1 KB.
static func size_text(bytes: int) -> String:
    if bytes < BYTES_PER_MB:
        var kb := roundi(float(bytes) / BYTES_PER_KB)
        if bytes > 0:
            kb = maxi(kb, 1)
        return TranslationServer.translate_plural("%d KB", "%d KB", kb) % kb
    return TranslationServer.translate("%.1f MB") % (float(bytes) / BYTES_PER_MB)


## "1 frame, 37 KB.", what the folder holds so far.
func _written_text() -> String:
    return tr("%s, %s.") % [frames_text(recorder.frame_count), size_text(recorder.bytes_written)]


func _on_frame_written(_path: String, _count: int) -> void:
    _say(tr("Recording: ") + _written_text())


func _on_stopped(reason: String) -> void:
    record_button.set_pressed_no_signal(false)
    _show_recording(false)
    # Without the folder, which the row above names in full.
    var frames := _written_text()
    if reason == "cap":
        _say(tr("Stopped, size limit reached. ") + frames)
    else:
        _say(tr("Stopped. ") + frames)


func _on_video_pressed() -> void:
    var video := recorder.directory.path_join("timelapse.mp4")
    var pid := recorder.make_video(video)
    if pid >= 0:
        watch_video(pid, video)


## Says the video is being made and asks after *pid* until it ends. ffmpeg runs
## on its own, so the pid is all `make_video` can answer at once.
func watch_video(pid: int, video: String) -> void:
    video_pid = pid
    video_path = ProjectSettings.globalize_path(video)
    _say(tr("Making the video..."))
    if video_timer.is_inside_tree():
        video_timer.start()


## One look at the ffmpeg Make Video started. While it runs nothing changes, and
## once it has ended the line says where the video is, or that there is none
## and the frames are still where they were.
func poll_video() -> void:
    if video_pid < 0:
        video_timer.stop()
        return
    if process_alive.call(video_pid):
        return
    video_timer.stop()
    video_pid = -1
    var bytes := 0
    if FileAccess.file_exists(video_path):
        var file := FileAccess.open(video_path, FileAccess.READ)
        if file != null:
            bytes = file.get_length()
            file.close()
    if bytes > 0:
        _say(tr("Video done: %s, %s.") % [video_path, size_text(bytes)])
    else:
        var frames := ProjectSettings.globalize_path(recorder.directory)
        var reason := recorder.video_error()
        if reason.is_empty():
            _say(tr("ffmpeg did not make the video. Its frames are still in %s.") % frames)
        else:
            _say(tr("ffmpeg did not make the video, and said: %s. Its frames are still in %s.") % [reason, frames])


## A docker closed with the video unfinished stops asking after it.
func _exit_tree() -> void:
    video_timer.stop()
    if EventBus.active_document_changed.is_connected(_on_front_changed):
        EventBus.active_document_changed.disconnect(_on_front_changed)


## Puts *text* on the status line and brings the line into sight.
func _say(text: String) -> void:
    status.text = text
    status.visible = true
