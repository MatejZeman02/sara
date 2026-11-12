## The live document's colour rounded as a save the painter asks for rounds the
## file, before an export reads the picture, so an export of the live document
## equals an export of the same document saved and opened again.
##
## **Why.** A save rounds every full precision colour field to
## [constant SaSadSnapshot.KEPT_BITS] significant bits on its own copy and
## leaves the document's float32 as painted. So the live picture and the
## reopened one differ by at most 2^-12 of a value, which is invisible on the
## canvas, but a value that sits on the edge between two steps of eight bits
## lands on a different step in each export, and even a small document holds
## thousands of such texels.
##
## **What moves.** Only a texture a save writes and that is not rounded already
## is rounded, in place on the card, so the chunks of an effect layer and of a
## scene layer, which the file never holds, are left as their refresh drew them.
## Which those are is read off the card in one pass, `SaSadHash`'s
## unrounded kernel, which counts in each full precision colour texture the
## channels the rounding would move, so a document saved and opened, or
## exported once already, rounds nothing and redraws nothing. Each layer whose
## texture moved is redrawn at its own chunks, and each cache of the fold that
## baked it folds again over them, as an undo's paint is. An export over frames
## asks the pass a share a turn, [SaLiveRounding.InTurns]. The rounding is no history step: it moves nothing the eye can see
## and a second rounding moves nothing at all.
##
## Half precision colour, every mask, the height and every other field are
## left as they are, as a save leaves them, and so is every field of a document
## whose painter turned the rounding at save off.
class_name SaLiveRounding
extends RefCounted


## Rounds the full precision colour of *document* that is not rounded yet and
## redraws what moved, all in this frame. Answers how many textures it rounded.
static func round_document(document: SaDocument) -> int:
    var found := Found.new(document)
    if found.textures.is_empty():
        return 0
    return found.apply(SaSadHash.of(found.textures, [], SaSadHash.UNROUNDED))


## The full precision colour textures of a document a save rounds, each with
## its layer and its place, and the place in the history they were listed at.
class Found:
    extends RefCounted

    var document: SaDocument
    var textures: Array[SaTexture] = []
    var layers: Array[SaLayer] = []
    var places: Array[Vector2i] = []
    ## The history's position when the list was made, -1 with no history.
    var serial := -1

    func _init(doc: SaDocument) -> void:
        document = doc
        # A document whose painter turned the rounding off is saved as it lies,
        # so the live colour already equals what a reopen reads.
        if document == null or not SaSadSnapshot.rounds_at_save(document):
            return
        serial = document.history.position() if document.history != null else -1
        for child in document.get_children():
            var layer := child as SaLayer
            if layer == null:
                continue
            # As a save does, so a derived colour is the one the file would hold.
            layer.resolve_pending()
            # Only the chunks the file stores. An effect layer's chunks are a
            # cache its input refreshes and a reopen draws again unrounded, so
            # rounding them changes no export and its redraw refreshes them
            # unrounded, which moves every effect reading them, and the next
            # export rounded those.
            var stored := SaSadSnapshot.stored_chunks(layer)
            for grid_pos: Vector2i in stored:
                var chunk: SaChunk = stored[grid_pos]
                if chunk == null:
                    continue
                for field_id: StringName in chunk.fields:
                    var texture: SaTexture = chunk.fields[field_id]
                    if SaLiveRounding._rounds(layer, field_id, texture):
                        textures.append(texture)
                        layers.append(layer)
                        places.append(grid_pos)

    ## Whether the document still stands where it stood when the list was
    ## made, so a count read since holds for every texture on it.
    func stands() -> bool:
        var now := document.history.position() if document != null and document.history != null else -1
        return now == serial

    ## Rounds each texture *said*, the words of `SaSadHash.UNROUNDED` in the
    ## list's order, names as moving, and redraws the layers they belong to.
    ## Answers how many it rounded, none when *said* does not hold one each.
    func apply(said: PackedStringArray) -> int:
        if said.size() != textures.size():
            return 0
        var moved: Dictionary[SaLayer, Dictionary] = {}
        var count := 0
        for slot in textures.size():
            if not SaSadHash.moves(said[slot]):
                continue
            SaSadSnapshot.round_in_place(textures[slot])
            var positions: Dictionary = moved.get_or_add(layers[slot], {})
            positions[places[slot]] = true
            count += 1
        for layer: SaLayer in moved:
            SaLiveRounding._redraw(document, layer, moved[layer].keys())
        return count


