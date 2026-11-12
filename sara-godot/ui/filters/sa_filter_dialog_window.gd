## The window a registered filter opens in, and the thing that answers the
## registry's `invoked`.
##
## The door is a signal on purpose: the Filter menu row and the filter's command
## both call `registry.invoke(key)`, which emits `invoked`, and nothing in that
## half knows a window exists. This is what listens. One window serves every
## filter, built on the first invoke and kept, the way `MainDialogs` keeps each
## of Sara's own dialogs.
##
## It owns three things a filter must not have to think about. The context,
## made by `SaFilterDialogTarget` for the active layer, again on a layer picked
## while open, and dropped on a close, so cancel is free: nothing was written. The
## rerun, which is [SaDialog]'s deferred flag, so two widgets moved in one frame
## cost one call to `run`. And apply, which is `SaFilterOps.one_shot` over the
## last pass the filter recorded or the last texture it showed, or, by the
## sliding choice of four over Apply, `SaFilterOps.attach` with the dialog's
## settings on the active layer or on the whole picture, or an adjustment layer
## holding them through `SaFilterConversion`.
##
## The chrome is `SaDialogWindow`'s, and nothing here changes it.
@tool
class_name SaFilterDialogWindow
extends SaDialogWindow

## The node this window is put under, and the name `install` looks for.
const NODE_NAME := "FilterDialog"

## A preview run shorter than this many milliseconds, about a frame at 60 Hz,
## opens no window in [member compressor]: it cannot have a drag outrun it, so
## nothing is held back. Only a run that outlasts the frame that asked for it is
## dropped when the painter moves the slider again.
const COALESCE_ABOVE_MSEC := 16

## How long the drag a run opens stays open, in seconds. Longer than a frame at
## any rate this runs at, so a run that outlasts its own frame cannot have the
## next slider tick start a second one before the first has been seen. The run's
## own CPU cost is measured by [SaPreviewCompressor] and is small: what a run
## costs the painter is the composite it asks for on the next frame, which the
## window covers.
const COALESCE_WINDOW_SECONDS := 0.2

## The dialog the current filter built, or null when nothing is open.
var dialog: SaDialog = null

## The filter being edited, and what it is being run against.
var filter: SaFilter = null
var context: SaFilterContext = null

## How many times `run` has actually been called since this window opened, which
## is the number a scenario reads beside the dialog's own.
var runs: int = 0

## The rule that decides when the preview runs again: the first change at once
## and the rest of a drag folded into one run when the window closes, the same
## rule the brush editor's strip and its tip preview answer to. A preview run
## costs a neighbourhood pass over every chunk, so a slider tick per frame was a
## run per frame queued behind the last on the card. Owns the redraw, which is
## [method run_filter].
var compressor: SaPreviewCompressor = null
## Whether the canvas preview of this run is a drag's coarser draft.
var _draft: SaCanvasDraft = null

## The three ways Apply can take, by the name a scenario picks one with, in
## the toggle's order, Bake first because it is the default. The whole
## picture is the Affect all check's, not a fourth way.
const WAYS: Array[StringName] = [&"bake", &"attach", &"layer"]

## The words over the three stops, in `WAYS`'s order. English, because the
## control translates its own labels. The first stop says Apply, the word the
## conventions give for writing an effect into the pixels. The id stays
## `bake`, which a profile stores.
const WAY_LABELS: Array[String] = ["Apply", "Attach", "Layer"]

## The toggle, one thumb sliding between Bake, Attach and Layer in
## `WAYS`'s order with each way's word over its stop, or null when the filter's page
## drew no Apply row for this window to put it over. It opens on the way a hand
## last picked, `SaSettings.filter_way`, which is Bake on a fresh profile, and
## on the first way left open where `SaFilterApply.way_refusal` dims that one.
##
## Bake writes the filter into the active layer's pixels, or into those of
## every paint layer of an active group, as one step. Attach puts one
## record on the active layer with the settings the widgets hold. Layer adds an
## adjustment layer above the active layer holding that record. Picture puts
## the record on the document's root, over every layer, which the Layers
## docker draws as a row of its own above them all.
##
## Not three buttons in one group, which in the row with Cancel and Apply read
## as three more buttons.
var way_toggle: SaStopSlider = null

## The Affect all check beside the toggle. Ticked, Apply reaches
## the whole picture: Bake writes every paint layer as one step,
## `SaFilterOps.bake_under` over the document, Attach hangs the record on the
## document and Layer makes the adjustment layer with Affect all on. It
## opens as a hand last left it, `SaSettings.filter_affect_all`, which is off on
## a fresh profile, and is null where there is no toggle.
var affect_all: CheckBox = null

## The layer types the adjustment layer of the Layer way is registered in.
## Written by `install` from Main's registries, and by a suite that builds the
## window by hand. Null leaves Layer dimmed, since nothing could make the layer.
var layer_types: SaLayerTypeRegistry = null

## What the last `run` said. False means it showed nothing, and Apply is dead.
var ran_clean: bool = false

## The scrolled page and its pinned Apply row.
var _frame: SaFilterDialogFrame = null
var _registry: SaFilterRegistry = null

