## The whole sentence for each shipped word a sentence of the interface names,
## so a language with grammatical cases translates the sentence and not a word
## dropped into it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "Add %s" with "Effect Layer" dropped in gives Czech the kind's name in its
## dictionary form where the sentence needs another ending. So each sentence
## that names a docker, a filter, a tool, a layer kind or a brush option is
## written whole here, once for every one Sara ships, keyed by the English word
## the call site holds. A call site reads its table first and falls back to its
## generic sentence with the placeholder, which is what a third-party module's
## own docker, filter or tool still reads, since no table can know it.
##
## The English of every entry is the generic sentence with the word put in, so
## the English a painter reads does not change, and
## `test_a_shipped_word_has_its_whole_sentence.gd` holds every table to
## that. The template reads each entry, because a translating call over a
## constant dictionary is read whole (`write_pot.py`, "a collection").
##
## **Here rather than beside each call site**, because the command registry in
## `core` and the Dockers page in `ui` name the same dockers, and `core` cannot
## name `ui`. This owns one thing, the whole sentences of the shipped words.
class_name SaWholeSentences
extends RefCounted

## The hidden docker's line when its toggle has no chord.
const DOCKER_FIRST_MENU: Dictionary[String, String] = {
    "Toolbox": "Show the Toolbox docker first, from the Window menu.",
    "Layers": "Show the Layers docker first, from the Window menu.",
    "Colour Picker": "Show the Colour Picker docker first, from the Window menu.",
    "Info": "Show the Info docker first, from the Window menu.",
    "Recorder": "Show the Recorder docker first, from the Window menu.",
    "Minimap": "Show the Minimap docker first, from the Window menu.",
    "Tool Options": "Show the Tool Options docker first, from the Window menu.",
    "Graph": "Show the Graph docker first, from the Window menu.",
    "Recent Presets": "Show the Recent Presets docker first, from the Window menu.",
    "Undo History": "Show the Undo History docker first, from the Window menu.",
    "Reference": "Show the Reference docker first, from the Window menu.",
    "Brush Presets": "Show the Brush Presets docker first, from the Window menu.",
    "Pop-up Palette": "Show the Pop-up Palette docker first, from the Window menu.",
    "Filters": "Show the Filters docker first, from the Window menu.",
    "Exposure": "Show the Exposure docker first, from the Window menu.",
    "Blender Live": "Show the Blender Live docker first, from the Window menu.",
    "Stats": "Show the Stats docker first, from the Window menu.",
    "Colourise": "Show the Colourise docker first, from the Window menu.",
    "Sphere": "Show the Sphere docker first, from the Window menu.",
}

## The hidden docker's line beside its toggle's chord, which stays a placeholder.
const DOCKER_FIRST_CHORD: Dictionary[String, String] = {
    "Toolbox": "Show the Toolbox docker first (%s).",
    "Layers": "Show the Layers docker first (%s).",
    "Colour Picker": "Show the Colour Picker docker first (%s).",
    "Info": "Show the Info docker first (%s).",
    "Recorder": "Show the Recorder docker first (%s).",
    "Minimap": "Show the Minimap docker first (%s).",
    "Tool Options": "Show the Tool Options docker first (%s).",
    "Graph": "Show the Graph docker first (%s).",
    "Recent Presets": "Show the Recent Presets docker first (%s).",
    "Undo History": "Show the Undo History docker first (%s).",
    "Reference": "Show the Reference docker first (%s).",
    "Brush Presets": "Show the Brush Presets docker first (%s).",
    "Pop-up Palette": "Show the Pop-up Palette docker first (%s).",
    "Filters": "Show the Filters docker first (%s).",
    "Exposure": "Show the Exposure docker first (%s).",
    "Blender Live": "Show the Blender Live docker first (%s).",
    "Stats": "Show the Stats docker first (%s).",
    "Colourise": "Show the Colourise docker first (%s).",
    "Sphere": "Show the Sphere docker first (%s).",
}

