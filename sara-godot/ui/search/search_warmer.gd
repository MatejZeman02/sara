## The build of the settings' rows the search lists, a page a frame, out of the
## painter's way.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A page took up to 0.45 s, so a page is built only while the hidden list's
## idle clock says the painter has stopped, or, when an opening found the rows
## stale and asked for them, while the open list's field has been still for
## [constant QUIET_FOR], so a painter typing never waits on one. No page bakes
## what only a drawn page needs, and the slowest, Keyboard shortcuts and Files,
## take under 100 ms. Each page is traced as `search warm page` in a perf
## window's frame lines. The last page in says [signal warmed], which the list
## reads its rows again on.
##
## A class apart from `SaSearchWindow`, which keeps its walk and its drawn
## rows: the build is the index's settings and the list's frames, and owns its
## own clock.
class_name SaSearchWarmer
extends Node

## The settings' rows are all in.
signal warmed

## How long the field has to be still, in seconds, before an open list builds
## a page of the settings' rows.
const QUIET_FOR := 0.5

## The index whose settings are built.
var index: SaSearchIndex = null
## Whether the list is up now, which a page waits on the still field for.
var _is_up: Callable
## Whether an opening asked for the rows, so the build does not wait for the
## painter to stop.
var _asked: bool = false
## Whether a build is under way.
var building: bool = false
## When the field last changed or the list last opened, in milliseconds.
var _still_since: int = 0


## *search_index* is the index built for, and *is_up* answers whether its list
## is open.
func _init(search_index: SaSearchIndex, is_up: Callable) -> void:
    name = "Warmer"
    index = search_index
    _is_up = is_up
    if index != null and index.context != null and index.context.ui != null:
        index.context.ui.settings_pages_changed.connect(start.bind(false))
    set_process(false)


## Builds the settings' rows a page a frame from now on, at once when *asked*.
func start(asked: bool = false) -> void:
    if not Engine.is_editor_hint() and index != null:
        _asked = _asked or asked
        building = true
        set_process(true)


## The field changed or the list opened, so an open list's page waits again.
func still() -> void:
    _still_since = Time.get_ticks_msec()


## An opening: the field is still from now, and rows found stale are asked for.
func opened() -> void:
    still()
    if index != null and index.settings_stale():
        start(true)


func _process(_delta: float) -> void:
    if not building:
        set_process(false)
        return
    if _is_up.call():
        if _asked and Time.get_ticks_msec() - _still_since >= QUIET_FOR * 1000.0:
            step()
        return
    if not (_asked or painter_stopped()):
        return
    var traced := SaFrameTrace.now()
    var done := index == null or index.warm_page()
    SaFrameTrace.spent("search warm page", traced)
    if done:
        _finish()


## Builds one page, and says [signal warmed] once the last is in. Answers
## whether the build is over.
func step() -> bool:
    if index != null and not index.warm_page():
        return false
    _finish()
    return true


func _finish() -> void:
    _asked = false
    building = false
    set_process(false)
    warmed.emit()


## Whether the app's idle clock says the painter has stopped and no stroke is
## open. True in a run with no clock, a suite's.
static func painter_stopped() -> bool:
    var clock := SaSettingsPerformance.idle_clock()
    if clock == null or clock.document == null:
        return clock == null
    return clock.said and not clock.is_stroke_open()