## The pass the last run recorded, or null for a filter that shows a texture.
var _handed: SaPointPass = null
## The document a point pass was handed to, so closing takes it back off.
var _previewed: SaDocument = null
## The registry key of the open filter, which attaching needs and the filter's
## own page does not carry.
var _key: StringName = &""
## The document and layer the open dialog works on, null while it is closed.
var _target: SaFilterDialogTarget = null
## The line under the preview that says the layer is not drawn, or null.
var _hidden_note: Label = null

## The canvas this window drives, or null for the front document's.
##
## Left null in the running app, where `SaCanvasView.front_canvas()` answers.
## Set by a test so a window outside the tree can drive a bench canvas.
var target_canvas: SaCanvas = null


func _init() -> void:
    _init_dialog(NODE_NAME, "", SaFilterDialogFrame.OPENING_SIZE, SaFilterDialogFrame.FLOOR)
    # A Window is visible the moment it joins the tree, and this one is
    # installed at boot: without this it sat blank over the top left of the
    # canvas from the first frame, an untitled 660 by 640 box that swallowed
    # every press under it and that park could not move.
    visible = false

    # The × and Escape both ask for this, so either one cancels.
    close_requested.connect(cancel_filter)
    # A number typed into a slider and taken with Enter is a setting to look
    # at, so the preview runs again on it and Apply waits for its own press.
    number_field_answers = false

    _frame = SaFilterDialogFrame.new()
    content.add_child(_frame)
    scrolling_body = _frame.scroll

    # The rule the rerun answers to, as the brush editor's previews do. Every
    # widget change asks it rather than running the filter on the spot. A run
    # shorter than [constant COALESCE_ABOVE_MSEC] opens no window, so a cheap
    # filter's preview still runs on every change and only a run that lags, one
    # longer than the frame that asked for it, is one the next change drops.
    compressor = SaPreviewCompressor.new(run_filter)
    compressor.coalesce_above_msec = COALESCE_ABOVE_MSEC
    compressor.window_seconds = COALESCE_WINDOW_SECONDS
    compressor.window_per_draw = 1.0
    add_child(compressor)
    _draft = SaCanvasDraft.new(_preview_on_canvas)
    add_child(_draft)


## Puts one of these under *host* and points it at the filter registry.
##
## The shape `SaMessage.install` has, and called from the same line of
## `Main`'s boot. Guarded, because a module reload runs the bootstrap
## again and a second connection to one callable is a warning at best.
static func install(host: Node) -> void:
    if host == null:
        return
    var found := host.get_node_or_null(NodePath(NODE_NAME)) as SaFilterDialogWindow
    if found == null:
        found = SaFilterDialogWindow.new()
        host.add_child(found)
    var registries := host.get("registries") as SaRegistries
    if registries != null:
        found.watch(registries.filters)
        found.layer_types = registries.layer_types


## The open window under the current scene, or null. What the capture step and
## a test reach it by.
static func find_in(tree: SceneTree) -> SaFilterDialogWindow:
    if tree == null:
        return null
    for node in tree.root.find_children(NODE_NAME, "Window", true, false):
        var window := node as SaFilterDialogWindow
        if window != null:
            return window
    return null


## Names the window, in the OS title and in the drag bar both.
##
## `SaDialogWindow` writes the drag bar's label once, from the title it was
## constructed with, and one window here serves every filter that is ever
## registered. So the label is written again rather than the window rebuilt,
## which is the same thing `SaRadiusDialog` does when it retitles itself for its
## two menu rows.
func retitle(text: String) -> void:
    title = text
    var label := drag_handle.find_child("TitleLabel", true, false) as Label if drag_handle != null else null
    if label != null:
        label.text = text


## Answers *registry*'s `invoked` from now on.
func watch(registry: SaFilterRegistry) -> void:
    if registry == null or registry == _registry:
        return
    if _registry != null and _registry.invoked.is_connected(open_filter):
        _registry.invoked.disconnect(open_filter)
    _registry = registry
    if not registry.invoked.is_connected(open_filter):
        registry.invoked.connect(open_filter)


## Opens the filter of that key on the document's active layer.
##
## Deferred nothing and awaits nothing: the menu row already defers its call,
## for the popup focus reason its own file records, so by the time this runs the
## popup is closed and taking focus is safe.
func open_filter(filter_key: StringName) -> void:
    _open(filter_key, {}, SaSettings.filter_preview_on_canvas)