## The tooltip of a docker's Customize button on the Dockers page.
const DOCKER_PARTS: Dictionary = {
    "Toolbox": "Choose which parts the Toolbox docker shows, and their order.",
    "Layers": "Choose which parts the Layers docker shows, and their order.",
    "Colour Picker": "Choose which parts the Colour Picker docker shows, and their order.",
    "Info": "Choose which parts the Info docker shows, and their order.",
    "Recorder": "Choose which parts the Recorder docker shows, and their order.",
    "Minimap": "Choose which parts the Minimap docker shows, and their order.",
    "Tool Options": "Choose which parts the Tool Options docker shows, and their order.",
    "Graph": "Choose which parts the Graph docker shows, and their order.",
    "Recent Presets": "Choose which parts the Recent Presets docker shows, and their order.",
    "Undo History": "Choose which parts the Undo History docker shows, and their order.",
    "Reference": "Choose which parts the Reference docker shows, and their order.",
    "Brush Presets": "Choose which parts the Brush Presets docker shows, and their order.",
    "Pop-up Palette": "Choose which parts the Pop-up Palette docker shows, and their order.",
    "Filters": "Choose which parts the Filters docker shows, and their order.",
    "Exposure": "Choose which parts the Exposure docker shows, and their order.",
    "Blender Live": "Choose which parts the Blender Live docker shows, and their order.",
    "Stats": "Choose which parts the Stats docker shows, and their order.",
    "Colourise": "Choose which parts the Colourise docker shows, and their order.",
    "Sphere": "Choose which parts the Sphere docker shows, and their order.",
}

## The tooltip of a docker's Options button on the Dockers page.
const DOCKER_SETTINGS: Dictionary = {
    "Toolbox": "Toolbox docker settings",
    "Layers": "Layers docker settings",
    "Colour Picker": "Colour Picker docker settings",
    "Info": "Info docker settings",
    "Recorder": "Recorder docker settings",
    "Minimap": "Minimap docker settings",
    "Tool Options": "Tool Options docker settings",
    "Graph": "Graph docker settings",
    "Recent Presets": "Recent Presets docker settings",
    "Undo History": "Undo History docker settings",
    "Reference": "Reference docker settings",
    "Brush Presets": "Brush Presets docker settings",
    "Pop-up Palette": "Pop-up Palette docker settings",
    "Filters": "Filters docker settings",
    "Exposure": "Exposure docker settings",
    "Blender Live": "Blender Live docker settings",
    "Stats": "Stats docker settings",
    "Colourise": "Colourise docker settings",
    "Sphere": "Sphere docker settings",
}

## Where a placed element comes from, beside its row: a docker or the top bar.
const DOCKER_FROM: Dictionary = {
    "Toolbox": "from Toolbox",
    "Layers": "from Layers",
    "Colour Picker": "from Colour Picker",
    "Info": "from Info",
    "Recorder": "from Recorder",
    "Minimap": "from Minimap",
    "Tool Options": "from Tool Options",
    "Graph": "from Graph",
    "Recent Presets": "from Recent Presets",
    "Undo History": "from Undo History",
    "Reference": "from Reference",
    "Brush Presets": "from Brush Presets",
    "Pop-up Palette": "from Pop-up Palette",
    "Filters": "from Filters",
    "Exposure": "from Exposure",
    "Blender Live": "from Blender Live",
    "Stats": "from Stats",
    "Colourise": "from Colourise",
    "Sphere": "from Sphere",
    "Top Bar": "from Top Bar",
}

