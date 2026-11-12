## The capture harness's `layer` step: builds the stack a screenshot needs, and
## edits it.
##
## The layers docker's buttons sit in an embedded subwindow an injected click
## cannot reach, so without this step a scenario could paint on the one layer a
## fresh document has and nothing else. Its own class rather than more of
## `SaCaptureLayers`, which keeps the steps that drive the docker and the brush:
## this one is the stack's own. The keys, their order and the answer are on `run`.
class_name SaLayerStep
extends RefCounted

## What `_copy_name` puts before a sentence that refuses the step, which no
## layer's name can begin with, since Godot takes a colon out of a node's name.
const REFUSAL := "refused: "
## What a mask write notes on the trail, so the line of a run of slow frames
## that mask writes fell in names them, and how many.
const MASK_WRITTEN := "a mask written through the door"

## The keys that change what the fold folds, a layer's pixels, its mask, or the
## stack's order, grouping, blend or clip, after which the step rebuilds the
## fold. `paints` is one because it gives a layer with no mask one. A rebuild
## whatever the step did marked every chunk at no layer and redrew every effect
## layer of a large document, so a key is left out whenever something else owes
## its fold:
## - `of`, `activate`, `lock`, `comment` and an `add` that finds its layer there
##   select, note or read and leave the fold as it stands.
## - `visible` is owed to `SaFoldDebt` through `SaLayerOps.set_visible`, `opacity`
##   and `blend` are marked and refolded by `SaLayerOps` at the end of the frame,
##   and an `add` of a plain layer holds no chunk and is owed through the
##   selection as the docker's button does.
## - `mask` redraws through `SaDocument.mask_moved` as a stroke on the mask does,
##   and `_mask` builds the fold itself only for a mask added, a group's or one
##   switched.
## A selection still folds once, inside `SaDocument.set_active_layer`, because
## the fold splits at the active layer, and a press on the layer's row does too.
const REFOLDS: Array[String] = [
    "add",
    "clip",
    "fill",
    "group",
    "ungroup",
    "isolated",
    "generator",
    "paints",
    "move",
    "duplicate",
    "delete",
    "merge_down",
    "flatten",
    "transform",
]


