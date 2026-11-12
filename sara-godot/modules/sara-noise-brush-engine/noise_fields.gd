## The noise brush's fields: which there are, the rows each puts on the Texture
## page, and what a dispatch binds for the one a stroke uses.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A field is a kernel function or a picture, registered.** Grain and Bristle
## are branches of `noise_field` in `noise_fields.gmacs`, and Picture is any
## pattern the door's `SaPatternStore` holds, tiled. Each is a field of
## [constant ENGINE] on the door's `SaBrushFieldRegistry`, the three built-ins
## registered by the module the way another module's is, and the Texture row,
## its page and a dab's numbers all read what is there. Another module's field
## runs one of these at numbers of its own, or its own kernel, [OwnField].
##
## **One channel or two, per field.** A field says how many it has, and the
## Channels and Relief rows are shown for a field with two. A picture has one,
## because the store decodes every pattern to one grey mask.
##
## **The stroke's offset is a hash of its seed.** [method offset_for] turns the
## seed `SaStrokeInfo` draws once a stroke into a point in a square
## [constant OFFSET_SPAN] pixels wide, so two strokes lay two fields and a held
## seed lays the same one again.
##
## **A field answers in stroke coordinates**: along the path and across it,
## which `noise_fields.gmacs` says in full, so a field bends with the stroke.
##
## **Drift slides the field along the stroke**. The state takes what the Drift
## row has carried the field so far off the travelled length it hands the
## kernel at every point, rather than writing it into the buffer, since the
## buffer is written once a stroke and a stroke has many points.
##
## The numbers a dispatch reads go into a storage buffer rather than the push
## constant, which has 24 bytes left, and are written once a stroke by the
## binding the state holds, `dab_list/noise_field_binding.gd`.
extends RefCounted

## The kernel's branches, the slot a field's kernel is laid in, in the order
## `noise_field` in the library tests them.
const SLOT_GRAIN: int = 0
const SLOT_BRISTLE: int = 1
const SLOT_PICTURE: int = 2
## The kernels this engine has, by the name a field gives, and their slots.
## A field naming any other is passed over, never painted as another, unless it
## brings its own, which [OwnField] builds a pass for, at the slot after these.
const KERNELS: Dictionary = {&"grain": SLOT_GRAIN, &"bristle": SLOT_BRISTLE, SaBrushFieldRegistry.PICTURE: SLOT_PICTURE}
const OwnField = preload("res://modules/sara-noise-brush-engine/field_kernel/noise_own_field.gd")
## The engine a field names to be one of this brush's, on the door's registry.
const ENGINE: StringName = &"noise"

## The built-ins' ids, which a preset stores in `texture_field`, so none of them
## changes once a painter has saved one.
const GRAIN: String = "grain"
const BRISTLE: String = "bristle"
const PICTURE: String = "picture"

## The side of the square a stroke's offset is drawn from, in document pixels.
## Wide enough that two strokes' grains share nothing a painter could line up,
## and small enough that a float still resolves a pixel's hundredth out there.
const OFFSET_SPAN: float = 4096.0

## The buffer's slots, the order `noise_fields.gmacs` names them in. The last
## two are the picture's tone range, where its grey is spread from, and a
## picture's third number, its invert, is the slot a Bristle's length takes.
const SLOT_COUNT: int = 18
const SLOT_INVERT: int = 7
const SLOT_TONE_LOW: int = 9
const SLOT_TONE_HIGH: int = 10
## The brush's look after the field's own numbers, the library's
## `NOISE_FIELD_STRAND_WIDTH` to `NOISE_FIELD_BUILD_UP`: each slot's setting
## and its rest, the number that paints as the brush did before the rows were
## there and that a stand-in buffer holds before a stroke writes its own.
const SLOT_STRAND_WIDTH: int = 11
const SLOT_STRAND_SOFT: int = 12
const SLOT_STRAND_TAPER: int = 13
const SLOT_FILL: int = 14
const SLOT_TONE: int = 15
const SLOT_RIM_FIRM: int = 16
const SLOT_BUILD_UP: int = 17
const LOOK: Dictionary = {
    SLOT_STRAND_WIDTH: [&"strand_width", 1.0],
    SLOT_STRAND_SOFT: [&"strand_softness", 0.5],
    SLOT_STRAND_TAPER: [&"strand_taper", 1.0],
    SLOT_FILL: [&"fill", 0.0],
    SLOT_TONE: [&"texture_tone", 0.0],
    SLOT_RIM_FIRM: [&"rim_firmness", 0.0],
    SLOT_BUILD_UP: [&"build_up", 1.0],
}
## The share of a picture's texels left out at each end of its tone range, so
## a few stray specks do not hold the stretch open.
const TONE_TAIL: float = 0.02
## The most texels along a side the tone range is measured over, a grid laid
## across a larger mask.
const TONE_SAMPLES: int = 128

