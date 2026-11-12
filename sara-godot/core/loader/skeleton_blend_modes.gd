## The skeleton's blend modes: the table every built-in mode is made from, what
## each one says about itself, and the loop that registers them through the
## public door (hard rule 6).
##
## Its own file, cut from `skeleton_module.gd` by what
## the code owns rather than by count: everything here is the modes, nothing in
## the skeleton's other registrations reads any of it, and the skeleton calls
## `register` and knows nothing else about them.
extends RefCounted

## Kernel names, each a `<kernel>_blended` formula of composite_blend_modes.gmacs,
## which makes the kernel and its commit twin. Names, so no order is a contract.
##
## The fourth column is the sort key within a section and the sixth is the
## section, one of SaBlendModeDescriptor.SECTIONS. The order the two give is the
## display order every menu shows: Normal and Erase first, then darken, lighten,
## contrast, comparative and the colour components. Erase sits under Normal
## because those two are what a painter switches between all day. Both the layer
## docker and the tool options bar are a BlendModeButton over the same registry,
## so the two menus cannot drift apart. Leave gaps of ten, so a module can slot
## a mode into a group without renumbering the ones after it. Erase takes 5, in
## the gap under Normal.
const BLEND_MODES: Array = [
    [&"normal", "composite", "Normal", 0, SaBlendModeDescriptor.Domain.ARITHMETIC, &"normal"],
    [&"erase", "erase", "Erase", 5, SaBlendModeDescriptor.Domain.ARITHMETIC, &"erase"],
    # Normal done in a space the layer names rather than the one the document
    # happens to store. On a document already storing that space, each of these
    # is exactly what plain Normal does, which is why plain Normal's label
    # carries the document's space in brackets: it says which of the three it
    # currently equals.
    #
    # **The space leads, and that is what stops the two forms colliding**. These
    # were "Normal (sRGB)" and its two siblings, and on an Oklab document the
    # menu drew "Normal (Oklab)" twice: once for plain Normal, saying what it
    # equals today, and once for `normal_oklab`, which is always that. Two rows,
    # the same words, and a painter who picked one of them had no way to know
    # which they had until the document's space moved under them. The bracket is
    # the half worth keeping, because it answers a question about this document,
    # so the pinned three moved instead: the space in front means the mode is
    # that space's for ever, and the space in brackets means the document is that
    # space today. `test_no_two_blend_modes_share_a_label` holds it over every
    # space Sara can make a document in.
    [&"normal_srgb", "composite_srgb", "sRGB Normal", 6, SaBlendModeDescriptor.Domain.ARITHMETIC, &"normal"],
    [&"normal_linear", "composite_linear", "Linear Normal", 7, SaBlendModeDescriptor.Domain.ARITHMETIC, &"normal"],
    [&"normal_oklab", "composite_oklab", "Oklab Normal", 8, SaBlendModeDescriptor.Domain.ARITHMETIC, &"normal"],
    [&"multiply", "multiply", "Multiply", 10, SaBlendModeDescriptor.Domain.ARITHMETIC, &"darken"],
    [&"darken", "darken", "Darken", 20, SaBlendModeDescriptor.Domain.ARITHMETIC, &"darken"],
    [&"screen", "screen", "Screen", 30, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"lighten"],
    [&"lighten", "lighten", "Lighten", 40, SaBlendModeDescriptor.Domain.ARITHMETIC, &"lighten"],
    [&"add", "add", "Add", 50, SaBlendModeDescriptor.Domain.ARITHMETIC, &"lighten"],
    [&"color_dodge", "color_dodge", "Colour Dodge", 60, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"lighten"],
    [&"divide", "divide", "Divide", 65, SaBlendModeDescriptor.Domain.ARITHMETIC, &"lighten"],
    [&"overlay", "overlay", "Overlay", 70, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"contrast"],
    [&"soft_light", "soft_light", "Soft Light", 80, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"contrast"],
    [&"hard_light", "hard_light", "Hard Light", 90, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"contrast"],
    [&"hard_mix", "hard_mix", "Hard Mix", 95, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"contrast"],
    [&"signed_add", "signed_add", "Signed Add", 95, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"contrast"],
    [&"difference", "difference", "Difference", 100, SaBlendModeDescriptor.Domain.ARITHMETIC, &"comparative"],
    [&"exclusion", "exclusion", "Exclusion", 110, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"comparative"],
    [&"hue", "hue", "Hue", 120, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"component"],
    [&"saturation", "saturation", "Saturation", 130, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"component"],
    [&"color", "color", "Colour", 140, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"component"],
    [&"lightness", "lightness", "Lightness", 150, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, &"component"],
    # What an alpha-locked stroke composites as, and the one row of this table
    # no menu shows. A wash stroke on an alpha-locked layer accumulates in the
    # buffer and lands once through here, keeping the destination's alpha and
    # its silhouette, which is the rule the dab kernel applies per dab when the
    # mode is build-up. It is in the table rather than beside it so the skeleton
    # still registers every mode it owns through the one public door.
    [&"alpha_lock", "alpha_lock", "Alpha Lock", 160, SaBlendModeDescriptor.Domain.ARITHMETIC, &"normal"],
]

