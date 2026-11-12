## The offer of the light mode to a weak GPU, made once.
##
## The two main cases come first: the rule fed each device type offers
## integrated and CPU and not discrete, and an answered offer is not made a
## second time. The rest hold what they stand on, the memory that keeps a
## well-equipped laptop out, the two surfaces, and a capture run that is never asked.
extends "res://tests/test_framework.gd"

const GIB: int = 1024 * 1024 * 1024
const PROPERTIES: Array[String] = [
    "painting_frame_rate", "half_size_view_while_moving", "thumbnails_while_painting", "history_depth", "light_mode_offer"
]

var _before: Dictionary = {}


func before_each() -> void:
    _before.clear()
    for property: String in PROPERTIES:
        _before[property] = SaSettings.get(property)
    SaSettingsPerformance.apply_defaults(SaSettings)
    SaSettings.light_mode_offer = ""
    SaWeakGpu.forget()


func after_each() -> void:
    for property: String in _before:
        SaSettings.set(property, _before[property])
    SaWeakGpu.forget()


func test_the_rule_offers_integrated_and_cpu_and_not_discrete() -> void:
    var eight := 8 * GIB
    assert_true(SaWeakGpu.judge(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, eight), "an integrated GPU on 8 GiB is offered")
    assert_true(SaWeakGpu.judge(RenderingDevice.DEVICE_TYPE_CPU, eight), "a CPU device is offered")
    assert_false(SaWeakGpu.judge(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, eight), "a discrete GPU is not")
    assert_false(SaWeakGpu.judge(RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU, eight), "nor a virtual one")
    assert_false(SaWeakGpu.judge(RenderingDevice.DEVICE_TYPE_OTHER, eight), "nor one the driver calls other")

    for word: String in ["integrated", "cpu"]:
        SaWeakGpu.fake(word, eight)
        assert_true(SaLightModeOffer.due(), "the offer is due for a faked %s device" % word)
    for word: String in ["discrete", "virtual", "other"]:
        SaWeakGpu.fake(word, eight)
        assert_false(SaLightModeOffer.due(), "and not for a faked %s one" % word)


func test_an_answered_offer_is_not_made_a_second_time() -> void:
    SaWeakGpu.fake("integrated", 8 * GIB)
    assert_true(SaLightModeOffer.due(), "the offer is due before an answer")
    SaLightModeOffer.answer(false)
    assert_eq(SaSettings.light_mode_offer, SaSettingsPerformance.OFFER_NOT_NOW, "not now is kept")
    assert_false(SaLightModeOffer.due(), "and the offer is not made again")
    var defaults := SaSettingsPerformance.default_values()
    for property: String in defaults:
        assert_eq(SaSettings.get(property), defaults[property], "and not now changed %s" % property)

    SaSettings.light_mode_offer = ""
    SaLightModeOffer.answer(true)
    assert_eq(SaSettings.light_mode_offer, SaSettingsPerformance.OFFER_TURNED_ON, "turned on is kept")
    SaWeakGpu.fake("cpu", 4 * GIB)
    assert_false(SaLightModeOffer.due(), "and the offer is not made again, whatever device is judged next")
    for property: String in SaSettingsPerformance.light_values():
        assert_eq(SaSettings.get(property), SaSettingsPerformance.light_values()[property], "turn it on wrote %s" % property)


func test_an_integrated_gpu_is_weighed_by_the_memory_it_shares() -> void:
    var integrated := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
    var windows_sitting := int(7.8 * GIB)
    assert_true(SaWeakGpu.judge(integrated, windows_sitting), "an Iris Plus with 7.8 GiB is offered")
    assert_false(SaWeakGpu.judge(integrated, 16 * GIB), "an integrated Intel beside 16 GiB is not")
    assert_false(SaWeakGpu.judge(integrated, SaWeakGpu.MEMORY_CEILING_BYTES), "the ceiling itself is not under it")
    assert_false(SaWeakGpu.judge(integrated, 0), "a machine that did not say its memory is not offered on a guess")
    assert_true(SaWeakGpu.judge(RenderingDevice.DEVICE_TYPE_CPU, 64 * GIB), "a CPU device is offered whatever its memory")
    assert_true(SaWeakGpu.reason(integrated, 16 * GIB).contains("over the 12 GiB ceiling"), "the reason says why")


