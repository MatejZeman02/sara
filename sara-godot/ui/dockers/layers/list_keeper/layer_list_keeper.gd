## Fills an `SaLayerList` from a canvas's document and answers what the list
## says: a press makes its layer active, a drop moves it, a fold mark shuts or
## opens its group, and a filter's row puts that filter's panel in Tool Options.
##
## The list draws rows and reports presses, drops and folds, and knows nothing
## of what they mean. This class is what does. It hears the document for every
## add, delete, activate, undo and reorder and builds the rows again from it,
## so a second list handed a keeper on the same canvas shows the same layers and
## the same active row as the Layers docker's, and a press or a drop in either
## acts on the one document. It was cut out of `LayersDocker`, which did all of
## it for its own list and was the only thing that could.
##
## The pick and the folds are shared by every list on one document. A list
## placed in another docker is a second view of the same stack, in step with
## the Layers docker's own, so a press, a Ctrl or Shift press, a filter's row
## and a fold mark in either show in both. The pick is not the document's and
## nothing of it is saved or undone. A fold is kept on the group itself, as
## `SaLayer.folded`, so it is saved with the document and opened again,
## and still no undo step. Each keeper holds its own copy of both, which the
## keeper the painter acted through hands on to the others.
class_name SaLayerListKeeper
extends RefCounted

## The rows were built again or redrawn from the document, or a press made a
## layer active, so whatever stands beside the list and reads the active layer
## or the list's pick follows it now. The Layers docker's actions and ground
## rows hear it.
signal followed

## The canvas whose document the rows show. Null shows nothing. The list is
## handed the same canvas, for the thumbnails it redraws on a stroke.
var target_canvas: SaCanvas = null:
    set(val):
        _listen_to(null)
        target_canvas = val
        _list.target_canvas = val
        _listen_to(val.document if val != null else null)
        # A list joining a document others show takes their folds.
        var peers := _peers()
        if not peers.is_empty():
            _closed_groups.clear()
            _closed_groups.merge(peers[0]._closed_groups)
        if _listening:
            sync()

## Every keeper alive, by its instance id, so the one a list was pressed through
## finds the others on its document. An id holds nothing, so a keeper is let go
## when what built it is, and the list holds no object the run could find left
## over at exit, which a `WeakRef` in it would be.
static var _live: Array[int] = []

## Where a filter row's title comes from and where its panel is shown. Both are
## found on first use in the running app, the registry on Main and the docker in
## the tree, and a suite sets them instead.
var filter_registry: SaFilterRegistry = null
var tool_options: ToolOptionsDocker = null

var _list: SaLayerList

## The document the keeper is connected to, kept apart from the canvas so the
## connections are taken off the one they were made on.
var _heard: SaDocument = null

## Whether the list's presses are answered yet, which `listen` turns on.
var _listening: bool = false

## Up while the rows are being built, when the list's own signals describe the
## rebuild rather than anything the painter did.
var _ignore_signals: bool = false

## Up from a layer added or gone until the rows are drawn again, which
## `_mark_stale` puts off to the end of the frame.
var _stale: bool = false

## The frame a layer's own property changed in, whose rows were drawn then, or
## -1. The `document_changed` that change brings is then answered with no other
## row drawn.
var _one_row_frame: int = -1

## Up while the list takes the pick another list was given, so the filter that
## comes with it is not shown again and the pick is not handed back.
var _following: bool = false

## The groups whose rows are folded shut, as a set keyed by the layer itself,
## mirroring each group's `folded`, which is what the file keeps. Every sync
## reads the set again from the groups, so a document opened from a file shows
## its folds, and every change here is written to the group in the same breath.
## The document's own order is untouched whichever way a mark points. Keyed
## by the layer rather than by its name so a rename cannot open a group behind
## the painter's back, and pruned on every sync because a deleted group would
## otherwise hold its key for the life of the session. Emptied and filled in
## place and never assigned, because the Layers docker keeps a reference to it,
## and the same in every keeper on the document.
var _closed_groups: Dictionary = {}

## The layer that was active when the picked filter's panel went up. A press on
## a filter's row leaves the layer set alone, so this is whichever layer the
## painter was on, and the panel is theirs only while that layer stays active.
var _panel_layer: SaLayer = null

## Which rows of a deep stack this frame builds, the rest owed to the frames
## after, as [SaLayerListBuild] says.
var _build := SaLayerListBuild.new()

## The list a build over frames took its pick from, a peer's when this list had
## no rows yet, read again by every part until the build ends.
var _build_source: SaLayerList = null


