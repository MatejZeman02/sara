## What the Performance settings may hold, and the light mode that sets them.
##
## Five settings ask less of the GPU: the frame rate while painting, the view
## drawn at half size while the canvas moves, when the layer thumbnails and the
## minimap redraw, how deep the undo history goes, and whether a filter's
## preview on the canvas starts on. The first three are stored on
## `SaSettingsValues`, the fourth is its `history_depth`, the fifth is
## `filter_preview_on_canvas` on its base `SaSettingsImporting`, and this class
## owns their vocabulary and the preset that writes all five at once, because
## the Performance page is one reader and the offer to a weak GPU is the next.
##
## **The light mode is a preset and nothing remembers it.** The switch only sets
## the settings: [method apply_light]
## writes five values and returns, and a painter who then moves one of them has
## moved one setting, with no mode left behind to fall out of.
##
## `@tool` because the autoload that reads it is.
@tool
class_name SaSettingsPerformance
extends RefCounted

## The frame rate while painting. The display's refresh rate is the default,
## because a frame the glass never shows is a composite spent for nothing and
## most painters are on a laptop whose GPU pays for it. Uncapped is the choice
## for a strong GPU, where it keeps the brush ring closest to the pen. Thirty is
## the floor for a GPU that cannot keep up with the glass.
const UNCAPPED: String = "uncapped"
const REFRESH: String = "refresh"
const THIRTY: String = "30"
const FRAME_RATES: Array[Dictionary] = [
    {"id": UNCAPPED, "label": "Uncapped"},
    {"id": REFRESH, "label": "The display's refresh rate"},
    {"id": THIRTY, "label": "30 frames a second"},
]

## When the layer thumbnails and the minimap redraw during a stroke. Every
## quarter second is the default. Only
## when the pen lifts holds both while a pointer button is down. When I stop
## painting holds both until the idle clock says the painter has stopped, so a
## weak GPU redraws neither between strokes either.
const QUARTER_SECOND: String = "quarter_second"
const PEN_LIFT: String = "pen_lift"
const STOPPED: String = "stopped"
const THUMBNAIL_MODES: Array[Dictionary] = [
    {"id": QUARTER_SECOND, "label": "Every quarter second"},
    {"id": PEN_LIFT, "label": "Only when the pen lifts"},
    {"id": STOPPED, "label": "When I stop painting"},
]

## The two answers the offer of the light mode keeps, beside the empty
## string of a profile that was never asked. Turned on is the light mode's
## button pressed from the offer, not now is the other button and a dialog
## closed without either.
const OFFER_TURNED_ON: String = "turned_on"
const OFFER_NOT_NOW: String = "not_now"
const OFFER_ANSWERS: Array[String] = [OFFER_TURNED_ON, OFFER_NOT_NOW]

## The undo depth the light mode writes. Six, what a 256 MiB budget holds of a
## 1920x1080 F32 document's whole-canvas steps, and so the depth at which that
## document's history sits on `SaHistory`'s floor rather than above it. The
## snapshots live in VRAM, and a weak GPU is most often an integrated one whose
## VRAM is the painter's RAM, so the history there holds about half of what
## twelve would, 256 MiB for 480.
const LIGHT_HISTORY_DEPTH: int = 6

## The frame rate `THIRTY` caps at, and the one assumed for `REFRESH` where the
## display server cannot say, which is a headless run and a driver that answers
## -1.
const THIRTY_FPS: int = 30
const REFRESH_UNKNOWN_FPS: int = 60


## *mode* when it is one of [constant FRAME_RATES], and the display's refresh
## rate otherwise.
static func frame_rate_or_default(mode: String) -> String:
    return mode if _listed(FRAME_RATES, mode) else REFRESH


## *mode* when it is one of [constant THUMBNAIL_MODES], and every quarter second
## otherwise.
static func thumbnails_or_default(mode: String) -> String:
    return mode if _listed(THUMBNAIL_MODES, mode) else QUARTER_SECOND


