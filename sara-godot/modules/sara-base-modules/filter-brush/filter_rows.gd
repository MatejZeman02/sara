## The chosen filter's own rows in the Tool Options, under the Filter choice,
## setting the brush's parameters and applying nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the filter brush's folder, built by `module.gd` for its
## `filter_rows` option.
##
## **In the docker rather than behind a button.** A window behind a Filter
## Settings button is not where a painter looks for how strong the Gaussian
## Blur is, so the rows stand in the Tool Options themselves, the Gaussian's
## Radius right under the Filter choice, and a press is not needed to see one.
##
## **The filter's dialog without its frame.** The rows are built with
## `SaDialog.for_filter`, exactly as the Filter menu's window and an attached
## filter's panel build them, so every filter's page is here with nothing to
## write per filter. The rows a brush has no use for are hidden, as the panel
## hides them: Apply and Cancel, since nothing is applied, and the thumbnail
## and the Preview switch, since the stroke on the canvas is the preview. Every
## settled change is handed to the docker's write through the dialog's own
## rerun, so it lands on the brush's `filter_page` the way a slider's move
## lands on its key, and the next stroke paints with it.
##
## The registry holds one instance per filter, and every reader hands it its
## own values before a run, the brush's evaluation and an attached filter's
## record alike, while the Filter menu's window opens on the defaults. So the
## rows leave the instance holding the brush's values, as the attached filter's
## panel leaves it holding the record's.
##
## **Another page on the same instance.** The Filter menu's window, an attached
## filter's panel and its edit window build their pages on that instance too,
## and the store then answers their controls, so the rows' write would hand the
## brush the other page's values. The rows ask `SaFilter.page` whose page the
## instance holds. While another page is up they hide behind a line and write
## nothing, as the panel does under the Filter dialog, and once it has gone
## they draw their rows again from the brush's page and take the instance back.
## They ask every frame rather than being told, because the rows are a
## module's and name none of the windows that build pages.
extends VBoxContainer

## The node name, which is how a capture and a suite find the rows.
const NODE_NAME: String = "FilterRows"

## The widgets of a filter's dialog the rows leave out, by the name `SaDialog`
## knows each by, the filter panel's list.
const LEFT_OUT: Array[String] = ["apply_cancel", "preview", "thumbnail", "canvas_preview"]

## The label column's width in logical pixels, the Tool Options docker's own,
## so a filter's labelled row lines up with the brush's rows around it.
const LABEL_WIDTH: int = 104

## The filter whose rows these are, null before the first page and for a
## filter no installed module offers.
var filter: SaFilter = null
## The page the filter declared.
var dialog: SaDialog = null

## Where a settled change goes, the docker's write of the option.
var _write: Callable = Callable()
## The filter's key and the values the rows were last drawn from or last wrote,
## which tells a change made behind the rows' back, a preset's, from their own.
var _shown_key: String = ""
var _shown: Dictionary = {}
## The line standing in for the rows while another page holds the instance,
## null while the rows hold it.
var _lent_note: Label = null


func _init(write: Callable) -> void:
    name = NODE_NAME
    _write = write
    size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Draws the rows of *page*, the brush's `filter_page`, unless they show it
## already. A change still waiting for its rerun is the hand's and is left to
## land.
func show_page(page: Dictionary) -> void:
    follow_holder()
    var key := String(page.get("filter_key", ""))
    var values: Dictionary = page.get("parameters", {})
    var chosen := page.get("filter") as SaFilter
    if key == _shown_key and values == _shown:
        return
    if key == _shown_key and dialog != null and dialog.rerun_pending:
        return
    _shown_key = key
    _shown = values.duplicate(true)
    # Drawn now, the rows would write the brush's values into the other page's
    # store, so they wait for it to go and draw from these then.
    if _lent_note != null and chosen == filter:
        return
    _draw_page(chosen)


## Hides the rows while another page holds the filter's instance and draws them
## again from the brush's page once it has gone. Every frame, and before every
## show and write, so a move of a row never lands on a page that is not theirs.
func follow_holder() -> void:
    if filter == null or dialog == null or _holds():
        return
    if _other_page_up():
        _lend()
    else:
        _draw_page(filter)


## Hands what the rows hold to the docker's write. The dialog's deferred rerun
## calls it, so two rows moved in one frame are one write, and a suite calls
## `dialog.flush_rerun()` in place of the frame boundary.
func write_back() -> void:
    if filter == null or not _holds():
        return
    var values := filter.parameters()
    if values == _shown:
        return
    _shown = values.duplicate(true)
    if _write.is_valid():
        _write.call({"filter_key": _shown_key, "parameters": values})


## Builds *chosen*'s page into this box from the values last shown. `realize`
## empties the box first, so a second call replaces the first page.
## `{"widget": "contrast", "value": 40}` moves the named row as a hand would
## and lets its write land, then answers whether the rows are lent and the
## values they show. A scenario's `option` step on `filter_rows` reaches it.
func capture_option_edit(spec: Dictionary) -> String:
    follow_holder()
    if dialog == null:
        return "FilterRows: no filter chosen"
    if spec.has("widget"):
        var entry := dialog.row(StringName(String(spec["widget"])))
        if entry == null:
            return "FilterRows: %s has no row '%s'" % [filter.title(), spec["widget"]]
        if entry.control != null and entry.control.has_method("capture_option_edit"):
            entry.control.call("capture_option_edit", {"value": spec.get("value")})
        else:
            entry.drive(spec.get("value"))
        dialog.flush_rerun()
    var lent := _lent_note != null
    return "FilterRows: lent %s, the rows show %s" % [lent, _shown if lent else filter.parameters()]


func _process(_delta: float) -> void:
    follow_holder()


## Whether the instance's store and widgets still answer this page's controls.
func _holds() -> bool:
    return dialog != null and filter != null and filter.page != null and filter.page.get_ref() == dialog


## Whether the page that holds the instance now is on the screen. A dialog that
## closed is freed or hidden with its window, and either way gives it back.
func _other_page_up() -> bool:
    var other := filter.page.get_ref() as SaDialog if filter.page != null else null
    if other == null:
        return false
    for entry: SaPageRow in other.rows():
        if is_instance_valid(entry.line) and entry.line.is_visible_in_tree():
            return true
    return false


## Hides the rows behind the line the panel shows under the Filter dialog. A
## change still waiting for its rerun finds the instance lent and writes
## nothing, rather than the other page's values.
func _lend() -> void:
    if _lent_note != null:
        return
    for child: Node in get_children().filter(func(node: Node) -> bool: return node is Control):
        (child as Control).visible = false
    _lent_note = Label.new()
    _lent_note.name = "LentNote"
    _lent_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var sentence := tr("%s is open in the Filter dialog. Its values come back here when that closes.")
    _lent_note.text = sentence % filter.translated_title()
    add_child(_lent_note)


func _draw_page(chosen: SaFilter) -> void:
    if dialog != null and dialog.rerun.is_connected(write_back):
        dialog.rerun.disconnect(write_back)
    dialog = null
    _lent_note = null
    filter = chosen
    if filter == null:
        for child in get_children():
            child.queue_free()
        return
    dialog = SaDialog.for_filter(filter)
    filter.set_parameters(_shown)
    dialog.realize(self)
    for declared: SaPageRow in dialog.rows():
        if declared.line == null:
            continue
        if LEFT_OUT.has(dialog.widget_name(declared.key)):
            declared.line.visible = false
        elif declared.line.get_child_count() > 0:
            (declared.line.get_child(0) as Control).custom_minimum_size.x = SaUI.px(LABEL_WIDTH)
    dialog.rerun.connect(write_back)