## The Texture page's title, and the key of the Texture row every field's rows
## hang off.
const PAGE: String = "Texture"
const FIELD_KEY: StringName = &"texture_field"
const CHANNELS_KEY: StringName = &"texture_channels"
const RELIEF_KEY: StringName = &"texture_relief"
const DRIFT_KEY: StringName = &"texture_drift"


## The pattern the settings name for a Picture field, made when it is chosen
## and never at a press.
##
## **The one read of a picture is here.** A generated pattern's grey mask, which
## the texture sensor reads on the CPU at a dab's centre, comes back from
## VRAM through `SaPatternKernel.picture`, a tile of `tile` texels a side, a
## megabyte at the default and 256 MB at the top. It is made here, when a row or
## a preset names the pattern, rather than at the first press after a pick,
## which would read VRAM back inside the stroke, which hard rule 1 (no CPU-GPU ping-pong) keeps the
## readbacks out of, and the press reads what was made.
##
## Held by the settings rather than by a brush's field binding, because the main
## canvas and the scratchpad each hold a brush over the one shared settings, and
## two bindings would read the same tile twice.
class Picture:
    extends RefCounted

    ## The name this was made for, empty until it was.
    var pattern_name: String = ""
    ## The pattern's texture, or null when there is no such pattern or it
    ## could not be made, with [member error] saying which.
    var texture: SaTexture = null
    ## The same pattern as a grey mask on the CPU.
    var mask: Image = null
    var error: String = ""

    ## Makes the texture and the mask of the pattern called *chosen_name* in
    ## *store*. The readback of a generated pattern is this call's, and it is
    ## made once while the name holds.
    func choose(store: SaPatternStore, chosen_name: String) -> void:
        if holds(chosen_name):
            return
        pattern_name = chosen_name
        texture = null
        mask = null
        var pattern: SaPattern = store.pattern(chosen_name) if store != null else null
        if pattern == null:
            error = tr("no pattern called '%s' in either patterns folder.") % chosen_name
            return
        texture = pattern.texture()
        error = pattern.error if texture == null else ""
        # A picture is its own mask. A generated one is read back, a tile of
        # texture and never the canvas, as the chooser's cell is.
        if texture != null:
            mask = pattern.image_at(texture.size.x) if pattern.is_generated() else pattern.mask()

    ## Whether this was made for *chosen_name* and its texture is still alive.
    func holds(chosen_name: String) -> bool:
        return chosen_name == pattern_name and texture != null and texture.rid.is_valid()


