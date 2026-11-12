## What Export Effects as LUT bakes: the colour change a node's effects make,
## measured on a scratch document and read back as a table.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The pass list is made once, the table at each size asked.** Built over a node,
## this walks what the node holds in stack order and keeps every enabled,
## visible effect a table can carry: its attached filters whose pass reads its
## own texel alone, the adjustment layers with their opacity and blend mode,
## and the groups between them that let their layers through. Everything else
## is named in [member left_out] in the painter's words, the painted layers,
## the masks, the filters that read their neighbours, a group that blends on
## its own and an effect layer, so the dialog can say what the file does not
## carry before it is written.
##
## **The table is measured, never derived.** [method bake] makes a document of
## its own in the source's colour space, whose only paint is the identity
## lattice, every point of the table's grid once, red running fastest along a
## row, green down it and blue from one square to the next. The effects kept
## are copied over it, the document is composited once by a compositor of its
## own that shares the app's blend modes and filters, and the output is read
## back once, which is the export rule's one read. Nothing is read during a
## stroke and the painter's document is not touched (hard rules 1 and 2,
## no CPU-GPU ping-pong and dirty-rect dispatch only).
##
## **Its values are the ones Filter > Colour > LUT feeds a table**, the
## document's RGB view: the stored values of an RGB document, and the curve's
## RGB of an Oklab one, taken there and back exactly as `lut.gmacs` does. So a
## file written here and loaded by that filter on the same document gives the
## picture the effects give.
##
## **A second lattice sits elsewhere on the scratch**, at another place in the
## chunk grid. A filter that reads its own texel alone may still change with
## where the texel is, a grain or a noise, and a table cannot carry that.
## When the two lattices disagree past a step of eight bits, [member moved] is
## set and the dialog says so.
extends RefCounted

## Where the second lattice starts, off the first by an amount no chunk side
## divides, so the two land at different places within their chunks too.
const SECOND := Vector2i(37, 300)

## How far the two lattices may differ before the effects count as changing
## with the place in the picture, one step of eight bits.
const PLACE_TOLERANCE := 1.0 / 255.0

## One line for each thing the node holds that the table leaves out, in stack
## order, in the painter's words.
var left_out: PackedStringArray = PackedStringArray()

## Whether the last [method bake] found the effects change with the place in
## the picture.
var moved: bool = false

## The worst difference between the two lattices of the last bake.
var place_difference: float = 0.0

var _source: SaDocument
var _node: SaLayer
## The source's compositor, whose blend modes and filters the scratch shares,
## and its colour space.
var _compositor: SaCompositor
var _space: SaColorSpace
## The scratch's stack, bottom first: one dictionary per layer, `lattice` for
## the paint, `from` the layer it copies otherwise, `records` the filters it
## keeps as key and values, `parent` the source group it sits in or null.
var _recipe: Array[Dictionary] = []
## Whether the top group's copy blends on its own, which puts the lattice
## inside it rather than under it.
var _top_isolates: bool = false


func _init(source: SaDocument, node: SaLayer) -> void:
    _source = source
    _node = node
    if source != null:
        _compositor = source.compositor
        _space = source.color_space
    if source != null and node != null:
        _plan(node)


## Whether there is anything to measure: a node with an effect kept.
func carries_anything() -> bool:
    for entry in _recipe:
        if not entry.get("lattice", false) and (not (entry["records"] as Array).is_empty() or _changes(entry)):
            return true
    return false