## Opens on the active layer with *kept* settings over the declared defaults,
## none for a fresh open, and the canvas preview ticked as *on_canvas*.
func _open(filter_key: StringName, kept: Dictionary, on_canvas: bool) -> void:
    var wanted := _registry.get_filter(filter_key) if _registry != null else null
    var document := SaFilterDialogTarget.document_of(_canvas())
    if wanted == null or SaFilterDialogTarget.refuses(document, filter_key):
        return
    _close(false)
    filter = wanted
    SaFilterPanel.give_way(self, wanted)
    _key = filter_key
    _target = SaFilterDialogTarget.new(document, _canvas)
    _target.switched.connect(_follow)
    _target.left.connect(cancel_filter)
    context = _target.context(_registry.owner_of(filter_key), wanted.title())
    # A one-shot opens on the declared defaults, whatever the last dialog or
    # record left in the registry's one instance, and a followed switch on the
    # settings the painter had.
    filter.store.reset()
    if not kept.is_empty():
        filter.set_parameters(kept)
    dialog = SaDialog.for_filter(filter, filter_key)
    retitle(dialog.dialog_title)
    _frame.show_page(dialog)
    _place_way_toggle(document.active_layer)
    _note_hidden(document)
    if dialog.canvas_box != null:
        # Set before the connection, so the first run below is the one that
        # reads it and no toggle is heard. The switch stays live either way.
        dialog.canvas_box.button_pressed = on_canvas
        dialog.canvas_box.toggled.connect(_on_canvas_box_toggled)
    dialog.rerun.connect(_ask_to_run)
    dialog.applied.connect(apply_filter)
    dialog.cancelled.connect(cancel_filter)
    default_button = dialog.apply_button
    # The layer as it stands, so a dialog whose filter shows nothing still opens
    # on a picture rather than on a hole. Reduced to the thumbnail's size, never
    # a copy of the layer at its own, and nothing at all for a dialog
    # that declared no picture.
    var thumbnail := dialog.preview_control
    if thumbnail != null and is_instance_valid(thumbnail):
        thumbnail.show_layer(context)
    _reopen_at_opening_size()
    # The run on open, through the same door every later change goes through.
    # The compressor's window is cleared first, so a filter opened just after a
    # drag on the last one draws at once rather than waiting on its window.
    compressor.reset()
    dialog.request_rerun()
    dialog.flush_rerun()


## Puts the window back at the size it was built with and shows it at the right
## edge of the main window, so the fit on the next frame grows it to this page
## and to no page before it.
##
## `fit_opening_size` grows and never shrinks, which is right for a dialog that
## shows one page and wrong for one window that serves every filter: once
## Curves had been open, Gaussian Blur opened at Curves' height. A window that
## is already up is not shown again, so it asks for the fit itself.
##
## **The floor goes down before the size does.** A `Window` keeps a size under
## its `min_size` at the `min_size`, and `apply_window_scale` writes the size
## first, so with the floor Curves' fit had raised still standing the reset
## would be taken back on the spot, and Gaussian Blur would open at Curves'
## height while `logical_size` said its own.
func _reopen_at_opening_size() -> void:
    var was_open := visible
    logical_size = SaFilterDialogFrame.OPENING_SIZE
    logical_min_size = SaFilterDialogFrame.FLOOR
    min_size = SaUI.window_size_for(self, logical_min_size)
    apply_window_scale()
    popup(Rect2i(_edge_position(), size))
    if was_open:
        _fit_next_frame()


## Where the window stands against the right edge of the main window, top
## aligned under the menu bar, moved inside the host by the rule every dialog is
## held to.
##
## Not centred, because a dialog over the middle of the document hides the
## strokes the filter is changing with Preview on canvas ticked. The right edge
## is where the dockers are and the middle of the canvas is not, and the window
## is draggable.
func _edge_position() -> Vector2i:
    var edge := _main_window_rect()
    return _clamped_to_host(corner_at_the_right_edge(edge, size))


## The corner a window of *wanted* stands at to touch the right edge of *host*
## with its top on the host's top, before the margin and the clamp.
##
## Static and by argument, so a suite can hold the 1920 by 1080 case
## without a window that size.
static func corner_at_the_right_edge(host: Rect2i, wanted: Vector2i) -> Vector2i:
    return Vector2i(maxi(host.end.x - wanted.x, host.position.x), host.position.y)


## The part of the host the main window covers: all of it for an embedded
## window, whose host is the main window, and the main window's own rectangle
## for an OS window, whose host is the screen the main window may only fill part
## of.
func _main_window_rect() -> Rect2i:
    var host := host_rect()
    if not is_inside_tree() or is_embedded():
        return host
    var main := get_tree().root
    var covered := host.intersection(Rect2i(main.position, main.size))
    return covered if covered.has_area() else host


## A widget change asks for a run. The compressor runs the first at once and
## folds the rest of a drag into one when its window closes, so a run that is
## still on the card when the slider moves again is dropped for the newer one
## rather than queued behind it.
func _ask_to_run() -> void:
    compressor.request()


## Calls the filter's `run` and puts whatever it showed in the preview.
##
## Through the guarded call, so a run that came back with nothing says so in the
## console naming the student's own file, and the layer is untouched either way
## because the context it was handed has no writer.
func run_filter() -> void:
    if filter == null or context == null:
        return
    runs += 1
    ran_clean = SaFilterApply.call_run(filter, context)
    _handed = context.point
    _fill_thumbnail()
    _preview_on_canvas()
    # The open's own run is fitted with the rest of the page a frame later.
    _thumbnail_follows_the_switch(runs > 1)
    if dialog.apply_button != null and is_instance_valid(dialog.apply_button):
        dialog.apply_button.disabled = not ran_clean
    _sync_layer_way()