## The Filter menu's row that runs the last filter again.
const FILTER_AGAIN: Dictionary = {
    "Box Blur": "Apply Box Blur Again",
    "Kaleidoscope": "Apply Kaleidoscope Again",
    "Brightness/Contrast": "Apply Brightness/Contrast Again",
    "Exposure": "Apply Exposure Again",
    "Hue/Saturation/Lightness": "Apply Hue/Saturation/Lightness Again",
    "Colour Balance": "Apply Colour Balance Again",
    "Levels": "Apply Levels Again",
    "Equalize": "Apply Equalize Again",
    "Curves": "Apply Curves Again",
    "Colour Lookup": "Apply Colour Lookup Again",
    "Gradient Map": "Apply Gradient Map Again",
    "White Point": "Apply White Point Again",
    "Red-eye Removal": "Apply Red-eye Removal Again",
    "Invert": "Apply Invert Again",
    "Desaturate": "Apply Desaturate Again",
    "Add Noise": "Apply Add Noise Again",
    "Drifting Noise": "Apply Drifting Noise Again",
    "Grain": "Apply Grain Again",
    "Denoise": "Apply Denoise Again",
    "Wavelet Denoise": "Apply Wavelet Denoise Again",
    "Hot Pixels": "Apply Hot Pixels Again",
    "Sharpen": "Apply Sharpen Again",
    "High Pass": "Apply High Pass Again",
    "Local Contrast": "Apply Local Contrast Again",
    "Height to Normal Map": "Apply Height to Normal Map Again",
    "Bump Map": "Apply Bump Map Again",
    "Wrap Offset": "Apply Wrap Offset Again",
    "Wobble": "Apply Wobble Again",
    "Mirror": "Apply Mirror Again",
    "Gaussian Blur": "Apply Gaussian Blur Again",
    "Low Pass": "Apply Low Pass Again",
    "Motion Blur": "Apply Motion Blur Again",
    "Lens Blur": "Apply Lens Blur Again",
    "Bloom": "Apply Bloom Again",
    "Threshold": "Apply Threshold Again",
    "Edge Detection": "Apply Edge Detection Again",
    "Laplacian": "Apply Laplacian Again",
    "Dither": "Apply Dither Again",
    "Pixelate": "Apply Pixelate Again",
    "Vignette": "Apply Vignette Again",
    "Posterize": "Apply Posterize Again",
    "Chromatic Aberration": "Apply Chromatic Aberration Again",
    "LUT": "Apply LUT Again",
    "Tonemap": "Apply Tonemap Again",
    "Lens Correction": "Apply Lens Correction Again",
}

## The tooltip of the filter window's Attach button.
const FILTER_ATTACHES: Dictionary = {
    "Box Blur": "Attaches Box Blur to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Kaleidoscope":
    "Attaches Kaleidoscope to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Brightness/Contrast":
    # gdlint:ignore=max-line-length
    "Attaches Brightness/Contrast to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Exposure": "Attaches Exposure to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Hue/Saturation/Lightness":
    # gdlint:ignore=max-line-length
    "Attaches Hue/Saturation/Lightness to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Colour Balance":
    "Attaches Colour Balance to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Levels": "Attaches Levels to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Equalize": "Attaches Equalize to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Curves": "Attaches Curves to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Colour Lookup":
    "Attaches Colour Lookup to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Gradient Map":
    "Attaches Gradient Map to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "White Point":
    "Attaches White Point to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Red-eye Removal":
    "Attaches Red-eye Removal to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Invert": "Attaches Invert to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Desaturate":
    "Attaches Desaturate to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Add Noise":
    "Attaches Add Noise to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Drifting Noise":
    "Attaches Drifting Noise to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Grain": "Attaches Grain to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Denoise": "Attaches Denoise to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Wavelet Denoise":
    "Attaches Wavelet Denoise to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Hot Pixels":
    "Attaches Hot Pixels to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Sharpen": "Attaches Sharpen to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "High Pass":
    "Attaches High Pass to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Local Contrast":
    "Attaches Local Contrast to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Height to Normal Map":
    # gdlint:ignore=max-line-length
    "Attaches Height to Normal Map to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Bump Map": "Attaches Bump Map to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Wrap Offset":
    "Attaches Wrap Offset to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Wobble": "Attaches Wobble to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Mirror": "Attaches Mirror to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Gaussian Blur":
    "Attaches Gaussian Blur to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Low Pass": "Attaches Low Pass to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Motion Blur":
    "Attaches Motion Blur to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Lens Blur":
    "Attaches Lens Blur to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Bloom": "Attaches Bloom to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Threshold":
    "Attaches Threshold to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Edge Detection":
    "Attaches Edge Detection to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Laplacian":
    "Attaches Laplacian to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Dither": "Attaches Dither to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Pixelate": "Attaches Pixelate to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Vignette": "Attaches Vignette to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Posterize":
    "Attaches Posterize to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Chromatic Aberration":
    # gdlint:ignore=max-line-length
    "Attaches Chromatic Aberration to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "LUT": "Attaches LUT to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Tonemap": "Attaches Tonemap to the active layer instead of writing it in, where it stays editable until it is flattened.",
    "Lens Correction":
    "Attaches Lens Correction to the active layer instead of writing it in, where it stays editable until it is flattened.",
}

