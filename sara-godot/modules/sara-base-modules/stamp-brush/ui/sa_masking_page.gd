## The brush editor's Masking Brush page, as the rows it declares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The Brush Tip page's rows over the second tip, rather than a second set
## written by hand.** The settings hold an `SaMaskingBrush` holding its own
## `SaBrushTip`, so every question the Brush Tip page asks about the painted tip
## is a question this page asks about the mask, with the same ranges and the
## same tooltips. [method rows] takes the module's own `tip_options()` and
## rewrites the three things that differ, the key, the property and the name, so
## a row added to the Brush Tip page tomorrow is on this page the same day and
## neither list can drift from the other.
##
## **What it drops, and why.** A row is taken when its property reaches into the
## tip, `tip:generator` and the twelve beside it. Spacing, Cross, the airbrush
## three and the two Sharpness rows are the brush's rather than the tip's, and
## Load Tip is an action on the tool that opens a file dialog writing to the
## painted tip. So a painter can point the mask at a tip already on disk through
## Tip Image, and loading a new file into the mask is a door not yet opened.
## Beside those, the rows in [constant NOT_THE_MASKS] are dropped for the other
## reason a row has no business here: the mask does not read its picture.
##
## **Declared and not drawn, the way the Texture page is.** No file under
## `ui/brush_editor/` names a mask, a second tip or a multiplier: the page is
## `SaOptionSpec` rows naming their page by title, so the same rows reach the
## Tool Options docker behind its Advanced check: a module declares a page the
## way a third-party one would, and no built-in page is drawn by hand.
##
## **The page's switch is the mask's own.** `masking_enabled` carries
## `page_switch`, so the editor draws it as the switch at the top of the page,
## with a dot in the page list while it is on, and the page draws no Enabled row
## of its own. A page takes a switch only where there is something to switch,
## the reason `page_list.gd` gives being that a switch on a page with nothing
## behind it reads as an option the painter is not allowed to turn off. A mask
## that is off by default is something to switch, so the flag says which row the
## tick is rather than making the mask pretend to be a modulated parameter.
class_name SaMaskingPage
extends RefCounted

## The page's title, and every row's `page`.
const PAGE: String = "Masking Brush"

## What a taken row's key and property both gain, so `tip_ratio` on the painted
## tip and `masking_tip_ratio` on the mask are two rows the layout can tell
## apart and two controls the docker builds separately.
const PREFIX: String = "masking_"
const PROPERTY_ROOT: String = "masking:"

## What a taken row's label gains, and the one thing about a taken row that the
## first draft left alone and should not have.
##
## Ratio means the same thing about either tip, so keeping the Brush Tip page's
## word read like the right answer. It is the right answer on a page, which has a
## heading over it saying which tip is being set, and the wrong one in the Tool
## Options docker, which draws every row a tool declares in one flat list with no
## headings at all. `ui/dockers/tool_options/tests/test_painter.gd` is where that shows: it holds that
## no name is on the brush's page twice, because the drive photographed six rows
## a painter could not tell apart, and thirteen unprefixed mask rows put the same
## six back.
const LABEL_PREFIX: String = "Mask "

## The property every row this page takes reaches through on the painted tip.
## A row that does not begin with it is the brush's rather than the tip's.
const TIP_ROOT: String = "tip:"

## The mask's diameter as a multiple of the dab's, which is the one number
## `SaMaskingBrush` chose over Krita's absolute size. Four is a mask four times
## the dab, which is the whole dab under one corner of the shape, and the floor
## is low rather than zero because zero is a mask of nothing over a dab that was
## going to paint.
const MIN_SIZE: float = 0.05
const MAX_SIZE: float = 4.0

## The Brush Tip rows that are about the painted tip's *picture* rather than
## about the shape of a tip, and are therefore not the mask's.
##
## **Because the mask's picture is never sampled.** The mask reads as a ramp
## whatever file its Tip Image names: an image second tip is the default
## generator over the mask's own ellipse, which `sa_mask_coverage` says where it
## chooses. So a row that moves something the kernel does not read is a control
## that lies, which is the same judgement `in_editor`'s rows are dropped by.
##
## A list rather than a rule, because there is no property of a row that says
## whether the mask can honour it: this one reaches into the tip exactly as
## Ratio and Spikes do, and the difference is in the kernel.
const NOT_THE_MASKS: Array[StringName] = [&"tip_lightness"]