## The Pattern row's list, which reads the folders again each time it opens.
##
## The Brush Editor builds its rows each time a page is shown, but the Tool
## Options docker builds its own once, so a list filled when it was built
## would miss a pattern a painter drops into `user://patterns` while Sara runs.
## Filled on the open instead, by a rescan of the module's one store, a listing
## of two folders and no file read, so both surfaces list what is on disk the
## moment the list is looked at.
class PatternList:
    extends SaChoiceButton

    var store: SaPatternStore = null

    func _init(listed: SaPatternStore) -> void:
        super()
        store = listed
        # A choice to the control walker, which moves a made control by name and
        # prefers the one on screen over the docker's hidden copy.
        set_meta(SaMake.KIND_META, SaMake.Kind.CHOICE)
        relist()

    ## Lists every pattern the store finds on disk now, keeping the choice
    ## shown when it is still among them.
    func relist() -> void:
        store.rescan()
        var held: Variant = selected_value()
        var shown := text
        var choices: Array = []
        for pattern_name: String in store.names():
            choices.append({"id": pattern_name, "label": pattern_name})
        set_choices(choices)
        # A refill falls back to the first row when the held name is gone, and
        # the button would show a pattern the stroke does not paint.
        if held == null and not shown.is_empty():
            clear_choice(shown)
        elif held != null and selected_value() != held:
            clear_choice(String(held))

    func toggle_list() -> void:
        if popup != null and not popup.visible and not closed_this_frame():
            relist()
        super()

    ## What the Brush Editor's dump prints for the row: the names listed and
    ## the one shown.
    func capture_option_report() -> Dictionary:
        return {"names": choice_labels(), "shows": text}


## The door's registry this reads its fields from, the module's context's, or
## one of its own for a suite that builds the brush without the module.
var _registry: SaBrushFieldRegistry = null
## The folder of the painter's own fields, `field_folder/noise_field_folder.gd`,
## held weakly, or null for a suite's registry, which has none. The module owns
## the folder, and the folder holds the module's context, whose tool registry
## holds the brush's settings and so these fields. A strong hold here closes
## that ring, and registries dropped by a suite or by the app's exit keep every
## object in it.
var _folder: WeakRef = null


func _init(registry: SaBrushFieldRegistry = null, folder: RefCounted = null) -> void:
    _registry = registry if registry != null else SaBrushFieldRegistry.new()
    _folder = weakref(folder) if folder != null else null


## Reads the painter's folder of fields again, so a file saved since the last
## stroke is what this one paints. Once a stroke, at its start.
func reread() -> void:
    var folder: RefCounted = _folder.get_ref() if _folder != null else null
    if folder != null:
        folder.call("reread")


## Adds *added* for a suite, refused when its id is taken or it is not this
## engine's with a kernel it has. The module registers through its context.
func register(added: SaBrushFieldRegistry.Field) -> bool:
    if added == null or not is_ours(added):
        return false
    return _registry.register(added)


## Whether *candidate* is for this engine with a kernel it has or its own.
static func is_ours(candidate: SaBrushFieldRegistry.Field) -> bool:
    return candidate.engine == ENGINE and (KERNELS.has(candidate.kernel) or OwnField.runs(candidate))


func has(field_id: String) -> bool:
    return field(field_id) != null


## The field called *field_id* with a kernel this engine has, or null.
func field(field_id: String) -> SaBrushFieldRegistry.Field:
    var found := _registry.field(ENGINE, field_id)
    return found if found != null and is_ours(found) else null


## Every field this engine paints, in the order the Texture row lists them.
func all() -> Array[SaBrushFieldRegistry.Field]:
    var out: Array[SaBrushFieldRegistry.Field] = []
    for each: SaBrushFieldRegistry.Field in _registry.fields_for(ENGINE):
        if is_ours(each):
            out.append(each)
    return out


## The field *settings* names, or the first registered when the name is none
## of them, which is what a preset from a later module reads as without it.
func chosen(settings: Resource) -> SaBrushFieldRegistry.Field:
    var found := field(String(settings.get(FIELD_KEY)))
    var known := all()
    if found == null and not known.is_empty():
        return known[0]
    return found


func ids() -> Array:
    return all().map(func(each: SaBrushFieldRegistry.Field) -> String: return each.id)


func labels() -> Array:
    return all().map(func(each: SaBrushFieldRegistry.Field) -> String: return each.label)


## The ids of the fields with two channels, for the rows only those show.
func two_channel_ids() -> Array:
    var out: Array = []
    for each: SaBrushFieldRegistry.Field in all():
        if each.channels > 1:
            out.append(each.id)
    return out


