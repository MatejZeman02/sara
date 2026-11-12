## The door a module takes to what the painter has in hand: the preferences,
## the colour pair and the canvas of the document in front.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A built-in that names `SaSettings`, the colour store or `SaCanvas` outright
## reaches past the door, and the direction suite's `OUTSIDE_THE_DOOR` keeps
## each such pair. A third party's module cannot do the same without naming a
## file behind the door, so this is how it reads what a built-in reads. Each
## part below answers what the built-ins used, no more, and a module names
## `SaInHand` alone.
##
## Static, as `SaPresetsInHand` is: a tool state, a filter and a docker all ask,
## and none of them holds a context to ask through. The three parts are inner
## classes because each is a small set of answers over one object the skeleton
## already owns, and none keeps state of its own.
class_name SaInHand
extends RefCounted


## The painter's preferences, the ones the profile stores. A name that is no
## stored preference is a mistake in the caller, said as an error rather than
## answered with a null that reads as a value.
class Settings:
    extends RefCounted

    ## The bounds of the four preferences a module draws a slider for, the
    ## skeleton's own constants rather than copies of their numbers.
    const MAX_SELECTION_FEATHER: float = SaSettingsValues.MAX_SELECTION_FEATHER
    const MAX_EXPOSURE_STOPS: float = SaSettingsValues.MAX_EXPOSURE_STOPS
    const MIN_SHAPE_LEVELS: int = SaSettingsValues.MIN_SHAPE_LEVELS
    const MAX_SHAPE_LEVELS: int = SaSettingsValues.MAX_SHAPE_LEVELS

    ## Whether *setting* is a preference the profile stores.
    static func knows(setting: StringName) -> bool:
        return not SaSettingsValues.place_of(setting).is_empty()

    ## The value of *setting*, or null with an error for a name that is no
    ## stored preference.
    static func read(setting: StringName) -> Variant:
        if not knows(setting):
            push_error("SaInHand.Settings: %s is not a stored preference" % setting)
            return null
        return SaSettings.get(setting)

    ## Writes *value* to *setting* through the preference's own setter, which
    ## clamps it and says so on [method changed]. An unknown name writes
    ## nothing and says why.
    static func write(setting: StringName, value: Variant) -> void:
        if not knows(setting):
            push_error("SaInHand.Settings: %s is not a stored preference" % setting)
            return
        SaSettings.set(setting, value)

    ## Sent with the name of the preference that moved.
    static func changed() -> Signal:
        return SaSettings.changed

    ## Sent when the profile a whole surface is rebuilt for changes, the
    ## shortcuts, the window buttons and the rows of the bars, which is when a
    ## docker lays itself out again.
    static func profile_changed() -> Signal:
        return SaSettings.profile_changed

    ## The object a page row binds to, so a dump reads a preference's row
    ## through its binding as it reads every other row. Untyped on purpose:
    ## a row's `target` is an `Object`, and what it is stays behind the door.
    static func row_target() -> Object:
        return SaSettings

    ## Gives *element* a place in *category*'s list and a title in Preferences,
    ## after *after*, as the toolbox's own rows are given theirs.
    static func place_element(
        category: String, element: String, title: String, hidden := false, after := "", view := Callable()
    ) -> void:
        SaSettings.register_layout_element(category, element, title, hidden, after, view)

    ## Takes *element* of *category* back, its view with it.
    static func remove_element(category: String, element: String) -> void:
        SaSettings.unregister_layout_element(category, element)


