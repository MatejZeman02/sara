## A linked file: a smart layer's source read from a picture on disk, so a logo,
## a photograph or a texture painted elsewhere is changed there and the layer
## in Sara follows it, as a linked file does in Blender, with a relative and an
## absolute path both kept.
##
## **A shared source with a file behind it.** A link is a `SaSharedSource`
## whose chunks are the picture the file gave, so the layer is drawn through
## its own map as any smart layer is, keeps the link through every transform,
## and two layers sharing it follow one file. The picture
## enters as an import does, read by the reader `SaImageFormatRegistry` holds
## for the file's bytes and converted from the space the file names, so a
## module's flat format is linkable once it registers. A layered document, a
## `.sad` among them, is refused with a sentence, and so is a file no reader
## reads, in the reader's own words.
##
## **Reload, never by itself.** Reload Linked File reads the file again and
## puts a new link holding the new picture on every layer drawn from it, as
## one history step, so the map, the crop and every setting stay and the undo
## gives the old picture back. A changed file is only marked: the watch below
## compares the file's size and modified time with the ones read, when the
## window regains the focus and every [constant WATCH_SECONDS], and says so in
## the corner. An open reads every link from its file again.
##
## **A broken link is a state.** A file that is missing, unreadable or of a
## format no module reads keeps the last picture, which the `.sad` stores as
## any smart layer's chunks, is reported by the layers report and in the
## corner, and never stops a document opening.
##
## **The path.** [member path] is always absolute in memory, and a save writes
## it relative to the `.sad` when [member relative] holds, which is the default,
## with the absolute form beside it as the second try when the relative one no
## longer resolves. An unsaved document has nothing to be relative to, so the
## first save is where a link turns relative. The `.sad` a save writes and an
## open reads is [method beside]'s and [method opened]'s, which the container
## hands in, since a layer's entry is written with no path.
##
## **Painting into a linked layer** writes the link's chunks, as painting any
## smart layer's contents writes its source, and the strokes are its override,
## [member override], kept over the file's picture by a reload and an open and
## saved in the `.sad`. Layer > Clear Override drops them as one history step.
## `SaLinkedOverride` holds them.
class_name SaLinkedFile
extends SaSharedSource

## The key a linked layer's `.sad` entry keeps its link under.
const ENTRY := "link"
## The names the commands take in the history and in the corner.
const LINK_FILE := "Link to File"
const RELOAD := "Reload Linked File"
const ABSOLUTE := "Make Path Absolute"
const RELATIVE := "Make Path Relative"
const EMBED := "Embed Linked File"
const CLEAR := "Clear Override"
## The states a link is in, what the layers report says under `"state"`.
const LINKED := "linked"
const CHANGED := "changed"
const MISSING := "missing"
const UNREADABLE := "unreadable"
## How often the watch looks at every linked file, in seconds. A stat each,
## so slow on purpose.
const WATCH_SECONDS := 10.0

## The file the picture was read from, absolute. Set in the constructor.
var path := ""
## Whether a save writes the path relative to the `.sad`.
var relative := true
## The file's size and modified time when the picture was read, which the
## watch compares, -1 and 0 for a link that read nothing.
var size := -1
var modified := 0
## One of [constant LINKED], [constant CHANGED], [constant MISSING] and
## [constant UNREADABLE].
var state := LINKED
## Why the link is broken, in words, or empty.
var reason := ""
## The file's picture kept apart from the strokes painted over it. Set in the
## constructor.
var override: SaLinkedOverride = null

## The `.sad` each document is being written to or read from, by the
## document's instance id, held while that save or open runs. Kept apart by
## document, because one `.sad` is saved while another opens, and a link
## must never read the other file's folder or blobs.
static var _beside: Dictionary[int, Beside] = {}
## The blobs of the `.sad` an open read, by the document's instance id, kept
## until its links are read again.
static var _opened_blobs: Dictionary[int, PackedByteArray] = {}
## The node that hears the focus come back and keeps the slow timer.
static var _watch: Watch = null


