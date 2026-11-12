## The light a document's impasto is drawn and baked under: where it stands and
## how steep it draws the paint's height.
##
## The light belongs to the painting rather than to the app's settings, where
## one `.sad` would export a different picture on a machine with other settings
## and a painting lit from the left would light every other painting from the
## left. The view, Rasterize Impasto and a
## flat export all read it here, and none of them reads Preferences.
##
## **Preferences keeps where a new one starts.** `SaSettings.relief_light_angle`
## and `relief_strength` are what a new document, an opened picture and a
## `.sad` with no light in its header start from, and nothing
## else reads them.
##
## **Kept in the `.sad` header under [constant HEADER_KEY], on every save**, the
## way the resolution is: absence cannot stand for a default when the value a
## reader would fall back on is each machine's own Preferences, so a file that
## left the key out would open lit differently on the next machine, which is the
## bug this class exists for.
class_name SaReliefLight
extends RefCounted

## Announced from both setters, so the canvas relights whoever moved the light.
signal changed

## The `.sad` header's key, an object of `angle` and `strength`.
const HEADER_KEY := "relief_light"

## Where the light comes from, in degrees clockwise from the top of the canvas,
## 315 being the upper left a painter's lamp usually stands at.
var angle: float = 315.0:
    set(value):
        angle = fposmod(value, 360.0)
        changed.emit()

## How steep the stored slope is drawn, a scale on it before the light, and 0
## draws it flat. The height stays in millimetres whatever this says.
var strength: float = 2.0:
    set(value):
        strength = clampf(value, 0.0, SaSettings.MAX_RELIEF_STRENGTH)
        changed.emit()


func _init() -> void:
    start_from_preferences()


## Puts the light where Preferences > Canvas and colour says a new document's
## stands, which is how every document begins.
func start_from_preferences() -> void:
    angle = SaSettings.relief_light_angle
    strength = SaSettings.relief_strength


## The direction from the surface to the light, which the view's shader and a
## flat export's pass take.
func toward() -> Vector3:
    return SaRelief.light_toward(angle)


## The light as the `.sad` header's [constant HEADER_KEY] holds it.
func to_header() -> Dictionary[String, Variant]:
    return {"angle": angle, "strength": strength}


## Takes what `to_header` wrote. A header without the key, and a key that is missing a value
## or holds the wrong type, read as Preferences' light, the light that file was
## seen under on the machine that opens it.
func read_header(raw: Variant) -> void:
    start_from_preferences()
    var stored := SaTyped.strings(raw)
    angle = SaTyped.float_at(stored, "angle", angle)
    strength = SaTyped.float_at(stored, "strength", strength)


## Makes the move of *document*'s light from *was_angle* and *was_strength* to
## where it stands now one step of the history, Relief Light, so one undo puts
## it back. The View menu's popup moves the light live while its sliders travel
## and records the move here once, as it closes. False, and no step, when the
## light stands where it was.
static func record(document: SaDocument, was_angle: float, was_strength: float) -> bool:
    if document == null:
        return false
    var light := document.relief_light
    if is_equal_approx(light.angle, was_angle) and is_equal_approx(light.strength, was_strength):
        return false
    var put := func(to_angle: float, to_strength: float) -> void:
        light.angle = to_angle
        light.strength = to_strength
    if document.history != null:
        document.history.commit_pair("Relief Light", put.bind(light.angle, light.strength), put.bind(was_angle, was_strength))
    # After the step, so the raise lands past the place a save left clean and
    # is a step an undo can take back rather than a change it never heard of.
    document.modified = true
    return true
