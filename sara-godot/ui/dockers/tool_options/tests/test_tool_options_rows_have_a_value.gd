## Every row the Tool Options docker draws says what it is set to, and no
## name is drawn twice on one page.
##
## The brush's page was forty-one rows with the nine curve options first
## and each of them drawing its own name twice and its value never, six of the
## nine sharing a name with a slider further down. `test_painter.gd` holds
## the two properties of the whole list. What is here is the row itself: what
## the button says for each state a `SaCurveOption` can be in, and that the
## brush editor's page no longer draws the option's name under its own heading.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is what `test_tool_options_docker.gd` does and why.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true


## A docker showing the brush with Advanced Options on, which is the only way
## the nine curve option rows are drawn at all.
class Page:
    var surface: SaSurface
    var machine: ToolMachine
    var host: Node
    var docker: ToolOptionsDocker
    var advanced: bool

    func _init() -> void:
        surface = Fixtures.make_surface()
        machine = Fixtures.make_bound_machine(surface)
        advanced = SaSettings.advanced_options
        SaSettings.advanced_options = true
        host = Node.new()
        docker = ToolOptionsDocker.new()
        host.add_child(docker)
        docker.target_tool_machine = machine
        machine.set_active_tool(&"brush")
        docker.sync_from_tool()

    func close() -> void:
        host.free()
        Fixtures.teardown(surface, machine)
        SaSettings.advanced_options = advanced

    ## The brush's settings, where the nine options live.
    func settings() -> Object:
        return machine.get_tool(&"brush").get("settings")

    ## The button of one curve option row, by option key.
    func button(key: StringName) -> Button:
        return docker.options.control(key) as Button

    ## The label column of one curve option row, by option key.
    func label(key: StringName) -> Label:
        var row := docker.find_child(String(key).capitalize().replace(" ", "") + "Row", true, false)
        return row.find_child("Label", true, false) as Label if row != null else null


## The defect itself: the button carried the option's name, which the label
## column beside it was already carrying, and the option's state reached the
## page nowhere.
func test_a_curve_option_row_says_its_strength_and_its_sensors() -> void:
    var page := Page.new()
    var option := page.settings().get("size_option") as SaCurveOption
    assert_not_null(option, "The brush's Size dynamics is an SaCurveOption")
    option.enabled = true
    option.use_curve = true
    option.strength = 0.75
    # A fresh brush's options carry no sensor at all, which is why the default
    # page reads "constant" rather than a sensor name. This one is asked to
    # follow the pen, so the row has both halves to say.
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    page.docker.sync_values_from_tool()

    var button := page.button(&"size_option")
    assert_not_null(button, "The Size dynamics row is a button")
    assert_eq(button.text, "75%, Pressure", "and it says the strength and the sensor, not 'Size' again")
    assert_eq(page.label(&"size_option").text, "Size dynamics", "The label column names what the row modulates")
    page.close()


## The Spacing curve page is named Spacing Dynamics, and the label column adds
## "dynamics" to every curve option, so a label that already says it is left as
## it is rather than reading "Spacing Dynamics dynamics".
func test_a_label_that_says_dynamics_is_not_given_the_word_twice() -> void:
    var page := Page.new()
    assert_eq(page.label(&"spacing_option").text, "Spacing Dynamics", "The Spacing page's row says it once")
    assert_eq(page.label(&"softness_option").text, "Softness dynamics", "and a row whose label does not still gets the word")
    page.close()


## The percentage is the raw strength times a hundred, which is what the
## editor's own Strength slider shows. A row and a page that disagreed about one
## number would be worse than the row that said nothing.
func test_the_percentage_is_the_one_the_editor_shows() -> void:
    var page := Page.new()
    var option := page.settings().get("size_option") as SaCurveOption
    option.enabled = true
    option.use_curve = true
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    for strength: float in [0.0, 0.33, 1.0]:
        option.strength = strength
        page.docker.sync_values_from_tool()
        assert_eq(
            page.button(&"size_option").text.split(",")[0],
            "%d%%" % roundi(strength * 100.0),
            "Strength %f reads as the editor's own percentage" % strength
        )
    page.close()


## `enabled` off and `use_curve` off are different states and neither is a
## strength. Krita keeps both and so does `SaCurveOption`, so the row has to
## tell them apart or it is lying about one of them.
func test_a_switched_off_option_says_so_and_a_constant_says_that() -> void:
    var page := Page.new()
    var option := page.settings().get("opacity_option") as SaCurveOption
    option.strength = 1.0

    option.enabled = false
    page.docker.sync_values_from_tool()
    assert_eq(page.button(&"opacity_option").text, "Off", "An option that does nothing says off, not 100%")

    option.enabled = true
    option.use_curve = false
    page.docker.sync_values_from_tool()
    assert_eq(page.button(&"opacity_option").text, "100%, Constant", "and one that reads no sensor says it is a constant")
    page.close()


## Two sensors are joined rather than one of them dropped, because an option
## following pressure and speed is not the same option as one following pressure.
func test_two_active_sensors_are_both_named() -> void:
    var page := Page.new()
    var option := page.settings().get("flow_option") as SaCurveOption
    option.enabled = true
    option.use_curve = true
    option.strength = 1.0
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    option.set_sensor(SaSensor.create(SaSensor.Id.SPEED, true))
    page.docker.sync_values_from_tool()
    assert_eq(page.button(&"flow_option").text, "100%, Pressure + Speed", "Both active sensors are on the row")
    page.close()


## The row follows the option the way every other row follows its value: the
## docker syncs and the text moves. Without this the button would be right once,
## at build time, and stale from the first edit onwards.
func test_the_row_follows_an_edit_made_elsewhere() -> void:
    var page := Page.new()
    var option := page.settings().get("softness_option") as SaCurveOption
    option.enabled = true
    option.use_curve = true
    option.strength = 0.5
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    page.docker.sync_values_from_tool()
    var before := page.button(&"softness_option").text
    option.strength = 0.9
    page.docker.sync_values_from_tool()
    assert_false(page.button(&"softness_option").text == before, "The row moved with the option")
    assert_true(page.button(&"softness_option").text.begins_with("90%"), "and it moved to the new strength")
    page.close()


## The other half, in the brush editor rather than the docker: the page
## heading names the option at font size 16 and the control's own title row
## repeated it directly underneath. The control has no title row at
## all, the editor's heading and the bare host's label being the two places the
## name is drawn, and the page is still reported, which a scenario reads.
func test_the_editor_page_names_the_option_once() -> void:
    var control := SaCurveOptionControl.new()
    control.bind_option(SaCurveOption.create_default(), "Size")
    assert_null(control.find_child("PageTitle", true, false), "The control draws no title row of its own")
    assert_eq(control.option_report()["page"], "Size", "The page is still reported, which a scenario reads")
    control.free()
