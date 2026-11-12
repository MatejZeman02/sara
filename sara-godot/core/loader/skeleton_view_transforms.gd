## The skeleton's view transforms: the switches and modes the canvas shader
## implements, Tonemap Highlights, Gamut Mapping, Display Exposure, Show
## Impasto, Gamut Warning and the five views, with why each one would change
## nothing, and the loop that registers them through the public door (hard
## rule 6).
##
## Its own file, cut from the skeleton by what the code owns, as the blend modes
## and the Select commands were: nothing here touches a pixel of the document,
## the skeleton calls `register` and reads nothing back.
extends RefCounted


## The view transforms the canvas shader implements, registered the way
## a module's proof would be. The rolloff and the display exposure keep their
## state in Preferences, so their toggles read and write SaSettings rather
## than the registry, and the two modes are values of the shader's
## `view_mode` uniform. The uniforms each toggle sets are the shader's, which
## is the one place the two have to agree.
static func register(ctx: SaContext) -> void:
    var rolloff := SaViewTransformDescriptor.create(
        &"highlight_rolloff", "Tonemap Highlights", SaViewTransformDescriptor.Kind.TOGGLE
    )
    rolloff.sort_order = 10
    rolloff.tooltip = (
        "Compress values above 1.0 instead of clipping them. Changes what you see, never what is stored."
        + " This is the Tonemap filter's Paper method, the same operator the filter runs when its Method row says Paper."
    )
    rolloff.read_enabled = func() -> bool: return SaSettings.tonemap_highlights
    rolloff.on_toggle = func(enabled: bool) -> void: SaSettings.tonemap_highlights = enabled
    rolloff.apply = _apply_rolloff
    rolloff.idle_reason = _rolloff_idle.bind(weakref(ctx))
    ctx.register_view_transform(rolloff)

    # Beside the roll-off because it finishes what the roll-off leaves, and a
    # toggle of its own because it runs whether the roll-off does or not: a
    # colour outside the display's gamut is mapped with tonemapping off too.
    # On is Oklab and off is clip, the two keys the preference
    # holds, and the Display page's row writes the same setting. No apply of its
    # own, like Show Impasto: the canvas writes the `gamut_mapping` uniform from
    # the setting beside the roll-off's three, and a second writer here would be
    # one uniform with two owners.
    var gamut := SaViewTransformDescriptor.create(&"gamut_mapping", "Gamut Mapping", SaViewTransformDescriptor.Kind.TOGGLE)
    gamut.sort_order = 15
    gamut.tooltip = (
        "Bring a colour the screen cannot show, a negative channel above all, inside it with its lightness and hue held."
        + " Off clips each channel on its own. Runs with or without Tonemap Highlights, and never touches a pixel."
    )
    gamut.read_enabled = func() -> bool: return SaSettings.gamut_mapping == SaGamutMapping.OKLAB
    gamut.on_toggle = func(enabled: bool) -> void:
        SaSettings.gamut_mapping = SaGamutMapping.OKLAB if enabled else SaGamutMapping.CLIP
    ctx.register_view_transform(gamut)

    var exposure := SaViewTransformDescriptor.create(
        &"display_exposure", "Display Exposure", SaViewTransformDescriptor.Kind.TOGGLE
    )
    exposure.sort_order = 20
    exposure.tooltip = (
        "Brighten or darken the view by the exposure set in Preferences > Canvas and colour." + " The pixels are not changed."
    )
    exposure.read_enabled = func() -> bool: return SaSettings.display_exposure_enabled
    exposure.on_toggle = func(enabled: bool) -> void: SaSettings.display_exposure_enabled = enabled
    exposure.apply = _apply_display_exposure
    exposure.idle_reason = func() -> String:
        if not is_zero_approx(SaSettings.display_exposure_stops):
            return ""
        return "Changes nothing at 0 stops. Exposure Stops... below opens the slider in Preferences > Canvas and colour."
    ctx.register_view_transform(exposure)

    # The canvas binds the relief itself, because the texture
    # is its easel's and a descriptor's apply is handed only the material, so
    # the toggle is the setting and nothing more.
    var relief := SaViewTransformDescriptor.create(&"show_relief", "Show Impasto", SaViewTransformDescriptor.Kind.TOGGLE)
    relief.sort_order = 40
    relief.tooltip = (
        "Light the impasto, so ridges catch the light and grooves fall into shadow. "
        + "The light and its strength are the document's own, set in View > Relief Light. The pixels are not changed."
    )
    relief.read_enabled = func() -> bool: return SaSettings.show_relief
    relief.on_toggle = func(enabled: bool) -> void: SaSettings.show_relief = enabled
    relief.idle_reason = _relief_idle.bind(weakref(ctx))
    ctx.register_view_transform(relief)

    var lightness := SaViewTransformDescriptor.create(&"lightness_check", "Lightness Check", SaViewTransformDescriptor.Kind.MODE)
    lightness.sort_order = 10
    lightness.tooltip = "The canvas as grey at its Oklab lightness, so values read without their hue."
    lightness.view_mode = 1
    ctx.register_view_transform(lightness)

    # Named for what it is rather than for what it holds, because False Colour
    # is what the rest of the trade calls a picture banded by exposure, and
    # because it is now where the magnitude the rolloff cannot show is read.
    # The id is the older one, so a saved proof still resolves.
    var heatmap := SaViewTransformDescriptor.create(&"hdr_heatmap", "False Colour", SaViewTransformDescriptor.Kind.MODE)
    heatmap.sort_order = 20
    heatmap.tooltip = (
        "Colour the canvas by brightness: grey up to 1.0, then yellow, orange, red and magenta "
        + "by doubling, and blue for a negative."
    )
    heatmap.view_mode = 2
    ctx.register_view_transform(heatmap)

    var proof := SaViewTransformDescriptor.create(&"soft_proof", "Soft Proof", SaViewTransformDescriptor.Kind.MODE)
    proof.sort_order = 30
    proof.tooltip = "The document's gamut as the proof gamut set in Preferences > Canvas and colour would show it, clipped to it."
    proof.view_mode = 3
    ctx.register_view_transform(proof)

    # Decoded and gamut mapped as usual and only the display encoding off, which
    # is what Blender means by Raw, rather than the stored numbers straight to
    # the screen, which would put an Oklab document's L, a and b into R, G and B
    # and show a blue sea as red. The id is the label's, and not `raw`, because
    # that name says something the mode does not do.
    var encoding_off := SaViewTransformDescriptor.create(
        &"encoding_off", "Show Linear Values", SaViewTransformDescriptor.Kind.MODE
    )
    encoding_off.sort_order = 40
    encoding_off.tooltip = (
        "The linear colour straight to the screen: decoded and gamut mapped as usual, " + "and not encoded for the display."
    )
    encoding_off.view_mode = 4
    ctx.register_view_transform(encoding_off)

    # One tool to judge a shape: the canvas downscaled and upscaled, or
    # quantized, so a silhouette reads without its detail. A view mode rather
    # than a filter, registered here with the other four, so nothing
    # of the document is touched and the painter keeps painting through it.
    # Every option it has, the method, its reach, the blocks across, the
    # count of lightness steps and the notan's values and thresholds, is a
    # preference of `SaSettingsShapeCheck`.
    var shape := SaViewTransformDescriptor.create(&"shape_check", "Shape Check", SaViewTransformDescriptor.Kind.MODE)
    shape.sort_order = 50
    shape.tooltip = (
        "Throw the detail away so the silhouette reads: average the canvas into flat blocks, or smooth "
        + "inside each mass and keep its edges, then snap the lightness to a few steps, in colour or in "
        + "grey, or cut it into a notan of two or three greys. The method and its numbers are in "
        + "Preferences > Canvas and colour, and the Info docker sets the steps too."
    )
    shape.view_mode = 5
    ctx.register_view_transform(shape)

    var warning := SaViewTransformDescriptor.create(&"gamut_warning", "Gamut Warning", SaViewTransformDescriptor.Kind.TOGGLE)
    warning.sort_order = 30
    warning.tooltip = "While proofing, paint flat grey wherever the proof gamut cannot hold the colour."
    warning.apply = func(material: ShaderMaterial, enabled: bool) -> void:
        material.set_shader_parameter("proof_gamut_warning", enabled)
    warning.idle_reason = _gamut_warning_idle.bind(weakref(ctx))
    ctx.register_view_transform(warning)