## The tooltip of a section's row in the Filter menu.
const FILTER_SECTION: Dictionary = {
    "Tone": "The Tone filters of every module.",
    "Colour": "The Colour filters of every module.",
    "3D": "The 3D filters of every module.",
    "Blur": "The Blur filters of every module.",
    "Sharpen": "The Sharpen filters of every module.",
    "Distort": "The Distort filters of every module.",
    "Noise": "The Noise filters of every module.",
    "Pixelate": "The Pixelate filters of every module.",
    "Stylize": "The Stylize filters of every module.",
    "Other": "The Other filters of every module.",
}

## The tooltip of a tool's row in the Tools menu.
const TOOL_SWITCHES: Dictionary = {
    "Brush": "Switches to the Brush tool.",
    "Eraser": "Switches to the Eraser tool.",
    "Fill": "Switches to the Fill tool.",
    "Gradient": "Switches to the Gradient tool.",
    "Crop": "Switches to the Crop tool.",
    "Transform": "Switches to the Transform tool.",
    "Liquify": "Switches to the Liquify tool.",
    "Eyedropper": "Switches to the Eyedropper tool.",
    "Pan": "Switches to the Pan tool.",
    "Zoom": "Switches to the Zoom tool.",
    "Marquee": "Switches to the Marquee tool.",
    "Ellipse Select": "Switches to the Ellipse Select tool.",
    "Lasso": "Switches to the Lasso tool.",
    "Polygonal Lasso": "Switches to the Polygonal Lasso tool.",
    "Magnetic Lasso": "Switches to the Magnetic Lasso tool.",
    "Magic Wand": "Switches to the Magic Wand tool.",
    "Select Subject": "Switches to the Select Subject tool.",
    "Object Selection": "Switches to the Object Selection tool.",
    "Patch": "Switches to the Patch tool.",
    "Filter Brush": "Switches to the Filter Brush tool.",
    "Noise Brush": "Switches to the Noise Brush tool.",
    "Assistants": "Switches to the Assistants tool.",
    "Text": "Switches to the Text tool.",
    "Shape": "Switches to the Shape tool.",
    "Object": "Switches to the Object tool.",
}

## The tooltip of a toolbox element whose tool no module loaded, keyed by the
## element, the tool's name and " Tool".
const TOOL_NOT_LOADED: Dictionary = {
    "Brush Tool": "Brush is not loaded.",
    "Bucket Fill Tool": "Bucket Fill is not loaded.",
    "Gradient Tool": "Gradient is not loaded.",
    "Eraser Tool": "Eraser is not loaded.",
    "Eyedropper Tool": "Eyedropper is not loaded.",
    "Pan Tool": "Pan is not loaded.",
    "Zoom Tool": "Zoom is not loaded.",
    "Marquee Tool": "Marquee is not loaded.",
    "Ellipse Select Tool": "Ellipse Select is not loaded.",
    "Lasso Tool": "Lasso is not loaded.",
    "Polygonal Lasso Tool": "Polygonal Lasso is not loaded.",
    "Magnetic Lasso Tool": "Magnetic Lasso is not loaded.",
    "Magic Wand Tool": "Magic Wand is not loaded.",
    "Patch Tool": "Patch is not loaded.",
    "Crop Tool": "Crop is not loaded.",
    "Transform Tool": "Transform is not loaded.",
    "Assistants Tool": "Assistants is not loaded.",
}

## A layer kind's row in the search.
const LAYER_NEW: Dictionary[String, String] = {
    "Paper Layer": "New Paper Layer",
    "Canvas Layer": "New Canvas Layer",
    "Adjustment Layer": "New Adjustment Layer",
    "Effect Layer": "New Effect Layer",
    "Frame Layer": "New Frame Layer",
    "Drifting Sky Layer": "New Drifting Sky Layer",
    "Colourise Line Art Layer": "New Colourise Line Art Layer",
    "Text Layer": "New Text Layer",
    "Vector Layer": "New Vector Layer",
}

## The title of the browser a layer kind that holds a filter opens.
const LAYER_ADD: Dictionary = {
    "Adjustment Layer": "Add Adjustment Layer",
    "Effect Layer": "Add Effect Layer",
}