## The keeper's connections to the document go when the keeper does, because
## an object that is freed takes every connection made to it along, so it needs
## no teardown of its own.
func _init(list: SaLayerList, canvas: SaCanvas = null) -> void:
    _list = list
    _live.append(get_instance_id())
    if canvas != null:
        target_canvas = canvas


## Starts answering the list: from here on a press, a drop, a fold and a
## filter's pick act on the document, and a new canvas builds the rows at once.
## Not done in `_init`, because a suite drives a Layers docker that never
## reaches the tree and connects by hand the one signal it wants, and the
## docker calls this from its `_ready`.
## Safe to call again.
func listen() -> void:
    _listening = true
    for pair: Array in [
        [_list.item_selected, select_row],
        [_list.item_dropped, drop],
        [_list.group_toggled, toggle_group],
        [_list.filter_selected, show_filter],
    ]:
        var heard: Signal = pair[0]
        if not heard.is_connected(pair[1]):
            heard.connect(pair[1])
    if target_canvas != null:
        sync()


## Makes the list this keeper fills and *strip*, the actions beside it, two
## elements of *category* another docker can hold, each placed copy a list or a
## strip of its own that follows this keeper, and returns *strip*. See
## [SaLayerListViews] for why a placed strip reads the docker's own list.
func with_views(category: String, strip: SaLayerActions) -> SaLayerActions:
    return SaLayerListViews.register(category, self, strip)


## The document's active layer, or null without a document.
func active_layer() -> SaLayer:
    var doc := _document()
    return doc.active_layer if doc != null else null


## Takes the keeper's connections off the document it heard and puts them on
## *doc*, or on nothing for null. A reorder and an undo change no child and no
## active layer, and `follow_document` says what each asks of the rows.
func _listen_to(doc: SaDocument) -> void:
    if _heard != null and is_instance_valid(_heard):
        for pair: Array in _heard_signals(_heard):
            var was: Signal = pair[0]
            var hears: Callable = pair[1]
            if was.is_connected(hears):
                was.disconnect(hears)
    _heard = doc
    if doc == null:
        return
    for pair: Array in _heard_signals(doc):
        (pair[0] as Signal).connect(pair[1] as Callable)


## What this keeper hears on *doc*, each signal beside what hears it. One list
## for both halves of `_listen_to`, so a signal added to the one it is
## connected on is taken off the old document too.
func _heard_signals(doc: SaDocument) -> Array:
    return [
        [doc.document_changed, follow_document],
        [doc.child_entered_tree, _on_structure_changed],
        [doc.child_exiting_tree, _on_structure_changed],
        [doc.active_layer_changed, _on_active_layer_changed],
        [doc.layer_changed, _on_layer_changed],
    ]


## The document the rows show, read off the canvas each time the way the
## docker read it.
func _document() -> SaDocument:
    return target_canvas.document if target_canvas != null else null


## The other keepers on this keeper's document, the dead ones let go of on the
## way.
func _peers() -> Array[SaLayerListKeeper]:
    var doc := _document()
    var found: Array[SaLayerListKeeper] = []
    var alive: Array[int] = []
    for id: int in _live:
        var keeper := instance_from_id(id) as SaLayerListKeeper
        if keeper == null:
            continue
        alive.append(id)
        var canvas := keeper.target_canvas
        if keeper != self and doc != null and is_instance_valid(canvas) and canvas.document == doc:
            found.append(keeper)
    _live = alive
    return found


## Hands the pick of this list to every other list on the document, after the
## painter changed it here.
func _share_pick() -> void:
    if _following or _ignore_signals:
        return
    var layers := _list.selected_layers()
    for peer: SaLayerListKeeper in _peers():
        peer.follow_pick(layers, _list.picked.selected_record)


## Picks *layers* and the filter *record*, or none for null, the pick another
## list on the document was just given. The filter's panel is up already, put
## there by the list that was pressed.
func follow_pick(layers: Array[SaLayer], record: SaAttachedFilter) -> void:
    var doc := _document()
    if doc == null:
        return
    _following = true
    _list.select_layers(layers, doc.active_layer)
    _list.picked.pick_filter(record)
    _following = false
    followed.emit()


## Shuts the groups in *closed* and opens every other, the folds another list
## on the document was just given, and draws the rows again, keeping the ones
## that stand.
func follow_folds(closed: Dictionary) -> void:
    for key: Variant in _closed_groups.keys():
        if not closed.has(key):
            _set_folded(key, false)
    for key: Variant in closed.keys():
        _set_folded(key, true)
    sync()


