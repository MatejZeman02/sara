## What the two cursor lead preferences may hold: the latency that follows the
## display, and the three modes of the lead with their wording.
##
## Its own class because it is the vocabulary of two preferences rather than a
## preference, the way [SaSettingsPerformance] holds the Performance page's.
## Both moved down from `SaCursorPrediction` into `SaSettingsValues` once,
## because a setter there clamps against them and `core` may not name a class
## under `ui`. They left the values for this file when two new preferences
## would have taken that one past the length gate.
##
## `@tool` because the autoload that reads it is.
@tool
class_name SaSettingsCursorLead
extends RefCounted

## What `cursor_prediction_ms` holds when the latency is the display's own
## refresh interval rather than a number somebody wrote.
const FOLLOW_DISPLAY: float = -1.0

## What `cursor_lead` may hold and what the Workspace page calls each one.
## Listed here rather than on the page, so the row and the rule cannot come to
## name different things.
const LEAD_MODES: Array[Dictionary] = [
    {"id": "auto", "label": "Auto, where the pointer lags"},
    {"id": "on", "label": "On"},
    {"id": "off", "label": "Off"},
]


## Whether *mode* is one of [constant LEAD_MODES].
static func is_lead_mode(mode: String) -> bool:
    for entry: Dictionary[String, Variant] in LEAD_MODES:
        if entry["id"] == mode:
            return true
    return false
