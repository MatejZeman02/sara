## The Magnetic Lasso's own rows in the tool options: Width, Contrast,
## Frequency and Sample merged. The mode, the Feather and the Anti-aliasing
## are the other lassos' rows, which `module.gd` adds after these, so the
## three read one setting on every lasso.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Off the bar, all four, as the lasso's Anti-aliasing is: they tune how the
## path finds an edge rather than what the next click makes, and the bar's
## first row is measured full at 1920.
extends RefCounted


static func rows() -> Array[SaOptionSpec]:
    var width := SaOptionSpec.make_float(
        &"magnetic_width",
        "Width",
        0.0,
        40.0,
        1.0,
        {
            "kind": SaOptionSpec.Kind.INT,
            "on_tool": true,
            "property": ^"width",
            "suffix": " px",
            "bar": false,
            "tooltip": "Look for an edge this many screen pixels from the pointer, and draw the path along the strongest."
        }
    )
    var contrast := SaOptionSpec.make_float(
        &"magnetic_contrast",
        "Contrast",
        0.0,
        1.0,
        0.01,
        {
            "on_tool": true,
            "property": ^"contrast",
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip": "Ignore edges weaker than this. Raise it on a busy picture, lower it for a faint edge."
        }
    )
    var frequency := SaOptionSpec.make_float(
        &"magnetic_frequency",
        "Frequency",
        0.0,
        1.0,
        0.01,
        {
            "on_tool": true,
            "property": ^"frequency",
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "bar": false,
            "tooltip": "Lay anchors on their own this often where the path has settled. At 0 only a click lays one."
        }
    )
    var merged := SaOptionSpec.make(
        &"sample_merged",
        "Sample merged",
        SaOptionSpec.Kind.BOOL,
        {"on_tool": true, "bar": false, "tooltip": "Read every layer as shown, rather than the active layer alone."}
    )
    return [width, contrast, frequency, merged]