## A layer added or gone draws the rows again at the frame's end, except once
## the quit is handed to the engine. Then every layer leaves the tree one by
## one, and a rebuild for each held the main thread five seconds on a document
## of thirty layers, over rows nobody will see.
func _on_structure_changed(_node: Node) -> void:
    if SaTrail._quitting:
        return
    _mark_stale()


## A layer made active from outside the list, by PageDown or an undo, opens the
## groups shut over it, so the active layer always has a lit row.
##
## It also takes the pick back from a filter whose panel was raised under
## another layer. The list rebuild lets go of a record that is gone and of
## nothing else, so without this the + button, PageDown and an undo would leave
## the old filter's sliders in Tool Options over a layer they do not belong to,
## and a click on one would change the canvas with no step on the undo list.
func _on_active_layer_changed(layer: SaLayer) -> void:
    _prune_closed_groups()
    var unfolded := false
    for group: SaLayer in _closed_groups.keys():
        if is_instance_valid(layer) and layer != group and SaLayerStack.is_inside(layer, group):
            _set_folded(group, false)
            unfolded = true
    # Rows already owed are drawn once at the end of the frame, for the stack
    # as it stands then. An open activates its layer before the caches that
    # say which rows it draws are rebuilt, and drawing them here built a
    # hundred rows of a deep file only to throw them away.
    if not _stale:
        var traced := SaFrameTrace.now()
        if unfolded or not _has_row(layer):
            sync()
        else:
            _follow_pick()
        SaFrameTrace.spent("sync", traced)
        SaFrameTrace.spent("layers docker follow", traced)
    # Every keeper on the document lets go of its own, so this is not handed on.
    if _list.picked.selected_record != null and layer != _panel_layer:
        _ignore_signals = true
        _list.picked.pick_filter(null)
        _ignore_signals = false


## Whether *layer* has a row of its own in the list.
func _has_row(layer: SaLayer) -> bool:
    if not is_instance_valid(layer):
        return false
    for row in _list.rows:
        if row.record == null and row.layer == layer:
            return true
    return false


## A layer made active that already has a row, with no group opened for it:
## the rows stand as they are, and the pick, the active row and the filter's
## pick are put back as a whole sync puts them, with the rows the pick moved
## restyled and the rows in view drawn again. A sync here built nothing and
## still went over every row of the stack four times, 31 ms of a large test
## document's 593 rows.
func _follow_pick() -> void:
    var doc := _document()
    if doc == null:
        return
    _ignore_signals = true
    _finish_pick(doc, _list, _kept(doc, _list))


## One layer's own property changed, its eye, opacity, mode, locks or name:
## its row is drawn again, with the rows inside it, which a group's eye dims, and
## no other. Drawing every row cost 13 ms a step on 540 layers. Every way such
## a change goes ends in a `document_changed`, at once or at the end of the
## frame's flush, and the first one heard in this frame draws no other row. One
## that something else brought before the flush's is followed by the flush's,
## which draws them all, so no row is left stale.
func _on_layer_changed(layer: SaLayer) -> void:
    var doc := _document()
    if _ignore_signals or doc == null or not is_instance_valid(layer):
        return
    var traced := SaFrameTrace.now()
    for index in _list.rows.size():
        var shown := _list.layer_at(index)
        if shown != null and SaLayerStack.is_inside(shown, layer):
            _list.rows[index].refresh(doc)
    _one_row_frame = Engine.get_process_frames()
    SaFrameTrace.spent("layer row", traced)


## What a `document_changed` asks of the rows. A reorder announces itself here
## and nowhere else. `SaLayerOps._place` moves the child and emits this, and the
## three signals that do rebuild the list are add, remove and activate, none of
## which a `move_child` is. Without this the panel would miss every reorder
## the list did not do itself: an undo, a redo, a command, a module. The
## actions under the list rely on this too, rather than rebuilding the rows
## themselves.
func follow_document() -> void:
    if _ignore_signals:
        return
    var traced := SaFrameTrace.now()
    # A stroke's commit moves the pixels of the layer it painted and nothing of
    # the stack, so its row is drawn again and no other, where asking whether
    # the rows match and drawing them all cost 33 ms a stroke on 300 layers.
    var stroked := _list.marks.stroked()
    if stroked != null:
        for index in _list.rows.size():
            if _list.layer_at(index) == stroked:
                _list.rows[index].refresh(_document())
        followed.emit()
        SaFrameTrace.spent("layers docker follow", traced)
        return
    var doc := _document()
    var drawn := _drawn_rows(doc) if doc != null else []
    var matched := doc == null or _rows_match(drawn)
    SaFrameTrace.spent("rows match", traced)
    if not matched:
        var synced := SaFrameTrace.now()
        _sync(drawn)
        SaFrameTrace.spent("sync", synced)
        SaFrameTrace.spent("layers docker follow", traced)
        return
    if _one_row_frame == Engine.get_process_frames():
        _one_row_frame = -1
        followed.emit()
        SaFrameTrace.spent("layers docker follow", traced)
        return
    var refreshed := SaFrameTrace.now()
    _list.refresh_all()
    SaFrameTrace.spent("refresh all", refreshed)
    followed.emit()
    SaFrameTrace.spent("layers docker follow", traced)