## The page's rows: the switch, the mask's own two numbers, then the tip rows of
## *tip_rows* rewritten onto the mask.
##
## *tip_rows* is handed in rather than reached for, because the module is what
## declares them and a file naming the module that the module names back is a
## cycle at parse time. Each tip row is remade over the mask rather than
## changed, so *tip_rows* are left as they came.
static func rows(tip_rows: Array[SaOptionSpec]) -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = [_switch(), _size(), _spacing()]
    for spec: SaOptionSpec in tip_rows:
        if spec == null or not String(spec.property).begins_with(TIP_ROOT):
            continue
        if NOT_THE_MASKS.has(spec.key):
            continue
        out.append(_over_the_mask(spec))
    return out


## What every row of the page shares: the page, and off the bar and behind
## Advanced for the reason the Texture page gives. The bar is measured, and a
## painter who has not met the idea of a second shape multiplying the first has
## no use for sixteen more rows in the docker.
static func _on_the_page(fields: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var all_fields: Dictionary[String, Variant] = {"page": PAGE, "bar": false, "advanced": true}
    all_fields.merge(fields, true)
    return all_fields


## The page's switch, drawn at the top of the page, and the only row on this
## page the editor does not put in the page box as a row.
static func _switch() -> SaOptionSpec:
    var spec := (
        SaOptionSpec
        . make(
            &"masking_enabled",
            "Masking Brush",
            SaOptionSpec.Kind.BOOL,
            _on_the_page(
                {
                    "property": ^"masking:enabled",
                    "page_switch": true,
                    # The switch at the top of the page is this row's face in the editor.
                    # Without this the page would show the same switch twice, once beside its
                    # title and once as an Enabled row under the heading.
                    "in_editor": false,
                    "tooltip": "Multiplies every dab by a second shape. Off leaves the brush painting exactly as it did."
                }
            )
        )
    )
    return spec


static func _size() -> SaOptionSpec:
    var spec := SaOptionSpec.make_float(
        &"masking_size",
        "Mask Size",
        MIN_SIZE,
        MAX_SIZE,
        0.05,
        _on_the_page(
            {
                "property": ^"masking:size",
                "decimals": 2,
                "suffix": "x",
                "tooltip":
                (
                    "The mask's diameter as a multiple of the dab's, so the mask stays on the dab at every brush size. "
                    + "1 is a mask exactly the size of the dab it masks."
                )
            }
        )
    )
    return spec


static func _spacing() -> SaOptionSpec:
    var spec := SaOptionSpec.make_float(
        &"masking_spacing",
        "Mask Spacing",
        0.01,
        1.0,
        0.01,
        _on_the_page(
            {
                "property": ^"masking:spacing",
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "tooltip": "How far the mask travels between its own dabs, as a share of its size."
            }
        )
    )
    return spec


## One Brush Tip row pointed at the mask instead.
##
## What describes the *setting* is left alone: the tooltip, the range, the
## width, the section, `in_editor` and the kind all say the same thing about a
## tip whichever tip it is. What changes is the row's address, the key, the
## property and every reference to another key, because the mask's rows have to
## have addresses of their own or the docker would build one control for both
## tips, and its name, for the reason [constant LABEL_PREFIX] gives.
static func _over_the_mask(spec: SaOptionSpec) -> SaOptionSpec:
    var fields := _on_the_page(
        {
            "property": NodePath(PROPERTY_ROOT + String(spec.property)),
            "label": LABEL_PREFIX + spec.label,
            "key": _renamed(spec.key),
            "enabled_when": _renamed(spec.enabled_when),
            "pair_with": _renamed(spec.pair_with),
        }
    )
    if not spec.pair_label.is_empty():
        fields["pair_label"] = LABEL_PREFIX + spec.pair_label
    if spec.shown_when.has("key"):
        var shown := spec.shown_when.duplicate()
        shown["key"] = _renamed(StringName(spec.shown_when["key"]))
        fields["shown_when"] = shown
    return spec.remade(fields)


## *key* on the mask, and an empty key left empty: `enabled_when` and
## `pair_with` are both empty for most rows and an empty one means no rule, not
## a rule about a row called `masking_`.
static func _renamed(key: StringName) -> StringName:
    return key if String(key).is_empty() else StringName(PREFIX + String(key))