func test_nothing_is_offered_until_a_device_is_judged() -> void:
    assert_false(SaWeakGpu.weak(), "no device is weak before one is read or faked")
    assert_false(SaLightModeOffer.due(), "so a suite and a scenario meet no offer")
    assert_eq(SaWeakGpu.state(), {"judged": false}, "and the dump says nothing was judged")


func test_a_capture_run_is_never_offered_and_judges_nothing() -> void:
    var host := Node.new()
    SaLightModeOffer.at_start(host, null, true)
    assert_false(SaWeakGpu.state()["judged"], "a refused start reads no device")
    assert_eq(host.get_child_count(), 0, "and asks nothing")
    host.free()


func test_the_row_shows_while_due_and_goes_once_answered() -> void:
    var row := SaLightModeOffer.new()
    assert_false(row.visible, "no row while nothing is judged")
    SaWeakGpu.fake("integrated", 8 * GIB)
    row.refresh()
    assert_true(row.visible, "the row shows for a weak device")
    assert_true((row.get_node("Sentence") as Label).text.contains("settings for a weak GPU"), "one sentence says what is offered")
    (row.get_node("LightModeOfferNotNow") as Button).pressed.emit()
    assert_false(row.visible, "and goes once answered")
    assert_eq(SaSettings.light_mode_offer, SaSettingsPerformance.OFFER_NOT_NOW, "with the answer kept")
    row.free()


func test_the_welcome_window_carries_the_row() -> void:
    SaWeakGpu.fake("cpu", 8 * GIB)
    var window := SaWelcomeWindow.new()
    assert_true(window.light_mode_offer != null, "the window built the row")
    assert_eq(window.light_mode_offer.get_parent().name, &"Column", "above the panes, in the window's column")
    assert_true(window.light_mode_offer.visible, "and shows it while the offer is due")
    window.free()


func test_the_question_of_its_own_answers_on_either_button_and_on_a_close() -> void:
    # In the tree, embedded, because a window out of it announces no hide and a
    # hide is the close this reads. Under the bus, as the message suite does,
    # since the root is still setting up its children while suites run.
    var root := (Engine.get_main_loop() as SceneTree).root
    var embedding := root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    var host := Node.new()
    EventBus.add_child(host)
    SaWeakGpu.fake("integrated", 8 * GIB)
    var dialog := SaLightModeOffer.ask_alone(host)
    assert_eq(dialog.name, &"LightModeOfferQuestion", "the question has a name a scenario finds")
    assert_eq(dialog.buttons.size(), 2, "two buttons")
    dialog.buttons[0].pressed.emit()
    assert_eq(SaSettings.light_mode_offer, SaSettingsPerformance.OFFER_TURNED_ON, "the first turns it on")
    assert_eq(SaSettings.thumbnails_while_painting, SaSettingsPerformance.PEN_LIFT, "through the light mode's own values")

    SaSettings.light_mode_offer = ""
    var closed := SaLightModeOffer.ask_alone(host)
    closed.hide()
    assert_eq(SaSettings.light_mode_offer, SaSettingsPerformance.OFFER_NOT_NOW, "a close without a button is not now")
    host.free()
    root.gui_embed_subwindows = embedding


func test_the_answer_is_a_stored_key_that_takes_only_its_two_words() -> void:
    assert_eq(SaSettingsValues.KEYS.get("light_mode_offer"), ["performance", "light_mode_offer"], "a stored key")
    SaSettings.light_mode_offer = "yes please"
    assert_eq(SaSettings.light_mode_offer, "", "a word that is not an answer reads as never asked")
    var fresh := SaSettingsValues.new()
    assert_eq(fresh.light_mode_offer, "", "a fresh profile has never been asked")
    fresh.free()
