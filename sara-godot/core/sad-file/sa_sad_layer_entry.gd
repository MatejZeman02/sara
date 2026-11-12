## One layer's entry in a `.sad` header, written and read back.
##
## **What it owns.** Every key a layer's entry carries but its chunks: what the
## painter set on the layer, its type and the type's own keys, its field
## schema, its mask, its attached filters, the modules' slices, the name of its
## group and the simulation a rule steps it by, with that simulation's seed. The
## writer and the reader come here for all of it.
##
## **What it leaves.** The header around the entries, the version a document is
## stamped with and the chunks' blobs stay in `SaSadFile`, which writes a
## layer's chunks into the entry `write` returns and reads them back into the
## layer `read` makes once it is in the document. A mask and a filter go to
## disk through `SaSadFile.write_mask` and `SaSadFile.write_filters`, the one
## writer of each, which the document's root shares with every layer.
##
## **Why a class.** A layer's entry is where a new key of a layer lands, so it
## owns the keys of a layer apart from the writer of the file, which every new
## key would otherwise grow.
class_name SaSadLayerEntry
extends RefCounted


## The entry for *layer*, every key but `"chunks"`, which the writer adds. A
## mask holding chunks of its own and a filter's mask append their blobs to
## *blobs* here, before the writer appends the layer's chunks, which is the
## order a file has always held them in.
static func write(layer: SaLayer, blobs: PackedByteArray, rd: RenderingDevice) -> Dictionary[String, Variant]:
    var layer_dict: Dictionary[String, Variant] = {
        # As the painter typed it. The node's own name is this with the
        # characters the engine refuses as underscores, so an older build that
        # takes it as a node name lands on the same node name as this one.
        "name": layer.shown_name(),
        "visible": layer.visible,
        "opacity": layer.opacity,
        "is_locked": layer.is_locked,
        "alpha_locked": layer.alpha_locked,
        "clip_to_below": layer.clip_to_below,
        "is_group": layer.is_group,
        "isolated": layer.isolated,
        "blend_mode": str(layer.blend_mode),
        # Additive to v4, so no version bump and no second reader. Empty and
        # 1.0 for a plain layer at the document's resolution, which is what a
        # file written before either key existed reads as.
        "layer_type": str(layer.layer_type),
        "resolution_scale": layer.resolution_scale,
        "schema": _serialize_schema(layer.schema),
    }
    # Additive, and written only when there is one: a document whose layers
    # carry no note is byte for byte the file it was before comments existed,
    # and an older build carries the key through untouched the way it carries
    # a module's slice.
    if not layer.comment.is_empty():
        layer_dict["comment"] = layer.comment
    # The row's colour, written the same way: a document with no colour on any
    # row is the file it was before colours existed.
    if not layer.color_tag.is_empty():
        layer_dict["color_tag"] = str(layer.color_tag)
    # Additive and written only for a folded group, the same way: a file with
    # every group open is the file it was before folds were kept, and a file
    # without the key opens with every group open.
    if layer.is_group and layer.folded:
        layer_dict["folded"] = true
    # Additive and written only when on, the same way: a file without the key
    # opens with Affect all off, which is what every layer read as before it.
    if layer.affects_all:
        layer_dict["affects_all"] = true

    # Additive too: the parameters of a layer that stores nothing, and a scene
    # layer's path and parameters in place of its chunks. An older build reads
    # no chunks for either, and shows the layer empty.
    if layer.is_generated():
        layer_dict["generator"] = SaGeneratedLayer.params_to_json(layer.generator_params)
    SaEffectLayer.write_input(layer, layer_dict)
    SaSceneLayer.write_header(layer, layer_dict)
    SaSadDrawn.write_header(layer, layer_dict)
    SaLiveTransform.write_header(layer, layer_dict)

    # What the layer hides, and the key that makes the file version 5. A layer's
    # own mask is a field of the chunks the writer adds, so the key carries the
    # flag alone, and a group's carries its chunks.
    if layer.mask != null:
        layer_dict["mask"] = SaSadFile.write_mask(layer.mask, blobs, rd)

    # The filters attached under the layer, bottom first. Absent for a layer
    # with none, which is every file written before the key existed.
    if not layer.filters.is_empty():
        layer_dict["filters"] = SaSadFile.write_filters(layer.filters, blobs, rd)

    # Per-layer module state. Kubelka-Munk is a layer type rather than a
    # document mode, so what a layer's concentration channels mean is a fact
    # about that layer.
    var layer_modules := SaSadFile.canonical_module_data(layer.module_data)
    if not layer_modules.is_empty():
        layer_dict["modules"] = layer_modules
    # The parent's name, additive: an older build ignores it and reads the stack
    # flat, with the group as an empty layer. Names are unique in a document,
    # which is what makes the name an id. The node's name rather than the shown
    # one, because the join on load and every older build match node names.
    if layer.group != null and is_instance_valid(layer.group):
        layer_dict["group"] = str(layer.group.name)
    _write_simulation(layer, layer_dict, blobs, rd)
    return layer_dict


