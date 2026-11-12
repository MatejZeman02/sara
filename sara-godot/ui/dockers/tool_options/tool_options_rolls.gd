## What a randomise row of the Tool Options docker says above itself, once the
## top bar holds the slider the row rolls.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A module puts a randomise row under each slider it randomises, and the row is
## a `CUSTOM` one with no label of its own, because under its slider the slider
## is its name. The docker leaves a slider out when the bar shows it, and the
## row stayed, a pair of "Random: 0 %" and "Per dab" with a blank above and
## nothing to say whose roll it was, which is what Grain Round's docker showed
## with Radius and Opacity on the bar. So the row takes the slider's name for
## its own label while the bar holds the slider, "Radius jitter", and gives it
## up again when the slider comes back to the docker, where it sits under it as
## it always did.
##
## **The row's key is the only fact this has of the module.** The noise brush
## spells it the slider's key and `_random`, and a row that spells it another
## way is left as it is rather than guessed at. The name comes from the slider's
## own spec, so a module that renames its slider renames the row with it.
##
## **Its own class rather than lines in `tool_options_docker.gd`**, which owns
## which rows there are and stood at 979 lines, and this owns one thing, what a
## randomise row is called.
class_name ToolOptionsRolls
extends RefCounted

## What a randomise row's key carries after its slider's.
const SUFFIX: String = "_random"


## Whether *spec* is a randomise row: a custom row with no label of its own whose
## key is a slider's with the suffix on it.
static func is_roll(spec: SaOptionSpec) -> bool:
    return spec.kind == SaOptionSpec.Kind.CUSTOM and spec.label.is_empty() and String(spec.key).ends_with(SUFFIX)


## The slider *spec* rolls among *options*, or null when *spec* is no randomise
## row or its slider is not declared.
static func slider_of(spec: SaOptionSpec, options: Array[SaOptionSpec]) -> SaOptionSpec:
    if not is_roll(spec):
        return null
    var key := StringName(String(spec.key).trim_suffix(SUFFIX))
    for other: SaOptionSpec in options:
        if other.key == key:
            return other
    return null


## Writes the label of *row*, the docker's row for *spec*, when *spec* is a
## randomise row: the slider's name and "jitter" while *on_bar* says the bar
## holds that slider, and nothing otherwise. Any other row is left alone.
static func name_row(row: Control, spec: SaOptionSpec, options: Array[SaOptionSpec], on_bar: Callable) -> void:
    var label := row.get_node_or_null("Label") as Label
    var slider := slider_of(spec, options)
    if label == null or slider == null:
        return
    if on_bar.call(slider.key):
        # A shipped slider's label is whole, so a language with cases can
        # decline its name. A module's own slider reads the generic one.
        if SaWholeSentences.OPTION_JITTER.has(slider.label):
            label.text = TranslationServer.translate(SaWholeSentences.OPTION_JITTER[slider.label])
        else:
            label.text = TranslationServer.translate("%s jitter") % TranslationServer.translate(slider.label)
    else:
        label.text = ""
