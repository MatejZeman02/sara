## What a new document is laid on: a colour, nothing, or a ground.
##
## The New Document dialog's three background rows hand this a dictionary,
## `{"kind": &"colour", "color": Color.WHITE, "ground": &"paper"}`, the colour
## in display terms the way the swatch showed it. An empty one is a grey
## stored background, so the harness, an opened picture and every other caller
## of `SaDocument.setup_default_document` that names no background get the
## plain ground they expect.
##
## A class of its own rather than lines in `SaDocument`, because the document
## is near the length the run fails at, and the choice is one thing: which
## layer goes at the bottom and what it is filled with.
class_name SaDocumentBackground
extends RefCounted

const KIND := "kind"
const COLOR := "color"
const GROUND := "ground"

## A stored layer named Background, filled everywhere with the colour.
const COLOUR := &"colour"
## No background at all, only the empty layer to paint on.
const TRANSPARENT := &"transparent"

## The name the bottom layer takes whichever kind it is, so a painter finds
## the ground under one name whatever its kind.
const LAYER_NAME := "Background"

## The colour the dialog opens on, white rather than the grey a document that
## names no background is laid on.
const DEFAULT_SHOWN := Color.WHITE


## The choice the dialog opens on: a white stored background and no ground.
static func default_choice() -> Dictionary:
    return {KIND: COLOUR, COLOR: DEFAULT_SHOWN, GROUND: &""}


## The colour *choice* asks for in display terms, the grey when it names none.
## Opaque always: a see-through background is what Transparent is for.
static func shown_of(choice: Dictionary, grey: Color) -> Color:
    var held: Variant = choice.get(COLOR)
    var shown: Color = held if held is Color else grey
    shown.a = 1.0
    return shown


## Adds the bottom layer *choice* asks for to *document*, or none for
## Transparent, before anything else is added. *types* is the registry a ground
## is looked up in, passed rather than the document's because a document is
## made per easel and owns none, as `SaLayerOps.add` takes it. A ground the
## registry does not know falls back to a stored layer of the colour and says
## so, because a document with no background at all is not what was asked.
static func lay(document: SaDocument, choice: Dictionary, types: SaLayerTypeRegistry, grey: Color) -> void:
    if StringName(str(choice.get(KIND, COLOUR))) == TRANSPARENT:
        return
    var space := document.color_space
    var shown := shown_of(choice, grey)
    var ground := StringName(str(choice.get(GROUND, "")))
    var layer := SaLayer.new()
    layer.name = LAYER_NAME
    layer.schema = SaFieldSpec.schema_for_space(space)
    if not String(ground).is_empty():
        var descriptor := types.get_descriptor(ground) if types != null else null
        if descriptor != null and descriptor.is_generated() and types.apply_to(layer, ground, space):
            _tint(layer, descriptor, shown, space)
            # A ground stores nothing (hard rule 3), so it allocates no grid.
            document.add_child(layer)
            return
        push_warning("SaDocumentBackground: no ground called '%s', laying a plain colour instead." % ground)
    # The one layer that holds paint everywhere, so the one that allocates the
    # grid.
    document.add_child(layer)
    layer.allocate_grid(document.canvas_size)
    layer.fill(space.from_display(shown) if space != null else shown)


## The ground's first colour becomes *shown*, and its second the descriptor's
## default second scaled by the same ratio per channel, so a white paper and a
## toned one keep the grain's contrast. Both go through `from_display` into the
## document's space, the way the descriptor's own defaults do.
##
## Then both move by the descriptor's `grain_median` of the step between them,
## in the document's space where the kernel mixes them, so the grain's median
## is *shown* and its mottle lies either side. A paper's first colour comes out
## lighter than the one asked, past white for a white one, which a float
## texture holds and the view shows as white (hard rule 5).
static func _tint(layer: SaLayer, descriptor: SaLayerTypeDescriptor, shown: Color, space: SaColorSpace) -> void:
    var defaults := descriptor.generator_defaults
    var first: Color = defaults.get(SaGeneratedLayer.PARAM_COLOR, shown)
    var params := layer.generator_params
    var held := space.from_display(shown) if space != null else shown
    params[SaGeneratedLayer.PARAM_COLOR] = held
    if not defaults.has(SaGeneratedLayer.PARAM_SECOND):
        return
    var second: Color = defaults[SaGeneratedLayer.PARAM_SECOND]
    var scaled := Color(
        second.r * _ratio(shown.r, first.r), second.g * _ratio(shown.g, first.g), second.b * _ratio(shown.b, first.b), second.a
    )
    var low := space.from_display(scaled) if space != null else scaled
    var lift := (held - low) * descriptor.grain_median
    lift.a = 0.0
    params[SaGeneratedLayer.PARAM_COLOR] = held + lift
    params[SaGeneratedLayer.PARAM_SECOND] = low + lift


## *to* over *from*, and one where *from* is black, so a default with a dark
## channel keeps its second rather than dividing by nought.
static func _ratio(to: float, from: float) -> float:
    return to / from if from > 0.0 else 1.0
