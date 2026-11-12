## Where the base module's filters and the Filter menu's sections are registered.
##
## Here rather than in `module.gd`, so the module is not the file a new filter
## edits. A filter is one preload below and one line in [method register], in
## the order the menu lists it, and nothing about a filter lives here beyond
## that. The module calls [method register] once.
extends RefCounted

## The three slider adjustments.
const BrightnessContrastFilter = preload("res://modules/sara-base-modules/base/filters/brightness_contrast_filter.gd")
const ExposureFilter = preload("res://modules/sara-base-modules/base/usual/exposure_filter.gd")
const HueSaturationLightnessFilter = preload("res://modules/sara-base-modules/base/filters/hue_saturation_lightness_filter.gd")
const ColorBalanceFilter = preload("res://modules/sara-base-modules/base/filters/color_balance_filter.gd")
## Levels, a feature folder of its own reached through its filter, and Curves.
const LevelsFilter = preload("res://modules/sara-base-modules/base/filters/levels/levels_filter.gd")
const CurvesFilter = preload("res://modules/sara-base-modules/base/filters/curves_filter.gd")
## The colour lookup, whose kernel, id and command all keep the word palette.
const ColorLookupFilter = preload("res://modules/sara-base-modules/base/filters/color_lookup/color_lookup_filter.gd")
## The usual filters, one file each under `base/usual`, a folder of their own
## beside `filters/`: add noise, the two denoises and the sharpens, then the
## two map filters.
const AddNoiseFilter = preload("res://modules/sara-base-modules/base/usual/add_noise_filter.gd")
const DenoiseFilter = preload("res://modules/sara-base-modules/base/usual/denoise_filter.gd")
## The wavelet denoise, the third of the usual denoises.
const WaveletDenoiseFilter = preload("res://modules/sara-base-modules/base/usual/wavelet_denoise_filter.gd")
## Hot Pixels, the single texels apart from all their neighbours, after the denoises.
const HotPixelsFilter = preload("res://modules/sara-base-modules/base/usual/hot_pixels_filter.gd")
const SharpenFilter = preload("res://modules/sara-base-modules/base/usual/sharpen_filter.gd")
## The high pass, the picture less its Gaussian blur, beside the sharpens.
const HighPassFilter = preload("res://modules/sara-base-modules/base/usual/high_pass_filter.gd")
## Local Contrast, darktable's local laplacian, after the high pass under Sharpen.
const LocalContrastFilter = preload("res://modules/sara-base-modules/base/filters/local_contrast/local_contrast_filter.gd")
const NormalMapFilter = preload("res://modules/sara-base-modules/base/usual/normal_map.gd")
const BumpMapFilter = preload("res://modules/sara-base-modules/base/usual/bump_map.gd")
## The wrap offset, one of the usual filters.
const WrapOffsetFilter = preload("res://modules/sara-base-modules/base/usual/wrap_offset.gd")
## The wobble, ripples a noise breaks up, beside the wrap under Distort.
const WobbleFilter = preload("res://modules/sara-base-modules/base/usual/wobble_filter.gd")
## The mirror, the paint reflected about a line, after the wobble under Distort.
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")
const GaussianBlurFilter = preload("res://modules/sara-base-modules/base/usual/gaussian_blur_filter.gd")
## Box Blur, the flat square, after the bell.
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")
## The low pass, the Gaussian blur under the name a frequency separation uses.
const LowPassFilter = preload("res://modules/sara-base-modules/base/usual/low_pass_filter.gd")
const MotionBlurFilter = preload("res://modules/sara-base-modules/base/usual/motion_blur.gd")
## The lens blur, a disc of the radius.
const LensBlurFilter = preload("res://modules/sara-base-modules/base/usual/lens_blur_filter.gd")
## The bloom, a glow from the values above a threshold, beside the blurs.
const BloomFilter = preload("res://modules/sara-base-modules/base/usual/bloom_filter.gd")
## The usual set, which has a folder of its own beside the adjustments because
## the two together would make one folder too large to read whole. Threshold is a pixel function, registered
## through the call a module's own takes, under the key of the class that holds it.
const THRESHOLD := "res://modules/sara-base-modules/base/usual/threshold.gmacs"
const EdgeDetectionFilter = preload("res://modules/sara-base-modules/base/usual/edge_detection.gd")
## The Laplacian, the second derivative as a detail map, beside Edge Detection.
const LaplacianFilter = preload("res://modules/sara-base-modules/base/usual/laplacian_filter.gd")
const DitherFilter = preload("res://modules/sara-base-modules/base/usual/dither_filter.gd")
## Posterize, under Tone, the cut to a few even levels Dither only does last.
const PosteriseFilter = preload("res://modules/sara-base-modules/base/usual/posterise_filter.gd")
## The one-click three: Invert and Desaturate under Colour, the second over
## Hue/Saturation's own kernel, and Pixelate, the first of its section.
const InvertFilter = preload("res://modules/sara-base-modules/base/usual/invert_filter.gd")
const DesaturateFilter = preload("res://modules/sara-base-modules/base/usual/desaturate_filter.gd")
const PixelateFilter = preload("res://modules/sara-base-modules/base/usual/pixelate_filter.gd")
## The vignette, beside Dither under Stylize.
const VignetteFilter = preload("res://modules/sara-base-modules/base/usual/vignette_filter.gd")
## The chromatic aberration, beside the wobble under Distort.
const ChromaticAberrationFilter = preload("res://modules/sara-base-modules/base/usual/chromatic_aberration_filter.gd")
## The LUT, a `.cube` file as a colour lookup table, under Colour.
const LutFilter = preload("res://modules/sara-base-modules/base/usual/lut_filter.gd")
## The lens correction, a barrel or a pincushion straightened, after it.
const LensCorrectionFilter = preload("res://modules/sara-base-modules/base/usual/lens_correction_filter.gd")
## Red-eye Removal, the last of the Colour adjustments a painter sets by hand.
const RedEyeRemovalFilter = preload("res://modules/sara-base-modules/base/usual/red_eye_removal_filter.gd")
## Tonemap, the view's highlight rolloff written into a layer, under Tone.
const TonemapFilter = preload("res://modules/sara-base-modules/base/usual/tonemap_filter.gd")


