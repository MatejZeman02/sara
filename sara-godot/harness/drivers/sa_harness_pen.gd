## The pen a harness run presses with: its pressure table, its ceiling, and
## the fit that made the table from the widths the default brush paints.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A stroke step's pressure reads as a script expects.** A script that sends
## a stroke at 0.5 expects it about half as wide as one at 1.0. The default
## brush with Size by Pressure on draws its size along pressure to the power
## 4.8, the curve `_follow_toggle` in the stamp brush's settings draws for a
## painter's hand, so on the diagonal table a fresh profile has, strokes from
## 0.5 to 1.0 differ in width by a factor of fifty. A painter's defaults stay as
## they are, because every painter brings a curve and a ceiling of their own, so
## the harness gets a calibration of its own, and this is it.
##
## **The table is fitted, not guessed.** [constant WIDTHS] holds the width a
## stroke of the default brush paints at each of 41 pressures on the diagonal
## table, and [method fit] reads them the way the Tablet page's sweep dialog
## reads a hand, through `SaTabletSweep.fit`. There the hand means an even
## ramp and the pen reports a bent one. Here the pressure sent is the ramp and
## the width that came out, over the width at full pressure, is the bent
## reading. The inverse sends a pressure to the brush as the one that paints
## that fraction of the full width, so the width follows the number nearly in
## proportion. The suite beside this measures the widths again, holds the
## table to the fit and takes both again when asked.
##
## **No step of the table rises more than [constant MOST_STEP].** The widths
## are whole texels, and the brush paints none up to a press of 0.25 on the
## diagonal and one texel from 0.275 to 0.45, so the bare inverse jumped from
## 0 to 0.26 at the table's first step and from 0.27 to 0.46 at its third. No
## reading between them could be asked, and a stroke whose asked size crossed
## the jump bulged. Down there the
## proportion cannot hold under any table without such a jump: the size runs
## along the reading to the power 4.8, so a tenth of the full width wants a
## reading of 0.6, and a table that climbs no faster than 0.02 a step reaches
## 0.51 at a press of 0.1. So [method capped] lays the table's foot as the
## steepest ramp the cap allows, which meets the fit at a press of 0.13 and
## leaves every entry from there up as it was, 0.5 reading 0.841.
## Below 0.13 a stroke is narrower than its number asks: on the suite's brush
## 128 px across, 5 texels at 0.1 where the fit laid 11 and nothing at 0.05
## where it laid 7, and every size between is reached on the way up.
##
## **Copied, not loaded.** `scripts/shot_profile.py` copies [constant TABLE]
## into the scratch settings folder of every capture and every door session,
## where `SaTablet.load_correction` reads it at startup as it reads a
## painter's, so every brush the run makes is stamped with it. A `--watch`
## session runs on the painter's own folder and never gets it.
##
## **The ceiling is the default, and nothing writes it.** The harness's pen has
## no hardware, so the whole range 0 to 1 is its travel and its ceiling is
## [constant CEILING], which a scratch profile starts on. It is not copied
## like the table, because the settings file is the only place it lives, and
## a file of one key and no version is read as a profile from before version 4
## and migrated to the 0.73 an old Wacom measured.
class_name SaHarnessPen
extends RefCounted

## The table a harness run reads pressure through, in `SaTablet`'s own format:
## one value a line, indexed by pressure from 0 to 1.
const TABLE: String = "res://harness/drivers/pen_pressure_curve.txt"

## The fit's inputs: a pressure and the width in pixels it painted, a pair a
## line, with `#` lines saying how they were measured.
const WIDTHS: String = "res://harness/drivers/pen_pressure_widths.txt"

## The pressure a harness stroke calls full.
const CEILING: float = SaTablet.DEFAULT_MAX_PRESSURE