## The simulation on *layer* under `"simulation"` in *layer_dict*, or no key for
## a layer no rule steps: the rule's key, the id of the module that registered
## it, its parameters, the count of steps, the speed, the domain when the
## painter set one, the grid positions the last ring left and the seed, one Zstd
## blob per chunk appended to *blobs* and addressed the way a chunk's field is,
## with its size and format beside it since the seed outlives the chunks it was
## copied from. The layer's chunks, which the writer adds, are the state at that
## count, so the document opens where it was left and Reset still reaches the
## seed. The parameters go through the JSON fixed point a filter's do, so a
## record whose module is missing is written back as it was read.
static func _write_simulation(
    layer: SaLayer, layer_dict: Dictionary[String, Variant], blobs: PackedByteArray, rd: RenderingDevice
) -> void:
    var record := SaSimulation.record_of(layer)
    if record == null:
        return
    var seed_written: Array = []
    for grid_pos: Vector2i in record.seed_chunks:
        var texture: SaTexture = record.seed_chunks[grid_pos]
        if texture == null or not texture.rid.is_valid():
            continue
        var slot := SaSadBlob.write(texture, blobs, rd)
        if slot.is_empty():
            continue
        slot.merge(
            {"x": grid_pos.x, "y": grid_pos.y, "width": texture.size.x, "height": texture.size.y, "format": texture.format}
        )
        seed_written.append(slot)
    var ringed: Array = []
    for grid_pos: Vector2i in record._ringed:
        ringed.append([grid_pos.x, grid_pos.y])
    var entry: Dictionary[String, Variant] = {
        "rule": String(record.rule),
        "module": String(record.module),
        "params": SaSadFile.canonical_module_data(record.params),
        "steps": record.steps,
        "speed": record.speed,
        "ringed": ringed,
        "seed": seed_written,
    }
    if record.domain.has_area():
        entry["domain"] = [record.domain.position.x, record.domain.position.y, record.domain.size.x, record.domain.size.y]
    layer_dict["simulation"] = entry