## A link drawn from *held*, over the file's picture *under*, which is a copy
## of *held* when none is given, as for a picture just read.
func _init(
    held: Dictionary[Vector2i, SaChunk],
    file: String,
    written_relative := true,
    broken := "",
    why := "",
    under: SaLinkedOverride = null
) -> void:
    super(held)
    override = under if under != null else SaLinkedOverride.new(SaLinkedOverride.apart(held))
    path = file
    relative = written_relative
    state = broken if not broken.is_empty() else LINKED
    reason = why
    if state == LINKED:
        var stamp := _stamp(file)
        size = stamp[0]
        modified = stamp[1]


## The link *layer* is drawn from, or null for a layer with no file behind it.
static func link_of(layer: SaLayer) -> SaLinkedFile:
    return SaSharedSource.of(layer) as SaLinkedFile if layer != null else null


## Layer > Link to File...: reads the picture at *file* and makes it *layer*'s
## source, at the map and crop it has, as one history step, and answers
## whether it did. An ordinary layer is made smart in the same step, so a new
## layer is linked by the one command. A layer whose transform cannot change
## and a file that cannot be read say why in the corner and leave the layer as
## it was.
static func link_file(document: SaDocument, layer: SaLayer, file: String) -> bool:
    if document == null or layer == null:
        return false
    var live := SaLiveTransform.of(layer)
    var why := SaLiveTransform.refusal(document, layer, live.matrix if live != null else Basis.IDENTITY)
    if not why.is_empty():
        SaProblems.refuse(LINK_FILE, TranslationServer.translate("The layer cannot be linked to a file. %s") % why)
        return false
    var absolute := _absolute(file)
    var read: Variant = _read(document, layer, absolute)
    if read is String:
        var said: String = read
        SaProblems.refuse(LINK_FILE, TranslationServer.translate("The layer cannot be linked to a file. %s") % said)
        return false
    var picture: Dictionary[Vector2i, SaChunk] = read
    # An ordinary layer is made smart in the same step. A layer holding its
    # paint alone puts it in a source first, so the undo finds the paint it had
    # rather than a copy of the file's.
    document.history.as_one(
        LINK_FILE,
        func() -> void:
            if SaSharedSource.of(layer) == null:
                _put(document, [layer], SaSharedSource.new(layer.chunks), LINK_FILE)
            _put(document, [layer], SaLinkedFile.new(picture, absolute), LINK_FILE)
    )
    _watch_over(document)
    return true


## Layer > Reload Linked File: reads *layer*'s file again and puts the new
## picture under every layer drawn from the link, as one history step, and
## answers whether it did. A file that cannot be read marks the link broken,
## says why in the corner and leaves the picture as it was.
static func reload_file(document: SaDocument, layer: SaLayer) -> bool:
    var held := link_of(layer)
    if document == null or held == null:
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(RELOAD, TranslationServer.translate("'%s' is not linked to a file.") % named)
        return false
    var read: Variant = _read(document, layer, held.path)
    if read is String:
        var why: String = read
        held._break(MISSING if not FileAccess.file_exists(held.path) else UNREADABLE, why)
        SaProblems.refuse(RELOAD, TranslationServer.translate("The linked file cannot be reloaded. %s") % why)
        return false
    var picture: Dictionary[Vector2i, SaChunk] = read
    # The strokes stay over the new picture, which is kept apart as the next
    # reload's old one.
    var painted := held.override.kept_over(held.chunks, picture, layer.schema)
    var after := SaLinkedFile.new(painted, held.path, held.relative, "", "", SaLinkedOverride.new(picture))
    _put(document, held.users_in(document), after, RELOAD)
    return true


