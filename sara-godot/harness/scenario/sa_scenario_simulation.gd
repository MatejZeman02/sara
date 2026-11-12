## The `simulation` step, through the commands a chord and the door run, so a
## scenario steps a layer the way a painter does.
class_name SaScenarioSimulation
extends RefCounted

## The harness's one lookup for the document the painter is working on.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")


## Steps the active layer's simulation: puts a rule on the active layer of the
## document in front and steps it, resets it or takes it off.
##
## `{"simulation": {"rule": "spread", "params": {"flow": 0.2}, "steps": 40}}`
## puts Spread on the active layer with those values over its defaults, its
## seed the layer as it stands, and runs Step Simulation forty times. A request
## with no `rule` steps the rule already there, `{"reset": true}` runs Reset
## Simulation, and `{"remove": true}` takes the rule off, its seed and second
## copy with it. The keys combine in that order, put, step, reset, remove.
##
## One verdict line, `SaCapture: simulation <json>`, with the layer, the rule
## and the count of steps since the seed, or an `error` saying what was
## refused, with the layer as it was when the refusal came.
static func run(tree: SceneTree, spec: Dictionary) -> String:
    var main_node := tree.current_scene if tree != null else null
    var canvas := CanvasDriver.main_canvas()
    if main_node == null or not ("registries" in main_node) or canvas == null or canvas.document == null:
        return _verdict({"error": "no canvas"})
    var registries: SaRegistries = main_node.registries
    var layer := canvas.document.active_layer
    var rule_key := StringName(String(spec.get("rule", "")))
    if rule_key != &"":
        var found := registries.simulation_rules.find(rule_key)
        if found == null:
            return _verdict({"error": "no rule %s" % rule_key, "rules": registries.simulation_rules.keys()})
        var values: Dictionary = spec.get("params", {})
        if SaSimulation.put_on(layer, found, values) == null:
            return _verdict({"error": SaSimulation.refusal(layer)})
    for _i in int(spec.get("steps", 0)):
        if not registries.commands.execute(SaSimulation.STEP_COMMAND):
            return _verdict({"error": "the step was refused", "layer": layer.name})
    if bool(spec.get("reset", false)) and not registries.commands.execute(SaSimulation.RESET_COMMAND):
        return _verdict({"error": "the reset was refused", "layer": layer.name})
    if bool(spec.get("remove", false)):
        SaSimulation.take_off(layer)
    var record := SaSimulation.record_of(layer)
    return _verdict(
        {
            "layer": layer.name,
            "rule": String(record.rule) if record != null else "",
            "steps": record.steps if record != null else 0,
        }
    )


static func _verdict(fields: Dictionary) -> String:
    return "SaCapture: simulation %s" % JSON.stringify(fields)