## Puts this run in the thumbnail, for every kind of filter.
##
## A texture the run showed is blended with the layer under the selection's
## mask, so the picture shows what Apply will write and not only the run's
## rectangle. A point pass is run over a reduced copy of the layer by the
## thumbnail itself. A neighbourhood pass is gathered at full size by the
## browser's own evaluation, because its radius is in document pixels and a
## reduced copy would read too far, and then blended the same way. A pass that
## reads the whole layer is the thumbnail's own run over where it writes. A
## dialog that declared no picture costs none of the four.
func _fill_thumbnail() -> void:
    var thumbnail := dialog.preview_control
    if thumbnail == null or not is_instance_valid(thumbnail):
        return
    if _handed == null:
        thumbnail.show_texture(SaFilterPreview.blended(context), context.shown_rect)
    elif SaFilterBrowser.reads_whole(context):
        # Under a canvas preview the thumbnail is hidden, and its own run over
        # the whole layer a second one nobody sees, so it waits for the switch.
        if _thumbnail_shown(true):
            thumbnail.show_whole_pass(context)
    elif _handed is SaNeighbourhoodPass:
        thumbnail.show_gathered(context, SaFilterBrowser.PassPicture.evaluate(context))
    else:
        thumbnail.show_point_pass(context)


## Writes the filter into the layer as one undo step, and closes. Through
## `SaFilterOps.one_shot`, which writes a point filter the way an attached one
## is flattened.
##
## On Attach it attaches instead: the layer keeps every pixel it had and gains
## one record, `Attach Filter` in history, whose settings are the ones the
## widgets hold. On Picture the same record goes on the document's root. On
## Layer an adjustment layer holding that record goes in above the active
## layer, `Add Adjustment Layer` in history. Apply is the only thing
## that reads the toggle, so a painter who picks Attach, looks at the preview
## and picks Bake again gets the write they asked for.
##
## What Apply ran is kept first, the filter, its widgets' values and the way,
## for Filter > Apply Again to run on another layer with no dialog.
func apply_filter() -> void:
    _let_go()
    if filter != null:
        SaFilterAgain.remember(_registry, _key, filter.title(), filter.parameters(), way())
    match way():
        &"attach":
            _attach(every())
        &"layer":
            _add_layer()
        _:
            SaFilterOps.one_shot(context, filter, every())
    _close(true)


## Attaches the open filter to the layer the dialog was made for, or to the
## document's root when *whole*, as one history step and with no pixel written.
##
## `SaFilterOps.attach` is what the Filter menu's Attach row and the browser's
## Attach button made, and the record is what `filter.filed_as` answers, the
## dialog's own widgets under its key for every filter but an entry over
## another's kernel, because the registry holds one filter instance per key and
## `build` gave it these rows. A refused attach, a key no registry answers for
## or a layer the document has lost, leaves the layer alone.
func _attach(whole: bool) -> void:
    if context == null or filter == null:
        return
    var filed := filter.filed_as(_key)
    SaFilterOps.new(context.document).attach(null if whole else context.layer, filed.key, filed.parameters)


## Adds an adjustment layer above the active layer holding the open filter's
## record, as `filter.filed_as` answers it, as one history step, named after the
## filter the painter picked, with Affect all on when the check is.
func _add_layer() -> void:
    if context == null or filter == null:
        return
    var filed := filter.filed_as(_key)
    var conversion := SaFilterConversion.new(context.document)
    conversion.add_holding(filed.key, filed.parameters, layer_types, filter.translated_title(), every())


## Layer's tooltip. The dialog previews the filter over the active layer alone
## while Layer would adjust everything under it, so the tooltip says which of
## the two the preview shows.
func _layer_tip() -> String:
    return (
        "%s %s"
        % [
            (
                tr("Adds an adjustment layer holding %s above the active layer, which adjusts everything under it.")
                % filter.translated_title()
            ),
            tr("The preview shows the active layer alone."),
        ]
    )


## The sentence the tooltips after Bake's end on under a selection, which
## each of those ways copies into the record's mask. Empty with nothing selected.
func _selection_note() -> String:
    var selection := context.document.selection if context != null else null
    return " " + tr("The selection becomes the filter's mask.") if selection != null and selection.active else ""


## Whether Apply reaches the whole picture, the Affect all check ticked.
func every() -> bool:
    return affect_all != null and is_instance_valid(affect_all) and affect_all.button_pressed


## The way Apply takes now, one of `WAYS`, and Bake for a page with no toggle.
func way() -> StringName:
    if way_toggle != null and is_instance_valid(way_toggle):
        return StringName(way_toggle.value)
    return WAYS[0]