## The table of *size* a side, size cubed entries of three floats, red running
## fastest then green then blue, in the RGB view. Empty when the scratch could
## not be composited.
func bake(size: int) -> PackedFloat32Array:
    var side := size * size
    var canvas := Vector2i(side + SECOND.x, SECOND.y + size)
    var space := _scratch_space()
    var compositor := SaCompositor.new()
    if _compositor != null:
        compositor.set_registry(_compositor.registry)
        compositor.blend_modes = _compositor.blend_modes.duplicate()
        compositor.filter_chain.registry = _compositor.filter_chain.registry
    var easel := SaEasel.create_default(canvas, compositor, space)
    var doc := easel.document
    for child in doc.get_children():
        if child is SaLayer:
            doc.remove_child(child)
            child.free()
    var lattice := _build(doc, space)
    if lattice != null:
        _fill_lattice(lattice, size, space)
        doc.set_active_layer(lattice)
    doc.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    var picture := SaExport.get_texture_image_float(easel.output)
    if picture == null:
        easel.free()
        return PackedFloat32Array()
    var read := Texels.new(picture)
    var out := PackedFloat32Array()
    out.resize(3 * side * size)
    place_difference = 0.0
    for b in size:
        for g in size:
            for r in size:
                var first := _to_view(space, read.at(Vector2i(r + b * size, g)))
                var second := _to_view(space, read.at(SECOND + Vector2i(r + b * size, g)))
                var i := 3 * (r + g * size + b * side)
                out[i] = first.r
                out[i + 1] = first.g
                out[i + 2] = first.b
                place_difference = maxf(place_difference, _apart(first, second))
    moved = place_difference > PLACE_TOLERANCE
    easel.free()
    return out


## The text of a `.cube` file holding *entries*, a table of *size* a side as
## [method bake] answers it, titled *title*. The domain is 0 to 1, the rows red
## fastest, the numbers at six places, which is finer than any eight or ten
## bit grade the readers apply it at.
static func cube_text(entries: PackedFloat32Array, size: int, title: String) -> String:
    var lines := PackedStringArray()
    lines.append("# Written by Sara, Export Effects as LUT")
    lines.append('TITLE "%s"' % title.replace('"', "'"))
    lines.append("LUT_3D_SIZE %d" % size)
    lines.append("DOMAIN_MIN 0.0 0.0 0.0")
    lines.append("DOMAIN_MAX 1.0 1.0 1.0")
    for index in range(0, entries.size(), 3):
        lines.append("%.6f %.6f %.6f" % [entries[index], entries[index + 1], entries[index + 2]])
    return "\n".join(lines) + "\n"


func _plan(node: SaLayer) -> void:
    if node.mask != null:
        left_out.append(tr("The mask on '%s', which says where its effects show.") % node.name)
    if node.clip_to_below:
        left_out.append(tr("The clip of '%s' to the layer below it.") % node.name)
    if node.is_group:
        var records := _kept(node, node.filters)
        _top_isolates = node.isolated or not records.is_empty()
        if _top_isolates and (node.opacity < 1.0 or node.blend_mode != SaLayer.BLEND_MODE.NORMAL):
            left_out.append(tr("The opacity and blend mode of '%s', which mix its own layers with what is under it.") % node.name)
        _recipe.append({"lattice": true, "records": [], "parent": node if _top_isolates else null})
        _members(node)
        _recipe.append({"from": node, "records": records, "parent": null})
        return
    if node.is_adjustment():
        _recipe.append({"lattice": true, "records": [], "parent": null})
        _recipe.append({"from": node, "records": _kept(node, node.filters), "parent": null})
        return
    left_out.append(tr("The paint of '%s' itself, which the filters on it run over.") % node.name)
    _recipe.append({"lattice": true, "records": _kept(node, node.filters), "parent": null})


## The members of *group*, bottom first, kept or named.
func _members(group: SaLayer) -> void:
    for member in SaLayerStack.members(_source, group):
        if not member.visible:
            continue
        if member.is_group:
            if SaLayerStack.isolates(member):
                var alone := tr("'%s', a group that blends on its own, so its effects reach only its own layers.")
                left_out.append(alone % member.name)
                continue
            _members(member)
            _recipe.append({"from": member, "records": [], "parent": group})
        elif member.is_adjustment():
            if member.mask != null:
                var masked := tr("'%s', an adjustment layer with a mask, which changes only part of the picture.")
                left_out.append(masked % member.name)
            elif member.clip_to_below:
                left_out.append(tr("'%s', an adjustment layer clipped to the layer below it.") % member.name)
            else:
                var records := _kept(member, member.filters)
                var entry := {"from": member, "records": records, "parent": group}
                if not records.is_empty() or _changes(entry):
                    _recipe.append(entry)
        elif member.is_effect():
            left_out.append(tr("'%s', an effect layer, which reads another layer rather than the colour under it.") % member.name)
        else:
            left_out.append(tr("'%s', a painted layer.") % member.name)


