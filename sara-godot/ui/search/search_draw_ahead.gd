## The empty query's rows drawn ahead out of sight, a few at a time on frames
## no menu is up in, so an opening of the list finds them made.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The hidden list reads its rows again every [constant LOOK_EVERY] while the
## painter has stopped, so a command that came to run since, an undo after a
## stroke, is dimmed or lit before an opening, and draws the empty query's rows
## again when they no longer match. Drawn in one frame, a page takes 31 to
## 33 ms, and a frame trace found it in the very frame a menu opened in, which
## took Image, Layer and View past 50 ms on a large painting.
##
## **A menu holds it.** While any window a press puts away is up, a menu of
## the bar, its overflow list or the Welcome window, nothing is read or drawn,
## nor in the frame after one was last seen up. **A frame draws rows for
## [constant BUDGET_MS] at most**, one row at the least, so a page comes in
## over several frames, and the columns are measured on the frame after the
## last row. Each frame's share is traced as `search rows drawn` in a perf
## window's frame lines, and the walk of a stale index as `search rows walked`
## on a frame of its own.
##
## An opening while a page is half drawn draws its own from the start, since
## the list keeps no page as its empty query's until the last frame of one has
## measured it, and the half is dropped.
##
## A class apart from `SaSearchWindow` because it owns something the list
## does not: this is the list's clock and its page in progress, and the
## drawing stays the list's.
class_name SaSearchDrawAhead
extends Node

## How often, in seconds, the hidden list reads its rows again while the
## painter has stopped.
const LOOK_EVERY := 0.5

## How long a frame draws rows for, in milliseconds.
const BUDGET_MS := 4.0

## The process priority that runs after every node at the default.
const LAST := 1000

## The index the rows are read from, which is not there in an editor.
var _index: SaSearchIndex = null
## The build of the settings' rows, which a draw-ahead waits for.
var _warmer: SaSearchWarmer = null
## Whether the list is up now, which drops a page in progress.
var _is_up: Callable
## The list's own steps of a page.
var _page: Page = null
## Whether the list wants its rows drawn again as soon as no menu holds it, a
## close on a typed query or the settings' rows come in.
var _wanted: bool = false
## Whether a page is being drawn, and the measuring of it is all that is left.
var _drawing: bool = false
var _measuring: bool = false
## When the hidden list last read its rows again, in milliseconds.
var _looked_at: int = 0
## The frame a menu was last seen up in.
var _menu_seen_on: int = -2


## *search_index* and *search_warmer* are the list's, *is_up* answers whether
## it is open, and *page* is its steps of a page.
func _init(search_index: SaSearchIndex, search_warmer: SaSearchWarmer, is_up: Callable, page: Page) -> void:
    name = "DrawAhead"
    _index = search_index
    _warmer = search_warmer
    _is_up = is_up
    _page = page
    # Last in the frame, so a menu the door or a deferred call opens in this
    # frame is already up when the draw-ahead looks.
    process_priority = LAST
    set_process(false)


## The rows are drawn again as soon as no menu holds them.
func want() -> void:
    _wanted = true
    set_process(true)


## Starts the clock that reads the rows again, as the list starts warming.
func wake() -> void:
    set_process(true)


## An opening drew its own rows, so nothing is wanted and a half page is
## dropped.
func drop() -> void:
    _wanted = false
    _drawing = false
    _measuring = false


## Whether a page is being drawn ahead now.
func is_drawing() -> bool:
    return _drawing or _measuring


func _process(_delta: float) -> void:
    if _is_up.call():
        drop()
        return
    if _warmer.building:
        return
    var frame := Engine.get_process_frames()
    if menu_up(self):
        _menu_seen_on = frame
        return
    if frame - _menu_seen_on <= 1:
        return
    if _measuring:
        var traced := SaFrameTrace.now()
        _page.finish.call()
        SaFrameTrace.spent("search rows drawn", traced)
        drop()
        return
    if _drawing:
        _draw_rows()
        return
    var due := Time.get_ticks_msec() - _looked_at >= LOOK_EVERY * 1000.0
    if _wanted or (due and SaSearchWarmer.painter_stopped()):
        _look()


## Reads the rows again, on a frame of its own when that walks them, and starts
## a page when the drawn rows no longer match.
func _look() -> void:
    _looked_at = Time.get_ticks_msec()
    if _index == null or _index.context == null:
        drop()
        set_process(false)
        return
    var traced := SaFrameTrace.now()
    if _page.read.call():
        SaFrameTrace.spent("search rows walked", traced)
        return
    _wanted = false
    if _page.stale.call():
        _page.start.call()
        _drawing = true
        _draw_rows()


## Draws rows of the first page until the frame's budget is spent, at least
## one, and leaves the measuring to the next frame once the page is in.
func _draw_rows() -> void:
    var traced := SaFrameTrace.now()
    var started := Time.get_ticks_usec()
    var done: bool = _page.add_row.call()
    while not done and Time.get_ticks_usec() - started < BUDGET_MS * 1000.0:
        done = _page.add_row.call()
    SaFrameTrace.spent("search rows drawn", traced)
    if done:
        _drawing = false
        _measuring = true


## Whether a window a press puts away is up in *node*'s tree, a menu above
## all. The search list joins no such group, so it never holds itself.
static func menu_up(node: Node) -> bool:
    if not node.is_inside_tree():
        return false
    for member in node.get_tree().get_nodes_in_group(SaPutAway.GROUP):
        var window := member as Window
        if window != null and window.visible:
            return true
    return false


## The list's steps of a page, handed in rather than the list, since the page
## drawn is the list's and the clock and the page in progress are this class's.
class Page:
    extends RefCounted

    ## Reads the rows again and answers whether that walked them.
    var read: Callable
    ## Answers whether the drawn rows are not the empty query's for the view.
    var stale: Callable
    ## Starts the empty query's rows, none drawn yet.
    var start: Callable
    ## Draws one more row and answers whether the first page is in.
    var add_row: Callable
    ## Measures the drawn page and keeps it as the empty query's.
    var finish: Callable

    func _init(read_rows: Callable, is_stale: Callable, start_page: Callable, add_one: Callable, finish_page: Callable) -> void:
        read = read_rows
        stale = is_stale
        start = start_page
        add_row = add_one
        finish = finish_page
