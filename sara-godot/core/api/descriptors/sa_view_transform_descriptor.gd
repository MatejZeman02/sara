## What a module fills in to add a view transform: something the canvas shows
## and the document never stores.
##
## The highlight rolloff was one preloaded shader behind one boolean, and
## four more transforms were queued to repeat that pattern, each a branch in
## the same shader behind another boolean. A transform registers instead, the
## way a tool or a blend mode does, so the View menu, the canvas and
## Preferences read one list.
##
## Two kinds. A TOGGLE stacks with everything else and is on or off: the
## rolloff, the display exposure. A MODE replaces the ordinary view and only
## one is active at a time: the lightness check, the HDR heatmap, a proof. A
## built-in mode names the `view_mode` value the canvas shader implements it
## under. A module's mode brings its own canvas_item `shader`, which the
## canvas swaps in while the mode is active and hands the same uniforms the
## built-in one gets: `document_is_srgb`, `document_is_oklab`,
## `display_passthrough`, the `to_display_col*` columns, `blend_white`, and
## whatever every toggle's `apply` sets.
class_name SaViewTransformDescriptor
extends RefCounted

enum Kind { TOGGLE, MODE }

var id: StringName
var display_name: String = ""
var kind: Kind = Kind.TOGGLE
var tooltip: String = ""

## Menu order within its kind. Leave gaps, so a module can slot in between.
var sort_order: int = 0

## MODE only. The value the canvas shader's `view_mode` uniform takes when
## this mode is active and the mode has no shader of its own.
var view_mode: int = 0

## MODE only, optional. A canvas_item shader the canvas uses while this mode
## is active, for a transform the built-in shader does not implement.
var shader: Shader = null

## TOGGLE only, optional. `(material: ShaderMaterial, enabled: bool) -> void`,
## called on every resync so the transform can set its uniforms.
var apply: Callable = Callable()

## TOGGLE only, optional. Where the on/off state lives when it is not the
## registry's to keep: `read_enabled() -> bool` and `on_toggle(enabled: bool)`.
## The rolloff persists in Preferences and uses both. A toggle without them is
## on or off for the session, in the registry.
var read_enabled: Callable = Callable()
var on_toggle: Callable = Callable()

## TOGGLE only, optional. `() -> String`, why the toggle changes nothing on
## screen as things stand, or "" while it changes something. The View menu
## greys a row that answers a reason, keeps its tick and says the reason on
## hover, so a painter who ticks it to see what it does is not left to conclude
## it is broken. The display exposure answers one at 0 stops, the gamut warning
## outside Soft Proof, and the relief while nothing in sight has a height.
var idle_reason: Callable = Callable()

var owner_module: StringName = &""


static func create(transform_id: StringName, name: String, transform_kind: Kind) -> SaViewTransformDescriptor:
    var descriptor := SaViewTransformDescriptor.new()
    descriptor.id = transform_id
    descriptor.display_name = name
    descriptor.kind = transform_kind
    return descriptor
