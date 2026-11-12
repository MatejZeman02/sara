## The gradient tool's rows, as the Tool Options docker draws them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Its own file rather than lines in `module.gd`**, beside the tool it
## declares the rows of, because the rows and the ramp row's two doors are one
## responsibility and the module's registration another.
class_name SaGradientOptions
extends RefCounted


## The gradient's seven: the ramp itself, the shape a drag makes, what happens
## past the release point and in how many bands, which wobble pushes it off its
## axis and how far, and whether the ramp replaces what is under it. All on the
## tool, because they are this surface's gradient rather than a setting shared
## with the brush, and all docker rows: a gradient is set up before the drag,
## not adjusted during it, so none of them belongs on the top bar, and the ramp
## editor could not fit there in any case.
static func rows(ends: SaGradientEnds = null) -> Array[SaOptionSpec]:
    var shape := SaOptionSpec.make_enum(
        &"gradient_shape",
        "Gradient",
        [SaGradient.Shape.LINEAR, SaGradient.Shape.RADIAL],
        ["Linear", "Radial"],
        {
            "on_tool": true,
            "property": ^"shape",
            "width": 84,
            "bar": false,
            "tooltip": "Linear runs the ramp along the drag, radial out from the press."
        }
    )

    var repeat := SaOptionSpec.make_enum(
        &"gradient_repeat",
        "Repeat",
        [SaGradient.Repeat.NONE, SaGradient.Repeat.MIRROR, SaGradient.Repeat.REPEAT, SaGradient.Repeat.STEPS],
        ["None", "Mirror", "Repeat", "Steps"],
        {
            "on_tool": true,
            "property": ^"repeat",
            "width": 84,
            "bar": false,
            "tooltip":
            (
                "What the ramp does past the release point: hold the far colour, run back to the near one, "
                + "start again, or come out in bands rather than a blend."
            )
        }
    )

    var steps := (
        SaOptionSpec
        . make_float(
            &"gradient_steps",
            "Steps",
            float(SaGradient.MIN_STEPS),
            16.0,
            1.0,
            {
                "kind": SaOptionSpec.Kind.INT,
                "on_tool": true,
                "property": ^"steps",
                "width": 84,
                "bar": false,
                "tooltip": "Number of bands for the Steps repeat mode. Only used with Steps.",
                # The note is "Repeat and Wobble options should be dimmed when they have None
                # as selected", and a dimmed control is also disabled.
                # Gated on Steps rather than on "not None", because the row's own tooltip
                # already said it means nothing under the other three and dimming it at None
                # alone would leave the same dead control under Mirror and Repeat.
                "enabled_when": &"gradient_repeat",
                "enabled_when_values": [SaGradient.Repeat.STEPS]
            }
        )
    )

    var wobble := SaOptionSpec.make_enum(
        &"gradient_wobble",
        "Wobble",
        [SaGradient.Wobble.NONE, SaGradient.Wobble.NOISE, SaGradient.Wobble.VORONOI],
        ["None", "Noise", "Voronoi"],
        {
            "on_tool": true,
            "property": ^"wobble",
            "width": 84,
            "bar": false,
            "tooltip": "Push the ramp off its axis: Noise for a soft ripple, Voronoi for cells."
        }
    )

    var wobble_amount := (
        SaOptionSpec
        . make_float(
            &"gradient_wobble_amount",
            "Wobble amount",
            0.0,
            1.0,
            0.01,
            {
                "on_tool": true,
                "property": ^"wobble_amount",
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "width": 96,
                "bar": false,
                "tooltip": "How far the wobble pushes, as a fraction of the ramp. Dimmed while the wobble is off.",
                # The amount belongs to the Wobble row above, so None there is what dims it.
                "enabled_when": &"gradient_wobble",
                "enabled_when_values": [SaGradient.Wobble.NOISE, SaGradient.Wobble.VORONOI]
            }
        )
    )

    var replace := SaOptionSpec.make(
        &"gradient_replace",
        "Replace",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"replace",
            "bar": false,
            "tooltip": "Replace the pixels, including transparency, instead of painting over them."
        }
    )

    var ramp := (
        SaOptionSpec
        . make_custom(
            &"gradient_ramp",
            "Ramp",
            build_ramp_control.bind(ends),
            bind_ramp_control,
            {
                "on_tool": true,
                # The tool's signal rather than its ramp, so the row's binder is handed the
                # tool: the row says whether the ramp follows the colours and its stock rows
                # make it follow them again, which only the tool knows.
                "property": ^"following_changed",
                "width": 160,
                "bar": false,
                "tooltip":
                "The colours the drag lays down. Click to add a stop, drag one to move it, right-click one to remove it."
            }
        )
    )

    # First, because it is the option a painter looks at rather than sets once,
    # and because the three below it are what to do with the ramp it holds.
    return [ramp, shape, repeat, steps, wobble, wobble_amount, replace]


## The ramp row's widget, which this module brings rather than the skeleton.
##
## An option kind a module fills with its own widget. The colour ramp control
## serves the gradient tool and nothing else, so it lives in `base/ui/` beside
## it, and this is the door it comes back through, the same shape
## `SaUIRegistry.register_docker` gives a docker.
##
## *write* is unused, and that is the ramp rather than the door: its value is the
## tool's `following_changed`, a signal the binder below points the control at the
## tool through, so every edit a painter makes lands on the tool's own ramp and
## there is nothing to report.
## A widget holding a number calls it and the skeleton does the writing. The
## width, the node name and the tooltip come off the descriptor on the skeleton's side,
## so a module bringing a widget does not also have to know how a row is named.
##
## *ends* is bound on by [method rows], the module's end rule, so an
## endpoint's alpha edited in the row is remembered in this module's own
## preferences.
static func build_ramp_control(_spec: SaOptionSpec, _write: Callable, ends: SaGradientEnds = null) -> Control:
    return SaColorRampControl.new(null, ends)


## What the built ramp does with the value behind its option, the tool's
## `following_changed`: the control finds the tool through it and binds the
## tool's own ramp, pointed at rather than handed a copy, for the reason above.
static func bind_ramp_control(control: Control, value: Variant) -> void:
    (control as SaColorRampControl).follow_tool(value)