## The colour pair the painter paints with, the paint exposure on the
## foreground, and the swatches they keep. Each answer stands with no store, a
## run with no autoloads, at the defaults a fresh profile has.
class Pair:
    extends RefCounted

    const DEFAULT_FOREGROUND: Color = SaColorStore.DEFAULT_FOREGROUND
    const DEFAULT_BACKGROUND: Color = SaColorStore.DEFAULT_BACKGROUND

    static func foreground() -> Color:
        return SaColors.foreground if SaColors != null else DEFAULT_FOREGROUND

    static func background() -> Color:
        return SaColors.background if SaColors != null else DEFAULT_BACKGROUND

    ## The paint exposure in stops, the foreground's own.
    static func exposure_stops() -> float:
        return SaColors.exposure_stops if SaColors != null else 0.0

    ## Moves the paint exposure to *stops*, the colour part kept, as the
    ## colour docker's slider does. Refused by the store while a mask is the
    ## paint target.
    static func expose(stops: float) -> void:
        if SaColors != null:
            SaColors.exposure_stops = stops

    ## Sent when the foreground moves. The background is said on the bus, as
    ## `EventBus.background_color_changed`, which a module already hears.
    static func foreground_changed() -> Signal:
        return SaColors.foreground_changed

    ## The swatches the painter keeps, a copy, so a caller holding it never
    ## moves the store's list.
    static func swatches() -> Array[Color]:
        var kept: Array[Color] = []
        if SaColors != null:
            kept.assign(SaColors.swatches)
        return kept

    ## Keeps *color* as a swatch, through the store's one door for it.
    static func keep_swatch(color: Color) -> void:
        if SaColors != null:
            SaColors.add_swatch(color)

    ## Records that *color* was used, so it heads the recent list.
    static func note_used(color: Color) -> void:
        if SaColors != null:
            SaColors.note_used(color)

    ## *color* with its alpha at one, the colour the store would keep.
    static func opaque(color: Color) -> Color:
        return SaColorStore.opaque(color)

    ## Whether the store would take *color*: its three channels are finite.
    static func finite(color: Color) -> bool:
        return SaColorStore.finite(color)


## The canvas a docker reads: the surface of the document in front, and what a
## docker asks of the canvas that shows it. A module holds the `SaSurface`,
## which is the door's, and never the `SaCanvas` Control behind it.
class Canvas:
    extends RefCounted

    ## The surface of the document the painter is working on, the one the
    ## front tab shows, or null outside a tree or before a document is open.
    static func front() -> SaSurface:
        var tree := Engine.get_main_loop() as SceneTree
        return SaDocuments.front_in(tree.current_scene) if tree != null else null

    ## Asks for the picture to be composited again on the next frame, as a
    ## preview that changed what chunks show and nothing in them needs.
    static func request_composite(surface: SaSurface) -> void:
        if surface != null and surface.easel != null:
            surface.easel.request_composite()

    ## The texture the canvas composites into, or an empty id when there is
    ## none yet. What a docker that shows the picture again binds.
    static func output_rid(surface: SaSurface) -> RID:
        if surface == null or surface.easel == null or surface.easel.output == null:
            return RID()
        return surface.easel.output.rid

    ## The canvas's own shader material, which a docker composes over to show
    ## the picture as the canvas does, or null for a surface shown through no
    ## canvas, a suite's own view.
    static func shader(surface: SaSurface) -> ShaderMaterial:
        var shown := SaCanvasView.canvas_of(surface)
        return shown.material as ShaderMaterial if shown != null else null

    ## Shows *recorded* over *document* on the canvas, writing no chunk.
    static func preview_point(surface: SaSurface, document: SaDocument, recorded: SaPointPass) -> void:
        if _composites(surface):
            surface.easel.compositor.point_preview.set_pass(document, recorded)

    ## Takes *document*'s preview off the canvas. An easel going away at exit
    ## has let its compositor go already, and then there is nothing to clear.
    static func clear_point_preview(surface: SaSurface, document: SaDocument) -> void:
        if _composites(surface):
            surface.easel.compositor.point_preview.clear(document)

    ## Whether *surface* has an easel with a compositor to show a preview on.
    static func _composites(surface: SaSurface) -> bool:
        return surface != null and surface.easel != null and surface.easel.compositor != null

    ## The texture filter the canvas samples with at *pixels_per_texel*, so a
    ## view of the picture beside it samples alike.
    static func texture_filter_for(pixels_per_texel: float) -> CanvasItem.TextureFilter:
        return SaCanvas.filter_for(pixels_per_texel)