## Runs one step against *document* and answers the line the harness prints,
## `SaCapture: layer {...}`, as the `write_pixels` step's does.
##
##     {"layer": {"add": "Multiply", "blend": "multiply", "clip": true,
##                "fill": [0.5, 0.5, 0.5, 1.0], "chunks": [[0, 0], [1, 0]],
##                "activate": "Layer 1"}}
##
## A step does its keys in this order, each optional. `add` makes a layer of that
## name above the active one and makes it active, or activates the layer already
## called that, of the registered type `type` names (`{"add": "Paper", "type":
## "background"}` adds the background that stores nothing). `blend` sets the
## mode, one a module registers, and a mode none does is left unset with an
## error naming the nearest that is. `clip` clips to the layer below, `fill`
## fills the listed chunks or the whole layer, and `activate` makes the named
## layer active again so the next stroke lands under what was just built.
## `"generator": {"second": [r, g, b, a], "scale": 40.0}` sets the parameters of
## a layer that stores nothing beyond the colour a fill sets, in the document's
## colour space, after `activate`.
##
## Then the history steps on the active layer, in this order: `"opacity"`,
## `"move": 1` places up, `"duplicate": true` or a name, `"delete"`,
## `"merge_down"` and `"flatten"`. The groups come before `activate`: `"group"`
## wraps the active layer in a new group and makes it active, `"ungroup"`
## dissolves the active group and `"isolated"` makes it composite as one.
## `"lock"` is the paint lock, which decides whether a fill lands at all, and
## `"comment"` is the layer's note (`""` takes it off). `delete` answers
## `deleted X`, `cleared X` or `kept the last layer`, because the only layer a
## document has is cleared rather than refused. `merge_down` answers `merged X
## down`, `refused, ` and the corner line's reason, or `nothing below to merge
## into`.
##
## `"mask": {"rects": [[x, y, w, h, value]], "enabled": true}` comes last of
## those: it gives the active layer a mask when it has none, rewrites the mask of
## every chunk the rectangles touch (each rectangle in document pixels holding
## its value, the rest of the chunk one) and switches it on or off. The active
## layer may be a group, whose mask holds chunks of its own.
##
## `"transform": {"move": [x, y], "turn": 90, "scale": 0.5, "pivot": [x, y]}`
## comes after the mask and draws the layer through a live transform as one
## history step: scaled and turned clockwise about `pivot` (the canvas's middle
## without it), then moved. `"scale"` takes `[sx, sy]` too, `"corners"` (four
## points for the canvas's top left, top right, bottom right and bottom left)
## says a perspective instead, and `"none"` takes the transform off. Its answers
## are `transformed X`, `untransformed X`, `refused, ` and the corner line's
## reason, and `X had no transform`.
##
## **`of`.** `{"of": "Sky", "blend": "multiply"}` names the layer every key acts
## on in place of the active one, a name or an index from the bottom as
## `read_pixels` counts it. The selection stays where it was, except where the
## operation itself moves it: `duplicate` leaves the copy active, `merge_down`
## the layer below, and a `delete` of the active layer the neighbour that takes
## its place. `group` makes the new group the layer the keys after it act on,
## and a key that follows one that took the layer out of the stack is left alone
## with a line saying so. An unknown layer refuses the whole step before anything
## runs, and so does `of` beside `add` or beside an `activate` naming no layer,
## so a typo never lands on the layer the painter has selected.
##
## The answer's `layer` is the layer acted on, `index` its place from the bottom
## afterwards (-1 when it left the stack), `active` the layer selected afterwards
## and `done` one line per key. A refusal is `{"error": ...}`, and the door
## raises it.
##
## **The fold.** The step rebuilds it at its end only when one of its keys is in
## [constant REFOLDS].
static func run(document: SaDocument, spec: Dictionary, types: SaLayerTypeRegistry = null) -> String:
    if document == null:
        return _refused("layer step has no document to act on")
    var named: SaLayer = null
    if spec.has("of"):
        var asked: Variant = SaScenarioPixels.layer_of(document, spec["of"])
        if asked is String:
            return _refused("%s, so nothing was done" % asked)
        named = asked
        if spec.has("add"):
            return _refused("`add` makes a layer of its own and takes no `of`, so nothing was done")
    var copy_name := _copy_name(document, spec.get("duplicate", false))
    if copy_name.begins_with(REFUSAL):
        return _refused(copy_name.trim_prefix(REFUSAL))
    # A name no layer has is refused before anything runs, with or without
    # `of`: answered among what was done, it would read as success, and a client
    # that guessed a renamed layer's name would paint on whichever layer was
    # active. The
    # layer the same step adds or duplicates under that name is one it will have.
    if spec.has("activate") and not _will_have(document, String(spec["activate"]), spec, copy_name):
        return _refused("there is no layer called %s to activate, so nothing was done" % spec["activate"])
    var aim := Aim.new(document, named)
    var acted: SaLayer = aim.layer()
    var done: Array[String] = []

    # A layer already called that is made active rather than a second one
    # added, which Godot would have renamed "name2" while a notebook kept
    # writing into the first. The rule is `SaScenarioPixels.named_target`'s.
    var kept: SaLayer = null
    if spec.has("add"):
        kept = SaScenarioPixels.named_target(document, String(spec["add"]))
        if kept != null:
            document.set_active_layer(kept)
            acted = kept
            done.append("kept %s" % kept.name)
        else:
            var layer := SaLayerOps.new(document).add(StringName(String(spec.get("type", ""))), types)
            layer.name = String(spec["add"])
            acted = layer
            done.append("added %s" % layer.name)

    # A mode no module registers draws as Normal, and the load is the first
    # place that says so, so a misspelt `colour` kept a layer painting as Normal
    # for a whole session. Refused here, in the answer's errors, and the rest of
    # the step's keys still run.
    if spec.has("blend"):
        var layer := aim.for_key("blend", done)
        if layer != null:
            var modes := _modes_of(document)
            var asked := StringName(String(spec["blend"]))
            var refusal := unregistered_blend(modes, asked, "the blend of %s" % layer.name)
            if refusal.is_empty():
                var mode := modes.canonical(asked) if modes != null else asked
                SaLayerOps.new(document).set_blend_mode(layer, mode)
                done.append("%s blends %s" % [layer.name, mode])
            else:
                push_error("SaCapture: layer %s" % refusal)
                done.append(refusal)

    if spec.has("clip"):
        var layer := aim.for_key("clip", done)
        if layer != null:
            SaLayerStack.set_clip_to_below(document, layer, bool(spec["clip"]))
            done.append("%s clip %s" % [layer.name, spec["clip"]])

    if spec.has("fill"):
        var layer := aim.for_key("fill", done)
        if layer != null:
            var channels := spec["fill"] as Array
            var color := Color(float(channels[0]), float(channels[1]), float(channels[2]), float(channels[3]))
            if spec.has("chunks"):
                var positions: Array = []
                for pair: Variant in spec["chunks"] as Array:
                    var grid_pos := Vector2i(int(pair[0]), int(pair[1]))
                    layer.get_or_create_chunk(grid_pos).clear(color)
                    positions.append(grid_pos)
                document.invalidate_chunks(positions)
                done.append("filled %d chunks of %s" % [positions.size(), layer.name])
            else:
                document.fill_layer(color, layer)
                done.append("filled %s" % layer.name)

    if spec.get("group", false):
        var layer := aim.for_key("group", done)
        if layer != null:
            var group := SaLayerOps.new(document).group_layers([layer])
            if group != null:
                aim.follow(group)
                done.append("grouped into %s" % group.name)
    if spec.get("ungroup", false):
        var layer := aim.for_key("ungroup", done)
        if layer != null and layer.is_group:
            var dissolved := layer.name
            SaLayerOps.new(document).ungroup(layer)
            done.append("ungrouped %s" % dissolved)
    if spec.has("isolated"):
        var layer := aim.for_key("isolated", done)
        if layer != null and layer.is_group:
            SaLayerOps.new(document).set_isolated(layer, bool(spec["isolated"]))
            done.append("%s isolated %s" % [layer.name, spec["isolated"]])

    if spec.has("activate"):
        var target := document.get_node_or_null(String(spec["activate"])) as SaLayer
        if target == null:
            done.append("no layer called %s" % spec["activate"])
        else:
            document.set_active_layer(target)
            done.append("active %s" % target.name)
            acted = aim.layer() if aim.layer() != null else acted

    # A generated layer's parameters beyond the one a fill sets: `second`
    # and `scale` reach a paper from nowhere else, because a fill writes `color`
    # and the layers docker has no page for a generator yet.
    #
    # A colour is written the way a painter picks one, in display colour,
    # and converted into the document's space here, because that is what the
    # kernel reads and what `SaGeneratedLayer.defaults_for` does with a type's
    # own defaults. Writing the raw triple instead is a scenario that reads
    # its numbers as Oklab and photographs a paper nobody asked for.
    #
    # Refused on a layer that stores something, because a plain layer carrying
    # generator parameters is a layer nothing will ever read them off.
    if spec.has("generator"):
        var layer := aim.for_key("generator", done)
        if layer != null and layer.is_generated():
            var params: Dictionary = spec["generator"]
            var space := document.color_space
            for key: String in params:
                var value: Variant = params[key]
                if value is Array:
                    var channels := value as Array
                    var color := Color(float(channels[0]), float(channels[1]), float(channels[2]), float(channels[3]))
                    value = space.from_display(color) if space != null else color
                layer.generator_params[key] = value
            document.modified = true
            document.request_cache_update()
            document.document_changed.emit()
            done.append("%s generator %s" % [layer.name, ", ".join(PackedStringArray(params.keys()))])

    # "mask" gives the active layer a mask when it has none and makes it what
    # the brush paints, "colour" hands the brush back to the layer's colour, so
    # a scenario can aim the brush without the layers docker's mask thumbnail.
    # A key of its own, because the layer step's "mask" writes the coverage and
    # this one only aims the brush.
    if spec.has("paints"):
        var layer := aim.for_key("paints", done)
        if layer != null:
            if String(spec["paints"]) == "mask":
                document.mask_target = layer.add_mask()
            else:
                document.mask_target = null
            done.append("%s paints its %s" % [layer.name, spec["paints"]])

    if spec.has("opacity"):
        var layer := aim.for_key("opacity", done)
        if layer != null:
            SaLayerOps.new(document).set_opacity(layer, float(spec["opacity"]))
            done.append("%s at opacity %s" % [layer.name, spec["opacity"]])

    if spec.has("visible"):
        var layer := aim.for_key("visible", done)
        if layer != null:
            SaLayerOps.new(document).set_visible(layer, bool(spec["visible"]))
            done.append("%s visible %s" % [layer.name, spec["visible"]])

    # The paint lock from a scenario: it lives in the docker's More menu, which
    # is in an embedded subwindow no injected click reaches, and a chord that
    # must leave a locked layer alone has to lock one first.
    if spec.has("lock"):
        var layer := aim.for_key("lock", done)
        if layer != null:
            SaLayerOps.new(document).set_locked(layer, bool(spec["lock"]))
            done.append("%s locked %s" % [layer.name, spec["lock"]])

    # The note is set from here and nowhere else: the docker shows it and
    # the rename field carries it, but nothing in the app types one, because
    # what the note is for is a companion working through the door saying what
    # it just painted on the layer it painted it on.
    if spec.has("comment"):
        var layer := aim.for_key("comment", done)
        if layer != null:
            layer.comment = String(spec["comment"])
            document.document_changed.emit()
            done.append("%s noted %d chars" % [layer.name, layer.comment.length()])

    if spec.has("move"):
        var layer := aim.for_key("move", done)
        if layer != null:
            SaLayerOps.new(document).move(layer, int(spec["move"]))
            done.append("moved %s to %d" % [layer.name, layer.get_index()])

    if spec.get("duplicate", false):
        var layer := aim.for_key("duplicate", done)
        if layer != null:
            var copy := SaLayerOps.new(document).duplicate(layer)
            # Renamed after the step is recorded, which is still inside it: the
            # step keeps the copy itself and puts it back as it is, name and all.
            if copy != null and not copy_name.is_empty():
                copy.name = copy_name
                document.document_changed.emit()
            done.append("duplicated as %s" % (String(copy.name) if copy != null else "nothing"))

    # The stack size either side of the call, because `SaLayerOps.remove` has
    # two ways to answer true: it takes a layer out, or, for the only layer a
    # document has, it clears that layer and leaves it there. A dump is what a
    # reader of a scenario trusts about what a step did, so the line names the
    # operation rather than the answer. False is left for the one case that
    # refuses, a locked last layer. A group goes with its members, and
    # the line names them, so a reader sees what left with it.
    if spec.get("delete", false):
        var doomed := aim.for_key("delete", done)
        if doomed != null:
            var before := SaLayerOps.new(document).layers().size()
            var doomed_name := String(doomed.name)
            var members := _member_names(document, doomed)
            if not SaLayerOps.new(document).remove(doomed):
                done.append("kept %s" % doomed_name if doomed.is_group else "kept the last layer")
            elif not members.is_empty():
                done.append("deleted %s with %s" % [doomed_name, ", ".join(members)])
            elif SaLayerOps.new(document).layers().size() < before:
                done.append("deleted %s" % doomed_name)
            else:
                done.append("cleared %s" % doomed.name)

    if spec.get("merge_down", false):
        var layer := aim.for_key("merge_down", done)
        if layer != null:
            done.append(_merge_down(document, layer))

    if spec.get("flatten", false):
        done.append("flattened" if SaLayerOps.new(document).flatten() else "nothing to flatten")

    if spec.has("mask"):
        var layer := aim.for_key("mask", done)
        if layer != null:
            done.append(_mask(document, layer, spec["mask"]))

    if spec.has("transform"):
        var layer := aim.for_key("transform", done)
        if layer != null:
            done.append(_transform(document, layer, spec["transform"]))

    # A rebuild after a change to the stack or its pixels: a chunk filled by
    # hand is not a stroke, and nothing else tells the caches it happened.
    if _refolds(spec, kept != null):
        document.update_caches()
    var selected := document.active_layer
    return _said(
        {
            "layer": String(acted.name) if acted != null else "",
            "index": SaLayerOps.new(document).layers().find(acted) if acted != null else -1,
            "active": String(selected.name) if selected != null else "",
            "done": done,
        }
    )