## The record *layer_data*'s `"simulation"` key describes, put back on *layer*,
## its seed read out of *blobs* at *color_format*, the format of the layer's
## `albedo`. Nothing for an entry with no such key, which is every file written
## before the key and every layer no rule steps. The rule is not looked up: a
## rule whose module is missing keeps its record as data, the layer shows its
## paint, and the next save writes the record back unchanged. A seed chunk
## whose blob is out of range, will not decompress or is not the colour
## format's size is left out, so Reset leaves that chunk as it stands.
static func _read_simulation(
    layer: SaLayer, layer_data: Dictionary[String, Variant], blobs: PackedByteArray, color_format: int
) -> void:
    var raw_entry: Variant = layer_data.get("simulation", null)
    if not raw_entry is Dictionary:
        return
    var entry := SaTyped.strings(raw_entry)
    var rd := GlobalShaderCompiler.get_rd()
    var kept: Dictionary[Vector2i, SaTexture] = {}
    for raw_slot: Variant in SaTyped.list(entry.get("seed")):
        var slot := SaTyped.strings(raw_slot)
        var grid_pos := Vector2i(SaTyped.int_at(slot, "x", 0), SaTyped.int_at(slot, "y", 0))
        var size := Vector2i(SaTyped.int_at(slot, "width", 0), SaTyped.int_at(slot, "height", 0))
        var offset := SaTyped.int_at(slot, "offset", 0)
        var packed := SaTyped.int_at(slot, "size", 0)
        var want := size.x * size.y * SaTyped.whole(SaFieldSpec.BYTES_PER_TEXEL.get(color_format, 0))
        if rd == null or size.x <= 0 or size.y <= 0 or packed <= 0 or offset + packed > blobs.size():
            push_warning("SaExport.load_sad: a seed chunk of '%s' is out of range" % layer.name)
            continue
        if SaTyped.int_at(slot, "format", color_format) != color_format or SaTyped.int_at(slot, "raw_size", 0) != want:
            push_warning("SaExport.load_sad: a seed chunk of '%s' is not the document's colour format" % layer.name)
            continue
        var bytes := SaSadBlob.read(slot, blobs)
        if bytes.size() != want:
            push_warning("SaExport.load_sad: a seed chunk of '%s' failed to decompress" % layer.name)
            continue
        var texture := SaTexture.new(size, color_format)
        SaSadBlob.upload(texture, bytes, SaSadBlob.is_planes(slot))
        kept[grid_pos] = texture
    var ringed: Array[Vector2i] = []
    for raw_pos: Variant in SaTyped.list(entry.get("ringed")):
        var pair := SaTyped.list(raw_pos)
        if pair.size() == 2:
            ringed.append(Vector2i(SaTyped.whole(pair[0]), SaTyped.whole(pair[1])))
    var rule_key := SaTyped.name_at(entry, "rule", &"")
    var module_id := SaTyped.name_at(entry, "module", &"")
    var record := SaSimulation.reopen(layer, rule_key, module_id, SaTyped.strings(entry.get("params")), kept, ringed)
    if record == null:
        push_warning("SaExport.load_sad: the simulation on '%s' names no rule or the layer takes none" % layer.name)
        return
    record.steps = maxi(SaTyped.int_at(entry, "steps", 0), 0)
    var speed := SaTyped.float_at(entry, "speed", SaSimulation.DEFAULT_SPEED)
    record.speed = clampf(speed, SaSimulation.SLOWEST, SaSimulation.FASTEST)
    var domain := SaTyped.list(entry.get("domain"))
    if domain.size() == 4:
        record.domain = Rect2i(
            SaTyped.whole(domain[0]), SaTyped.whole(domain[1]), SaTyped.whole(domain[2]), SaTyped.whole(domain[3])
        )


## The layer a v4 file's *layer_data* describes, with every key but its chunks,
## which the reader adds once the layer is in the document. A colour field
## takes *color_format*, the document's, whatever the entry records of it.
static func read(layer_data: Dictionary[String, Variant], blobs: PackedByteArray, color_format: int) -> SaLayer:
    var layer := layer_from(layer_data)
    var loaded_schema := _deserialize_schema(layer_data.get("schema", []))
    # A colour field's format is the document's, never the file's own record of
    # it: a stale or hand-edited schema whose colour field disagrees with the
    # header's depth allocates chunks the compositor then refuses to composite
    # ("one dispatch cannot serve both"), and the layer silently never draws.
    # Non-colour fields keep whatever precision the file recorded, since that is
    # the layer type's own business, not the document's.
    for spec in loaded_schema:
        if spec.is_color:
            spec.format = color_format
    layer.schema = loaded_schema
    # The schema's setter gave the layer a mask when the file's schema carries
    # the field, a hand-written v4 file included, and the key holds what the
    # schema cannot: the flag, and for a group the chunks.
    var raw_mask: Variant = layer_data.get("mask", null)
    if raw_mask is Dictionary:
        var mask_entry := SaTyped.strings(raw_mask)
        if mask_entry.has("chunks"):
            layer.mask = SaSadFile.read_mask(mask_entry, blobs)
        elif layer.mask != null:
            layer.mask.enabled = SaTyped.bool_at(mask_entry, "enabled", true)
            layer.mask.rest = SaTyped.float_at(mask_entry, "rest", 1.0)
    # Here and not in `layer_from`, which has no blobs to read a filter's
    # mask out of.
    layer.filters = SaSadFile.read_filters(layer_data.get("filters", null), blobs)
    # After the schema, which says whether the layer stores paint a rule steps,
    # and before the chunks, which the reader adds and are the state at the
    # record's step.
    _read_simulation(layer, layer_data, blobs, color_format)
    return layer


