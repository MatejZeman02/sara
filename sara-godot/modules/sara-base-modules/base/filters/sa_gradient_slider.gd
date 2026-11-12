## A FactorSlider with a gradient behind the value instead of a fill: the hue
## slider shows the ring of hues, saturation grey to full chroma, lightness
## black to white, so the painter reads what a position means before dragging
## to it. The gradients are computed in Oklab by whoever builds the slider, so
## their middle is perceptually the middle.
##
## A subclass rather than a change to FactorSlider, because this is the only
## slider that wants a picture behind its number.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The base module's, because the six adjustments are its only users and
## all six live here, so the slider followed them through the door: the
## toolkit it is built from, `FactorSlider`, stays under `ui`.
@tool
class_name SaGradientSlider
extends FactorSlider

var _gradient: GradientTexture1D = null


## *colors* evenly spaced from left to right.
func set_stops(colors: PackedColorArray) -> void:
    if colors.size() < 2:
        _gradient = null
        queue_redraw()
        return
    var gradient := Gradient.new()
    var offsets := PackedFloat32Array()
    for i in colors.size():
        offsets.append(float(i) / float(colors.size() - 1))
    gradient.offsets = offsets
    gradient.colors = colors
    _gradient = GradientTexture1D.new()
    _gradient.gradient = gradient
    _gradient.width = 256
    queue_redraw()


func _draw() -> void:
    draw_style_box(_style_bg, Rect2(Vector2.ZERO, size))
    var inset := float(SaUI.px(2))
    var inner := Rect2(inset, inset, maxf(0.0, size.x - 2.0 * inset), maxf(0.0, size.y - 2.0 * inset))
    if _gradient != null:
        draw_texture_rect(_gradient, inner, false)
    var ratio: float = 0.0
    if max_value > min_value:
        ratio = clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
    # The marker: a light line with a dark edge either side, so it reads on
    # every colour the gradient can hold.
    var x := inner.position.x + inner.size.x * ratio
    var half := float(SaUI.px(1))
    draw_rect(Rect2(x - half - 1.0, 0.0, 2.0 * half + 2.0, size.y), Color(0.0, 0.0, 0.0, 0.6))
    draw_rect(Rect2(x - half, 0.0, 2.0 * half, size.y), Color(1.0, 1.0, 1.0, 0.95))