## *answer* when it is one of [constant OFFER_ANSWERS], and unasked otherwise.
static func offer_answer_or_unasked(answer: String) -> String:
    return answer if OFFER_ANSWERS.has(answer) else ""


## The `Engine.max_fps` a frame rate setting asks for while the hand moves, 0
## being uncapped. Rounded up, so a 59.94 Hz display is capped at 60 and the
## cap never lands a frame after the refresh it was meant for.
static func painting_max_fps(mode: String) -> int:
    match mode:
        REFRESH:
            var hertz := DisplayServer.screen_get_refresh_rate() if DisplayServer.get_name() != "headless" else -1.0
            return int(ceilf(hertz)) if hertz > 0.0 else REFRESH_UNKNOWN_FPS
        THIRTY:
            return THIRTY_FPS
    return 0


## Whether a thumbnail or the minimap holds its redraw now. The pen lift holds
## while a pointer button is down, the button rather than a stroke the document
## opened, because the pen is what the row names and a pen on a tablet presses
## the left button as it lands. The stop holds until the idle clock has said the
## painter stopped, and again from the next edit or the next stroke. A run with
## no clock, or one whose clock watches no document, holds nothing, because no
## painter is painting and nothing would ever let the picture go.
static func holds_redraw(mode: String) -> bool:
    match mode:
        PEN_LIFT:
            return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
        STOPPED:
            var clock := idle_clock()
            return clock != null and clock.document != null and (not clock.said or clock.is_stroke_open())
    return false


## The idle clock the app runs, the autoload `SaIdle`, or null in a run without
## it. Found by its path, the way `SaReductionService` finds it.
static func idle_clock() -> SaIdleClock:
    var tree := Engine.get_main_loop() as SceneTree
    return tree.root.get_node_or_null(^"SaIdle") as SaIdleClock if tree != null else null


## The five values the light mode writes, by property. The frame rate is the
## default's too, and stays here because a profile that chose Uncapped is the
## one a weak GPU most needs it written back into. The preview on the canvas is
## off here and on by default: a filter's preview starts off only where the
## settings for a weak GPU are on.
static func light_values() -> Dictionary[String, Variant]:
    return {
        "painting_frame_rate": REFRESH,
        "half_size_view_while_moving": true,
        "thumbnails_while_painting": PEN_LIFT,
        "history_depth": LIGHT_HISTORY_DEPTH,
        "filter_preview_on_canvas": false,
    }


## The five values a fresh profile has, by property, read off a fresh values
## object so a default is still written down once.
static func default_values() -> Dictionary[String, Variant]:
    var fresh := SaSettingsValues.new()
    var out: Dictionary[String, Variant] = {}
    for property: String in light_values():
        out[property] = fresh.get(property)
    fresh.free()
    return out


## Writes the light mode's five values into *settings* and answers the
## properties whose value moved, in the order of [method light_values].
static func apply_light(settings: SaSettingsValues) -> Array[String]:
    return _write(settings, light_values())


## Puts the five back to their defaults and answers what moved.
static func apply_defaults(settings: SaSettingsValues) -> Array[String]:
    return _write(settings, default_values())


static func _write(settings: SaSettingsValues, values: Dictionary[String, Variant]) -> Array[String]:
    var moved: Array[String] = []
    if settings == null:
        return moved
    for property: String in values:
        if settings.get(property) == values[property]:
            continue
        settings.set(property, values[property])
        moved.append(property)
    return moved


## The label *mode* carries in *entries*, or *mode* itself where none does.
static func label_of(entries: Array[Dictionary], mode: String) -> String:
    for entry: Dictionary[String, Variant] in entries:
        if entry["id"] == mode:
            return str(entry["label"])
    return mode


static func _listed(entries: Array[Dictionary], mode: String) -> bool:
    for entry: Dictionary[String, Variant] in entries:
        if entry["id"] == mode:
            return true
    return false