## Whether a key of *spec* is one of [constant REFOLDS]. An `add` that *kept*
## the layer already called that made it active rather than adding one, which
## is a selection.
static func _refolds(spec: Dictionary, kept: bool) -> bool:
    for key: String in REFOLDS:
        if key == "add" and (kept or String(spec.get("type", "")).is_empty()):
            continue
        if spec.has(key):
            return true
    return false


## Whether `activate` will find a layer called *wanted* when it runs: one the
## document holds, found the way `activate` finds it, or the one *spec* adds or
## duplicates under that name earlier in the same step.
static func _will_have(document: SaDocument, wanted: String, spec: Dictionary, copy_name: String) -> bool:
    if document.get_node_or_null(wanted) is SaLayer:
        return true
    return (spec.has("add") and String(spec["add"]) == wanted) or (not copy_name.is_empty() and copy_name == wanted)


## The name `duplicate` asks for, empty for `true` and for no copy at all, or
## [constant REFUSAL] and the sentence when the name cannot be a new layer's.
## The whole stack is asked, groups' members too, because a name the copy
## shared would make `of` find whichever of the two comes first.
static func _copy_name(document: SaDocument, asked: Variant) -> String:
    if not asked is String and not asked is StringName:
        return ""
    var wanted := String(asked)
    if wanted.strip_edges().is_empty():
        return REFUSAL + "a copy needs a name, and `duplicate` was given an empty one, so nothing was done"
    if wanted.validate_node_name() != wanted:
        var why := "a name holds none of the characters Godot keeps out of a node's"
        return REFUSAL + "a layer cannot be called '%s', %s, so nothing was done" % [wanted, why]
    var holder := SaScenarioPixels.named_target(document, wanted)
    if holder != null:
        var at := SaLayerOps.new(document).layers().find(holder)
        return REFUSAL + "layer %d is already called '%s', and a copy is a new layer, so nothing was done" % [at, wanted]
    return wanted