## Why the Tonemap Highlights row greys out and goes unticked: a filter already
## forms the picture, so the view's own roll-off would transform it twice.
##
## Asked of the easel's filter chain by the very rule the canvas writes the
## shader's `tonemap_enabled` uniform by, so the row and the shader can never
## disagree about whether the view is standing aside. Nothing here names the
## Tonemap: a filter says `forms_the_picture` and this reads whoever says it.
## The setting is not written either, so removing, hiding or covering the filter
## brings the view back as it was.
static func _rolloff_idle(ctx_ref: WeakRef) -> String:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document == null or easel.compositor == null:
        return ""
    if not easel.compositor.filter_chain.covers_the_picture(document):
        return ""
    return (
        "A Tonemap filter forms the picture, over the canvas or on a filter layer with nothing visible above it,"
        + " so the view has nothing left to roll off."
    )


## Why the gamut warning greys nothing: the shader paints it in the soft proof's
## branch alone, so outside that mode the tick reaches no pixel.
static func _gamut_warning_idle(ctx_ref: WeakRef) -> String:
    var ctx: SaContext = ctx_ref.get_ref()
    if ctx == null or ctx.view_transforms == null or ctx.view_transforms.mode == &"soft_proof":
        return ""
    return "Changes nothing outside Soft Proof, which is one of the views above."


## Why Show Impasto lights nothing: no strength in the document's light, or
## nothing in sight to light. `SaRelief.shows_height` counts the paint's height
## alone, the question the export's Include impasto lighting asks, and the view
## sums a Paper or Canvas ground's tooth under it as well, so the grounds are
## asked here by the rule `SaRelief` sums them by.
static func _relief_idle(ctx_ref: WeakRef) -> String:
    var ctx: SaContext = ctx_ref.get_ref()
    var easel := ctx.get_easel() if ctx != null else null
    var document: SaDocument = easel.document if easel != null else null
    if document != null and document.relief_light.strength <= 0.0:
        return "Changes nothing at a relief strength of 0. Relief Light... below sets this document's."
    if document == null or SaRelief.shows_height(document):
        return ""
    for child in document.get_children():
        var layer := child as SaLayer
        if SaGeneratedLayer.tooth_of(layer) > 0.0 and SaLayerStack.contributes(document, layer):
            return ""
    return (
        "Changes nothing yet, because nothing in sight has impasto. A brush that lays down impasto"
        + " gives a layer some, and so does a Paper or Canvas ground with a tooth."
    )


static func _apply_rolloff(material: ShaderMaterial, enabled: bool) -> void:
    material.set_shader_parameter("tonemap_enabled", enabled)
    material.set_shader_parameter("knee", SaSettings.tonemap_knee)
    material.set_shader_parameter("desaturation", SaSettings.tonemap_desaturation)


static func _apply_display_exposure(material: ShaderMaterial, enabled: bool) -> void:
    var factor := pow(2.0, SaSettings.display_exposure_stops) if enabled else 1.0
    material.set_shader_parameter("display_exposure", factor)