## [method round_document] over turns, so an export of a deep stack holds no
## frame while the card is asked which textures a save would round. Each
## [method turn] does one step: a share of the textures sent, the words read,
## and the rounding and the redraw. When the document has moved between the
## list and the words, a stroke ended or a layer added, the list is made again,
## and after [constant ASKS] of them the rest is done in one frame, as
## [method round_document] does, so a painter who never stops still gets the
## file. [method finish] ends it at once wherever it stands.
class InTurns:
    extends RefCounted

    ## The lists made before the rest is done in one frame.
    const ASKS := 3

    ## How many textures were rounded, read once [member done].
    var moved := 0
    var done := false
    var _document: SaDocument
    var _found: Found = null
    var _shares: SaSadHashShares = null
    var _asks := 0
    var _drawn_seen := -1

    func _init(document: SaDocument) -> void:
        _document = document
        _ask()

    ## One step, and whether the rounding has ended.
    func turn() -> bool:
        if done:
            return true
        if _shares == null:
            return _end(0)
        if not _shares.all_sent():
            if not _shares.send():
                _again()
            # Each share runs on the card in the frame it was sent in, rather
            # than all of them in the first frame an idle window draws.
            _draw_while_owed()
            return done
        if not _shares.words_in:
            _draw_while_owed()
            return false
        if not _shares.read():
            return false
        if not _found.stands() or _shares.superseded():
            _again()
            return done
        var said := PackedStringArray()
        for texture: SaTexture in _found.textures:
            var word: String = _shares.said.get(texture.rid, "")
            said.append(word)
        return _end(_found.apply(said))

    ## Ends the rounding in this frame, wherever it stood.
    func finish() -> void:
        if not done:
            _end(SaLiveRounding.round_document(_document) if is_instance_valid(_document) else 0)

    func _ask() -> void:
        _asks += 1
        _found = Found.new(_document)
        _shares = null
        if _found.textures.is_empty():
            return
        var asked := SaSadHashShares.new(_found.textures, SaSadHash.UNROUNDED)
        _shares = asked if asked.is_open() else null
        if _shares == null:
            finish()

    # The device hands the words over only as frames are drawn, and the window
    # in low processor mode draws one only when something on screen changed,
    # so a turn that saw no frame drawn since the last draws one, as the save
    # does (the pitfall "A read asked of the main device answers only as a
    # frame is drawn, and an idle window draws none"). Never a present.
    func _draw_while_owed() -> void:
        var drawn := Engine.get_frames_drawn()
        if drawn == _drawn_seen and RenderingServer.get_rendering_device() != null:
            RenderingServer.force_draw(false, 0.0)
        _drawn_seen = drawn

    func _again() -> void:
        if _asks >= ASKS:
            finish()
            return
        _ask()

    func _end(count: int) -> bool:
        moved = count
        done = true
        return true


## Whether a save the painter asks for rounds *texture*, the field *field_id*
## of *layer*.
static func _rounds(layer: SaLayer, field_id: StringName, texture: SaTexture) -> bool:
    if texture == null or not texture.rid.is_valid() or texture.format != SaSadSnapshot.FULL:
        return false
    var spec := SaFieldSpec.find(layer.schema, field_id)
    return spec != null and spec.is_color


## Marks *grid_positions* of *layer* dirty at the layer and folds again over
## them, and over the halo a filter of the root reads, each cache that baked
## it, the way the document redraws the paint an undo brought back.
static func _redraw(document: SaDocument, layer: SaLayer, grid_positions: Array) -> void:
    document.invalidate_chunks(grid_positions, layer)
    if document.fold == null or document.compositor == null:
        return
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in grid_positions:
        regions[grid_pos] = SaDocument.WHOLE_CHUNK
    var spread := SaStaleSpread.new().spread(
        document, document.root_filters, regions, document.canvas_size, null, document.projection.wrapping
    )
    var stale := SaTyped.positions(spread)
    document.invalidate_chunks(document.fold.refold(document, document.compositor, layer, stale).keys(), layer)