## The line a step prints: the same prefix the door looks for, then the answer
## as JSON, which is what `write_pixels` prints too.
static func _said(answer: Dictionary) -> String:
    return "SaCapture: layer %s" % JSON.stringify(answer)


## The blend modes *document* draws with, its compositor's registry, or null in
## a host that gave it none.
static func _modes_of(document: SaDocument) -> SaBlendModeRegistry:
    return document.compositor.registry if document.compositor != null else null


## The sentence that refuses *asked* as a blend mode for *what*, or empty when
## *modes* registers it under that id or a former one. A registry holding no
## mode is a host with nothing loaded, where every mode would be refused, so it
## refuses none, as `SaBlendModeRegistry.rebind` says nothing there either.
##
## The sentence names the registered id nearest in spelling, so a script that
## wrote `colour` reads `color` and corrects itself. Ids stay American by the
## house rule, and no British spelling is taken in their place.
static func unregistered_blend(modes: SaBlendModeRegistry, asked: StringName, what: String) -> String:
    if modes == null or modes.list_ids().is_empty() or modes.has(modes.canonical(asked)):
        return ""
    var wanted := String(asked).to_lower()
    var nearest := ""
    var best := -1.0
    for mode_id: StringName in modes.list_ids():
        var alike := wanted.similarity(String(mode_id).to_lower())
        if alike > best:
            best = alike
            nearest = String(mode_id)
    var said := "%s was left as it was, no module registers a blend mode '%s', the nearest is '%s'"
    return said % [what, asked, nearest]


