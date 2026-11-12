## Container for values with non-linear transfer curves.
##
## Stores a base float and a gamma exponent. Useful for parameters
## like brush hardness or flow where linear sliders feel unnatural.
class_name GammaFloat extends Resource

@export_range(0.0, 1.0) var value: float = 0.0
@export var gamma_val: float = 1.0


func _init(init_val: float = 0.0, init_gamma: float = 1.0) -> void:
    self.value = init_val
    self.gamma_val = init_gamma


## Get gamma exponent
func gamma() -> float:
    return gamma_val


## Get inverted gamma exponent
func gamma_inv() -> float:
    return 1.0 / gamma_val


## Get raw float value
func raw() -> float:
    return value


## Apply gamma curve
func apply(input_val: float = value) -> float:
    return pow(clamp(input_val, 0.0, 1.0), gamma_val)


## Apply inverse gamma curve
func apply_inverse(input_val: float = value) -> float:
    return pow(clamp(input_val, 0.0, 1.0), 1.0 / gamma_val)


func _to_string() -> String:
    return "GammaFloat(%.2f, %.2f)" % [value, gamma_val]


## Checks if gammas are compatible
func has_same_gamma(other: Variant) -> bool:
    if other is GammaFloat:
        return is_equal_approx(gamma_val, other.gamma())
    return false
