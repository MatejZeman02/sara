## Every sentence written whole reads, under British English, as the generic
## sentence with its word dropped in read before, and every shipped word has
## one.
##
## A call site reads its whole sentence from a table and falls back to the
## generic one, so the English is unchanged exactly when each entry is the
## generic sentence with its key put in. The tables are those of
## `SaWholeSentences` and the ones beside the dialogs and pages they serve. The
## second half loads every module the tree ships and finds each docker, filter,
## section, tool, layer kind and curve option it registers in its tables, so a
## shipped word added later without its sentence fails here rather than in a
## catalogue.
extends "res://tests/test_framework.gd"

const LOCALE := "en_GB"

var _locale := ""


func before_each() -> void:
    _locale = TranslationServer.get_locale()
    TranslationServer.set_locale(LOCALE)


func after_each() -> void:
    ModuleLoader.unload_all()
    TranslationServer.set_locale(_locale)


func _say(message: String) -> String:
    return TranslationServer.translate(message)


## Each entry of *table* against *generic* with its key, or with *word* of the
## key when the key is not the word itself.
func _matches(table: Dictionary, generic: String, named: String, word: Callable = Callable()) -> void:
    assert_false(table.is_empty(), "%s holds entries" % named)
    for key: Variant in table:
        var dropped := String(word.call(key)) if word.is_valid() else String(key)
        assert_eq(_say(table[key]), _say(generic) % _say(dropped), "%s's %s reads as before" % [named, key])


func test_the_shared_tables_read_as_the_generic_sentences() -> void:
    _matches(SaWholeSentences.DOCKER_FIRST_MENU, "Show the %s docker first, from the Window menu.", "DOCKER_FIRST_MENU")
    for key: Variant in SaWholeSentences.DOCKER_FIRST_CHORD:
        assert_eq(
            _say(SaWholeSentences.DOCKER_FIRST_CHORD[key]) % "Ctrl+L",
            _say("Show the %s docker first (%s).") % [_say(key), "Ctrl+L"],
            "DOCKER_FIRST_CHORD's %s reads as before" % key
        )
    _matches(SaWholeSentences.DOCKER_PARTS, "Choose which parts the %s docker shows, and their order.", "DOCKER_PARTS")
    _matches(SaWholeSentences.DOCKER_SETTINGS, "%s docker settings", "DOCKER_SETTINGS")
    _matches(SaWholeSentences.DOCKER_FROM, "from %s", "DOCKER_FROM")
    _matches(SaWholeSentences.FILTER_AGAIN, "Apply %s Again", "FILTER_AGAIN")
    _matches(
        SaWholeSentences.FILTER_ATTACHES,
        "Attaches %s to the active layer instead of writing it in, where it stays editable until it is flattened.",
        "FILTER_ATTACHES"
    )
    _matches(SaWholeSentences.FILTER_SECTION, "The %s filters of every module.", "FILTER_SECTION")
    _matches(SaWholeSentences.TOOL_SWITCHES, "Switches to the %s tool.", "TOOL_SWITCHES")
    _matches(
        SaWholeSentences.TOOL_NOT_LOADED,
        "%s is not loaded.",
        "TOOL_NOT_LOADED",
        func(key: Variant) -> String: return String(key).trim_suffix(" Tool")
    )
    _matches(SaWholeSentences.LAYER_NEW, "New %s", "LAYER_NEW")
    _matches(SaWholeSentences.LAYER_ADD, "Add %s", "LAYER_ADD")
    _matches(SaWholeSentences.OPTION_DYNAMICS, "%s dynamics", "OPTION_DYNAMICS")
    _matches(SaWholeSentences.OPTION_JITTER, "%s jitter", "OPTION_JITTER")
    _matches(
        SaWholeSentences.PAGE_SWITCH,
        "Turns %s on for this brush. Off, the brush paints as if the page were not there.",
        "PAGE_SWITCH"
    )


