## Preferences > Performance: what Sara asks of the GPU while the hand moves, and
## the settings for a weak GPU, which ask less of it in one press.
##
## Four rows, each a setting of its own, under two buttons. **Apply** writes
## `SaSettingsPerformance.light_values()` into the three, into the General
## page's `history_depth` and into the filter preview's row, and lists what it
## changed one setting to a line, and **Restore** puts the five back. Both are
## presets and nothing remembers them: the rows are re-read after a press, and a
## row moved afterwards is one setting moved, because the switch only sets the
## settings. The undo steps are General's one row, and this page keeps a line
## under the three saying so rather than a second slider, because two sliders on
## two pages always reading the same make the search list both and move
## General's value behind its back. The second row, under the frame rate, is the
## half size view while the canvas moves. The Graphics card section's row is
## the GPU memory budget, which the weak GPU buttons leave alone because it is
## about what else shares the card and not about how fast it is.
##
## **The words say what a painter gets**, and not "Light mode", which every
## other program uses for a pale theme, so the painter who most needs it reads
## it as the wrong thing. The words are constants here because the offer to a
## weak GPU, `SaLightModeOffer`, says the same ones.
class_name SaPerformancePage
extends SaSettingsPage

## The section's title, and what the offer and its notices call the set.
const WEAK_GPU := "Settings for a weak GPU"
## The button that writes them, on the page and on the offer.
const USE_THEM := "Apply"
## The first line of what a press of [constant USE_THEM] leaves, over a line
## for each moved setting: "Frame rate while painting: 30 frames a second.".
const WEAK_GPU_SET := "The settings for a weak GPU are in use:"

## What a moved frame rate or thumbnail setting reads as, a whole sentence for
## each choice rather than the choice's label dropped into one, so a language
## with cases can decline it. Keyed by the label in `SaSettingsPerformance`.
const RATE_NOW: Dictionary = {
    "Uncapped": "Frame rate while painting: Uncapped.",
    "The display's refresh rate": "Frame rate while painting: The display's refresh rate.",
    "30 frames a second": "Frame rate while painting: 30 frames a second.",
}

## The same for the thumbnails setting.
const THUMBNAILS_NOW: Dictionary = {
    "Every quarter second": "Thumbnails while painting: Every quarter second.",
    "Only when the pen lifts": "Thumbnails while painting: Only when the pen lifts.",
    "When I stop painting": "Thumbnails while painting: When I stop painting.",
}

## The line under the two buttons that says what the last press changed. Empty,
## and hidden, until one is pressed.
var _summary_row: SaPageRow = null