## Pins the toggle of four over the row that holds Apply and Cancel, on the
## first way it leaves open for *layer*.
##
## The toggle is this window's and not the page's: it is pinned over the two
## buttons `SaDialog.apply_cancel` drew rather than declared by a call a filter
## writes, because choosing a way is the one-shot dialog's option alone. The
## window a double click on an attached filter's row opens, `SaFilterEditWindow`,
## builds its page from the same `apply_cancel` and shows no toggle, which is
## right because Apply there already edits the attachment.
##
## A way *layer* refuses is dimmed with `SaFilterApply.way_refusal`'s
## sentence as its tooltip, which is Bake on a locked layer and on one that
## stores no paint: Apply there wrote nothing and said nothing. A filter that
## cannot be attached, one whose `problem()` says why, gets every way but Bake
## dimmed with the first line of that answer. Picture takes a pass
## that reads the whole layer, because the root gathers the whole composite. A
## page with no Apply row draws no toggle.
##
## The Affect all check goes on the toggle's left, in one row with it, and
## is ticked before the dims are read, since Bake over the whole picture is
## refused only where no layer of it takes paint.
func _place_way_toggle(layer: SaLayer) -> void:
    way_toggle = null
    affect_all = null
    if dialog == null or filter == null or SaFilterDialogFrame.apply_row(dialog) == null:
        return
    # Ticked before the connection, so opening on it is not heard as a tick.
    affect_all = SaMake.check_box(null, "AffectAll", tr("Affect all"), SaSettings.filter_affect_all)
    affect_all.tooltip_text = tr(
        "Applies to the whole picture: Bake writes every paint layer, Attach the document, Layer a layer set to it."
    )
    var named := filter.translated_title()
    var into := tr("Writes %s into the active layer's pixels.")
    if layer != null and layer.is_group:
        into = tr("Writes %s into the pixels of every paint layer in the group.")
    var attaches := (
        tr("Attaches %s to the active layer instead of writing it in, where it stays editable until it is flattened.") % named
    )
    if SaWholeSentences.FILTER_ATTACHES.has(filter.title()):
        attaches = tr(SaWholeSentences.FILTER_ATTACHES[filter.title()])
    var tips: Array[String] = [
        into % named,
        attaches,
        _layer_tip(),
    ]
    var choices: Array = []
    for index in WAYS.size():
        var tip := tips[index] + (_selection_note() if index > 0 else "")
        choices.append({"id": WAYS[index], "label": WAY_LABELS[index], "tooltip": tip})
    var toggle := SaMake.stops(null, "WayToggle", choices)
    var problem := filter.problem().split("\n")[0].strip_edges()
    for id: StringName in WAYS:
        var why := SaFilterApply.way_refusal(layer, id, every())
        if why.is_empty() and id != WAYS[0]:
            why = problem
        if not why.is_empty():
            toggle.dim(id, why)
    # Written before the first settle and the connection, so the thumb opens on
    # the remembered way without that being heard as a pick.
    toggle.value = StringName(SaSettings.filter_way)
    toggle.picked.connect(_on_way_picked)
    # The check re-dims the Bake of the toggle beside it, for the layer both were built for.
    affect_all.toggled.connect(_on_affect_all_toggled.bind(layer, toggle))
    way_toggle = toggle
    var row := SaMake.row(null, "WayRow")
    row.add_child(affect_all)
    row.add_child(way_toggle)
    _frame.pin_over_buttons(row)
    _sync_layer_way()


## Dims Layer where an adjustment layer could not hold the filter: no registry
## of layer types to make one from, or a run that handed a pass reading the
## whole layer or a texture rather than a pass, since the adjustment layer
## reads the backdrop around each chunk and not gathered whole. Asked after
## every run, because the pass is what says which, and the thumb is settled
## again after it.
func _sync_layer_way() -> void:
    if way_toggle == null:
        return
    if filter.problem().is_empty():
        var why := ""
        if layer_types == null:
            why = tr("No module registers the adjustment layer.")
        elif _handed == null or (_handed is SaNeighbourhoodPass and (_handed as SaNeighbourhoodPass).whole()):
            why = tr("An adjustment layer runs no filter that reads the whole layer yet, and this one does.")
        way_toggle.dim(&"layer", why)
    _settle_way()


## Puts the thumb on the way a hand last picked, `SaSettings.filter_way`, when
## that way is open, and otherwise moves it off a dimmed way to the first open
## one in `WAYS`'s order, which is Attach over a layer that takes no bake. It
## greys Apply out when no way is open, a filter that cannot be attached over
## such a layer.
##
## A settle is not a pick and writes nothing: the remembered way stays as it
## was, so it is the thumb's place again as soon as the way is open, on the
## next filter or after a run that frees Layer.
func _settle_way() -> void:
    var open := WAYS.filter(_way_open)
    var wanted := StringName(SaSettings.filter_way)
    if open.has(wanted):
        way_toggle.value = wanted
    elif not open.is_empty() and not open.has(way_toggle.value):
        way_toggle.value = open[0]
    var apply := dialog.apply_button
    if open.is_empty() and apply != null and is_instance_valid(apply):
        apply.disabled = true


## Puts one line under the preview when *document*'s active layer is not
## drawn, hidden itself, inside a hidden group or clipped to a hidden base,
## because Apply then changes nothing the painter sees. Over the toggle for a
## page that declared no picture.
func _note_hidden(document: SaDocument) -> void:
    if SaLayerStack.contributes(document, document.active_layer):
        return
    _hidden_note = Label.new()
    _hidden_note.name = "HiddenNote"
    _hidden_note.text = tr("This layer is hidden, so the canvas will not show the result.")
    _hidden_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(_hidden_note, "text_muted")
    if dialog.preview_control != null:
        dialog.preview_control.add_child(_hidden_note)
    else:
        _frame.footer.add_child(_hidden_note)
        _frame.footer.move_child(_hidden_note, 0)


## Whether the toggle offers the way *named* to a hand, false for a dimmed way
## and for a page with no toggle.
func _way_open(named: StringName) -> bool:
    return way_toggle != null and not way_toggle.dimmed.has(named)


## Closes, and nothing was ever written.
func cancel_filter() -> void:
    _close(true)