## A refusal, which the door raises when the answer carries `error`.
static func _refused(sentence: String) -> String:
    return _said({"error": sentence})


## What goes with *doomed* when it is a group: each member by name, a member's
## attached filters by key in brackets after it, top of the stack first. Empty
## for a layer that is no group, whose filters go unsaid as they always have.
static func _member_names(document: SaDocument, doomed: SaLayer) -> PackedStringArray:
    var names := PackedStringArray()
    if not doomed.is_group:
        return names
    var block := SaLayerOps.new(document).subtree(doomed)
    block.reverse()
    for member in block:
        if member == doomed:
            continue
        var keys := PackedStringArray()
        for filter in member.filters:
            keys.append(String(filter.key))
        names.append(String(member.name) + (" (%s)" % ", ".join(keys) if not keys.is_empty() else ""))
    return names


## The `merge_down` key, with three answers rather than two, as `delete` has.
## `SaLayerOps.merge_down` answers false for a refused group or generated layer
## as well as for a bottom layer, and a line that read every false as the
## second would print "nothing below to merge into" for a refused group, beside
## a corner line naming the real reason.
## The layer below is asked first, and a refusal is quoted from the corner.
static func _merge_down(document: SaDocument, upper: SaLayer) -> String:
    var ops := SaLayerOps.new(document)
    if ops.layers().find(upper) <= 0:
        return "nothing below to merge into"
    var heard := RefusalEar.new()
    if ops.merge_down(upper):
        heard.stop()
        return "merged %s down" % upper.name
    heard.stop()
    return "refused, %s" % heard.last()