## Layer > Clear Override: drops the strokes painted into *layer*'s linked
## contents, so every layer drawn from the link shows the file's picture alone,
## as one history step, and answers whether it did. A link with no strokes says
## so in the corner and writes no step.
static func clear_override(document: SaDocument, layer: SaLayer) -> bool:
    var held := link_of(layer)
    if document == null or held == null:
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(CLEAR, TranslationServer.translate("'%s' is not linked to a file.") % named)
        return false
    if held.override.strokes(held.chunks, layer.schema).is_empty():
        SaProblems.refuse(CLEAR, TranslationServer.translate("'%s' has no strokes over its linked file.") % String(layer.name))
        return false
    var picture := SaLinkedOverride.apart(held.override.picture)
    var after := SaLinkedFile.new(picture, held.path, held.relative, held.state, held.reason, held.override)
    after.size = held.size
    after.modified = held.modified
    _put(document, held.users_in(document), after, CLEAR)
    return true


## Layer > Embed Linked File: keeps *layer*'s picture as its own source and
## drops the link, as one history step, and answers whether it did. The layer
## stays smart at its map.
static func embed(document: SaDocument, layer: SaLayer) -> bool:
    if document == null or link_of(layer) == null:
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(EMBED, TranslationServer.translate("'%s' is not linked to a file.") % named)
        return false
    _put(document, [layer], null, EMBED)
    return true


## Layer > Make Path Absolute, *to_relative* false, and Make Path Relative, true:
## how a save writes *layer*'s link, as one history step, and whether it changed.
static func write_path(document: SaDocument, layer: SaLayer, to_relative: bool) -> bool:
    var held := link_of(layer)
    var step := RELATIVE if to_relative else ABSOLUTE
    if document == null or held == null:
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(step, TranslationServer.translate("'%s' is not linked to a file.") % named)
        return false
    if held.relative == to_relative:
        var already := "The path of '%s' is relative already." if to_relative else "The path of '%s' is absolute already."
        SaProblems.refuse(step, TranslationServer.translate(already) % String(layer.name))
        return false
    held._choose(to_relative)
    document.modified = true
    document.history.commit_pair(step, held._choose.bind(to_relative), held._choose.bind(not to_relative))
    return true


## [method write_path] to the absolute form, as the menu's command runs it.
static func make_absolute(document: SaDocument, layer: SaLayer) -> bool:
    return write_path(document, layer, false)


## [method write_path] to the relative form, as the menu's command runs it.
static func make_relative(document: SaDocument, layer: SaLayer) -> bool:
    return write_path(document, layer, true)


## Whether *layer* is linked to a file, which lights the link's rows. Quiet,
## because the menu asks it on every open.
static func is_linked(layer: SaLayer) -> bool:
    return link_of(layer) != null


func _choose(to_relative: bool) -> void:
    relative = to_relative


func _break(broken: String, why: String) -> void:
    state = broken
    reason = why


## Puts on each of *layers* a smart transform at its map and crop drawn from
## *source*, null for a copy of its own, an ordinary layer made smart at no map, as one history step named *name*, and
## marks the paint to be resolved, as an import marks what it uploads.
static func _put(document: SaDocument, layers: Array, source: SaSharedSource, name: String) -> void:
    document.history.as_one(
        name,
        func() -> void:
            for user: SaLayer in layers:
                var live := SaLiveTransform.of(user)
                var map := live.matrix if live != null else Basis.IDENTITY
                var after := SaLiveTransform.new(map, live.crop if live != null else null, true, source)
                SaLiveTransform.put_step(document, user, after, name)
                user.mark_all_unresolved()
    )
    document.update_caches()


## The picture at *file* as chunks for *layer* at *document*'s depth and space,
## or the sentence that says why it is not one.
static func _read(document: SaDocument, layer: SaLayer, file: String) -> Variant:
    var named := file.get_file()
    var formats := SaImageImport.formats()
    if file.get_extension().to_lower() == "sad" or formats.layered_named(file) != null:
        var layered := "'%s' is a layered document, and a linked layer reads a flat picture. Export it flat and link that."
        return TranslationServer.translate(layered) % named
    if not FileAccess.file_exists(file):
        return TranslationServer.translate("'%s' is not there any more.") % file
    var image := SaImageImport.read(file)
    if image == null or image.is_empty():
        return TranslationServer.translate("'%s' could not be read as a picture, and the corner says why.") % named
    var scratch := SaLayer.new()
    scratch.schema = layer.schema
    SaImageImport.upload(document, scratch, image)
    SaColorConversion.new(document).convert_layer(scratch, SaImageImport.space_for(file))
    var picture := scratch.chunks
    scratch.free()
    return picture


