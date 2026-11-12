## The walk of a document into the header of a save, one layer's entry at a
## time. A save that waits walks every layer at once, through
## `SaSadFile.header_of`, and a save in the background walks a share of the
## stack a turn, [method go_on], since on the seasons file, about 750 layers
## and 9168 blobs, the whole walk took 140 ms of the one frame of its snapshot
## where a frame is to stay under a tenth of a second.
##
## **What a walk in shares counts on.** The head of the header is walked when
## the walk is made, and each later share writes the entries of the next
## layers in the stack as it stood then. Nothing here checks the document:
## `SaSadSave` asks before each share whether it stands where it stood when
## the walk began, and drops the walk and begins again when it does not, so a
## file never holds one layer from before a change and another from after it.
## Each share runs inside the codec and the linked file's place the walk at
## once runs inside, `SaSadCodec.during` and `SaLinkedFile.beside`, since
## both are set only for the length of the call they wrap.
class_name SaSadWalk
extends RefCounted

## The time a share of the walk spends before it hands the turn back, in
## microseconds. It ends at the first layer past it, so a share always walks
## one layer at least, and a suite sets it to 0 to walk a layer a turn.
static var usec_a_turn := 30000

## The header so far, its head whole and the entries of the layers walked.
var header: Dictionary[String, Variant] = {}
## When the walk began, and the turns it has taken, its head's among them.
var began_usec := 0
var turns := 1

var _document: SaDocument = null
var _path := ""
var _blobs := PackedByteArray()
var _rd: RenderingDevice = null
var _codec: SaCodecRegistry.Codec = null
## The layers of the stack as it stood at the walk's start, in order, and the
## next to walk.
var _layers: Array[SaLayer] = []
var _next := 0


## Walks the head of the header of *document*, which the save writes to *path*
## coding its chunks with *codec*, null for Zstd, its blobs appended to
## *blobs*, and notes the layers the shares walk.
func _init(document: SaDocument, path: String, blobs: PackedByteArray, rd: RenderingDevice, codec: SaCodecRegistry.Codec) -> void:
    began_usec = Time.get_ticks_usec()
    _document = document
    _path = path
    _blobs = blobs
    _rd = rd
    _codec = codec
    for child in document.get_children():
        if child is SaLayer:
            _layers.append(child as SaLayer)
    header = _within(SaSadFile.header_head.bind(document, blobs, rd))


## Whether every layer's entry is in [member header].
func is_done() -> bool:
    return _next >= _layers.size()


## Walks the next layers until *usec* went by, and answers whether the walk
## is done. A negative *usec* walks every layer left.
func go_on(usec: int) -> bool:
    turns += 1
    _within(_share.bind(usec))
    return is_done()


func _share(usec: int) -> Variant:
    var until := Time.get_ticks_usec() + usec
    var written: Array = header["layers"]
    while _next < _layers.size():
        var layer := _layers[_next]
        _next += 1
        if is_instance_valid(layer):
            written.append(entry_of(layer, _blobs, _rd))
        if usec >= 0 and Time.get_ticks_usec() >= until:
            break
    return null


func _within(work: Callable) -> Variant:
    return SaSadCodec.during(_codec, SaLinkedFile.beside.bind(_document, _path, work, _blobs))


## The entry of *layer* in the header, its chunks' blobs appended to *blobs*.
static func entry_of(layer: SaLayer, blobs: PackedByteArray, rd: RenderingDevice) -> Dictionary[String, Variant]:
    # Every key of the entry but its chunks is `SaSadLayerEntry`'s, and the
    # blobs of its masks go in before the chunks' own below.
    var layer_dict := SaSadLayerEntry.write(layer, blobs, rd)
    var chunks_written: Array = []
    layer_dict["chunks"] = chunks_written
    # A colour worked out from other fields is written as last resolved.
    layer.resolve_pending()
    var stored := SaSadSharedSource.stored_chunks(layer)
    for grid_pos: Vector2i in stored:
        var chunk: SaChunk = stored[grid_pos]
        if chunk == null or SaSadSnapshot.leaves_out(chunk.albedo()):
            continue
        var entry: Dictionary[String, Variant] = {
            "x": grid_pos.x,
            "y": grid_pos.y,
            "resolution_scale": chunk.resolution_scale,
            "fields": {},
        }
        for field_id: StringName in chunk.fields:
            var texture: SaTexture = chunk.fields[field_id]
            if texture == null or not texture.rid.is_valid():
                continue
            # A chunk below 1.0 is stored plain, since it opens widened
            # on the CPU and planes are only undone on the GPU at full size,
            # and so is a mask, where plain wins on most chunks.
            var plain := chunk.resolution_scale < SaSadCoarseLayer.LOWEST_SCALE or field_id == SaFieldSpec.MASK
            var slot := SaSadBlob.write(texture, blobs, rd, plain, true)
            if slot.is_empty():
                continue
            slot["format"] = texture.format
            entry["fields"][String(field_id)] = slot
        chunks_written.append(entry)
    return layer_dict