func test_the_tables_beside_their_dialogs_and_pages_read_as_before() -> void:
    for row: Array in SaCanvasSizeDialog.LABELS:
        for cell: String in row:
            assert_eq(
                _say(SaCanvasSizeDialog.ANCHOR_UNCHANGED[cell]),
                _say("Anchor: %s. The canvas does not change.") % _say(cell),
                "The anchor %s's unchanged line reads as before" % cell
            )
            assert_eq(
                _say(SaCanvasSizeDialog.ANCHOR_MOVES[cell]) % [12, -4],
                _say("Anchor: %s. The picture's top-left corner moves to %s, %s px.") % [_say(cell), 12, -4],
                "and its moving line"
            )
    for label: String in SaImageSizeDialog.FILTER_LABELS:
        assert_eq(
            _say(SaImageSizeDialog.RESAMPLED_WITH[label]) % ["200", "50"],
            _say("%s%% × %s%%, resampled with %s.") % ["200", "50", _say(label)],
            "The image size's line for %s reads as before" % label
        )
    for entry: Dictionary in SaSettingsPerformance.FRAME_RATES:
        var rate := String(entry["label"])
        assert_eq(
            _say(SaPerformancePage.RATE_NOW[rate]),
            _say("Frame rate while painting: %s.") % _say(rate),
            "The frame rate line for %s reads as before" % rate
        )
    for entry: Dictionary in SaSettingsPerformance.THUMBNAIL_MODES:
        var mode := String(entry["label"])
        assert_eq(
            _say(SaPerformancePage.THUMBNAILS_NOW[mode]),
            _say("Thumbnails while painting: %s.") % _say(mode),
            "The thumbnails line for %s reads as before" % mode
        )
    for key: Variant in SaSensorList.LABELS:
        assert_eq(
            _say(SaSensorList.SHARED_HEADINGS[key]),
            _say("%s. The curve is shared by every ticked sensor.") % _say(SaSensorList.LABELS[key]),
            "The shared heading of %s reads as before" % key
        )
    for shipped: String in SaDockerLayoutPresets.SHIPPED:
        assert_eq(_say(SaDockerLayoutPresets.SHIPPED_TITLES[shipped]), _say(shipped.capitalize()), "%s reads as before" % shipped)
        assert_eq(
            _say(SaDockerLayoutPresets.CUSTOM_TITLES[shipped]),
            _say("%s (Custom)") % _say(shipped.capitalize()),
            "and so does its fork"
        )


## The three lines whose one shipped word is now written into the sentence at
## the call, compared with the sentence they were made from.
func test_the_lines_written_out_at_their_call_read_as_before() -> void:
    assert_eq(_say("Tag: All"), _say("Tag: %s") % _say("All"), "The tag button's All reads as before")
    assert_eq(
        _say("There is no layer in the picture to bake into."),
        _say("There is no layer in %s to bake into.") % _say("the picture"),
        "and so does the bake's refusal for the picture"
    )
    assert_eq(
        _say("Automatic (no country found)"),
        _say("Automatic (%s)") % _say("no country found"),
        "and the location's automatic row with no country"
    )


func test_every_shipped_word_has_its_whole_sentence() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaBuiltinDockers.register(registries.ui)
    ModuleLoader.load_and_register_modules(registries.context)
    for entry: Dictionary in registries.ui.list_dockers():
        var title := String(entry["title"])
        for table: Dictionary in [
            SaWholeSentences.DOCKER_FIRST_MENU,
            SaWholeSentences.DOCKER_FIRST_CHORD,
            SaWholeSentences.DOCKER_PARTS,
            SaWholeSentences.DOCKER_SETTINGS,
            SaWholeSentences.DOCKER_FROM,
        ]:
            assert_true(table.has(title), "The shipped docker %s has its whole sentences" % title)
    for key: StringName in registries.filters.list_keys():
        var title := registries.filters.get_filter(key).title()
        assert_true(SaWholeSentences.FILTER_AGAIN.has(title), "The shipped filter %s has its Again row" % title)
        assert_true(SaWholeSentences.FILTER_ATTACHES.has(title), "and its Attach tooltip")
    for section: SaFilterRegistry.Section in registries.filters.list_sections():
        assert_true(SaWholeSentences.FILTER_SECTION.has(section.label), "The section %s has its tooltip" % section.label)
    for descriptor: SaToolDescriptor in registries.tools.list_tools():
        assert_true(
            SaWholeSentences.TOOL_SWITCHES.has(descriptor.display_name),
            "The shipped tool %s has its Tools menu tooltip" % descriptor.display_name
        )
    for element: String in SaToolBoxViews.tool_elements():
        assert_true(SaWholeSentences.TOOL_NOT_LOADED.has(element), "The toolbox's %s has its line" % element)
    for descriptor: SaToolDescriptor in registries.tools.list_descriptors():
        for spec: SaOptionSpec in descriptor.options:
            if spec.kind == SaOptionSpec.Kind.CURVE_OPTION and not spec.label.ends_with("Dynamics"):
                assert_true(SaWholeSentences.OPTION_DYNAMICS.has(spec.label), "The curve option %s has its row" % spec.label)
            var slider := ToolOptionsRolls.slider_of(spec, descriptor.options)
            if slider != null:
                assert_true(SaWholeSentences.OPTION_JITTER.has(slider.label), "The slider %s has its jitter" % slider.label)
    for descriptor: SaLayerTypeDescriptor in registries.layer_types.list_descriptors():
        if descriptor.id in [&"background", SaLayerTypeDescriptor.PLAIN]:
            continue
        var words := descriptor.display_name
        var named := words if words.to_lower().ends_with("layer") else "%s Layer" % words
        assert_true(SaWholeSentences.LAYER_NEW.has(named), "The shipped kind %s has its New row" % named)
        if not descriptor.input.is_empty():
            assert_true(SaWholeSentences.LAYER_ADD.has(words), "and, holding a filter, its browser's title")