## *file* made absolute, `user://` and `res://` turned into the disk's own.
static func _absolute(file: String) -> String:
    var global := ProjectSettings.globalize_path(file)
    if global.is_relative_path():
        global = OS.get_executable_path().get_base_dir().path_join(global)
    return global.simplify_path()


## The size and modified time of *file*, or -1 and 0 when it is not there.
static func _stamp(file: String) -> Array[int]:
    var opened_file := FileAccess.open(file, FileAccess.READ)
    if opened_file == null:
        return [-1, 0]
    var length := opened_file.get_length()
    opened_file.close()
    return [length, FileAccess.get_modified_time(file)]


## Looks at this link's file and answers whether the state changed: a file
## gone is [constant MISSING], one of another size or time [constant CHANGED],
## and one back as it was read [constant LINKED] again.
func _look() -> bool:
    var stamp := _stamp(path)
    var now := state
    if stamp[0] < 0:
        now = MISSING
    elif stamp[0] != size or stamp[1] != modified:
        now = CHANGED
    elif state != UNREADABLE:
        now = LINKED
    if now == state:
        return false
    state = now
    reason = _said(now)
    return true


func _said(now: String) -> String:
    match now:
        CHANGED:
            return (
                TranslationServer.translate("'%s' changed on disk. Layer > Reload Linked File reads it again.") % path.get_file()
            )
        MISSING:
            return TranslationServer.translate("'%s' is not there any more. The layer keeps the last picture.") % path
    return ""


## Looks at every linked file of *document*, marks each that changed or went
## missing, says so in the corner, and answers the layers marked now. What the
## watch runs, and a suite.
static func check(document: SaDocument) -> Array[SaLayer]:
    var marked: Array[SaLayer] = []
    if document == null:
        return marked
    var seen: Dictionary[SaLinkedFile, bool] = {}
    for child in document.get_children():
        var held := link_of(child as SaLayer)
        if held == null or seen.has(held):
            continue
        seen[held] = true
        if held._look() and held.state != LINKED:
            marked.append_array(held.users_in(document))
            var named := held.users_in(document)[0].name
            SaProblems.report(
                RELOAD, TranslationServer.translate("The linked layer '%s' needs a look. %s") % [named, held.reason]
            )
    return marked


## What the layers report says under `"link"` for *layer*: its path, whether a
## save writes it relative, its state and the reason, and empty for a layer
## with no file behind it.
static func state_of(layer: SaLayer) -> Dictionary[String, Variant]:
    var held := link_of(layer)
    var said: Dictionary[String, Variant] = {}
    if held != null:
        said = {"path": held.path, "relative": held.relative, "state": held.state, "reason": held.reason}
    return said


## Runs *work*, a save of *document* writing the `.sad` at *file*, with *file*
## as what its links are written relative to, and answers what *work* answers.
## *blobs* is what the save appends its blobs to, which the picture under a
## link's strokes goes into. Another document's save or open meanwhile has a
## [Beside] of its own.
static func beside(document: SaDocument, file: String, work: Callable, blobs := PackedByteArray()) -> Variant:
    var id := document.get_instance_id()
    var before: Beside = _beside.get(id, null)
    _beside[id] = Beside.new(_absolute(file) if not file.is_empty() else "", blobs)
    var answer: Variant = work.call()
    if before != null:
        _beside[id] = before
    else:
        _beside.erase(id)
    return answer


## Notes *blobs*, the blobs of the `.sad` an open of *document* is reading, for
## [method opened] to read the picture under each link's strokes out of. The
## container calls it.
static func reading(document: SaDocument, blobs: PackedByteArray) -> void:
    _opened_blobs[document.get_instance_id()] = blobs