## A layer made from the keys of its entry, every key but
## its schema, its mask, its records and its chunks, which the reader adds.
static func layer_from(layer_data: Dictionary[String, Variant]) -> SaLayer:
    var layer := SaLayer.new()
    layer.take_name(SaTyped.text_at(layer_data, "name", "Layer"))
    layer.visible = layer_data.get("visible", true)
    layer.opacity = layer_data.get("opacity", 1.0)
    layer.is_locked = layer_data.get("is_locked", false)
    layer.alpha_locked = layer_data.get("alpha_locked", false)
    layer.clip_to_below = layer_data.get("clip_to_below", false)
    layer.is_group = layer_data.get("is_group", false)
    layer.isolated = layer_data.get("isolated", false)
    layer.folded = layer.is_group and SaTyped.bool_at(layer_data, "folded", false)
    layer.affects_all = SaTyped.bool_at(layer_data, "affects_all", false)
    layer.blend_mode = SaLayer.blend_mode_from_legacy(layer_data.get("blend_mode", SaLayer.BLEND_MODE.NORMAL))
    # Absent in every file written before layer types, and in every layer of a
    # document that only ever had plain ones. The id is kept even when nothing
    # can resolve it, so a document opened on a build without the module that
    # owns the type writes that type back out on the next save.
    layer.layer_type = SaTyped.name_at(layer_data, "layer_type", "")
    # Absent in every file written before notes existed, and in every layer
    # nobody wrote a note on, which is what the empty default reads as.
    layer.comment = SaTyped.text_at(layer_data, "comment", "")
    # Absent in every file written before row colours, which reads as No
    # Colour, and a colour this build does not know reads as none too.
    layer.color_tag = SaLayerColorTag.known(SaTyped.name_at(layer_data, "color_tag", ""))
    # Nothing paints a layer below 1.0 yet, so one is opened at 1.0 and said.
    layer.resolution_scale = SaSadCoarseLayer.opened_scale(layer.name, SaTyped.float_at(layer_data, "resolution_scale", 1.0))
    if layer_data.has("generator"):
        layer.generator_params = SaGeneratedLayer.params_from_json(layer_data["generator"])
    SaEffectLayer.read_input(layer, layer_data)
    SaSceneLayer.read_header(layer, layer_data)
    SaSadDrawn.read_header(layer, layer_data)
    SaLiveTransform.read_header(layer, layer_data)
    # Kept as a name until every layer exists, then joined in
    # `SaSadFile.finish_load`.
    if layer_data.has("group"):
        layer.set_meta("group_name", str(layer_data["group"]))
    # Every module's slice, including the slices of modules this build has never
    # heard of. Kept verbatim so the next save writes them back unchanged.
    layer.module_data = SaTyped.strings(layer_data.get("modules"))
    return layer


## Field schema as it goes to disk. The format is stored per field because a
## reader must not guess it, and derived fields are recorded so a layer loads
## back knowing which of its fields nobody paints.
static func _serialize_schema(schema: Array[SaFieldSpec]) -> Array:
    var out: Array = []
    for spec in schema:
        if spec == null:
            continue
        var sources: Array = []
        for source in spec.derived_from:
            sources.append(String(source))
        var entry := {"id": String(spec.id), "format": spec.format, "is_color": spec.is_color, "derived_from": sources}
        # Only where true, so a schema with no lazy field writes what it wrote
        # before, and a reader that does not know the key allocates the field in
        # every chunk, which costs memory and misreads nothing.
        if spec.lazy:
            entry["lazy"] = true
        out.append(entry)
    return out


## The schema an entry's `"schema"` key describes, or the default one when the
## key is absent, is not a list, or lists nothing.
static func _deserialize_schema(raw: Variant) -> Array[SaFieldSpec]:
    var schema: Array[SaFieldSpec] = []
    if not (raw is Array):
        return SaFieldSpec.default_schema()
    for raw_entry: Variant in raw:
        var entry := SaTyped.strings(raw_entry)
        var sources: Array[StringName] = []
        for source: Variant in entry.get("derived_from", []):
            sources.append(StringName(str(source)))
        # A mask is one format and one blank whatever a file says of it, so the
        # spec comes from its own factory rather than from the entry.
        if SaTyped.name_at(entry, "id", "") == SaFieldSpec.MASK and not SaTyped.bool_at(entry, "is_color", true):
            schema.append(SaFieldSpec.mask())
            continue
        var spec := SaFieldSpec.create(
            SaTyped.name_at(entry, "id", SaFieldSpec.ALBEDO),
            SaTyped.int_at(entry, "format", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT),
            SaTyped.bool_at(entry, "is_color", true),
            sources
        )
        # A lazy field is never colour, so an entry that says both is read as
        # colour, the safer half: allocated everywhere rather than missing.
        if SaTyped.bool_at(entry, "lazy", false) and not spec.is_color:
            spec = SaFieldSpec.sparse(spec.id, spec.format)
        schema.append(spec)
    return schema if not schema.is_empty() else SaFieldSpec.default_schema()
