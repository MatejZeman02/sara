## The pages the stamp brush declares, and the rule on each.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The window that draws them is `ui/brush_editor/brush_editor_window.gd`, tested
## in the parent. What is here is the module's half: which pages exist, in what
## order, what each curve option page names, and the house rule on every title a
## painter reads.
##
## **Against the spec list rather than against the editor**, because a page is a
## declaration and the editor is one consumer of it. A test that opened a window
## would prove the editor as well and fail for either one's reasons.
extends "res://tests/test_framework.gd"

## By path rather than by `class_name`, the way `tests/fixtures.gd` reaches the
## same file: the module has none, being loaded through `SaRegistries` like any
## third party's.
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## The curve options in the order the module declares them, which is the brush
## editor's page order: a page appears where its first row is declared, so the
## options are declared in that order.
## Krita's grouping, with the additions in the places that list gave them,
## Hardness beside Softness and Mirror after Rotation, and the pages it never
## named after it, Sharpness, the smudge stage and the mask's two, in the order
## they came.
##
## **These are the options and not the pages any more**. The five colour ones
## share the Colour Dynamics page, so the list of options and the list of page
## titles stopped being the same list and are two constants now.
const CURVE_OPTIONS: Array[String] = [
    "Size",
    "Opacity",
    "Flow",
    "Spacing Dynamics",
    "Softness",
    "Hardness",
    "Rotation",
    "Mirror",
    "Ratio",
    "Hue",
    "Saturation",
    "Value",
    "Darken",
    "Mix",
    "Scatter",
    "Texture",
    "Airbrush Rate",
    "Sharpness",
    "Smudge Pickup",
    "Colour Rate",
    "Smear Length",
    # The mask's own two options, declared after the smudge stage's, which
    # is the place every later addition has taken.
    "Mask Size",
    "Mask Opacity",
]

## The page titles the options above declare, which is the same list with the
## five colour options collapsed into the one page they name.
const CURVE_PAGES: Array[String] = [
    "Size",
    "Opacity",
    "Flow",
    "Spacing Dynamics",
    "Softness",
    "Hardness",
    "Rotation",
    "Mirror",
    "Ratio",
    "Colour Dynamics",
    "Scatter",
    "Texture",
    "Airbrush Rate",
    "Sharpness",
    "Smudge Pickup",
    "Colour Rate",
    "Smear Length",
    "Mask Size",
    "Mask Opacity",
]


func _specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    out.assign(ModuleScript.brush_options())
    return out


## Every page a spec declares, in declaration order, which is the order the
## editor builds its list in.
func _page_titles() -> Array[String]:
    var seen: Array[String] = []
    for spec: SaOptionSpec in _specs():
        # The same rule `SaBrushEditorPages.pages_from` reads a title by: a
        # curve option's page is its label until it names one.
        var title := spec.page if not spec.page.is_empty() else spec.label
        if title.is_empty() or seen.has(title):
            continue
        seen.append(title)
    return seen


## The pages in their set order, which the editor
## reads off this declaration: the tip first, the dashboard next, then the
## numbers, and the Masking Brush page between Texture and Airbrush Rate where
## the list puts it. The Masking Brush page is the Brush Tip page's
## rows a second time, over the second tip, and neither a curve option nor a
## page the module wrote rows for by hand.
func test_the_pages_are_declared_in_the_decided_order() -> void:
    var expected: Array[String] = [ModuleScript.TIP_PAGE, ModuleScript.GENERAL_PAGE]
    var cut := CURVE_PAGES.find("Airbrush Rate")
    expected.append_array(CURVE_PAGES.slice(0, cut))
    expected.append(SaMaskingPage.PAGE)
    expected.append_array(CURVE_PAGES.slice(cut))
    assert_eq(_page_titles(), expected, "Brush Tip, General, the curve pages to Texture, Masking Brush and the rest")


## A curve option page is one spec of its own kind naming a real `SaCurveOption`
## on the settings. A page whose property resolves to nothing draws a checkbox
## bound to nothing, which is a page a painter can tick and untick with no
## effect anywhere.
func test_every_curve_page_names_a_curve_option_the_settings_hold() -> void:
    var settings := SaStampBrushSettings.new()
    var found: Array[String] = []
    for spec: SaOptionSpec in _specs():
        if spec.kind != SaOptionSpec.Kind.CURVE_OPTION:
            continue
        found.append(spec.label)
        var value: Variant = settings.get_indexed(spec.property_path())
        assert_true(value is SaCurveOption, "%s names an SaCurveOption, and got %s" % [spec.label, value])
    assert_eq(found, CURVE_OPTIONS, "and every one of them is here, in order")


## Every row a spec puts on a plain page names that page, rather than reaching it
## through the editor's fallback. The fallback is for a tool that declares
## nothing, and this module declares.
func test_no_row_reaches_its_page_through_the_editor_s_fallback() -> void:
    for spec: SaOptionSpec in _specs():
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            continue
        assert_false(spec.page.is_empty(), "%s names its own page" % spec.key)


## The bar is unchanged by the pages: nine buttons on a bar with 45 pixels
## spare is not a reduction.
func test_no_curve_page_reaches_the_top_bar() -> void:
    for spec: SaOptionSpec in _specs():
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            assert_false(spec.bar, "%s stays off the top bar" % spec.label)


## British English in every string the app puts on screen, which is the house
## rule and which a page title is squarely inside.
##
## The American spellings are checked rather than the British ones, because there
## is no list of correct words and there is a short list of the ones this project
## keeps getting wrong. `-ize` is the Oxford spelling and is correct, so it is not
## here.
func test_every_page_title_and_tooltip_is_british() -> void:
    const AMERICAN: Array[String] = ["color", "Color", "center", "Center", "gray", "Gray", "behavior", "Behavior"]
    for spec: SaOptionSpec in _specs():
        for word: String in AMERICAN:
            assert_false(spec.label.contains(word), "%s is British in its label" % spec.key)
            assert_false(spec.page.contains(word), "%s is British in its page title" % spec.key)
            assert_false(spec.tooltip.contains(word), "%s is British in its tooltip" % spec.key)