## What the dialog is, for the state dump.
##
## The page half is already in the dump: `SaPage.capture_state` finds any
## container a page was realized into, and `SaDialog.describe` is what answers,
## so the widget tree, the values, the dimming, the run count and the preview
## all arrive without a line here. This is the window's own half, which is the
## filter that is open, whether its last run came back clean, and the size the
## window stands at, logical and as the window itself has it, which is what
## says a short page opened short.
func describe() -> Dictionary:
    # The covered rectangle read once, because four reads into the context from
    # one line is the reach the structure cut counts.
    var box := Rect2()
    if context != null:
        box = context.rect
    var described := {
        "open": visible,
        "keyboard": has_focus(),
        "title": title,
        "filter": filter.title() if filter != null else "",
        "runs": runs,
        "coalesced": compressor.coalesced if compressor != null else 0,
        "ran_clean": ran_clean,
        "way": way() if way_toggle != null else &"",
        "affect_all": every(),
        "attach": way() == &"attach",
        "can_bake": _way_open(&"bake"),
        "can_attach": _way_open(&"attach"),
        "can_layer": _way_open(&"layer"),
        "dimmed": way_toggle.dimmed if way_toggle != null else {},
        "hidden_note": _hidden_note.text if _hidden_note != null else "",
        "point": _handed != null,
        "kernel_params": (_handed as SaNeighbourhoodPass).params if _handed is SaNeighbourhoodPass else {},
        "on_canvas": _previewed != null,
        "rect": [box.position.x, box.position.y, box.size.x, box.size.y],
        "size": [logical_size.x, logical_size.y],
        "window": [size.x, size.y],
        "position": [position.x, position.y],
        "buttons": _frame.describe_buttons(),
    }
    var centre := SaFilterDialogTarget.centre_on_screen(self, _canvas())
    if centre.is_finite():
        described["document_centre"] = [roundi(centre.x), roundi(centre.y)]
        described["covers_document_centre"] = visible and Rect2(position, size).has_point(centre)
    return described


## Drives a filter's dialog: `{"filter": {"open": "sara-base-modules.box_blur"}}` opens a
## filter by its registry key, `{"filter": {"widget": "radius", "value": 9}}`
## moves a widget the way a hand would, `{"filter": {"canvas_preview": false}}`
## unticks the Preview box, `{"filter": {"way": "layer"}}` picks one of the
## toggle's four ways by name, `{"filter": {"attach": true}}` picks Attach and
## `false` Bake, a step older scenarios write,
## `{"filter": {"affect_all": true}}` ticks the Affect all check and `false`
## unticks it, as a hand's press would,
## `"apply"`, `"cancel"` and `"flush"` press the two buttons and the frame
## boundary, and `"describe"` prints what the dialog says it is.
##
## A row the filter declared with `ui.custom` takes its widget's own keys in
## place of `value`, `{"widget": "ramp", "stop": 3}`, because what that control
## understands is its author's business and not this window's.
##
## A step of its own because this window is an embedded subwindow and an
## injected click does not route into one, which is the same reason
## `sa_preferences_driver.gd` exists.
static func capture(tree: SceneTree, spec: Variant) -> String:
    var window := find_in(tree)
    if window == null:
        return "SaCapture: no filter dialog installed"
    var options: Dictionary = spec if spec is Dictionary else {"do": String(spec)}
    if options.has("open"):
        window.open_filter(StringName(String(options["open"])))
        return "SaCapture: filter '%s' opened, %s" % [options["open"], JSON.stringify(window.describe())]
    if window.dialog == null:
        return "SaCapture: no filter dialog open"
    if options.has("canvas_preview"):
        return window._tick_canvas_box(bool(options["canvas_preview"]))
    if options.has("way"):
        return window._pick_way(StringName(String(options["way"])))
    if options.has("attach"):
        return window._pick_way(&"attach" if bool(options["attach"]) else &"bake")
    if options.has("affect_all"):
        return window._tick_affect_all(bool(options["affect_all"]))
    if options.has("widget"):
        return window._move_widgets([options])
    # A list, because a capture runs one step a frame and the rerun is deferred
    # to the end of one: two widgets in two steps are two frames and two runs,
    # and only two widgets in the same step are the case the coalescing is for.
    if options.has("widgets"):
        return window._move_widgets(options["widgets"] as Array)
    if options.has("close") or String(options.get("do", "")) == "close":
        window.close_button.pressed.emit()
        return "SaCapture: filter window close button pressed"
    match String(options.get("do", "")):
        "apply":
            window.apply_filter()
            return "SaCapture: filter applied"
        "cancel":
            window.cancel_filter()
            return "SaCapture: filter cancelled"
        "close_requested":
            window.close_requested.emit()
            return "SaCapture: filter window close requested"
        "escape":
            var key := InputEventKey.new()
            key.keycode = KEY_ESCAPE
            key.physical_keycode = KEY_ESCAPE
            key.pressed = true
            ShortcutRouter.escape_in_a_dialog(key, window)
            return "SaCapture: filter window escaped"
        "flush":
            window.dialog.flush_rerun()
            return "SaCapture: rerun flushed, %s" % JSON.stringify(window.describe())
        "describe":
            return "SaCapture: filter dialog is %s" % JSON.stringify(window.describe())
    return "SaCapture: no filter dialog command %s" % JSON.stringify(spec)


## Ticks or unticks the dialog's Preview box the way a click would, through
## its `toggled`, and says where the canvas stands after it. A step of its own
## because the switch is a custom row, which the `widget` step does not drive.
func _tick_canvas_box(on: bool) -> String:
    var box := dialog.canvas_box
    if box == null or not is_instance_valid(box):
        return "SaCapture: the dialog declared no Preview box"
    box.button_pressed = on
    return "SaCapture: Preview box %s, %s" % ["ticked" if on else "unticked", JSON.stringify(describe())]