func build(ui: SaPage) -> void:
    var light := ui.section(WEAK_GPU)
    light.action("Use these settings", press_light).button(USE_THEM).named(&"light_mode").node("LightModeButton").explain(
        tr(
            (
                "Lowers five settings for a weak GPU: the frame rate while painting, the view while the canvas moves, "
                + "the thumbnails, the undo steps and a filter's preview on the canvas. You can change any of them "
                + "afterwards."
            )
        )
    )
    (
        light
        . action("Restore defaults", press_defaults)
        . button("Restore")
        . named(&"defaults")
        . node("PerformanceDefaultsButton")
        . explain(tr("Restore the rows below and the undo steps in Preferences > Interface to their defaults."))
    )
    _summary_row = light.note(tr("")).named(&"summary").node("PerformanceSummary")

    var painting := ui.section("While painting")
    (
        painting
        . choice("Frame rate", _choices(SaSettingsPerformance.FRAME_RATES), SaSettings, ^"painting_frame_rate")
        . named(&"painting_frame_rate")
        . node("PaintingFrameRate")
        . explain(
            tr(
                (
                    "How often Sara draws while the pen moves. Uncapped draws as often as the GPU can, which keeps "
                    + "the brush ring closest to the pen on a strong GPU and works a weak one hardest. At rest Sara "
                    + "draws only when something changed, whatever this says."
                )
            )
        )
    )
    (
        painting
        . toggle("Half-size view while the canvas moves", SaSettings, ^"half_size_view_while_moving")
        . named(&"half_size_view_while_moving")
        . node("HalfSizeViewWhileMoving")
        . explain(
            tr(
                (
                    "Draws the picture at half the window's size while it pans, zooms or turns, and sharp again a few "
                    + "frames after it stops. A stroke is always drawn at full size, even while the view moves."
                )
            )
        )
    )
    (
        painting
        . choice("Thumbnails", _choices(SaSettingsPerformance.THUMBNAIL_MODES), SaSettings, ^"thumbnails_while_painting")
        . named(&"thumbnails_while_painting")
        . node("ThumbnailsWhilePainting")
        . explain(
            tr(
                (
                    "When the layer thumbnails and the minimap catch up with a stroke. When I stop painting waits for "
                    + "the Idle after time below. The part of the picture the canvas shows reaches the minimap as it is "
                    + "painted whichever you choose."
                )
            )
        )
    )
    (
        painting
        . note(
            tr(
                (
                    "Undo steps are set in Preferences > Interface. Each whole-canvas step Ctrl+Z can walk back is a copy "
                    + "of the picture held in video memory, and the settings for a weak GPU lower them."
                )
            )
        )
        . named(&"undo_steps_on_general")
        . node("PerformanceUndoStepsNote")
    )

    var idle := ui.section("When you stop")
    (
        idle
        . slider("Idle after", SaSettings.MIN_IDLE_SECONDS, SaSettings.MAX_IDLE_SECONDS, SaSettings, ^"idle_after_seconds")
        . step(1.0)
        . with_suffix(tr(" s"))
        . named(&"idle_after_seconds")
        . node("IdleAfterSeconds")
        . explain(
            tr(
                (
                    "How long you leave the picture alone, with no stroke, fill or layer change, before the jobs that "
                    + "wait for you to stop run. The Info docker's numbers and the autosave read it, and so do "
                    + "the thumbnails when they wait for you to stop. Panning and zooming are not edits."
                )
            )
        )
    )

    # A share of the card rather than GiB, as `card_memory_share` says why, and
    # its top is the default, so the row only lowers it.
    var memory := ui.section("Graphics card")
    (
        memory
        . slider(
            "Memory budget", SaSettings.MIN_CARD_MEMORY_SHARE, SaSettings.MAX_CARD_MEMORY_SHARE, SaSettings, ^"card_memory_share"
        )
        . scale(100.0)
        . step(5.0)
        . decimals(0)
        . with_suffix(tr(" %"))
        . named(&"card_memory_share")
        . node("CardMemoryShare")
        . explain(
            tr(
                (
                    "How much of the graphics card's memory your open documents may use, as a share of it. Lower it "
                    + "when another program, Blender say, shares the card. The Info docker shows how much of it is in use."
                )
            )
        )
    )

    var filters := ui.section("Filters")
    (
        filters
        . toggle("Start a filter's preview on the canvas", SaSettings, ^"filter_preview_on_canvas")
        . named(&"filter_preview_on_canvas")
        . node("FilterPreviewOnCanvas")
        . explain(
            tr(
                (
                    "Whether the Preview on canvas switch of a filter's window is on when the window opens. The "
                    + "switch stays there to turn on or off either way. A filter that shows its picture in the "
                    + "thumbnail has no canvas preview."
                )
            )
        )
    )


func _init() -> void:
    super()
    _summary_row.line.visible = false


## The settings for a weak GPU, as the button presses it and as a suite does.
func press_light() -> void:
    _show(SaSettingsPerformance.apply_light(SaSettings), WEAK_GPU_SET, "The settings for a weak GPU are already in use.")


## The defaults, as the button presses them.
func press_defaults() -> void:
    _show(
        SaSettingsPerformance.apply_defaults(SaSettings),
        "Restored the defaults:",
        "These settings are already at their defaults."
    )