## The `transform` key: *layer* drawn through the map *asked* describes, or
## where it was painted for `"none"`. A refusal is quoted from the corner, as
## `merge_down`'s is.
static func _transform(document: SaDocument, layer: SaLayer, asked: Variant) -> String:
    var map: Variant = null
    if asked is Dictionary:
        map = _map(document, asked)
        if map is String:
            return "refused, %s" % map
    elif asked != null and str(asked) != "none":
        return 'refused, `transform` takes a dictionary or "none"'
    if map == null and SaLiveTransform.of(layer) == null:
        return "%s had no transform" % layer.name
    var heard := RefusalEar.new()
    var put := SaLiveTransform.put(document, layer, map)
    heard.stop()
    if not put:
        return "refused, %s" % heard.last()
    return ("transformed %s" if map != null else "untransformed %s") % layer.name


## The map a `transform` key describes, or a sentence saying what in it is not
## a map.
static func _map(document: SaDocument, asked: Dictionary) -> Variant:
    var canvas := Rect2(Vector2.ZERO, Vector2(document.canvas_size))
    if asked.has("corners"):
        var corners := PackedVector2Array()
        var listed: Array = asked["corners"] if asked["corners"] is Array else []
        for corner: Variant in listed:
            var at: Variant = _point(corner)
            if at is Vector2:
                corners.append(at)
        var map: Variant = SaLiveTransform.cornered(canvas, corners) if corners.size() == 4 else null
        return map if map != null else "`corners` takes four points no three of which are on one line"
    var move: Variant = _point(asked.get("move", [0, 0]))
    var pivot: Variant = _point(asked.get("pivot", [canvas.get_center().x, canvas.get_center().y]))
    var size: Variant = asked.get("scale", 1.0)
    var scale: Variant = Vector2(float(size), float(size)) if size is float or size is int else _point(size)
    var turn: Variant = asked.get("turn", 0.0)
    if not move is Vector2 or not pivot is Vector2 or not scale is Vector2 or not (turn is float or turn is int):
        return "`move`, `pivot` and `scale` take [x, y] and `turn` a number of degrees"
    return SaLiveTransform.composed(move, float(turn), scale, pivot)