## Ticks or unticks Affect all the way a click would, through its `toggled`,
## and says what the dialog stands at after it, for the way step's reason.
func _tick_affect_all(on: bool) -> String:
    if affect_all == null or not is_instance_valid(affect_all):
        return "SaCapture: the dialog offers no Affect all"
    affect_all.button_pressed = on
    return "SaCapture: Affect all %s, %s" % ["ticked" if on else "unticked", JSON.stringify(describe())]


## Picks one of the toggle's ways by name the way a click would, and says what
## the dialog stands at after it. A step of its own for the Preview box's
## reason, and one more: the toggle is put in by the window and not declared by
## the filter, so no widget name a scenario's `widget` step could use reaches it.
## A dimmed way is refused as a click on it would be.
func _pick_way(named: StringName) -> String:
    if way_toggle == null:
        return "SaCapture: the dialog offers no way toggle"
    if not WAYS.has(named):
        return "SaCapture: no way '%s', the ways are %s" % [named, ", ".join(PackedStringArray(WAYS))]
    if not _way_open(named):
        return "SaCapture: the %s way is dimmed, %s" % [named, way_toggle.dimmed[named]]
    way_toggle.pick(named)
    return "SaCapture: way %s picked, %s" % [named, JSON.stringify(describe())]


## Moves every widget in *moves*, in this frame, and says what is pending.
##
## Nothing is flushed here. The rerun is [SaDialog]'s deferred call, so it fires
## when this frame's work is done whatever else moved between now and then,
## which is the whole claim: the line printed here says two widgets moved and
## one run is pending, and the dump the next step takes says one run happened.
func _move_widgets(moves: Array) -> String:
    var said: Array = []
    for move: Variant in moves:
        var one: Dictionary = move as Dictionary
        var named := String(one.get("widget", ""))
        var row := dialog.row(StringName(named))
        if row == null:
            return "SaCapture: the dialog has no widget '%s'" % named
        said.append(SaFilterDialogWindow._drive(row, one))
    return (
        "SaCapture: moved %s, runs so far %d, rerun pending %s"
        % [", ".join(PackedStringArray(said)), dialog.runs, dialog.rerun_pending]
    )


## Moves one widget and answers what to say about it.
##
## **A `CUSTOM` row is handed the step's own words** through `capture_option_edit`
## on its control, so a widget the skeleton knows nothing about is driven by the
## one method its author wrote rather than by a branch here. The key that named it
## comes back out first, so the control reads the shape its own scenario writes
## for it, `{"stop": 3}`. A custom control that answers no door is left to the
## ordinary path below.
##
## Every other kind moves through the signal its control raises, for the reason
## `SaPageRow.drive` gives: half of Godot's controls do not raise one for a
## script's assignment, and a `Range` raises its a frame later or not at all.
static func _drive(row: SaPageRow, one: Dictionary) -> String:
    var named := String(one.get("widget", ""))
    if row.kind == SaPageRow.Kind.CUSTOM:
        var custom := row.control
        if custom != null and is_instance_valid(custom) and custom.has_method("capture_option_edit"):
            var handed := one.duplicate()
            handed.erase("widget")
            return String(custom.call("capture_option_edit", handed))
    var value: Variant = one.get("value", null)
    var slider := row.control as FactorSlider
    if slider != null:
        slider.value = float(value)
        slider.value_changed.emit(slider.value)
    else:
        row.drive(value)
    return "%s -> %s" % [named, row.value]


## Hands the run's pass to the compositor while the dialog's Preview box is
## ticked, and takes it back off when it is not, marking the layer's chunks
## dirty either way. What `main_dialogs.gd` does for Sara's own adjustments,
## because a pass shows nothing on the canvas until the compositor runs it.
##
## The box is the dialog's, declared by `ui.canvas_preview()` or `ui.preview()`,
## and this only reads it. A dialog that declared none is not
## drawn on the canvas at all. A point pass and a neighbourhood pass both go
## through the compositor's point preview, and a filter that shows a texture
## has no canvas preview, so its box is greyed out and says why.
func _preview_on_canvas() -> void:
    var box := dialog.canvas_box if dialog != null else null
    if box != null and is_instance_valid(box):
        box.disabled = _handed == null
        if box.disabled:
            box.tooltip_text = tr("This filter shows its picture in the thumbnail and has no preview on the canvas.")
        else:
            box.tooltip_text = tr("Show the filter on the canvas while you drag. Not a history step.")
    else:
        box = null
    if _handed == null and _previewed == null:
        return
    var canvas := _canvas()
    if canvas == null or canvas.easel == null:
        return
    var document := canvas.document
    var before := canvas.easel.compositor.point_preview.reached(document)
    if box != null and box.button_pressed and _handed != null:
        canvas.easel.compositor.point_preview.set_pass(document, _handed, _draft.halvings(canvas.pixels_per_texel()))
        _previewed = document
    elif _previewed != null:
        canvas.easel.compositor.point_preview.clear(_previewed)
        _previewed = null
    _redraw_active_layer(canvas, document, before)