## Whether the rows are the document's layers, in the document's own order.
##
## Compared by layer rather than by name, against the layers a rebuild would
## draw, so a folded group is not read as a change. A rebuild costs the
## selection its scroll position, and this signal fires on every stroke commit,
## so the question has to be asked before the answer is acted on.
##
## The whole question rather than the layers the rows already hold, which
## would see a reorder and nothing else: a delete of a layer that is not the
## active one moves no active mark and exits the tree before it leaves the
## document's children, so only this catches it, and the actions need not
## rebuild the rows by hand after each operation.
func rows_match_document() -> bool:
    var doc := _document()
    return doc == null or _rows_match(_drawn_rows(doc))


## Whether the rows are the ones *drawn* names, by layer and record, in order.
func _rows_match(drawn: Array) -> bool:
    if drawn.size() != _list.row_count():
        return false
    # A row is a layer or an attached filter's record, so an attach, a detach or
    # a reorder of a filter is a change the rows have to follow, and each
    # row is asked for whichever it holds.
    var rows := _list.rows
    for i in drawn.size():
        var row := rows[i]
        var shown: Object = null
        if row.record != null:
            shown = row.record
        elif row.has_layer():
            shown = row.layer
        if shown != drawn[i][0]:
            return false
    return true


## The records drawn under *layer*'s row, the one that runs last nearest it, and
## none for a group that is folded shut, the way its members are skipped. An
## adjustment layer's first record is its row and is not drawn again.
func _listed_filters(layer: SaLayer) -> Array[SaAttachedFilter]:
    if layer.is_group and _closed_groups.has(layer):
        return []
    return SaLayerList.listed_filters(layer.filters, layer)


## What a filter's row is called: the filter's own title, or the key when no
## installed module answers to it, which a document of somebody else's may hold,
## numbered from the second of its kind in *among*, the records it stands with.
func _filter_title(record: SaAttachedFilter, among: Array[SaAttachedFilter]) -> String:
    var found := _filter_of(record.key)
    return SaAttachedFilter.numbered(found.title() if found != null else String(record.key), among, record)


## The filter registered under *key*, or null. The registry is Main's, found
## the first time a row needs it.
func _filter_of(key: StringName) -> SaFilter:
    if filter_registry == null and _list.is_inside_tree() and _list.get_tree().current_scene != null:
        var registries := _list.get_tree().current_scene.get("registries") as SaRegistries
        filter_registry = registries.filters if registries != null else null
    return filter_registry.get_filter(key) if filter_registry != null else null


## A filter row was picked, or null when a layer's row took the pick back. The
## record's widgets go to the tool options docker rather than to a dialog, so
## the painter keeps painting under them.
func show_filter(record: SaAttachedFilter) -> void:
    _panel_layer = active_layer() if record != null else null
    if _following:
        return
    _share_pick()
    FiltersDocker.follow_pick(_list, record)
    if tool_options == null and _list.is_inside_tree():
        tool_options = _list.get_tree().root.find_child(SaDockerIds.TOOL_OPTIONS, true, false) as ToolOptionsDocker
    if tool_options == null or not is_instance_valid(tool_options):
        return
    var doc := _document()
    if record == null or doc == null:
        tool_options.clear_filter_panel()
        return
    tool_options.show_filter_panel(SaFilterPanel.new(record, _filter_of(record.key), doc))


## Whether *record* still hangs somewhere in *doc* with a row of its own. An
## undo can take a picked record away, and its panel must not outlive it, and
## nor must it outlive the removal of the record before it on an adjustment
## layer, which makes it that layer's own and leaves it no row.
func _still_attached(doc: SaDocument, record: SaAttachedFilter) -> bool:
    if doc.root_filters.has(record):
        return true
    for layer: SaLayer in _layers_of(doc):
        if layer.filters.has(record):
            return SaBackdropLayer.own_filter(layer) != record
    return false


func _layers_of(doc: SaDocument) -> Array[SaLayer]:
    var result: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer and not child.is_queued_for_deletion():
            result.append(child)
    return result


