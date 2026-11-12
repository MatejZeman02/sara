## The tool options bar's four switches: the three symmetry toggles and the
## stabiliser one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Apart from `ui/tool_options/tool_options_bar.gd` by responsibility: every
## other control on that bar is built from a tool's `SaOptionSpec` list and
## writes to a tool, and these four write to the document or through the option
## door without a spec of their own. Three of them are not a brush setting at
## all.
##
## A `RefCounted` holding four `Button`s rather than a `Container` of its own,
## because the bar's stored layout moves each of them independently: the painter
## can put Mirror H on the second row and Radial on the first, and a box would
## make the four one element.
class_name SaToolOptionsSwitches
extends RefCounted

## What the toggle turns on when the painter has not chosen a mode yet. Average
## rather than Rope, because it is the gentler of the two and the one a
## stabilizer is usually reached for.
const DEFAULT_STABILIZER_MODE: int = 1

## The stabiliser toggle's word on every row and in the overflow's list. The
## first row once carried a cut "Stab" where its room is scarcest, which two
## sweeps read as a word that says nothing to a painter, so the whole name is
## the one it has.
const STABILIZER_NAME := "Stabilizer"

## The symmetry switches, on the document rather than the brush, so they read
## the document under the bar and follow it.
var mirror_h_btn: Button = null
var mirror_v_btn: Button = null
var radial_btn: Button = null

## The stabiliser's quick toggle, and the mode it puts back. The mode is
## remembered so a painter who chose Rope gets Rope again rather than the
## default.
var stabilizer_btn: Button = null
var last_stabilizer_mode: int = DEFAULT_STABILIZER_MODE

## Answers the document whose symmetry the three toggles write, the settings
## resource the stabiliser reads, and the door it writes through. All three are
## handed over, the way `ToolOptionsPresets` takes its two, so this knows nothing
## about the bar that built it.
var document_source: Callable = Callable()
var settings_source: Callable = Callable()
var write_option: Callable = Callable()

## True while the host is the one moving a control, so mirroring a value onto a
## toggle does not write it straight back.
var muted: bool = false


## Builds the four toggles as children of *host*, in the order the bar shows
## them.
##
## The two axes are Mirror H and Mirror V, the short form of the commands'
## Mirror Horizontally and Mirror Vertically, and show an icon. The view's flip
## on H says Flip and never Mirror: one word for both jobs had a painter who
## meant to check a face flipped paint two noses. The icon is an axis between a
## shape and its reflection, and the word is the fallback's when the icon
## cannot be found.
func build(host: Container, make_toggle: Callable) -> void:
    mirror_h_btn = make_toggle.call(host, tr("Mirror H"), _on_symmetry_toggled.bind(&"mirror_horizontal"), "symmetry_horizontal")
    mirror_h_btn.name = "SymmetryHorizontal"
    mirror_h_btn.tooltip_text = tr("Paint every stroke again, mirrored left to right.")
    mirror_v_btn = make_toggle.call(host, tr("Mirror V"), _on_symmetry_toggled.bind(&"mirror_vertical"), "symmetry_vertical")
    mirror_v_btn.name = "SymmetryVertical"
    mirror_v_btn.tooltip_text = tr("Paint every stroke again, mirrored top to bottom.")
    radial_btn = make_toggle.call(host, tr("Radial"), _on_symmetry_toggled.bind(&"radial"))
    radial_btn.tooltip_text = tr("Repeat every stroke around the centre.")

    # Beside the symmetry three because they are the same kind of thing: a
    # switch that changes what the next stroke does. It is one control for a
    # value the dropdown states in full, so the two write through the same door
    # and hear each other's writes.
    stabilizer_btn = make_toggle.call(host, tr(STABILIZER_NAME), _on_stabilizer_toggled)
    stabilizer_btn.tooltip_text = tr("Steady the stroke. Choose the stabilizer and its strength in the Tool Options docker.")


## The document's symmetry, or null on a bar with no document behind it.
func symmetry() -> SaSymmetry:
    var document := document_source.call() as SaDocument if document_source.is_valid() else null
    return document.symmetry if document != null else null


func _on_symmetry_toggled(pressed: bool, field: StringName) -> void:
    if muted:
        return
    var mirrors := symmetry()
    if mirrors == null:
        return
    if field == &"radial":
        mirrors.radial = mirrors.radial_count if pressed else 0
    else:
        mirrors.set(field, pressed)


## Mirrors the document's symmetry onto the three toggles, and follows it, so a
## command or another surface flipping a switch shows here too.
func sync_symmetry() -> void:
    var mirrors := symmetry()
    if mirrors == null or mirror_h_btn == null:
        return
    if not mirrors.changed.is_connected(sync_symmetry):
        mirrors.changed.connect(sync_symmetry)
    mirror_h_btn.set_pressed_no_signal(mirrors.mirror_horizontal)
    mirror_v_btn.set_pressed_no_signal(mirrors.mirror_vertical)
    radial_btn.set_pressed_no_signal(mirrors.radial >= 2)


## The quick toggle moved. Off is No Stabilizer and on is whichever mode the
## painter last had, so a toggle cannot silently change Rope into Average.
## Written through the bar's `write_option`, which is the door the docker's own
## dropdown writes through, so neither surface can hold a value the other does
## not.
func _on_stabilizer_toggled(pressed: bool) -> void:
    if muted or not write_option.is_valid():
        return
    write_option.call(&"stabilizer_mode", last_stabilizer_mode if pressed else 0)


## Puts the toggle where the shown tool's own value is, and remembers a mode
## worth putting back.
func sync_stabilizer() -> void:
    if stabilizer_btn == null:
        return
    var settings := settings_source.call() as Resource if settings_source.is_valid() else null
    if settings == null or not ("stabilizer_mode" in settings):
        return
    show_stabilizer_mode(int(settings.stabilizer_mode))


func show_stabilizer_mode(mode: int) -> void:
    if stabilizer_btn == null:
        return
    if mode > 0:
        last_stabilizer_mode = mode
    stabilizer_btn.set_pressed_no_signal(mode > 0)


## What the four switches are showing and which row the stabiliser is on, for a
## capture. The three symmetry toggles are read from the document elsewhere, so
## this is about the stabiliser's toggle, and what the symmetry pair shows a
## painter: its icon, its word and where it sits.
func report(host: Container) -> Dictionary:
    var out := {}
    for button: Button in [mirror_h_btn, mirror_v_btn]:
        if button != null:
            var place := button.get_global_rect()
            out[String(button.name)] = {
                "icon": button.icon.resource_path if button.icon != null else "",
                "text": button.text,
                "tooltip": button.tooltip_text,
                "pressed": button.button_pressed,
                "rect": {"x": place.position.x, "y": place.position.y, "w": place.size.x, "h": place.size.y},
            }
    if stabilizer_btn != null:
        var rect := stabilizer_btn.get_global_rect()
        out["stabilizer_toggle"] = {
            "text": stabilizer_btn.text,
            "tooltip": stabilizer_btn.tooltip_text,
            "pressed": stabilizer_btn.button_pressed,
            "visible": stabilizer_btn.visible,
            "remembered_mode": last_stabilizer_mode,
            "on_second_row": stabilizer_btn.get_parent() != host,
            "rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
        }
    # Outside the branch above, because a bar built before the toggle exists still
    # has a stabilizer mode worth dumping, and reading the two as one is how a
    # report of a half-built bar would come back empty rather than partial.
    var settings := settings_source.call() as Resource if settings_source.is_valid() else null
    if settings != null and "stabilizer_mode" in settings:
        out["stabilizer_mode"] = int(settings.stabilizer_mode)
    return out