## A hand's pick on the toggle, which a scenario's `way` step is too, becomes the
## way every filter opens on. Only here and on the Exposure docker's toggle is
## `SaSettings.filter_way` written.
func _on_way_picked(id: Variant) -> void:
    SaSettings.filter_way = String(id)


## A hand's tick on Affect all, which a scenario's `affect_all` step is too,
## becomes where every filter's Apply reaches, and Bake is dimmed again for it
## and the thumb settled, Apply live again where a way opens. Only here and on
## the Exposure docker's check is `SaSettings.filter_affect_all` written.
func _on_affect_all_toggled(on: bool, layer: SaLayer, toggle: SaStopSlider) -> void:
    SaSettings.filter_affect_all = on
    toggle.dim(&"bake", SaFilterApply.way_refusal(layer, &"bake", on))
    if dialog.apply_button != null and is_instance_valid(dialog.apply_button):
        dialog.apply_button.disabled = not ran_clean
    _settle_way()


func _on_canvas_box_toggled(_on: bool) -> void:
    _fill_thumbnail()
    _preview_on_canvas()
    _thumbnail_follows_the_switch(true)


## Hides the thumbnail and its caption while the canvas shows the preview,
## because a second picture of the same run takes room for nothing. Kept wherever
## it is the only picture of the run: by a dimmed switch, under a click a
## filter picks on it, and over a layer the canvas does not draw, whose note
## is its child. A change *refit* asks for fits the window to the page again
## from the opening height, at the corner it stands at, so the thumbnail's
## height is given back and taken again.
func _thumbnail_follows_the_switch(refit: bool) -> void:
    var box := dialog.canvas_box
    var thumbnail := dialog.preview_control
    if box == null or thumbnail == null or not is_instance_valid(box) or not is_instance_valid(thumbnail):
        return
    var shown := _thumbnail_shown(not box.disabled)
    for entry: SaPageRow in dialog.rows():
        if entry.control != thumbnail or entry.line == null or entry.line.visible == shown:
            continue
        entry.line.visible = shown
        if refit and visible and not SaDockerMaximise.is_maximised(self):
            var corner := position
            logical_size.y = SaFilterDialogFrame.OPENING_SIZE.y
            logical_min_size = SaFilterDialogFrame.FLOOR
            # The floor first, for the reason `_reopen_at_opening_size` gives.
            min_size = SaUI.window_size_for(self, logical_min_size)
            apply_window_scale()
            fit_opening_size()
            position = _clamped_to_host(corner)


## Whether the thumbnail shows, with the canvas's switch *live*.
func _thumbnail_shown(live: bool) -> bool:
    var box := dialog.canvas_box
    if box == null or not is_instance_valid(box) or dialog.preview_control == null:
        return true
    return not box.button_pressed or not live or dialog.preview_control.takes_clicks or _hidden_note != null


## Takes a handed point pass back off the canvas, on Cancel, on Apply and on
## any close.
func _clear_canvas_preview() -> void:
    if _previewed == null:
        return
    var canvas := _canvas()
    if canvas != null and canvas.easel != null:
        var before := canvas.easel.compositor.point_preview.reached(_previewed)
        canvas.easel.compositor.point_preview.clear(_previewed)
        _redraw_active_layer(canvas, _previewed, before)
    _previewed = null


## The preview changes what the active layer's chunks show and nothing in
## them, so they are marked dirty by hand and composited on the next frame.
## With them goes every position the pass shown *before* reached and the one
## shown now reaches, `SaPointPreview.reached`, so a wrap's paint is drawn
## where it lands on ground the layer holds no chunk at and taken off it again
## when the offset moves, on Cancel and on Apply.
func _redraw_active_layer(canvas: SaCanvas, document: SaDocument, before: Dictionary[Vector2i, bool]) -> void:
    if document != null and document.active_layer != null:
        var reached := canvas.easel.compositor.point_preview.reached(document).merged(before).keys()
        # Shown and not painted, so a gather kept of the layer copies nothing.
        document.invalidate_chunks(reached, null, false)
    canvas.request_composite()


func _close(hide_window: bool) -> void:
    _let_go()
    _draft.stop()
    _clear_canvas_preview()
    _handed = null
    if dialog != null:
        dialog.rerun.disconnect(_ask_to_run)
        dialog.applied.disconnect(apply_filter)
        dialog.cancelled.disconnect(cancel_filter)
    dialog = null
    filter = null
    context = null
    # A run the compressor was holding for a dialog that has closed would draw
    # nothing, but it holds the window open with a pending Timer, so it goes.
    compressor.reset()
    way_toggle = null
    affect_all = null
    _hidden_note = null
    _key = &""
    runs = 0
    ran_clean = false
    default_button = null
    if hide_window:
        hide()


## Opens again on the layer the painter picked with the dialog open, where it
## stands and with the settings and canvas switch it had, so the canvas
## preview, the thumbnail and Apply are all of one layer.
func _follow() -> void:
    var corner := position
    _open(_key, filter.parameters(), dialog.canvas_box != null and dialog.canvas_box.button_pressed)
    position = _clamped_to_host(corner)


func _let_go() -> void:
    if _target != null:
        _target.release()
    _target = null


func _canvas() -> SaCanvas:
    return SaFilterDialogTarget.canvas_for(target_canvas, self)
