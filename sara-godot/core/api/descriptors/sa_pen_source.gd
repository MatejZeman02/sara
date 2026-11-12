## What a module fills in to tell Sara where the pen is when it reads the pen
## outside Godot, a module reading the kernel's own node on Linux the first.
##
## **Godot's word on the pen is not always the pen's.** Under Wayland the
## engine reports the upper barrel button as the tip's left press, so the one
## left bit is cleared at the tip's lift and the upper let go in the air is no
## event at all, godotengine/godot#124067.
## A source reads the pen where the kernel reports it and says which buttons
## are held. A module extends this and registers it through
## [method SaContext.register_pen_source], and it lands on `SaRegistries.pens`,
## which the tool machine asks before it presumes anything and a brush engine
## may ask through `SaContext.pens`, neither naming the module (hard rule 6).
##
## **A source that knows nothing says null.** A node not found, not readable,
## or read since before the pen came into range, all leave the tools on what
## Godot says, as they are with no source registered.
##
## Each method is called on the main thread, so a source reading on a thread of
## its own answers from a copy it keeps under a lock. [method now] hands out a
## new [State] and is asked at a press and at a page shown, never per dab.
## [method wheel] is the one a brush asks at every dab or every motion: a float
## read under the lock, with nothing made.
##
## **The airbrush's finger wheel** is a place from 0 to 1, which a brush reads
## as tangential pressure. A source that reads no wheel, because its node
## declares none or because it cannot learn the wheel's range, says so through
## [method reads_wheel] and answers nought.
class_name SaPenSource
extends RefCounted

## The barrel buttons as the kernel numbers them: `BTN_STYLUS`, `BTN_STYLUS2`
## and `BTN_STYLUS3`. Which of them a painter calls upper depends on the pen and
## on the desktop, so a reader learns it rather than assuming it.
enum Barrel { NONE, FIRST, SECOND, THIRD }


## The pen as a source read it at one moment, a copy the source hands out so
## the reader on its own thread and the tool on the main one never share it.
class State:
    extends RefCounted

    ## Whether the pen is in the tablet's range, by either end.
    var in_range: bool = false
    ## Whether the end in range is the eraser's.
    var rubber: bool = false
    ## Whether the tool in range is an airbrush.
    var airbrush: bool = false
    ## The airbrush's finger wheel, 0 to 1, where the last frame that moved it
    ## left it, out of range as well. Nought before any did.
    var wheel: float = 0.0
    ## Whether the tip, or the eraser end, is on the surface.
    var touching: bool = false
    ## The barrel buttons held, a bit for each [enum Barrel] by its value.
    var barrels: int = 0
    ## The barrel pressed last, held or since let go, [constant Barrel.NONE]
    ## before any.
    var last_pressed: Barrel = Barrel.NONE

    ## Whether *barrel* is held.
    func held(barrel: Barrel) -> bool:
        return barrel != Barrel.NONE and (barrels & (1 << barrel)) != 0

    ## The state as a capture's dump writes it.
    func described() -> Dictionary:
        return {
            "in_range": in_range,
            "rubber": rubber,
            "airbrush": airbrush,
            "wheel": wheel,
            "touching": touching,
            "barrels": barrels,
            "last_pressed": int(last_pressed),
        }

    func copy() -> State:
        var out := State.new()
        out.in_range = in_range
        out.rubber = rubber
        out.airbrush = airbrush
        out.wheel = wheel
        out.touching = touching
        out.barrels = barrels
        out.last_pressed = last_pressed
        return out


## The pen as last read, or null while the source knows nothing of it: no
## node, no permission, or no word since the pen came into range.
func now() -> State:
    return null


## The airbrush's finger wheel as last read, 0 to 1, or nought while the source
## knows nothing of the pen or reads no wheel. Asked per dab, see the class's
## note.
func wheel() -> float:
    return 0.0


## Whether the source holds a pen's node open and reads it.
func reads() -> bool:
    return false


## Whether the node read declares an airbrush wheel and the source reads it.
func reads_wheel() -> bool:
    return false


## One sentence for the Tablet page, what the source reads or why it reads
## nothing and how to turn it on, in the module's own words.
func said() -> String:
    return ""


## The source the main scene's registries ask, the newest on `SaContext.pens`,
## or null where none is registered or no main scene holds registries, as in a
## suite. A walk to the main scene and a lookup, so it is asked at a press and
## never per dab: [method SaStrokeInfo.begin] holds what it answers for the
## stroke, which is how a brush reads the wheel with no module named.
static func registered() -> SaPenSource:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.get("registries")
    return registries.pens.source() if registries != null else null


## The source the main scene's door asks, as a capture's state dump reads it:
## whether one is registered, what it reads and says, its wheel, and the pen's
## state, null while the source knows nothing. Only `registered`, false, where
## no source is registered or no main scene holds registries, as in a suite.
static func capture_state() -> Dictionary:
    var source := registered()
    if source == null:
        return {"registered": false}
    var report := {
        "registered": true,
        "reads": source.reads(),
        "reads_wheel": source.reads_wheel(),
        "wheel": source.wheel(),
        "said": source.said(),
        "state": null,
    }
    var pen := source.now()
    if pen != null:
        report["state"] = pen.described()
    return report