## Draws the rows again from the document, keeping the picked set, the folds
## and a picked filter that still hangs in it.
##
## A list that has rows keeps every one that still stands, as [SaLayerRowReuse]
## says, so an add, a delete, a drop, a reorder, a fold and an activation build
## only the rows new to the list. Building a row is about three milliseconds,
## and building every row again cost a tenth of a second on a stack of thirty.
## A list with no rows yet, or with a name being typed into a row, is
## built whole.
func sync() -> void:
    _sync([])


## [method sync] with the rows *drawn* already read for the stack as it stands,
## or read here when empty.
func _sync(drawn: Array) -> void:
    # An open over frames lands in one long frame and the easel draws it in
    # the next, so rows built in either made it longer by the half second the
    # rows of a deep file take. They are built in the frame after. Before the
    # landing the rows go, since their layers did when the open let go of them.
    var doc := _document()
    if SaSadFile.opening() and doc != null and doc.get_children().any(func(child: Node) -> bool: return child is SaLayer):
        _owe_after_open()
        return
    var synced := Time.get_ticks_usec()
    _stale = false
    if doc == null:
        return
    var layers := _layers_of(doc)

    # The set survives the rebuild, by layer rather than by index: a group or a
    # delete renumbers every row under it. It is read from the groups first, so
    # a document opened shut where it was saved shut shows it so.
    # Drawn rows read before a fold changed here are read again.
    if _read_folds(layers):
        drawn = []
    _prune_closed_groups()
    _name_layers(doc, layers)

    # A list with no rows yet takes the pick of one already showing the stack.
    var source := _list
    if _list.row_count() == 0:
        var peers := _peers()
        if not peers.is_empty():
            source = peers[0]._list
    if _build.owing and is_instance_valid(_build_source):
        source = _build_source
    var kept := _kept(doc, source)

    _ignore_signals = true
    if drawn.is_empty():
        drawn = _drawn_rows(doc)
    var wanted := _build.part(_list, drawn)
    var began := Time.get_ticks_usec()
    var fresh := []
    var worn := []
    if _build.rebuild(_list, wanted, fresh, worn):
        var rows_usec := Time.get_ticks_usec() - began
        _finish_rows(doc, source, kept, fresh)
        SaLayerRowReuse.restyle(worn, synced)
        _build.took(rows_usec, Time.get_ticks_usec() - synced)
        _owe_part(source)
        return
    _build.stop()
    _list.clear()
    for entry: Array in drawn:
        if entry.size() == 2:
            var layer: SaLayer = entry[0]
            _list.add_item(str(layer.name), int(entry[1]), layer.is_group, layer)
        else:
            _list.add_filter_item(entry[0], entry[1], String(entry[2]), int(entry[3]))
    _finish_rows(doc, source, kept, _list.rows)


## Gives each of *layers* that carries a fresh layer's name one of its own, the
## bottom one "Background" and every other the next "Layer N" by
## `SaLayerNames`, the rule `SaLayerOps.add` names a new layer by, so the two
## cannot number the same layer apart. The bottom up, so the lower of two
## unnamed layers takes the lower number. Run for every layer, folded or not,
## because it is what keeps "Layer 3" unique across the document, and a name
## that depended on which groups happened to be shut would be a new bug.
static func _name_layers(doc: SaDocument, layers: Array[SaLayer]) -> void:
    var any := false
    for layer in layers:
        if _wants_a_name(layer):
            any = true
            break
    if not any:
        return
    var taken := SaLayerNames.taken_in(doc)
    for i in layers.size():
        var layer := layers[i]
        if not _wants_a_name(layer):
            continue
        if i == 0:
            layer.name = "Background"
            continue
        var new_name := SaLayerNames.next_in(taken)
        taken[new_name] = true
        layer.name = new_name


## A layer added or gone marks the rows stale, and they are drawn again once,
## at the end of the frame, however many layers came and went in it. A
## document's load adds the file's layers one by one, and a rebuild for each
## built the rows of the welcome picture's 68 layers 68 times over, while the
## rows each rebuild let go of waited for a frame end the load never reached.
## Whatever asks sooner, the activation and the `document_changed` that end
## every operation and the load itself, draws the rows at once and clears the
## mark.
func _mark_stale() -> void:
    if _stale:
        return
    _stale = true
    _flush_stale.call_deferred()


func _owe_after_open() -> void:
    _stale = true
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null and not tree.process_frame.is_connected(_flush_stale):
        tree.process_frame.connect(_flush_stale, CONNECT_ONE_SHOT)