## A curve option's row in the Tool Options docker.
const OPTION_DYNAMICS: Dictionary = {
    "Size": "Size dynamics",
    "Opacity": "Opacity dynamics",
    "Flow": "Flow dynamics",
    "Softness": "Softness dynamics",
    "Hardness": "Hardness dynamics",
    "Rotation": "Rotation dynamics",
    "Mirror": "Mirror dynamics",
    "Ratio": "Ratio dynamics",
    "Hue": "Hue dynamics",
    "Saturation": "Saturation dynamics",
    "Value": "Value dynamics",
    "Darken": "Darken dynamics",
    "Mix": "Mix dynamics",
    "Scatter": "Scatter dynamics",
    "Texture": "Texture dynamics",
    "Airbrush Rate": "Airbrush Rate dynamics",
    "Sharpness": "Sharpness dynamics",
    "Smudge Pickup": "Smudge Pickup dynamics",
    "Colour Rate": "Colour Rate dynamics",
    "Smear Length": "Smear Length dynamics",
    "Mask Size": "Mask Size dynamics",
    "Mask Opacity": "Mask Opacity dynamics",
    "Strength": "Strength dynamics",
    "Thickness": "Thickness dynamics",
    "Tilt Stretch": "Tilt Stretch dynamics",
    "Tilt Thickness": "Tilt Thickness dynamics",
    "Drift Speed": "Drift Speed dynamics",
}

## A randomise row's label while the top bar holds its slider.
const OPTION_JITTER: Dictionary = {
    "Radius": "Radius jitter",
    "Opacity": "Opacity jitter",
    "Hardness": "Hardness jitter",
    "Strength": "Strength jitter",
    "Thickness": "Thickness jitter",
}

## The tooltip of a brush editor page's switch.
const PAGE_SWITCH: Dictionary = {
    "Size": "Turns Size on for this brush. Off, the brush paints as if the page were not there.",
    "Opacity": "Turns Opacity on for this brush. Off, the brush paints as if the page were not there.",
    "Flow": "Turns Flow on for this brush. Off, the brush paints as if the page were not there.",
    "Spacing Dynamics": "Turns Spacing Dynamics on for this brush. Off, the brush paints as if the page were not there.",
    "Softness": "Turns Softness on for this brush. Off, the brush paints as if the page were not there.",
    "Hardness": "Turns Hardness on for this brush. Off, the brush paints as if the page were not there.",
    "Rotation": "Turns Rotation on for this brush. Off, the brush paints as if the page were not there.",
    "Mirror": "Turns Mirror on for this brush. Off, the brush paints as if the page were not there.",
    "Ratio": "Turns Ratio on for this brush. Off, the brush paints as if the page were not there.",
    "Hue": "Turns Hue on for this brush. Off, the brush paints as if the page were not there.",
    "Saturation": "Turns Saturation on for this brush. Off, the brush paints as if the page were not there.",
    "Value": "Turns Value on for this brush. Off, the brush paints as if the page were not there.",
    "Darken": "Turns Darken on for this brush. Off, the brush paints as if the page were not there.",
    "Mix": "Turns Mix on for this brush. Off, the brush paints as if the page were not there.",
    "Scatter": "Turns Scatter on for this brush. Off, the brush paints as if the page were not there.",
    "Texture": "Turns Texture on for this brush. Off, the brush paints as if the page were not there.",
    "Airbrush Rate": "Turns Airbrush Rate on for this brush. Off, the brush paints as if the page were not there.",
    "Sharpness": "Turns Sharpness on for this brush. Off, the brush paints as if the page were not there.",
    "Smudge Pickup": "Turns Smudge Pickup on for this brush. Off, the brush paints as if the page were not there.",
    "Colour Rate": "Turns Colour Rate on for this brush. Off, the brush paints as if the page were not there.",
    "Smear Length": "Turns Smear Length on for this brush. Off, the brush paints as if the page were not there.",
    "Mask Size": "Turns Mask Size on for this brush. Off, the brush paints as if the page were not there.",
    "Mask Opacity": "Turns Mask Opacity on for this brush. Off, the brush paints as if the page were not there.",
    "Strength": "Turns Strength on for this brush. Off, the brush paints as if the page were not there.",
    "Thickness": "Turns Thickness on for this brush. Off, the brush paints as if the page were not there.",
    "Tilt Stretch": "Turns Tilt Stretch on for this brush. Off, the brush paints as if the page were not there.",
    "Tilt Thickness": "Turns Tilt Thickness on for this brush. Off, the brush paints as if the page were not there.",
    "Drift Speed": "Turns Drift Speed on for this brush. Off, the brush paints as if the page were not there.",
    "Masking Brush": "Turns Masking Brush on for this brush. Off, the brush paints as if the page were not there.",
}