## The records of *records* a table carries, as key and values, naming the
## rest. A record switched off is passed over, since it changes nothing.
func _kept(node: SaLayer, records: Array[SaAttachedFilter]) -> Array:
    var out: Array = []
    var chain := _compositor.filter_chain if _compositor != null else null
    for record in records:
        if record == null or not record.enabled:
            continue
        var title := _title(record)
        if record.mask != null:
            left_out.append(tr("%s on '%s', a filter with a mask, which changes only part of the picture.") % [title, node.name])
            continue
        var made: SaPointPass = chain.pass_for(_source, node, record) if chain != null else null
        if made == null:
            left_out.append(tr("%s on '%s', which no installed module runs.") % [title, node.name])
        elif made is SaNeighbourhoodPass:
            left_out.append(tr("%s on '%s', which reads the pixels around each pixel.") % [title, node.name])
        else:
            out.append([record.key, record.parameters.duplicate(true)])
    return out


func _title(record: SaAttachedFilter) -> String:
    var registry := _compositor.filter_chain.registry if _compositor != null else null
    var filter := registry.get_filter(record.key) if registry != null else null
    return "'%s'" % (filter.translated_title() if filter != null else String(record.key))


## Whether an adjustment layer *entry* copies changes the picture with no
## record to run, which a blend mode other than Normal does.
static func _changes(entry: Dictionary) -> bool:
    var from := entry.get("from") as SaLayer
    return from != null and from.is_adjustment() and from.blend_mode != SaLayer.BLEND_MODE.NORMAL


## The scratch's space: the source's, at 32 bit float where it can be, so the
## measurement adds no rounding of its own.
func _scratch_space() -> SaColorSpace:
    var space := _space if _space != null else SaColorSpace.srgb()
    if SaColorSpace.storage_supports_depth(SaColorSpace.Depth.F32):
        space = space.with_depth(SaColorSpace.Depth.F32)
    return space


## Every layer of the recipe put into *doc*, bottom first, answering the
## lattice. The top group's copy is pass-through unless the source's records
## or flag isolate it, and then it is at full opacity in Normal, because its
## own mix is with what lies outside it.
func _build(doc: SaDocument, space: SaColorSpace) -> SaLayer:
    var copies: Dictionary[SaLayer, SaLayer] = {}
    var lattice: SaLayer = null
    var placed: Array[Array] = []
    for entry in _recipe:
        var layer := SaLayer.new()
        var from := entry.get("from") as SaLayer
        if entry.get("lattice", false):
            layer.name = "Lattice"
            layer.schema = SaFieldSpec.schema_for_space(space)
            lattice = layer
        elif from.is_group:
            layer.name = "Group %d" % copies.size()
            layer.is_group = true
            var top := from == _node
            layer.isolated = top and _top_isolates
            layer.opacity = 1.0 if top and _top_isolates else from.opacity
            layer.blend_mode = SaLayer.BLEND_MODE.NORMAL if top and _top_isolates else from.blend_mode
            copies[from] = layer
        else:
            layer.name = "Adjustment %d" % copies.size()
            layer.layer_type = SaBackdropLayer.TYPE_ID
            layer.input = SaLayerTypeDescriptor.INPUT_BELOW
            layer.schema = SaFieldSpec.schema_for_space(space)
            layer.opacity = from.opacity
            layer.blend_mode = from.blend_mode
            copies[from] = layer
        for kept: Array in entry["records"]:
            layer.filters.append(SaAttachedFilter.new(kept[0], (kept[1] as Dictionary).duplicate(true)))
        doc.add_child(layer)
        placed.append([layer, entry.get("parent")])
    # A group sits above its members, so a member's parent is copied after it.
    for pair in placed:
        var parent := pair[1] as SaLayer
        (pair[0] as SaLayer).group = copies.get(parent, null) if parent != null else null
    return lattice


