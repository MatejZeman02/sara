## The transform tool's rows, as the Tool Options docker draws them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Its own file rather than lines in `module.gd`**, for the reason
## [SaGradientOptions] gives. Beside the module rather than in `transform/`,
## which is already as long as a folder read whole should be.
class_name SaTransformOptions
extends RefCounted

const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")


## The transform's rows: where the picture is, how big it is, how far it has
## been turned and leaned, the two buttons that mirror it, which filter the
## resample reads with, and the two buttons that end the gesture.
##
## Every row is a reading of the one matrix the handles drive, so typing a
## number and pulling the matching handle end in the same document. All of them
## are off the bar: the first row is already full at 1920 and eight more rows
## is not a question worth asking.
static func rows() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []

    # First, because it decides what every row under it and every handle on the
    # canvas mean. The ids are `StateTransform.Mode` rather than the numbers, so
    # a mode added there appears here by name, which is the rule the filter row
    # below already follows for `SaResampleKernel.Filter`.
    var modes := StateTransformScript.Mode
    var mode := SaOptionSpec.make_enum(
        &"transform_mode",
        "Mode",
        [modes.NORMAL, modes.PERSPECTIVE, modes.SHEAR, modes.FREEHAND, modes.MIRRORED, modes.CAGE],
        ["Normal", "Perspective", "Shear", "Freehand", "Mirrored", "Cage"],
        {
            "on_tool": true,
            "property": ^"transform_mode",
            "width": 130,
            "bar": false,
            "tooltip":
            (
                "What a handle drag means. Normal scales, Shift keeping the proportions and Ctrl and an edge handle "
                + "shearing. Shear leans an edge "
                + "over from any handle. Perspective moves a corner and its neighbour the mirror way along the edge "
                + "you drag it along, Shift and a corner moving the one corner. Freehand bends the picture by the nine "
                + "points of its grid, which are what you drag, and Mirrored moves the opposite corner or side the "
                + "other way with the one you drag. Cage bends what lies inside a cage you click round it."
            )
        }
    )
    out.append(mode)

    for axis: Array in [["x", "X"], ["y", "Y"]]:
        var moved := SaOptionSpec.make_float(
            StringName("transform_move_%s" % axis[0]),
            "Position %s" % axis[1],
            -4096.0,
            4096.0,
            1.0,
            {
                "on_tool": true,
                "property": NodePath("move_%s" % axis[0]),
                "decimals": 0,
                "suffix": " px",
                "bar": false,
                "tooltip": "How far the picture has moved from where it was lifted, along %s." % axis[1]
            }
        )
        out.append(moved)

    for axis: Array in [
        ["x", "Width", "Horizontal scale, as a share of the lifted area."],
        ["y", "Height", "Vertical scale, as a share of the lifted area."],
    ]:
        # 5 per cent to 400, rather than the pass's own floor of 1 per cent to
        # anything: a slider whose whole useful range is its first eighth is a
        # slider a painter cannot land 100 on.
        var sized := SaOptionSpec.make_float(
            StringName("transform_scale_%s" % axis[0]),
            axis[1],
            0.05,
            4.0,
            0.01,
            {
                "on_tool": true,
                "property": NodePath("scale_%s" % axis[0]),
                "percent": true,
                "decimals": 0,
                "suffix": "%",
                "bar": false,
                "tooltip": axis[2]
            }
        )
        out.append(sized)

    var angle := SaOptionSpec.make_float(
        &"transform_angle",
        "Angle",
        -180.0,
        180.0,
        0.5,
        {
            "on_tool": true,
            "property": ^"angle_degrees",
            "decimals": 1,
            "suffix": "°",
            "bar": false,
            "tooltip": "How far the picture is turned about the box's centre. A drag just outside a corner does the same."
        }
    )
    out.append(angle)

    var shear := SaOptionSpec.make_float(
        &"transform_shear",
        "Shear",
        -70.0,
        70.0,
        0.5,
        {
            "on_tool": true,
            "property": ^"shear_degrees",
            "decimals": 1,
            "suffix": "°",
            "bar": false,
            "tooltip": "How far the box leans off square. Ctrl and an edge handle does the same."
        }
    )
    out.append(shear)

    # Beside the rows that read the picture's shape, because a flip is a width
    # or a height of minus a hundred per cent that nobody should have to type.
    for flip: Array in [["horizontal", "Horizontally", "left to right"], ["vertical", "Vertically", "top to bottom"]]:
        var button := SaOptionSpec.make(
            StringName("transform_flip_%s" % flip[0]),
            "Flip %s" % flip[1],
            SaOptionSpec.Kind.ACTION,
            {
                "on_tool": true,
                "property": NodePath("flip_%s" % flip[0]),
                "bar": false,
                "tooltip":
                (
                    "Mirror what is in the box %s about its own middle, the selection's pixels when there is one. " % flip[2]
                    + "Apply writes it down."
                )
            }
        )
        out.append(button)

    # The ids are `SaResampleKernel.Filter` rather than the numbers, so a filter added
    # there appears here by name and neither list can drift from the other.
    var filters := SaResampleKernel.Filter
    var filter := SaOptionSpec.make_enum(
        &"transform_filter",
        "Filter",
        [filters.BILINEAR, filters.NEAREST],
        ["Bilinear", "Nearest"],
        {
            "on_tool": true,
            "property": ^"filter_mode",
            "width": 110,
            "bar": false,
            "tooltip":
            (
                "How the pixels are resampled. Bilinear blends neighbouring pixels for a smooth result, "
                + "Nearest keeps hard pixel edges and adds no new colours."
            )
        }
    )
    out.append(filter)

    var apply := SaOptionSpec.make(
        &"transform_apply",
        "Apply",
        SaOptionSpec.Kind.ACTION,
        {
            "on_tool": true,
            "property": ^"commit_move",
            "bar": false,
            "tooltip": "Write the move into the layer as one undo step. Enter does the same."
        }
    )
    out.append(apply)

    var reset := SaOptionSpec.make(
        &"transform_reset",
        "Reset",
        SaOptionSpec.Kind.ACTION,
        {
            "on_tool": true,
            "property": ^"cancel_move",
            "bar": false,
            "tooltip": "Put the pixels back where they were lifted from. Escape does the same."
        }
    )
    out.append(reset)

    return out