## Re-reads the rows the press wrote behind their backs and says what moved.
func _show(moved: Array[String], lead: String, unchanged: String) -> void:
    page.refresh()
    var label := _summary_row.line as Label
    label.text = summary(moved, lead, unchanged)
    label.visible = true


## What a press leaves under the buttons: *lead* on a line of its own, then a
## line for each moved setting with the value it has now, or *unchanged* when
## nothing moved. A list rather than one sentence, because a sentence joined
## from lowercased labels with an English "and" could not be translated whole.
## Each line ends in a full stop, so a sentence the offer puts after the last
## one still reads.
static func summary(moved: Array[String], lead: String, unchanged: String) -> String:
    if moved.is_empty():
        return SaPage.translated(unchanged)
    var lines: Array[String] = [SaPage.translated(lead)]
    for property: String in moved:
        lines.append(_now_reads(property))
    return "\n".join(lines)


## What one moved setting reads as now, its row's label and its value.
static func _now_reads(property: String) -> String:
    match property:
        "painting_frame_rate":
            var rate := SaSettingsPerformance.label_of(SaSettingsPerformance.FRAME_RATES, SaSettings.painting_frame_rate)
            return SaPage.translated(RATE_NOW[rate]) if RATE_NOW.has(rate) else rate
        "half_size_view_while_moving":
            return (
                SaPage.translated("Half-size view while the canvas moves: %s.") % _on_off(SaSettings.half_size_view_while_moving)
            )
        "thumbnails_while_painting":
            var mode := SaSettingsPerformance.label_of(
                SaSettingsPerformance.THUMBNAIL_MODES, SaSettings.thumbnails_while_painting
            )
            return SaPage.translated(THUMBNAILS_NOW[mode]) if THUMBNAILS_NOW.has(mode) else mode
        "history_depth":
            var depth := SaSettings.history_depth
            return TranslationServer.translate_plural("Undo steps: %d.", "Undo steps: %d.", depth) % depth
        "filter_preview_on_canvas":
            return SaPage.translated("Start a filter's preview on the canvas: %s.") % _on_off(SaSettings.filter_preview_on_canvas)
    return property


static func _on_off(on: bool) -> String:
    return SaPage.translated("On") if on else SaPage.translated("Off")


## Drives the Performance page: `{"performance": "light"}`, `"defaults"` or
## `"read"` presses a button of the page as a hand would, through the row's own
## `drive`, and answers the five settings, the pacer's cap while painting and
## the summary line. Preferences is an embedded subwindow an injected click does
## not reach, which is why a scenario comes through here. Untyped page, for the
## reason `SaColorThemesPage.capture_rows` gives.
static func capture_page(tree: SceneTree, spec: Variant) -> String:
    for window in tree.root.find_children("*", "Window", true, false):
        if not window.has_method("show_page"):
            continue
        for found in window.find_children(SaSettingsPage.NODE_NAME, "VBoxContainer", true, false):
            if not found.has_method("press_light") or found.is_queued_for_deletion():
                continue
            match String(spec):
                "light":
                    found.page.row(&"light_mode").drive(null)
                "defaults":
                    found.page.row(&"defaults").drive(null)
            var summary_label := found.find_child("PerformanceSummary", true, false) as Label
            var report := {
                "painting_frame_rate": SaSettings.painting_frame_rate,
                "painting_max_fps": SaSettingsPerformance.painting_max_fps(SaSettings.painting_frame_rate),
                "thumbnails_while_painting": SaSettings.thumbnails_while_painting,
                "half_size_view_while_moving": SaSettings.half_size_view_while_moving,
                "history_depth": SaSettings.history_depth,
                "filter_preview_on_canvas": SaSettings.filter_preview_on_canvas,
                "summary": summary_label.text if summary_label != null and summary_label.visible else "",
            }
            return "SaCapture: performance %s" % JSON.stringify(report)
    return "SaCapture: no open Performance page"


static func _choices(entries: Array[Dictionary]) -> Array:
    var out: Array = []
    for entry: Dictionary in entries:
        out.append({"id": String(entry["id"]), "label": String(entry["label"])})
    return out