## Both lattices of *size* a side written into *layer*'s chunks, as the RGB
## view's grid points carried into what *space* stores.
func _fill_lattice(layer: SaLayer, size: int, space: SaColorSpace) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var first := layer.get_or_create_chunk(Vector2i.ZERO).field(SaFieldSpec.ALBEDO)
    var side := first.size
    var lattice_size := Vector2i(size * size, size)
    var wanted: Dictionary[Vector2i, bool] = {}
    for origin: Vector2i in [Vector2i.ZERO, SECOND]:
        var low := Vector2i(floori(origin.x / float(side.x)), floori(origin.y / float(side.y)))
        var far := origin + lattice_size - Vector2i.ONE
        var high := Vector2i(floori(far.x / float(side.x)), floori(far.y / float(side.y)))
        for gy in range(low.y, high.y + 1):
            for gx in range(low.x, high.x + 1):
                wanted[Vector2i(gx, gy)] = true
    for grid_pos: Vector2i in wanted:
        var texture := layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
        var values := PackedFloat32Array()
        values.resize(side.x * side.y * 4)
        for y in side.y:
            for x in side.x:
                var at := grid_pos * side + Vector2i(x, y)
                var local := at if _inside(at, lattice_size) else at - SECOND
                if not _inside(local, lattice_size):
                    continue
                var view := Color(local.x % size, local.y, floori(local.x / float(size))) / float(size - 1)
                var stored := _from_view(space, Color(view.r, view.g, view.b, 1.0))
                var i := (y * side.x + x) * 4
                values[i] = stored.r
                values[i + 1] = stored.g
                values[i + 2] = stored.b
                values[i + 3] = 1.0
        rd.texture_update(texture.rid, 0, values.to_byte_array())


static func _inside(at: Vector2i, size: Vector2i) -> bool:
    return at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y


static func _apart(a: Color, b: Color) -> float:
    return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


## A colour of the RGB view `lut.gmacs` reads as *space* stores it: itself in
## an RGB document, and through the curve, the gamut and Oklab in an Oklab one.
static func _from_view(space: SaColorSpace, view: Color) -> Color:
    if space.coordinates != SaColorSpace.Coordinates.OKLAB:
        return view
    var curve := space.transfer
    var encoded := Vector3(view.r, view.g, view.b)
    var linear := encoded if curve == null else Vector3(curve.decode(view.r), curve.decode(view.g), curve.decode(view.b))
    var lab := SaOklab.from_linear_srgb(space.to_linear_srgb_matrix() * linear)
    return Color(lab.x, lab.y, lab.z, view.a)


## The inverse, a stored colour as the RGB view.
static func _to_view(space: SaColorSpace, stored: Color) -> Color:
    if space.coordinates != SaColorSpace.Coordinates.OKLAB:
        return stored
    var curve := space.transfer
    var linear: Vector3 = space.from_linear_srgb_matrix() * SaOklab.to_linear_srgb(Vector3(stored.r, stored.g, stored.b))
    if curve == null:
        return Color(linear.x, linear.y, linear.z, stored.a)
    return Color(curve.encode(linear.x), curve.encode(linear.y), curve.encode(linear.z), stored.a)


## The output read back once, through the export's float read, and asked
## texel by texel. A picture of four floats is read as one array, which is the
## scratch's own format and the fast case.
class Texels:
    extends RefCounted

    var _picture: Image
    var _floats: PackedFloat32Array
    var _width: int

    func _init(picture: Image) -> void:
        _picture = picture
        _width = picture.get_width()
        if picture.get_format() == Image.FORMAT_RGBAF:
            _floats = picture.get_data().to_float32_array()

    func at(point: Vector2i) -> Color:
        if _floats.is_empty():
            return _picture.get_pixelv(point)
        var index := (point.y * _width + point.x) * 4
        return Color(_floats[index], _floats[index + 1], _floats[index + 2], _floats[index + 3])
