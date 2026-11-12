## What every picker on screen wears while a mask is the paint target: a cover
## over the whole picker that draws what lies under it as the grey a brush
## would paint there, so the shape, the chips and the rows offer no hue while
## [SaColorStore] holds the pair grey, and lets every press through to them.
##
## A pick through it is a colour still, which the store turns into the grey a
## brush paints into the mask, so what the cover shows is what is painted. The
## two are one rule rather than two: the cover asks the store for
## [method SaColorStore.mask_grey], whose numbers are the document's own colour
## space and whose table of greys is the store's own bisection, and draws that.
## Only the maths of the lightness itself lives in the shader, with the picker's
## suite on the greyed picker reading its pixels back against the store.
##
## Top level, so the picker's container lays it out with nothing else and it
## draws after every row of the picker, and fitted each frame to the part of
## the picker its clipping parents leave visible, which a scrolled docker
## moves without a signal.
##
## A file of its own rather than an inner class of [SaPickerShape], because the
## colour docker's view wears one over its whole picker as well and reached
## into the shape for it, and because a cover that carries a rule is a thing
## that owns something rather than a corner of the shape's geometry.
extends ColorRect

class_name SaGreyVeil

## Loaded where the material wants it rather than preloaded, the reason
## `sa_picker_shape.gd` gives for its own two shaders: a preload of a resource
## that is not a script is a nested threaded load on the boot's worker, and
## Godot 4.7 leaks that load's token at exit.
const SHADER_PATH := "res://shaders/ui/grey_veil.gdshader"

## The store whose masking this follows and whose rule it draws.
var _store: SaColorStore

## The picker it covers, the parent it is added to.
var _over: Control

## The rule last pushed into the shader, so a frame that changes nothing
## uploads nothing.
var _rule: SaColorStore.MaskGrey = null


## *store* is the store to follow, the app's own unless a caller hands over one
## of its own, which a suite does to leave the app's pair alone.
func _init(store: SaColorStore = null) -> void:
    _store = store if store != null else SaColors
    name = "GreyVeil"
    top_level = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var veil := ShaderMaterial.new()
    veil.shader = load(SHADER_PATH)
    material = veil
    visible = false
    _store.masking_changed.connect(_on_masking_changed)


func _ready() -> void:
    _over = get_parent() as Control
    _fit()


func _process(_delta: float) -> void:
    _fit()


func _on_masking_changed(_on: bool) -> void:
    _fit()


## Shown while the store is grey and the picker is, over the part of it on
## screen, drawing the rule the document asks for.
func _fit() -> void:
    var shown := _store.masking and is_instance_valid(_over) and _over.is_visible_in_tree()
    if not shown:
        visible = false
        return
    _sync_rule()
    var area := _over.get_global_rect()
    var clip := _over.get_parent_control()
    while clip != null:
        if clip.clip_contents:
            area = area.intersection(clip.get_global_rect())
        clip = clip.get_parent_control()
    visible = area.has_area()
    global_position = area.position
    size = area.size


## The rule the store's document asks for, pushed into the shader when it is
## not the one already there. The store holds it while the colour space stands,
## so a frame that changes nothing costs one comparison.
func _sync_rule() -> void:
    var rule := _store.mask_grey()
    if rule == _rule:
        return
    _rule = rule
    var veil := material as ShaderMaterial
    veil.set_shader_parameter("rule", rule.rule)
    veil.set_shader_parameter("carry", rule.carry)
    veil.set_shader_parameter("weights", rule.weights)
    veil.set_shader_parameter("display", rule.display_curve)
    veil.set_shader_parameter("shape", rule.shape)
    veil.set_shader_parameter("steps", float(rule.greys.size()))
    veil.set_shader_parameter("ramp", _table(rule.greys))


## *greys* as the one pixel high texture a coverage is read from. Float rather
## than bytes, so the halving between two entries is not itself rounded to the
## eight bits the answer is wanted to.
static func _table(greys: PackedFloat32Array) -> ImageTexture:
    var image := Image.create_from_data(greys.size(), 1, false, Image.FORMAT_RF, greys.to_byte_array())
    return ImageTexture.create_from_image(image)