## The most the pressure Sara reads may rise from one entry of the table to the
## next, a step of 1 in 255 of the press. Under the 0.02 Friction 13's row asks
## by enough that six decimals and a read between two entries stay under it,
## and over the 0.0196 that lifts a press of 0.1 past half, which the noise
## brush's taper suite asks of this table.
const MOST_STEP: float = 0.0199


## The pairs in *path*, as `Vector2(pressure, width)` in the order written, or
## none when the file is missing or a line is not a pair of numbers.
static func read_widths(path: String = WIDTHS) -> PackedVector2Array:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return PackedVector2Array()
    var pairs := PackedVector2Array()
    for line in file.get_as_text().split("\n", false):
        var text := String(line).strip_edges()
        if text.is_empty() or text.begins_with("#"):
            continue
        var pair := text.split(" ", false)
        if pair.size() != 2 or not pair[0].is_valid_float() or not pair[1].is_valid_float():
            push_warning("SaHarnessPen: '%s' in the pen's widths is not a pair." % text)
            return PackedVector2Array()
        pairs.append(Vector2(pair[0].to_float(), pair[1].to_float()))
    return pairs


## The table in *path*, or none when the file is missing or a line is not a
## number.
static func read_table(path: String = TABLE) -> PackedFloat32Array:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return PackedFloat32Array()
    var values := PackedFloat32Array()
    for line in file.get_as_text().split("\n", false):
        var text := String(line).strip_edges()
        if text.is_empty():
            continue
        if not text.is_valid_float():
            return PackedFloat32Array()
        values.append(text.to_float())
    return values


## The table that makes *widths* follow the pressure, or none when they are too
## few to fit or the widest is no width at all.
##
## Each width is taken over the width at the highest pressure, so the fit
## reads a shape rather than a brush size, and the pairs go to
## `SaTabletSweep.fit` as one sweep with the pressure for its time. What comes
## back is [method capped], so no step of it is wider than
## [constant MOST_STEP].
static func fit(widths: PackedVector2Array) -> PackedFloat32Array:
    if widths.is_empty() or widths[widths.size() - 1].y <= 0.0:
        return PackedFloat32Array()
    var full := widths[widths.size() - 1].y
    var sweep := PackedVector2Array()
    for pair in widths:
        sweep.append(Vector2(pair.x, pair.y / full))
    return capped(SaTabletSweep.fit([sweep]))


## *table* with no entry more than [constant MOST_STEP] above the one before.
##
## The pass up from the first entry lowers each to at most that over the one
## before it, which is where a steep foot becomes a ramp, and the pass down
## from the fit's own last entry raises each to at least that under the one
## after, so a jump
## near the top is spread below it and full pressure still reads the last
## entry. Both keep a rising table rising, and an entry neither pass moves is
## the fit's own.
static func capped(table: PackedFloat32Array) -> PackedFloat32Array:
    var out := table.duplicate()
    if out.size() < 2:
        return out
    for i in range(1, out.size()):
        out[i] = minf(out[i], out[i - 1] + MOST_STEP)
    out[out.size() - 1] = table[table.size() - 1]
    for i in range(out.size() - 2, -1, -1):
        out[i] = maxf(out[i], out[i + 1] - MOST_STEP)
    return out


## Writes *widths* with *notes* as its `#` lines, and the table fitted from
## them, which is how the fit is taken again. Answers false when either file
## could not be written or the widths fit no table.
static func write(widths: PackedVector2Array, notes: PackedStringArray) -> bool:
    var table := fit(widths)
    if table.is_empty():
        return false
    var inputs := FileAccess.open(WIDTHS, FileAccess.WRITE)
    if inputs == null:
        return false
    for note in notes:
        inputs.store_line("# " + note)
    for pair in widths:
        inputs.store_line("%.3f %.1f" % [pair.x, pair.y])
    inputs.close()
    var output := FileAccess.open(TABLE, FileAccess.WRITE)
    if output == null:
        return false
    for value in table:
        output.store_line("%.6f" % value)
    return true