## Runs *work*, an open of the `.sad` at *file* into *document*, then reads
## every link it holds from its file again, and answers *work*'s error.
static func opened(document: SaDocument, file: String, work: Callable) -> Error:
    var id := document.get_instance_id()
    var error: Error = beside(document, file, work)
    if error == OK:
        var blobs: PackedByteArray = _opened_blobs.get(id, PackedByteArray())
        beside(document, file, _reopen.bind(document), blobs)
    _opened_blobs.erase(id)
    return error


## What *document*'s save or open in hand writes beside, or an empty one when
## none runs.
static func _of(document: SaDocument) -> Beside:
    var held: Beside = _beside.get(document.get_instance_id(), null) if document != null else null
    return held if held != null else Beside.new("", PackedByteArray())


## Writes *layer*'s link into its entry *layer_dict*: the path as a save writes
## it, the absolute form and whether it is written relative, and nothing for a
## layer with no file behind it. Its picture is the layer's chunks, stored as
## any smart layer's are.
static func write_header(layer: SaLayer, layer_dict: Dictionary[String, Variant]) -> void:
    var held := link_of(layer)
    if held == null:
        return
    var document := layer.get_parent() as SaDocument
    var here := _of(document)
    var target := here.file if not here.file.is_empty() else (document.file_path if document != null else "")
    var written := held.path
    if held.relative and not target.is_empty():
        written = _relative_to(_absolute(target).get_base_dir(), held.path)
    var entry: Dictionary[String, Variant] = {"path": written, "absolute": held.path, "relative": held.relative}
    # The picture under the strokes goes in the entry that keeps the paint.
    if SaSharedSource.keeps_chunks(layer):
        held.override.write(held.chunks, layer.schema, entry, here.blobs)
    layer_dict[ENTRY] = entry


## Notes the link *layer_data* keeps, for [method opened] to read once every
## layer of the file is in its document.
static func read_header(layer: SaLayer, layer_data: Dictionary[String, Variant]) -> void:
    var entry: Variant = layer_data.get(ENTRY, null)
    if entry is Dictionary and SaLiveTransform.of(layer) != null:
        layer.set_meta(ENTRY, entry)


## Puts a link read from its file again on every layer of a loaded *document*
## whose entry kept one. Users of one shared source get one link. A file that
## cannot be read leaves the picture the `.sad` stored, marked broken, and the
## corner says so.
static func _reopen(document: SaDocument) -> Variant:
    var made: Dictionary[SaSharedSource, SaLinkedFile] = {}
    var any := false
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null or not layer.has_meta(ENTRY):
            continue
        var entry := SaTyped.strings(layer.get_meta(ENTRY))
        layer.remove_meta(ENTRY)
        var shared := SaSharedSource.of(layer)
        var held: SaLinkedFile = made.get(shared, null) if shared != null else null
        if held == null:
            held = _relinked(document, layer, entry)
            if shared != null:
                made[shared] = held
        var before := SaLiveTransform.of(layer)
        var after := SaLiveTransform.new(before.matrix, before.crop, true, held)
        before.release()
        layer.live_transform = after
        SaSharedSource.relink(layer, before, after)
        layer.mark_all_unresolved()
        any = true
    if any:
        document.invalidate_all_allocated_chunks()
        document.update_caches()
        _watch_over(document)
    return null