func _flush_stale() -> void:
    if _stale:
        # Traced as the docker's following of the document, which it is, and
        # its first part after an open was an unnamed 70 ms.
        var traced := SaFrameTrace.now()
        sync()
        SaFrameTrace.spent("layers docker follow", traced)


## Owes the rows a part left out to the next frame, whose sync builds the next
## part of the stack as it then stands, or ends the build.
func _owe_part(source: SaLayerList) -> void:
    _build_source = source if _build.owing else null
    var tree := _list.get_tree() if _list.is_inside_tree() else null
    if _build.owing and tree != null and not tree.process_frame.is_connected(next_part):
        tree.process_frame.connect(next_part, CONNECT_ONE_SHOT)


## The next frame's part of a build over frames, which the frame calls and a
## suite that cannot wait for one calls in its place. Traced as the docker's
## following of the document is, because it is that following spread over
## frames. Nothing while no rows are owed.
func next_part() -> void:
    if not _build.owing:
        return
    _build.new_frame()
    var traced := SaFrameTrace.now()
    sync()
    SaFrameTrace.spent("sync", traced)
    SaFrameTrace.spent("layers docker follow", traced)


## The layers picked in *source* that the rows will still draw, which is the set
## a redraw puts back. A set without the active layer gives way to the
## document's pick, which a paste of several layers leaves on what it put down.
func _kept(doc: SaDocument, source: SaLayerList) -> Array[SaLayer]:
    var kept: Array[SaLayer] = []
    var shown := source.selected_layers()
    for layer: SaLayer in shown if shown.has(doc.active_layer) else doc.picked.acted_on(doc):
        if is_instance_valid(layer) and layer.get_parent() == doc and not _folded_away(layer):
            kept.append(layer)
    return kept


## Whether *layer* carries a name `sync` replaces: a fresh layer's `@` name, or
## the bare "Layer" an older file gave it.
static func _wants_a_name(layer: SaLayer) -> bool:
    var named := String(layer.name)
    return named.begins_with("@") or named == "Layer-1" or named == "Layer"


## What a rebuild draws, top of the list first, one entry a row in the shape
## [method SaLayerRowReuse.rebuild] reads.
func _drawn_rows(doc: SaDocument) -> Array:
    var out: Array = []
    for record: SaAttachedFilter in SaLayerList.listed_filters(doc.root_filters):
        out.append([record, null, _filter_title(record, doc.root_filters), -1])
    var layers := _layers_of(doc)
    # A group stands above its members in the document's order, so walking
    # from the top reads each layer's group before the layer, and its depth and
    # its fold are the group's own and one more, rather than a walk up the
    # groups for every layer.
    var depths: Dictionary[SaLayer, int] = {}
    var away: Dictionary[SaLayer, bool] = {}
    for i in range(layers.size() - 1, -1, -1):
        var layer := layers[i]
        var group := SaLayerStack.parent_of(layer)
        var depth := 0
        var hidden := false
        if group != null:
            depth = depths[group] + 1 if depths.has(group) else SaLayerStack.depth(layer)
            hidden = (away[group] if away.has(group) else _folded_away(group)) or _closed_groups.has(group)
        depths[layer] = depth
        away[layer] = hidden
        if hidden:
            continue
        out.append([layer, depth])
        if layer.filters.is_empty():
            continue
        for record: SaAttachedFilter in _listed_filters(layer):
            out.append([record, layer, _filter_title(record, layer.filters), depth])
    return out


## What every way of drawing the rows ends with: the fold marks, the lock
## signals of each layer *fresh* to the list, the picked set *kept* and the
## filter *source*'s pick put back, and the rows redrawn from their layers.
func _finish_rows(doc: SaDocument, source: SaLayerList, kept: Array[SaLayer], fresh: Array) -> void:
    for row in _list.rows:
        if row.is_group and row.record == null and row.has_layer():
            row.set_collapsed(_closed_groups.has(row.layer))
    # Bound to the layer, so the lock that changed draws its own row and not
    # the list's. A bound callable is equal to another bound to the same layer,
    # which is what keeps the connection from being made twice. A row kept from
    # the last sync has its layer's connected already.
    for row: Variant in fresh:
        if row.record != null or not row.has_layer():
            continue
        var locked := _on_layer_lock_signal.bind(row.layer)
        if not row.layer.lock_changed.is_connected(locked):
            row.layer.lock_changed.connect(locked)
        if not row.layer.alpha_lock_changed.is_connected(locked):
            row.layer.alpha_lock_changed.connect(locked)
    _finish_pick(doc, source, kept)