## *value* as a point when it is two numbers, and null otherwise.
static func _point(value: Variant) -> Variant:
    if not value is Array or (value as Array).size() != 2:
        return null
    var pair: Array = value
    if not (pair[0] is float or pair[0] is int) or not (pair[1] is float or pair[1] is int):
        return null
    return Vector2(float(pair[0]), float(pair[1]))


## The `mask` key: *layer*'s mask, added when it has none, written by upload
## rather than by a stroke, and switched on or off. An upload is a CPU write
## into VRAM and never a read back, which is why a chunk it touches is
## rewritten whole rather than merged with what it held: hard rule 1.
static func _mask(document: SaDocument, layer: SaLayer, spec: Dictionary) -> String:
    if layer.is_generated():
        return "no layer to mask"
    var had := layer.mask != null
    var mask := layer.add_mask()
    var said := "%s masked" % layer.name
    var side := SaLayer.CHUNK_SIZE
    # Each chunk is an R32 float image filled rect by rect in the engine, whose
    # bytes are the texture's, and a rect visits only the chunks it covers. A
    # loop over the texels in script, and over every chunk from the canvas's
    # corner to each rect's end, took 10 to 55 ms of one frame for each of the
    # large masks' posts of 4,000 to 18,000 one-row rects.
    var buffers: Dictionary[Vector2i, Image] = {}
    for entry: Array in spec.get("rects", []) as Array:
        var rect := Rect2i(int(entry[0]), int(entry[1]), int(entry[2]), int(entry[3]))
        rect = rect.intersection(Rect2i(0, 0, rect.end.x, rect.end.y))
        if rect.size.x <= 0 or rect.size.y <= 0:
            continue
        var colour := Color(float(entry[4]), 0.0, 0.0)
        @warning_ignore("integer_division")
        var first := rect.position / side
        @warning_ignore("integer_division")
        var last := (rect.end - Vector2i.ONE) / side
        for chunk_y in range(first.y, last.y + 1):
            for chunk_x in range(first.x, last.x + 1):
                var grid_pos := Vector2i(chunk_x, chunk_y)
                var image: Image = buffers.get(grid_pos)
                if image == null:
                    image = Image.create_empty(side, side, false, Image.FORMAT_RF)
                    image.fill(Color(1.0, 0.0, 0.0))
                    buffers[grid_pos] = image
                var local := Rect2i(grid_pos * side, Vector2i(side, side)).intersection(rect)
                local.position -= grid_pos * side
                image.fill_rect(local, colour)
    for grid_pos: Vector2i in buffers:
        var texture := mask.get_or_create(grid_pos)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, buffers[grid_pos].get_data())
    if not buffers.is_empty():
        said += ", %d chunks written" % buffers.size()
        SaTrail.note(MASK_WRITTEN)
    if spec.has("enabled"):
        mask.enabled = bool(spec["enabled"])
        document.invalidate_chunks(layer.chunks.keys() + mask.grid_positions())
        said += ", on" if mask.enabled else ", off"
    if not had or layer.is_group or spec.has("enabled"):
        # A mask added, a group's, which isolates it, or one switched changes
        # the walk and not only the chunks, so the fold is built again.
        document.update_caches()
    elif not buffers.is_empty():
        _mask_moved(document, layer, mask, buffers.keys())
    return said


