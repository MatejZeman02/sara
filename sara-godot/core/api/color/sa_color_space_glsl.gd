## The GLSL side of a colour space: the matrix layout a shader wants, and the
## `.gmacs` include generated from a document's descriptor. Split out of
## `sa_color_space.gd`. Static helpers taking the space as an argument,
## because `SaColorSpace` is a value type that composes nothing.
class_name SaColorSpaceGlsl
extends RefCounted


## The three columns of a basis, in the order GLSL wants them.
##
## A GLSL mat3 constructor takes columns, and so does a Godot Basis, so the three
## basis vectors go out in order with no transpose. Writing this the other way
## produces a matrix that still compiles, still inverts, and is silently wrong.
##
## Public because the view shader needs the same convention the kernels use. A
## GLSL mat3 constructor takes columns and an std430 mat3 is stored by column, so
## this one function is what keeps the .gmacs push constant, the generated
## mat3 literal and the canvas material from disagreeing about which is which.
static func basis_columns(basis: Basis) -> Array[Vector3]:
    return [basis * Vector3(1.0, 0.0, 0.0), basis * Vector3(0.0, 1.0, 0.0), basis * Vector3(0.0, 0.0, 1.0)]


static func _mat3_literal(basis: Basis) -> String:
    var columns := basis_columns(basis)
    var parts := PackedStringArray()
    for column: Vector3 in columns:
        parts.append("%.9f, %.9f, %.9f" % [column.x, column.y, column.z])
    return "mat3( %s )" % ", ".join(parts)


## `space`'s colour maths as a `.gmacs` include.
##
## Emits the RGB<->XYZ matrices this descriptor implies and a transfer pair named
## for the document rather than for sRGB, so a kernel asks "decode this document's
## values" instead of hardcoding one curve. A linear document gets an identity
## transfer, which is the whole point: nothing in the kernel changes, the
## generated function does.
##
## The sRGB branch is the mirrored form from `linear_srgb_color_space.gmacs`, for
## the reason recorded there, `pow` is undefined for a negative base and GLSL
## `mix()` evaluates both arms, so out-of-range values need the curve mirrored
## through the origin rather than clamped away.
static func to_glsl(space: SaColorSpace) -> String:
    var lines := PackedStringArray()
    lines.append("// Generated from the document's SaColorSpace. Do not edit by hand.")
    lines.append("// Source of truth: core/api/color/sa_color_space.gd")
    lines.append("const mat3 DOCUMENT_RGB_TO_XYZ = %s;" % _mat3_literal(space.rgb_to_xyz()))
    lines.append("const mat3 DOCUMENT_XYZ_TO_RGB = %s;" % _mat3_literal(space.xyz_to_rgb()))
    lines.append("")

    var transfer := space.transfer
    if transfer.is_identity():
        lines.append("// Linear document: the transfer pair is the identity, written as one so")
        lines.append("// pow( x, 1.0 ) never gets the chance to perturb a value that should not move.")
        lines.append("vec3 document_to_linear( vec3 c ) { return c; }")
        lines.append("vec3 linear_to_document( vec3 c ) { return c; }")
    else:
        lines.append("// %s: the piecewise curve, mirrored through the origin so negatives" % transfer.display_name)
        lines.append("// survive instead of becoming NaN.")
        lines.append("vec3 document_to_linear( vec3 c )")
        lines.append("{")
        lines.append("    vec3 m = abs( c );")
        lines.append(
            (
                "    return sign( c ) * mix( m / %.9f, pow( ( m + %.9f ) / %.9f, vec3( %.9f ) ), step( %.9f, m ) );"
                % [transfer.slope, transfer.offset(), transfer.gain, transfer.exponent, transfer.threshold]
            )
        )
        lines.append("}")
        lines.append("vec3 linear_to_document( vec3 c )")
        lines.append("{")
        lines.append("    vec3 m = abs( c );")
        (
            lines
            . append(
                (
                    "    return sign( c ) * mix( %.9f * m, %.9f * pow( m, vec3( %.9f ) ) - %.9f, step( %.9f, m ) );"
                    % [
                        transfer.slope,
                        transfer.gain,
                        1.0 / transfer.exponent,
                        transfer.offset(),
                        transfer.linear_threshold(),
                    ]
                )
            )
        )
        lines.append("}")

    lines.append("")
    lines.append("vec3 document_to_xyz( vec3 c ) { return DOCUMENT_RGB_TO_XYZ * document_to_linear( c ); }")
    lines.append("vec3 xyz_to_document( vec3 c ) { return linear_to_document( DOCUMENT_XYZ_TO_RGB * c ); }")
    return "\n".join(lines)