## Every field's rows, each shown only while its field is the chosen one.
##
## Each is remade on the Texture page under its field's heading, rather than
## the registered row changed, so a field's own rows stay as its module made
## them.
func rows() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    for each: SaBrushFieldRegistry.Field in all():
        for spec: SaOptionSpec in each.rows:
            out.append(spec.remade({"page": PAGE, "section": each.label, "shown_when": {"key": FIELD_KEY, "value": each.id}}))
    return out


## The buffer's numbers for a stroke of *settings* laid with *stroke_seed_value*, whose
## Bristle band is *width* pixels across. The order is the library's slots.
func numbers_for(settings: Resource, stroke_seed_value: int, width: float) -> PackedFloat32Array:
    var chosen_field := chosen(settings)
    var out := blank()
    for slot: int in LOOK:
        var value: Variant = settings.get(LOOK[slot][0])
        if value is float or value is int:
            out[slot] = float(value)
    if chosen_field == null:
        return out
    var offset := offset_for(stroke_seed_value)
    var two := chosen_field.channels > 1 and int(settings.get(CHANNELS_KEY)) > 1
    out[0] = float(KERNELS.get(chosen_field.kernel, KERNELS.size()))
    out[1] = 2.0 if two else 1.0
    out[2] = float(settings.get(RELIEF_KEY))
    out[3] = offset.x
    out[4] = offset.y
    for index in mini(chosen_field.numbers.size(), 3):
        out[5 + index] = chosen_field.number(settings, index)
    out[8] = width
    out[SLOT_TONE_LOW] = 0.0
    out[SLOT_TONE_HIGH] = 1.0
    return out


## The buffer's numbers before a stroke writes its own: nought for the field's
## and each of [constant LOOK]'s slots at its rest.
static func blank() -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(SLOT_COUNT)
    for slot: int in LOOK:
        out[slot] = float(LOOK[slot][1])
    return out


## The field's offset for a stroke laid with *stroke_seed_value*: two numbers in 0 to
## [constant OFFSET_SPAN] from a hash of the seed and nothing else, so the same
## seed answers the same offset on every machine.
static func offset_for(stroke_seed_value: int) -> Vector2:
    var random := RandomNumberGenerator.new()
    random.seed = hash([stroke_seed_value, "noise-field"])
    return Vector2(random.randf() * OFFSET_SPAN, random.randf() * OFFSET_SPAN)


## Registers the three fields Sara ships through [method register], for a
## suite that builds the brush without the module. *store* is what the Picture
## row lists.
func register_shipped(store: SaPatternStore = null) -> void:
    for each: SaBrushFieldRegistry.Field in shipped(store):
        register(each)


## The three fields Sara ships, with their rows, which the module registers
## through its context the way another module registers its own. *store* is
## the module's one pattern store, which the Picture row lists, and null gives
## the row a store of its own.
static func shipped(store: SaPatternStore = null) -> Array[SaBrushFieldRegistry.Field]:
    return [
        SaBrushFieldRegistry.Field.new(GRAIN, "Grain", ENGINE, &"grain", 2, [&"grain_scale", &"grain_contrast"], _grain_rows()),
        SaBrushFieldRegistry.Field.new(
            BRISTLE, "Bristle", ENGINE, &"bristle", 2, [&"bristle_count", &"bristle_spread", &"bristle_length"], _bristle_rows()
        ),
        SaBrushFieldRegistry.Field.new(
            PICTURE,
            "Picture",
            ENGINE,
            SaBrushFieldRegistry.PICTURE,
            1,
            [&"picture_scale", &"picture_rotation", &"picture_invert"],
            _picture_rows(store)
        ),
    ]


static func _grain_rows() -> Array[SaOptionSpec]:
    var scale := _slider(
        &"grain_scale",
        "Scale",
        1.0,
        64.0,
        0.1,
        {
            "suffix": "px",
            "logarithmic": true,
            "decimals": 1,
            "tooltip": "How wide one speck of the grain is, in pixels of the document."
        }
    )
    var contrast := _slider(
        &"grain_contrast",
        "Contrast",
        0.0,
        4.0,
        0.01,
        {
            "decimals": 2,
            "tooltip": "How far the grain is stretched about its middle. Low is a soft haze of specks, high a hard pepper."
        }
    )
    return [scale, contrast]