## Redraws what rewriting *mask*'s chunks at *grid_positions* moves, as a stroke
## on the mask does: marked at *layer*, which holds it, and folded again over
## those chunks alone. A layer the picture leaves out, hidden or inside a
## hidden group, moves nothing in it. A rebuild of the fold after each write
## marked every chunk at no layer, so on a document with 219 effect layers each of ten posts a
## mask redrew all 219 effect layers, and 14 masks held the frames slow for
## three minutes.
static func _mask_moved(document: SaDocument, layer: SaLayer, mask: SaMask, grid_positions: Array) -> void:
    document.modified = true
    if not SaLayerStack.contributes(document, layer):
        document.document_changed.emit()
        return
    document.mask_moved(mask, grid_positions)


## The layer the keys of one step act on: the one `of` named, or the active
## layer wherever the keys before this one left it, which is what a step with no
## `of` acts on. Without `of` the selection is read afresh for every key, so the
## two meet in one method rather than in two code paths.
class Aim:
    extends RefCounted

    var _document: SaDocument = null
    var _named: SaLayer = null
    var _name: String = ""

    ## *named* is the layer `of` found, and null leaves the aim on the selection.
    func _init(document: SaDocument, named: SaLayer = null) -> void:
        _document = document
        _named = named
        _name = String(named.name) if named != null else ""

    ## The layer to act on, which for an `of` is null once that layer has left
    ## the stack: a delete, a merge down or an ungroup took it out, and what a
    ## later key would find in its place is another layer than the one named.
    func layer() -> SaLayer:
        if _named == null:
            return _document.active_layer
        if is_instance_valid(_named) and _named.get_parent() == _document:
            return _named
        return null

    ## [method layer] for the key *key*, with a line in *done* saying the key was
    ## left alone when the layer is gone.
    func for_key(key: String, done: Array[String]) -> SaLayer:
        var here := layer()
        if here == null:
            done.append("%s left alone, %s has left the stack" % [key, _name])
        return here

    ## Aims the keys after this at *layer*, a group the step just made. With no
    ## `of` the aim is the selection, so that is where the group goes, as it did.
    func follow(layer_made: SaLayer) -> void:
        if _named == null:
            _document.set_active_layer(layer_made)
        else:
            _named = layer_made
            _name = String(layer_made.name)


## Hears the refusals `SaProblems` delivers while it listens, so a step can
## quote the corner line rather than guess at it. The sink that was attached,
## `SaMessage`'s in the running app, is handed every line as well and put
## back afterwards, so the painter's corner still shows the refusal. With no
## sink attached, in a suite, a refusal is kept in `pending_refusals`, and the
## ear reads what was added there rather than attaching, because attaching
## would drain what was waiting into the ear.
class RefusalEar:
    extends RefCounted

    var _kept: Callable = Callable()
    var _waiting: int = -1
    var _heard: PackedStringArray = PackedStringArray()

    func _init() -> void:
        _kept = SaProblems._sink
        if _kept.is_valid():
            SaProblems.attach_sink(_hear)
        else:
            _waiting = SaProblems.pending_refusals.size()

    ## Puts the sink back, or collects what arrived in the queue.
    func stop() -> void:
        if _kept.is_valid():
            SaProblems.attach_sink(_kept)
            return
        var queued := SaProblems.pending_refusals
        for index in range(_waiting, queued.size()):
            _heard.append(queued[index])

    ## The last refusal heard, or a line saying none came.
    func last() -> String:
        return _heard[_heard.size() - 1] if not _heard.is_empty() else "with no reason given"

    func _hear(line: String, kind: SaProblems.Kind) -> void:
        if kind == SaProblems.Kind.REFUSAL:
            _heard.append(line)
        _kept.call(line, kind)
