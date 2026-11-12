## The noise brush's Tip row, the Edge Hardness row under its generated tips,
## the Angle row, the tip's fixed turn, and, under its Image choice, the Tip
## Image list and the Load Tip action, which load a picture into the tip as the
## stamp brush's rows do.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The kernel paints whatever picture the door's `SaBrushTipMask` binds, so
## these rows only choose one and load it.
##
## **What the list offers is the door's.** The row is the door's
## `SaOptionSpec.Kind.TIP_IMAGE`, the same row the stamp brush declares under
## the same key, so the surfaces draw one grid of the tips' pictures for either
## engine, filtered by the folders [SaTipChoices] lists them under. This module
## once drew a dropdown of its own through the `CUSTOM` door, because the
## stamp's list was an `ENUM` whose choices were fixed when the spec was made
## and the key could not be shared with a control of another kind. The grid is
## the door's now, and both rows are of its kind.
##
## **A press writes the tip's path, and the Load Tip action goes through the
## tool's `load_tip`**, so a picture read from outside the tip folders is
## refused with its reason when it cannot be read, and the grid hears every
## load on the tool's `tip_loaded`.
extends RefCounted

## The Tip row's choices, the door's three generators and the picture. Image is
## the generator the kernel branches on for a picture, and the two rows below
## are shown only while it is chosen.
const IMAGE: int = SaDabGeometry.Generator.IMAGE
const GENERATORS: Array = [0, 1, 2, IMAGE]
const LABELS: Array = ["Default", "Gaussian", "Soft Curve", "Image"]

## The Tip Image row's key, the stamp's, so the docker draws one grid for both.
const LIST_KEY: StringName = &"tip_image_path"

## The Edge Hardness row's key, this engine's own rather than the stamp's
## `tip_softness`, since the docker builds one row for a key whichever engine
## declared it first and the stamp's row says a different sentence. The
## module's `UNROLLED` names it, since the tip's softness has no curve option
## for a randomise control to bind.
const EDGE_KEY: StringName = &"noise_tip_edge"

## The Angle row's key, the stamp's, so the docker draws one row for both.
const ANGLE_KEY: StringName = &"tip_angle"


## The Tip row and the Edge Hardness row under it while Tip is not Image,
## then the Tip Image list and the Load Tip action, the two shown only while
## Image is chosen, as on the stamp's Brush Tip page. Each on *page*, the
## engine's, and an empty one leaves them where a row with no page goes.
static func rows(page: String = "") -> Array[SaOptionSpec]:
    var tip := SaOptionSpec.make_enum(
        &"tip_generator",
        "Tip",
        GENERATORS,
        LABELS,
        {
            "page": page,
            "property": ^"tip:generator",
            "bar": false,
            "width": 96,
            "tooltip": "How the tip's edge falls off, or Image for a picture whose outline bounds the stroke."
        }
    )

    # The round's edge. A strict round mask reads harsh, because the noise
    # brush has no opacity in play to soften it. The noise brush's fades are
    # one, so the tip's
    # softness alone says where the edge starts to fall: 100 is the hard disc
    # and lower starts the fall nearer the centre. The tip is applied after the
    # cut, so the fall softens the rim as alpha and the grain inside stays cut.
    var edge := SaOptionSpec.make_float(
        EDGE_KEY,
        "Edge Hardness",
        0.0,
        1.0,
        0.01,
        {
            "page": page,
            "property": ^"tip:softness",
            "bar": false,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "shown_when": {"key": &"tip_generator", "value": IMAGE, "equals": false},
            "tooltip":
            (
                "How hard the tip's round edge is: at 100 it is hard, and lower starts its fade nearer the centre. "
                + "Hardness above is the edge of the texture's holes, not the tip's."
            )
        }
    )

    # The tip's fixed turn, the stamp's Angle row word for word under its key,
    # because the docker builds one row for a key whichever engine came first.
    # The kernel turns the tip by it before the Rotation option adds its own, and
    # it shows on a picture, whose outline turns, while a plain round looks the
    # same at every angle.
    var angle := SaOptionSpec.make_float(
        ANGLE_KEY,
        "Angle",
        0.0,
        TAU,
        deg_to_rad(1.0),
        {
            "page": page,
            "property": ^"tip:angle",
            "bar": false,
            "display_scale": 180.0 / PI,
            "decimals": 0,
            "suffix": "°",
            "tooltip": "The tip's fixed turn. The Rotation page's sensors turn it further from here."
        }
    )

    var listed := (
        SaOptionSpec
        . make_tip_image(
            LIST_KEY,
            "Tip image",
            {
                "page": page,
                "bar": false,
                "advanced": true,
                "shown_when": {"key": &"tip_generator", "value": IMAGE},
                # The stamp's sentence word for word, because the docker builds one row for
                # the key whichever engine declared it first.
                "tooltip":
                (
                    "The tip image. Choose from Sara's tips, imported tips or a folder. "
                    + "The filter above shows one folder at a time."
                )
            }
        )
    )

    # The stamp's action under the stamp's key, so the docker's one button
    # loads a tip into whichever engine the Brush paints with.
    var load_tip := SaOptionSpec.make(
        &"tip_load",
        "Load Tip",
        SaOptionSpec.Kind.ACTION,
        {
            "page": page,
            "on_tool": true,
            "property": ^"load_tip_dialog",
            "bar": false,
            "advanced": true,
            "shown_when": {"key": &"tip_generator", "value": IMAGE},
            "tooltip": "Reads a .png or a .gbr picture and paints through it."
        }
    )
    return [tip, edge, angle, listed, load_tip]