static func _bristle_rows() -> Array[SaOptionSpec]:
    var count := _slider(
        &"bristle_count",
        "Count",
        2.0,
        96.0,
        1.0,
        {"kind": SaOptionSpec.Kind.INT, "decimals": 0, "tooltip": "How many streaks lie across the stroke."}
    )
    var spread := _slider(
        &"bristle_spread",
        "Spread",
        0.0,
        1.0,
        0.01,
        {
            "suffix": "%",
            "percent": true,
            "decimals": 0,
            "tooltip": "How far each streak strays across the stroke from an even comb. 0 lays them evenly."
        }
    )
    var length := _slider(
        &"bristle_length",
        "Length",
        0.1,
        8.0,
        0.01,
        {
            "suffix": "×",
            "logarithmic": true,
            "decimals": 2,
            "tooltip": "How far a streak runs along the stroke before it breaks, in widths of the brush."
        }
    )
    return [count, spread, length]


## The Picture field's rows. The Pattern row is a list built through the
## `CUSTOM` door rather than an `ENUM`, whose choices are fixed when the spec is
## made: the names were read once at registration, so a pattern dropped into
## `user://patterns` while Sara ran never became a row.
static func _picture_rows(store: SaPatternStore) -> Array[SaOptionSpec]:
    var picture := SaOptionSpec.make_custom(
        &"picture_name",
        "Pattern",
        build_pattern_list.bind(store),
        bind_pattern_list,
        {
            "bar": false,
            "advanced": true,
            "width": 120,
            "tooltip": "The pattern the stroke paints through, from Sara's patterns or your own."
        }
    )
    var scale := _slider(
        &"picture_scale",
        "Scale",
        0.1,
        8.0,
        0.01,
        {
            "suffix": "×",
            "logarithmic": true,
            "decimals": 2,
            "tooltip": "How large one repeat of the pattern is, against its own pixels."
        }
    )
    var rotation := _slider(
        &"picture_rotation",
        "Rotation",
        -180.0,
        180.0,
        1.0,
        {"suffix": "°", "decimals": 0, "tooltip": "How far the pattern is turned, in degrees."}
    )
    var invert := (
        SaOptionSpec
        . make(
            &"picture_invert",
            "Invert",
            SaOptionSpec.Kind.BOOL,
            {
                "bar": false,
                "advanced": true,
                "tooltip":
                # gdlint:ignore=max-line-length
                "Lets the pattern's light parts take paint first. Off, its dark parts take paint at any pressure and its white only at a full press."
            }
        )
    )
    return [picture, scale, rotation, invert]


## The Pattern row, a [PatternList] over *store*. *write* is the skeleton's
## door for a pick. *store* comes last because `Callable.bind` appends it, and
## null reads a store of its own.
static func build_pattern_list(_spec: SaOptionSpec, write: Callable, store: SaPatternStore = null) -> Control:
    var list := PatternList.new(store if store != null else SaPatternStore.new())
    if write.is_valid():
        list.choice_picked.connect(write)
    return list


## Shows *value*, the settings' `picture_name`, on the list. A name no file
## carries any more, from a preset made on another machine, is shown as it is
## with no row marked, rather than as the first pattern it does not paint.
static func bind_pattern_list(control: Control, value: Variant) -> void:
    var list := control as SaChoiceButton
    if list != null and not list.select_value(String(value)):
        list.clear_choice(String(value))


## A slider on the Texture page, behind the Advanced switch in the Tool Options
## docker and never on the bar.
## A field's slider, off the bar and behind Advanced as every field row is,
## with *fields* the rest of the row as [method SaOptionSpec.make_float] takes them.
static func _slider(
    key: StringName, label: String, low: float, high: float, step: float, fields: Dictionary[String, Variant]
) -> SaOptionSpec:
    var all_fields: Dictionary[String, Variant] = {"bar": false, "advanced": true}
    all_fields.merge(fields, true)
    return SaOptionSpec.make_float(key, label, low, high, step, all_fields)