## The modes above that the app selects for itself and no dropdown offers.
const INTERNAL_MODES: Array[StringName] = [&"alpha_lock"]

## The ids a mode above was saved under by an older build, so a `.sad` or a
## pinned favourite holding one opens as that mode rather than as Normal. Hard
## Mix's is the name a module gave it before it became a row here.
const FORMER_IDS: Dictionary[StringName, Array] = {
    &"hard_mix": [&"pga_hard_mix"],
}

## What each mode above does, the hover of its row in the blend list. A table of
## its own rather than a seventh column, because a sentence on each row of
## `BLEND_MODES` took every row past the line a run fails.
##
## The four Normals are why it exists. Each says which space it mixes in, so
## "Normal (Oklab)", which follows the document, and "Oklab Normal", which is
## Oklab on every document, read apart on hover as well as by the bracket. The
## rest say what they do to paint, since a row whose hover is its own name
## tells a painter nothing the row does not. Each speaks of the colour on top and
## the paint underneath, because one list serves a brush and a layer.
const BLEND_SENTENCES: Dictionary[StringName, String] = {
    &"normal": "Mixes in whatever space the document stores, so it changes when the document's colour space does.",
    &"erase": "Takes paint away where the brush passes rather than laying any.",
    &"normal_srgb": "Mixes in encoded sRGB on every document, the way most painting programs mix.",
    &"normal_linear": "Mixes in linear light on every document, so a soft edge of light paint over dark reads lighter.",
    &"normal_oklab": "Mixes in Oklab on every document, so a soft edge falls halfway in lightness and its hue holds.",
    &"multiply": "Darkens by multiplying the two colours, like inks laid over one another, and white changes nothing.",
    &"darken": "Keeps the darker of the two colours, channel by channel.",
    &"screen": "Lightens, like two lights shone on one wall, and black changes nothing.",
    &"lighten": "Keeps the lighter of the two colours, channel by channel.",
    &"add": "Adds the two colours, which lightens fast and can go past white.",
    &"color_dodge": "Brightens the paint underneath by the colour on top, a hard glow that leaves black as it is.",
    &"divide": "Divides the paint underneath by the colour on top, so white changes nothing and a darker colour lightens it.",
    &"overlay": "Raises the contrast underneath, darkening its darks and lightening its lights by the colour on top.",
    &"soft_light": "A gentler Overlay, darkening or lightening the paint underneath a little by the colour on top.",
    &"hard_light": "Darkens where the colour on top is dark and lightens where it is light, Overlay with the two swapped.",
    &"hard_mix": "Turns each channel full on where the two colours together reach white and off where they do not.",
    &"signed_add": "Adds what the colour on top holds above or below middle grey, so grey changes nothing.",
    &"difference": "Takes the darker colour from the lighter, so a colour over itself gives black.",
    &"exclusion": "Like Difference but softer, so a middle grey on top turns everything grey.",
    &"hue": "Takes the hue of the colour on top and keeps the saturation and lightness underneath.",
    &"saturation": "Takes the saturation of the colour on top and keeps the hue and lightness underneath.",
    &"color": "Takes the hue and saturation of the colour on top and keeps the lightness underneath.",
    &"lightness": "Takes the lightness of the colour on top and keeps the hue and saturation underneath.",
    &"alpha_lock": "Paints only where there is paint already, keeping the layer's outline.",
}


## Registers every mode in [constant BLEND_MODES] through *ctx*, the way a
## module registers its own.
static func register(ctx: SaContext) -> void:
    for entry: Array in BLEND_MODES:
        var entry_id: StringName = entry[0]
        var kernel: String = entry[1]
        var descriptor := SaBlendModeDescriptor.create(entry_id, kernel)
        descriptor.display_name = entry[2]
        descriptor.sort_order = entry[3]
        descriptor.domain = entry[4]
        descriptor.category = entry[5]
        descriptor.sentence = BLEND_SENTENCES.get(entry_id, "")
        # Erase is a brush concept: carving a hole is what the eraser does, not
        # something a layer should be set to.
        descriptor.hidden_in_layer_list = entry_id == &"erase"
        descriptor.internal = INTERNAL_MODES.has(entry_id)
        var former: Array = FORMER_IDS.get(entry_id, [])
        descriptor.former_ids.assign(former)
        # Plain Normal is the one mode with no space of its own: it mixes in
        # whatever the document stores. The dropdown says which that is, so the
        # three explicit ones above are a choice rather than a mystery.
        descriptor.follows_document_space = entry_id == &"normal"
        ctx.register_blend_mode(descriptor)