## Hard rule 6, for the Filter menu: the built-in adjustments come through the
## door a stranger's filter uses, in the order the menu lists them. Here and
## not in a module of their own, because a third folder would cost a
## `module.gd` for nothing a painter or a module author can see.
##
## A context built for a tool registry alone has no filter registry, which
## is what `tests/fixtures.gd` builds, and asking it would be refused six
## times over in every suite that registers this module for its tools.
static func register(ctx: SaContext) -> void:
    if ctx.filters == null:
        return
    _register_sections(ctx)
    ctx.register_filter(BrightnessContrastFilter.new())
    ctx.register_filter(ExposureFilter.new())
    ctx.register_filter(HueSaturationLightnessFilter.new())
    ctx.register_filter(ColorBalanceFilter.new())
    ctx.register_filter(LevelsFilter.new())
    ctx.register_filter(LevelsFilter.equalize_entry())
    ctx.register_filter(CurvesFilter.new())
    ctx.register_filter(ColorLookupFilter.new())
    ctx.register_filter(SaGradientMapFilter.new())
    ctx.register_filter(SaWhitePointFilter.over(ctx))
    ctx.register_filter(RedEyeRemovalFilter.new())
    # The one-click colour two close Colour, after the adjustments a
    # painter sets by hand.
    ctx.register_filter(InvertFilter.new())
    ctx.register_filter(DesaturateFilter.new())
    # The usual set begins here, in the order a painter works through it:
    # noise, the denoises and the sharpens, then a height read as a surface
    # and that same surface shaded, and the wrap that closes the list.
    ctx.register_filter(AddNoiseFilter.new())
    ctx.register_filter(SaDriftingNoiseFilter.new())
    ctx.register_filter(DenoiseFilter.new())
    ctx.register_filter(WaveletDenoiseFilter.new())
    ctx.register_filter(HotPixelsFilter.new())
    ctx.register_filter(SharpenFilter.new())
    ctx.register_filter(HighPassFilter.new())
    ctx.register_filter(LocalContrastFilter.new())
    ctx.register_filter(NormalMapFilter.new())
    ctx.register_filter(BumpMapFilter.new())
    ctx.register_filter(WrapOffsetFilter.new())
    ctx.register_filter(WobbleFilter.new())
    ctx.register_filter(MirrorFilter.new())
    ctx.register_filter(GaussianBlurFilter.new())
    ctx.register_filter(BoxBlurFilter.new())
    ctx.register_filter(LowPassFilter.new())
    ctx.register_filter(MotionBlurFilter.new())
    ctx.register_filter(LensBlurFilter.new())
    ctx.register_filter(BloomFilter.new())
    ctx.register_filter(SaPixelFilter.new(THRESHOLD, "Threshold", 0, &"tone"))
    ctx.register_filter(EdgeDetectionFilter.new())
    ctx.register_filter(LaplacianFilter.new())
    ctx.register_filter(DitherFilter.new())
    ctx.register_filter(PixelateFilter.new())
    ctx.register_filter(VignetteFilter.new())
    ctx.register_filter(PosteriseFilter.new())
    ctx.register_filter(ChromaticAberrationFilter.new())
    ctx.register_filter(LutFilter.new())
    ctx.register_filter(TonemapFilter.new())
    ctx.register_filter(LensCorrectionFilter.new())


## The Filter menu's submenus, which are the base module's and no table's, so a
## stranger's filter that names `blur` sits in Blur beside Sara's own and a
## stranger's module may register a section of its own between two of these.
## The two adjustments first because a painter reaches for them most, then the
## rest in the order a menu of filters usually runs, Sharpen beside Blur, and Other last,
## where the registry keeps it whatever its place says. A hundred apart so a
## module's section has room between any two. The menu shows a section only
## once a filter is in it.
static func _register_sections(ctx: SaContext) -> void:
    ctx.register_filter_section(&"tone", "Tone", 100)
    ctx.register_filter_section(&"color", "Colour", 200)
    ctx.register_filter_section(&"3d", "3D", 300)
    ctx.register_filter_section(&"blur", "Blur", 400)
    ctx.register_filter_section(&"sharpen", "Sharpen", 500)
    ctx.register_filter_section(&"distort", "Distort", 600)
    ctx.register_filter_section(&"noise", "Noise", 700)
    ctx.register_filter_section(&"pixelate", "Pixelate", 800)
    ctx.register_filter_section(&"stylize", "Stylize", 900)
    ctx.register_filter_section(SaFilter.OTHER_SECTION, "Other", 1000)