## Puts the picked set *kept* and the filter *source*'s pick back on the rows
## as they stand, says the list followed, and draws the rows again.
func _finish_pick(doc: SaDocument, source: SaLayerList, kept: Array[SaLayer]) -> void:
    # An active layer with no row lights none, which the list answers itself.
    _list.select_layers(kept, doc.active_layer)
    var record := source.picked.selected_record
    if record != null and not _still_attached(doc, record):
        record = null
    # A filter another list picked has its panel up already, and one this list
    # lets go of takes its panel down.
    _following = source != _list
    _list.picked.pick_filter(record)
    _following = false

    followed.emit()
    _list.refresh_all()
    _ignore_signals = false


## A group's fold mark was pressed. Nothing about the document moves: the set of
## shut groups changes and the rows are drawn again from the same stack in the
## same order, which is why expanding brings the children back exactly as they
## were rather than restoring a remembered arrangement. Only the rows the fold
## brings back are built, which is what took a fold from a fifth of a second to
## a few milliseconds.
func toggle_group(index: int) -> void:
    var layer: SaLayer = _list.layer_at(index)
    if layer == null or not layer.is_group:
        return
    if _closed_groups.has(layer):
        _set_folded(layer, false)
    else:
        _set_folded(layer, true)
        _lift_active_out_of(layer)
    sync()
    for peer: SaLayerListKeeper in _peers():
        peer.follow_folds(_closed_groups)


## Shutting a group whose child is the active layer moves the mark onto the
## group itself.
##
## Without it the list has no active row while the document still points inside
## the folded group: nothing on screen is lit, `active_index()` is -1, and a
## shift click has no anchor to range from, while a stroke still lands on a
## layer the painter cannot see a row for. The anchor closed the gap between
## "the row that is active" and "the layer that is active", and a filter that
## hides rows is exactly what reopens it.
##
## The group is the right answer rather than the nearest visible row, because it
## is the row now standing in for what was folded away. The document's order is
## untouched: which layer is active is not where a layer sits.
func _lift_active_out_of(group: SaLayer) -> void:
    var doc := _document()
    if doc == null or doc.active_layer == null:
        return
    if SaLayerStack.is_inside(doc.active_layer, group) and doc.active_layer != group:
        doc.set_active_layer(group)


## Whether a group above *layer* is shut, at any depth. A group's own row is
## always drawn, whatever it holds, or a collapse would hide the mark that
## reopens it.
func _folded_away(layer: SaLayer) -> bool:
    var group := SaLayerStack.parent_of(layer)
    var guard := 0
    while group != null and guard < 64:
        if _closed_groups.has(group):
            return true
        group = SaLayerStack.parent_of(group)
        guard += 1
    return false


## Shuts or opens *key*'s row, on the group and in the set together. The key is
## untyped for the reason `_prune_closed_groups` gives, and a freed one is
## dropped from the set.
func _set_folded(key: Variant, shut: bool) -> void:
    var layer: SaLayer = key as SaLayer if is_instance_valid(key) else null
    if layer == null:
        _closed_groups.erase(key)
        return
    layer.folded = shut
    if shut:
        _closed_groups[layer] = true
    else:
        _closed_groups.erase(layer)


## Takes the set from the groups among *layers*: a group saved folded, or
## folded through another keeper, is shut here, and one opened anywhere is
## open. Answers whether the set changed.
func _read_folds(layers: Array[SaLayer]) -> bool:
    var changed := false
    for layer in layers:
        if layer.is_group and layer.folded:
            if not _closed_groups.has(layer):
                _closed_groups[layer] = true
                changed = true
        elif _closed_groups.has(layer):
            _closed_groups.erase(layer)
            changed = true
    return changed


## Forgets every folded group that has left the document, whichever way it
## left: deleted, flattened, merged, or freed with a document replaced under it.
## A group the history still holds is out of the tree and forgotten as well, so
## an undo brings it back open.
##
## The loop variable is untyped on purpose. A key whose layer was freed cannot be
## assigned to a variable typed `SaLayer`, and a New Document frees every layer
## at once, so a typed loop would raise a script error on every change after it
## and stop `_on_active_layer_changed` before its `sync()`, leaving the docker
## lighting a layer that is not the active one.
func _prune_closed_groups() -> void:
    var doc := _document()
    for key: Variant in _closed_groups.keys():
        var layer: SaLayer = key as SaLayer if is_instance_valid(key) else null
        if layer == null or not layer.is_group or doc == null or not doc.is_ancestor_of(layer):
            _closed_groups.erase(key)
            # One the history holds opens, so an undo brings it back open. One
            # of another document still in the tree keeps its own fold.
            if layer != null and not layer.is_inside_tree():
                layer.folded = false


