## `SLIDER_WIDTH` is one slider's floor, not the row's width.
##
## The docstring on that constant said "three of them stack in a docker whose
## default width is 260 logical units", which multiplied the number as though
## the three sliders sat side by side and named a docker width that had moved.
## They stack, because the row is a VBoxContainer, so the row wants one
## slider's width and the sentence was arithmetic on the wrong axis.
##
## These pin the two facts the rewritten docstring rests on. What the assembled
## picker column measures is `scenarios/picker-slider-width-reason.json`.
extends "res://tests/test_framework.gd"


func test_the_row_stacks_its_sliders() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.RGB)
    assert_true(row is VBoxContainer, "The row is a VBoxContainer, so its three sliders are one above the other")
    assert_eq(row.sliders.size(), 3, "and there are three of them")
    row.free()


## The number in the report a scenario reads, so the record's 96 is the app's 96
## rather than a constant quoted at itself.
func test_the_report_carries_the_width_it_was_built_at() -> void:
    var row := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    var report := row.report()
    assert_eq(report["slider_width"], DockerUtils.px(SaPickerSliders.SLIDER_WIDTH), "The report says what the floor is")
    assert_true(report.has("wants_width"), "and what the row as a whole wants, which is the number the docstring is about")
    row.free()


## The floor is a floor. `FactorSlider` raises it when its own text is wider,
## which is why a channel that reads `R: 12.345` is not clipped.
func test_the_width_is_a_floor_that_text_can_raise() -> void:
    var slider := FactorSlider.new()
    slider.prefix = "R: "
    slider.decimal_places = 3
    slider.preferred_width = DockerUtils.px(SaPickerSliders.SLIDER_WIDTH)
    slider.max_value = 100.0
    slider.value = 0.5
    var narrow := slider.custom_minimum_size.x
    slider.value = 87.654
    var wide := slider.custom_minimum_size.x
    assert_true(narrow >= float(DockerUtils.px(SaPickerSliders.SLIDER_WIDTH)), "A short number leaves the floor standing")
    assert_true(wide >= narrow, "and a long one can only raise it")
    slider.free()