## The link *entry* names for *layer*, read from the first of its relative and
## absolute forms that is there, or holding the stored picture and broken.
static func _relinked(document: SaDocument, layer: SaLayer, entry: Dictionary[String, Variant]) -> SaLinkedFile:
    var written := SaTyped.text_at(entry, "path", "")
    var absolute := SaTyped.text_at(entry, "absolute", written)
    var written_relative: bool = entry.get("relative", true) == true
    var here := _of(document)
    var tries: Array[String] = []
    if written.is_relative_path() and not here.file.is_empty():
        tries.append(here.file.get_base_dir().path_join(written).simplify_path())
    elif not written.is_empty():
        tries.append(written)
    if not absolute.is_empty() and not tries.has(absolute):
        tries.append(absolute)
    # The picture the link had when it was saved, the stored paint with what
    # lay under its strokes put back, kept as it is while the file cannot be read.
    var was := SaLinkedOverride.stored(entry, layer.chunks, layer.schema, here.blobs)
    for file in tries:
        if not FileAccess.file_exists(file):
            continue
        var read: Variant = _read(document, layer, file)
        if read is String:
            var said: String = read
            SaProblems.report(
                RELOAD, TranslationServer.translate("The linked layer '%s' could not read its file. %s") % [layer.name, said]
            )
            return SaLinkedFile.new(layer.chunks, file, written_relative, UNREADABLE, said, _kept(was))
        # The strokes the `.sad` stored stay over what the file holds now.
        var picture: Dictionary[Vector2i, SaChunk] = read
        var painted := SaLinkedOverride.new(was).kept_over(layer.chunks, picture, layer.schema)
        return SaLinkedFile.new(painted, file, written_relative, "", "", SaLinkedOverride.new(picture))
    var kept := absolute if not absolute.is_empty() else (tries[0] if not tries.is_empty() else written)
    var why := TranslationServer.translate("'%s' is not there any more. The layer keeps the last picture.") % kept
    SaProblems.report(RELOAD, TranslationServer.translate("The linked layer '%s' lost its file. %s") % [layer.name, why])
    return SaLinkedFile.new(layer.chunks, kept, written_relative, MISSING, why, _kept(was))


## The override of a link whose file cannot be read, over a copy of *was*, the
## picture it had when it was saved.
static func _kept(was: Dictionary[Vector2i, SaChunk]) -> SaLinkedOverride:
    return SaLinkedOverride.new(SaLinkedOverride.apart(was))


## *file*, absolute, written relative to the folder *folder*, or as it is when
## the two share no root, a second drive on Windows.
static func _relative_to(folder: String, file: String) -> String:
    var from := folder.simplify_path().split("/", false)
    var to := file.get_base_dir().simplify_path().split("/", false)
    var rooted := folder.begins_with("/") == file.begins_with("/")
    if not rooted or (not from.is_empty() and not to.is_empty() and from[0].ends_with(":") and from[0] != to[0]):
        return file
    var common := 0
    while common < from.size() and common < to.size() and from[common] == to[common]:
        common += 1
    var parts: PackedStringArray = []
    for _up in range(common, from.size()):
        parts.append("..")
    parts.append_array(to.slice(common))
    parts.append(file.get_file())
    return "/".join(parts)


## Hands *document* to the watch, made under the tree's root the first time.
static func _watch_over(document: SaDocument) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or document == null:
        return
    if _watch == null or not is_instance_valid(_watch):
        _watch = Watch.new()
        _watch.name = "SaLinkedFileWatch"
        tree.root.add_child.call_deferred(_watch)
    _watch.hold(document)


## Looks at the linked files of every document it holds when the window
## regains the focus, which the tree hands every node, and on a slow timer.
class Watch:
    extends Node

    var _documents: Array[WeakRef] = []

    func _ready() -> void:
        var timer := Timer.new()
        timer.wait_time = SaLinkedFile.WATCH_SECONDS
        timer.autostart = true
        timer.timeout.connect(look)
        add_child(timer)

    func hold(document: SaDocument) -> void:
        for held: WeakRef in _documents:
            if held.get_ref() == document:
                return
        _documents.append(weakref(document))

    func _notification(what: int) -> void:
        if what == NOTIFICATION_APPLICATION_FOCUS_IN:
            look()

    func look() -> void:
        for held: WeakRef in _documents.duplicate():
            var found: Object = held.get_ref()
            var document := found as SaDocument
            if document == null:
                _documents.erase(held)
            else:
                SaLinkedFile.check(document)


## The `.sad` one save or open of one document is writing or reading: its
## absolute path, which a relative link is relative to, and its blobs, which
## the picture under a link's strokes is stored in.
class Beside:
    extends RefCounted

    ## The absolute path, or empty for a save to no file. Set in the constructor.
    var file := ""
    ## The blobs. Set in the constructor.
    var blobs := PackedByteArray()

    func _init(path: String, held: PackedByteArray) -> void:
        file = path
        blobs = held