## A row draws its layer's two locks, so a lock written anywhere draws that
## row, the rows inside it when it is a group, and no other. A lock set
## straight on the layer brings no `layer_changed` with it, which is why the
## layer's own signals are heard as well as the document's, and
## `SaLayerFlagStep` writes a whole picked set that way in one step.
func _on_layer_lock_signal(_val: bool, layer: SaLayer) -> void:
    _on_layer_changed(layer)
    followed.emit()


## Makes the layer on row *index* the active one, which is what a press on the
## row, its note mark and a right press over it all do. A press opens nothing,
## an adjustment layer's included: its settings open on a double click on its
## picture, which the list answers as it does a ground's.
func select_row(index: int) -> void:
    var doc := _document()
    if _ignore_signals or doc == null:
        return
    var layer: SaLayer = _list.layer_at(index)
    if layer:
        doc.set_active_layer(layer)
        followed.emit()
        _share_pick()


## A row dragged onto another. Rows run top of the stack first, so a drop
## further down the list is a move down the stack. The layer joins the group of
## the row it lands on, and landing on a group's own row from above puts it
## inside as the group's bottom member. A group takes its subtree with it. The
## list says where and what kind, rather than a drop inside a group being
## inferred from the direction of travel, which would put a layer dragged *up*
## onto a group beside the group instead of in it.
func drop(from_idx: int, to_idx: int, edge: SaLayerList.Drop) -> void:
    var doc := _document()
    if doc == null:
        return
    var layer: SaLayer = _list.layer_at(from_idx)
    var target: SaLayer = _list.layer_at(to_idx)
    if layer == null or target == null:
        return
    var into_group := edge == SaLayerList.Drop.INTO
    var group: SaLayer = target if into_group else SaLayerStack.parent_of(target)
    var picked := _list.selected_layers()
    if picked.size() > 1 and picked.has(layer):
        _drop_set(doc, picked, target, edge, group)
    else:
        SaLayerOps.new(doc).place(layer, group, drop_index(layer, target, edge))
    sync()


## A picked row dragged onto *target* takes every picked row with it, in their
## order, as one Move Layers step. Each root of
## the set is placed against *target* the way a single row is, one after the
## other: above and into a group the top one goes first and each after it lands
## under the last, below a block the bottom one goes first and each after it
## lands over the last. A drop onto a row of the set, or inside a picked group,
## moves nothing, because the set cannot land among itself.
static func _drop_set(doc: SaDocument, picked: Array[SaLayer], target: SaLayer, edge: SaLayerList.Drop, group: SaLayer) -> void:
    var roots := SaLayerStack.roots(doc, picked)
    for root in roots:
        if root == target or SaLayerStack.is_inside(target, root):
            return
    var top_first := edge != SaLayerList.Drop.BELOW
    roots.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return (a.get_index() > b.get_index()) == top_first)
    var ops := SaLayerOps.new(doc)
    var each := func() -> void:
        for root in roots:
            ops.place(root, group, drop_index(root, target, edge))
    if doc.history == null:
        each.call()
    else:
        doc.history.as_one("Move Layers", each)


## Where `place` has to be told to put the layer, given where the drop landed.
##
## `move_child` counts the index the node ends at, so the answer depends on
## which side of the target the layer is coming from: a layer already below the
## target takes the target's own index to end above it, and one coming from
## above needs one more. The list is drawn top of the stack first and the
## document holds it the other way up, which is why *above* here is a higher
## index than the target's.
##
## A group is a block rather than a row, and both drops that land under the
## target land under the whole block, which is why only *above* reads the
## target's own index.
static func drop_index(layer: SaLayer, target: SaLayer, edge: SaLayerList.Drop) -> int:
    var at := target.get_index()
    if edge == SaLayerList.Drop.ABOVE:
        # A group's own node is the top of its block, so the row's index is
        # already the far side of everything it holds.
        return at if layer.get_index() < at else at + 1
    # A group's contents sit below its own node, so the bottom of what it holds
    # is as far down as its block reaches. INTO wants the layer as the group's
    # lowest member and BELOW wants it just under the block, and those are the
    # same slot: they differ in the group `place` is given, not in the index.
    # BELOW counted from the group's own row instead, which is the top of the
    # block, so a layer dropped on the bottom quarter left the group and was
    # then drawn unindented between it and the members it had left. A plain row
    # is a block of one, and the same arithmetic answers it.
    var bottom := at - SaLayerOps.new(target.get_parent() as SaDocument).subtree(target).size() + 1
    # A layer dragged up from under the block leaves that block one lower
    # behind it.
    return bottom - 1 if layer.get_index() < bottom else bottom
