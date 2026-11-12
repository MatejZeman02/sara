## The stabiliser of the brush in hand, held off for one stroke and given back
## after it, which is what `"smoothing": false` on a `stroke` step asks.
##
## Paint ships with the Average at 0.5, which smooths a step's points as it
## does a hand's, so an arc a step traces lands inside the points it was sent
## along. A
## brush reads its stabiliser at the press, so the stroke step asks
## [method hold_for] before it splices the press, and the stroke's report asks
## [method put_back] after the release, whichever route and pace the stroke
## went by. The preset in hand holds the setting it had once the stroke is
## done. The bar is not told, so it never shows the stroke's own setting.
##
## **Its own package** because it is the one part of a stroke that writes a
## painter's setting. It reaches the tool machine and the settings of the tool
## in hand, which the stroke step otherwise only paints through. The field is
## asked by name, so the skeleton names no module script. Every function is
## static, because what is held travels in the stroke's report, which is a step
## and so the scenario vocabulary a replay reads, rather than in an object.
##
## The key is named in the stroke step's first sentence and not under its
## **Arguments**, because the door's answer to `list` has no room left for a key.
class_name SaStrokeSmoothing
extends RefCounted

## The key of a `stroke` step, and of its report, that this answers.
const KEY := "smoothing"
## The field of a brush's settings that names its stabiliser, 0 for none.
const STABILIZER := "stabilizer_mode"


## Holds the stabiliser of the tool in hand on *canvas* off when *spec* asks
## `"smoothing": false`, and writes into *verdict*, the stroke's report, what
## [method put_back] gives back. Nothing is held when the tool has no
## stabiliser or has it off already, since then nothing smooths the stroke.
##
## False, with a warning, when the key is neither true nor false, and then
## nothing is held and the step splices nothing rather than guess which was
## meant. True otherwise, and a stroke without the key is left as it was.
## The stroke step asks it last, after every refusal of its own, so a stroke
## refused for any reason never leaves a stabiliser off.
static func hold_for(spec: Dictionary, verdict: Dictionary, canvas: SaCanvas) -> bool:
    var asked: Variant = spec.get(KEY, true)
    if not asked is bool:
        push_warning("SaCapture: a stroke's 'smoothing' is true or false, not %s" % JSON.stringify(asked))
        return false
    if asked:
        return true
    verdict[KEY] = {}
    var machine := canvas.tool_machine() if canvas != null else null
    var settings := _settings_of(machine.active_tool if machine != null else null)
    if settings == null or int(settings.get(STABILIZER)) == 0:
        return true
    verdict[KEY] = {"tool": String(machine.active_tool_name), STABILIZER: int(settings.get(STABILIZER))}
    settings.set(STABILIZER, 0)
    return true


## Gives the tool that the report *spec* names the stabiliser [method hold_for]
## held off, on *canvas*, and does nothing for a stroke that held none.
static func put_back(spec: Dictionary, canvas: SaCanvas) -> void:
    var held := spec.get(KEY, {}) as Dictionary
    if held == null or held.is_empty():
        return
    var machine := canvas.tool_machine() if canvas != null else null
    if machine == null:
        push_warning("SaCapture: no tool machine to give the %s tool its stabiliser back" % held.get("tool", ""))
        return
    var settings := _settings_of(machine.get_tool(StringName(String(held.get("tool", "")))))
    if settings != null:
        settings.set(STABILIZER, int(held.get(STABILIZER, 0)))


## What a stroke's report *spec* says of the stabiliser, as the end of its
## shape, or nothing for a stroke that left it alone, so a line without the
## key carries no clause for it. The mode it names is the one given back.
static func clause(spec: Dictionary) -> String:
    if not spec.has(KEY):
        return ""
    var held := spec[KEY] as Dictionary
    if held == null or held.is_empty():
        return ", unsmoothed"
    return ", unsmoothed, the %s tool's stabiliser %d off for it and put back" % [held["tool"], int(held[STABILIZER])]


## The settings of *tool* when they carry a stabiliser, or null.
static func _settings_of(tool: Object) -> Resource:
    if tool == null or not "settings" in tool:
        return null
    var settings := tool.get("settings") as Resource
    if settings == null or not STABILIZER in settings:
        return null
    return settings
