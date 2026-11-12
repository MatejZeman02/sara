## Krita's own pressure curve, read from the `kritarc` of the machine running
## a Krita import, as the table a stamp preset carries.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why an import reads it.** Krita has one pressure curve for the whole
## program, and a Krita preset was tuned under it: its option curves were drawn
## against pressure that had already been through that curve. Sara's stamp
## preset carries the table it was made under in `maker_pressure_curve`,
## so the import stamps the preset with Krita's curve rather than with the
## importing painter's, and the preset then answers Krita's curve and its own
## option curves whatever table the painter has. Rewriting the option curves
## through the inverse of Sara's table was not taken, because a curve with a
## flat stretch has no inverse.
##
## **The file**, as the Krita FAQ at docs.krita.org places it:
## `$HOME/.config/kritarc` on Linux, `%LOCALAPPDATA%\kritarc` on Windows and
## `$HOME/Library/Preferences/kritarc` on macOS. On Linux `XDG_CONFIG_HOME`
## replaces `$HOME/.config` when it is set, as it does for every KConfig file.
## The key is `tabletPressureCurve`, which `KisConfig::pressureTabletCurve` in
## `libs/ui/kis_config.cc` reads from the file's default group, the lines
## above the first `[section]`, in the `x,y;x,y;` form every Krita curve is
## written in. No file or no key is Krita's own default, `0,0;1,1;`, linear.
##
## **The curve is sampled as Sara reads every imported curve**, the monotone
## cubic of `SaMonotoneCurve`. Krita draws it as a natural cubic spline, which
## can overshoot where the monotone one does not, so a curve with two close
## points far apart in height reads a little differently in the two programs.
## That is the same difference every option curve an import carries already has.
class_name SaKritarc
extends RefCounted

## The key Krita keeps its global pressure curve under.
const KEY: String = "tabletPressureCurve"

## Entries in the table, the size `SaTabletSweep.SAMPLES` gives the painter's
## own correction. Written out because a module sees the door only, and the
## suite holds the two to each other.
const SAMPLES: int = 256

## Krita's default, what a painter who never changed the curve has.
const LINEAR: String = "0,0;1,1;"


## Where Krita keeps its settings on this machine, or empty on a system Krita
## names no place for.
static func default_path() -> String:
    match OS.get_name():
        "Windows":
            var local := OS.get_environment("LOCALAPPDATA")
            return "" if local.is_empty() else local.path_join("kritarc")
        "macOS":
            return OS.get_environment("HOME").path_join("Library/Preferences/kritarc")
        "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
            var xdg := OS.get_environment("XDG_CONFIG_HOME")
            if xdg.is_empty():
                xdg = OS.get_environment("HOME").path_join(".config")
            return xdg.path_join("kritarc")
    return ""


## Krita's curve read from *path*, the machine's `kritarc` when empty, as
## `table`, the curve sampled into [constant SAMPLES] entries, `points`, the
## curve as written, and `said`, the phrase the import's console line carries
## about which curve it used and from where.
static func read(path: String = "") -> Dictionary:
    var where := path if not path.is_empty() else default_path()
    var text := ""
    var found := false
    if not where.is_empty() and FileAccess.file_exists(where):
        var value := _value_of(FileAccess.get_file_as_string(where))
        found = not value.is_empty()
        text = value
    var points := SaKppSensors.parse_curve(text) if found else PackedVector2Array()
    var said := ""
    if points.size() >= 2:
        said = TranslationServer.translate("Krita's pressure curve %s from %s") % [text, where]
    elif found:
        said = TranslationServer.translate("Krita's pressure curve read as linear, %s in %s is not a curve") % [KEY, where]
    elif where.is_empty():
        said = TranslationServer.translate(
            "Krita's pressure curve read as linear, no kritarc at any place Krita names on this system"
        )
    elif not FileAccess.file_exists(where):
        said = TranslationServer.translate("Krita's pressure curve read as linear, no kritarc at %s") % where
    else:
        said = TranslationServer.translate("Krita's pressure curve read as linear, no %s in %s") % [KEY, where]
    if points.size() < 2:
        points = SaKppSensors.parse_curve(LINEAR)
    return {"table": SaMonotoneCurve.sample(points, SAMPLES), "points": points, "said": said}


## The value of [constant KEY] in the default group of *ini*, or empty. A line
## under any `[section]` is another group's and is not Krita's curve.
static func _value_of(ini: String) -> String:
    for raw_line: String in ini.split("\n"):
        var line := raw_line.strip_edges()
        if line.begins_with("["):
            return ""
        var equals := line.find("=")
        if equals < 0:
            continue
        if line.substr(0, equals).strip_edges() == KEY:
            return line.substr(equals + 1).strip_edges()
    return ""
