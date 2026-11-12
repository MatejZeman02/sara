## OpenDRT's parameter set: the rows the Tonemap's OpenDRT method shows, the
## look and tonescale presets that fill them, and the block the kernel reads.
##
## A sibling of the filter and not an inner class, because it owns something of
## its own: seventy-two parameters, seven look presets and fourteen tonescale
## presets, none of which the filter's `run` reads one at a time. A reader
## looking for what a row is called, what it may hold or what Standard sets it
## to has one file to open, and the filter beside it is the door.
##
## **The rows are the DCTL's Stickshift mode**, which is the whole parameter
## space its Look Preset combo stands in front of, with the DCTL's own labels,
## ranges and steps, grouped as its own UI groups them. Three rows are not the
## DCTL's and the kernel's header says so: Brilliance C, M and Y beside its R, G
## and B, since the parameters page lists six windows, and Contrast Low Per
## Channel. All four default to the value that leaves a DCTL preset untouched.
##
## **The presets are the DCTL's own numbers**, taken from `OpenDRT.dctl` v1.1.0
## and carried as the difference from Standard rather than as sixty values each,
## so a number read here can be read against the line of the DCTL it came from.
## Standard is the table's own defaults, and `Standard matches the table` in the
## filter's suite asserts the two have not drifted.
##
## **Creative White is six rows and not the DCTL's seven**: the DCTL's first
## entry means "whatever the look preset said", and here the look preset writes
## this row like every other, so a seventh entry could not be packed into the
## kernel's white index, which is a white and not a state.
class_name SaOpenDrtParameters
extends RefCounted

## The Method row's two entries, in the order the row lists them.
const METHOD_PAPER := 0
const METHOD_OPENDRT := 1
const METHODS := ["Paper", "OpenDRT"]
## The ids the Method row's entries take, which are the two methods themselves.
const METHOD_IDS := [METHOD_PAPER, METHOD_OPENDRT]

## The DCTL's look presets, in its own order, under its own names.
const LOOK_STANDARD := 0
const LOOKS := ["Standard", "Arriba", "Sylvan", "Colorful", "Aery", "Dystopic", "Umbra"]

## The DCTL's tonescale presets. Entry nought is its own "USE LOOK PRESET", which
## writes nothing, so a look preset's tonescale survives it.
const TONESCALE_FROM_LOOK := 0
const TONESCALES := [
    "Use Look Preset",
    "Low Contrast",
    "Medium Contrast",
    "High Contrast",
    "Arriba Tonescale",
    "Sylvan Tonescale",
    "Colorful Tonescale",
    "Aery Tonescale",
    "Dystopic Tonescale",
    "Umbra Tonescale",
    "ACES-1.x",
    "ACES-2.0",
    "Marvelous Tonescape",
    "DaGrinchi ToneGroan",
]

## Every row, in the groups the DCTL's own UI lists them in. A row names its
## key, its label, its range, its step, what Standard holds it at and the kind
## of control it is, and `under` names the enable row it is only shown behind.
const GROUPS := [
    {
        "title": "Tonescale",
        "rows":
        [
            {"k": &"tn_lp", "l": "Display Peak Luminance", "lo": 100.0, "hi": 1000.0, "d": 100.0, "st": 1.0},
            {"k": &"tn_gb", "l": "HDR Grey Boost", "lo": 0.0, "hi": 1.0, "d": 0.13, "st": 0.001},
            {"k": &"pt_hdr", "l": "HDR Purity", "lo": 0.0, "hi": 1.0, "d": 0.5, "st": 0.01},
            {"k": &"tn_lg", "l": "Display Grey Luminance", "lo": 3.0, "hi": 25.0, "d": 10.0, "st": 0.1},
            {"k": &"tn_con", "l": "Contrast", "lo": 1.0, "hi": 2.0, "d": 1.66, "st": 0.01},
            {"k": &"tn_sh", "l": "Shoulder Clip", "lo": 0.0, "hi": 1.0, "d": 0.5, "st": 0.01},
            {"k": &"tn_toe", "l": "Toe", "lo": 0.0, "hi": 0.1, "d": 0.003, "st": 0.001},
            {"k": &"tn_off", "l": "Offset", "lo": 0.0, "hi": 0.02, "d": 0.005, "st": 0.0002},
            {"k": &"tn_hcon_enable", "l": "Enable Contrast High", "d": false, "kind": "check"},
            {"k": &"tn_hcon", "l": "Contrast High", "lo": -1.0, "hi": 1.0, "d": 0.0, "st": 0.02, "under": &"tn_hcon_enable"},
            {
                "k": &"tn_hcon_pv",
                "l": "Contrast High Pivot",
                "lo": 0.0,
                "hi": 4.0,
                "d": 1.0,
                "st": 0.04,
                "under": &"tn_hcon_enable"
            },
            {
                "k": &"tn_hcon_st",
                "l": "Contrast High Strength",
                "lo": 0.0,
                "hi": 4.0,
                "d": 4.0,
                "st": 0.04,
                "under": &"tn_hcon_enable"
            },
            {"k": &"tn_lcon_enable", "l": "Enable Contrast Low", "d": false, "kind": "check"},
            {"k": &"tn_lcon", "l": "Contrast Low", "lo": 0.0, "hi": 3.0, "d": 0.0, "st": 0.03, "under": &"tn_lcon_enable"},
            {
                "k": &"tn_lcon_w",
                "l": "Contrast Low Width",
                "lo": 0.0,
                "hi": 2.0,
                "d": 0.5,
                "st": 0.02,
                "under": &"tn_lcon_enable"
            },
            {"k": &"tn_lcon_pc", "l": "Contrast Low Per Channel", "d": false, "kind": "check", "under": &"tn_lcon_enable"},
        ],
    },
    {
        "title": "Creative White",
        "rows":
        [
            {"k": &"cwp", "l": "Creative White", "d": 2, "kind": "choice", "choices": ["D93", "D75", "D65", "D60", "D55", "D50"]},
            {"k": &"cwp_lm", "l": "Creative White Limit", "lo": 0.0, "hi": 1.0, "d": 0.25, "st": 0.01},
        ],
    },
    {
        "title": "Purity",
        "rows":
        [
            {"k": &"rs_sa", "l": "Render Space Strength", "lo": 0.0, "hi": 0.6, "d": 0.35, "st": 0.006},
            {"k": &"rs_rw", "l": "Render Space Weight R", "lo": 0.0, "hi": 0.8, "d": 0.25, "st": 0.008},
            {"k": &"rs_bw", "l": "Render Space Weight B", "lo": 0.0, "hi": 0.8, "d": 0.55, "st": 0.008},
            {"k": &"pt_enable", "l": "Enable Purity Compress High", "d": true, "kind": "check"},
            {"k": &"pt_lml", "l": "Purity Limit Low", "lo": 0.0, "hi": 1.0, "d": 0.25, "st": 0.01, "under": &"pt_enable"},
            {"k": &"pt_lml_r", "l": "Purity Limit Low R", "lo": 0.0, "hi": 1.0, "d": 0.5, "st": 0.01, "under": &"pt_enable"},
            {"k": &"pt_lml_g", "l": "Purity Limit Low G", "lo": 0.0, "hi": 1.0, "d": 0.0, "st": 0.01, "under": &"pt_enable"},
            {"k": &"pt_lml_b", "l": "Purity Limit Low B", "lo": 0.0, "hi": 1.0, "d": 0.1, "st": 0.01, "under": &"pt_enable"},
            {"k": &"pt_lmh", "l": "Purity Limit High", "lo": 0.0, "hi": 1.0, "d": 0.25, "st": 0.01, "under": &"pt_enable"},
            {"k": &"pt_lmh_r", "l": "Purity Limit High R", "lo": 0.0, "hi": 1.0, "d": 0.5, "st": 0.01, "under": &"pt_enable"},
            {"k": &"pt_lmh_b", "l": "Purity Limit High B", "lo": 0.0, "hi": 1.0, "d": 0.0, "st": 0.01, "under": &"pt_enable"},
            {"k": &"ptm_enable", "l": "Enable Mid Purity", "d": true, "kind": "check"},
            {"k": &"ptm_low", "l": "Mid Purity Low", "lo": 0.0, "hi": 2.0, "d": 0.4, "st": 0.02, "under": &"ptm_enable"},
            {
                "k": &"ptm_low_rng",
                "l": "Mid Purity Low Range",
                "lo": 0.0,
                "hi": 1.0,
                "d": 0.25,
                "st": 0.01,
                "under": &"ptm_enable"
            },
            {
                "k": &"ptm_low_st",
                "l": "Mid Purity Low Strength",
                "lo": 0.1,
                "hi": 1.0,
                "d": 0.5,
                "st": 0.01,
                "under": &"ptm_enable"
            },
            {"k": &"ptm_high", "l": "Mid Purity High", "lo": -0.9, "hi": 0.0, "d": -0.8, "st": 0.01, "under": &"ptm_enable"},
            {
                "k": &"ptm_high_rng",
                "l": "Mid Purity High Range",
                "lo": 0.0,
                "hi": 1.0,
                "d": 0.35,
                "st": 0.01,
                "under": &"ptm_enable"
            },
            {
                "k": &"ptm_high_st",
                "l": "Mid Purity High Strength",
                "lo": 0.1,
                "hi": 1.0,
                "d": 0.4,
                "st": 0.01,
                "under": &"ptm_enable"
            },
            {"k": &"ptl_enable", "l": "Enable Purity Softclip", "d": true, "kind": "check"},
            {"k": &"ptl_c", "l": "Purity Softclip C", "lo": 0.0, "hi": 0.25, "d": 0.06, "st": 0.0025, "under": &"ptl_enable"},
            {"k": &"ptl_m", "l": "Purity Softclip M", "lo": 0.0, "hi": 0.25, "d": 0.08, "st": 0.0025, "under": &"ptl_enable"},
            {"k": &"ptl_y", "l": "Purity Softclip Y", "lo": 0.0, "hi": 0.25, "d": 0.06, "st": 0.0025, "under": &"ptl_enable"},
        ],
    },
    {
        "title": "Brilliance",
        "rows":
        [
            {"k": &"brl_enable", "l": "Enable Brilliance", "d": true, "kind": "check"},
            {"k": &"brl", "l": "Brilliance", "lo": -6.0, "hi": 2.0, "d": 0.0, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_r", "l": "Brilliance R", "lo": -6.0, "hi": 2.0, "d": -2.5, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_g", "l": "Brilliance G", "lo": -6.0, "hi": 2.0, "d": -1.5, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_b", "l": "Brilliance B", "lo": -6.0, "hi": 2.0, "d": -1.5, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_c", "l": "Brilliance C", "lo": -6.0, "hi": 2.0, "d": 0.0, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_m", "l": "Brilliance M", "lo": -6.0, "hi": 2.0, "d": 0.0, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_y", "l": "Brilliance Y", "lo": -6.0, "hi": 2.0, "d": 0.0, "st": 0.08, "under": &"brl_enable"},
            {"k": &"brl_rng", "l": "Brilliance Range", "lo": 0.0, "hi": 1.0, "d": 0.5, "st": 0.01, "under": &"brl_enable"},
            {"k": &"brl_st", "l": "Brilliance Strength", "lo": 0.0, "hi": 1.0, "d": 0.35, "st": 0.01, "under": &"brl_enable"},
            {"k": &"brlp_enable", "l": "Enable Post Brilliance", "d": true, "kind": "check"},
            {"k": &"brlp", "l": "Brilliance Post", "lo": -1.0, "hi": 0.0, "d": -0.5, "st": 0.01, "under": &"brlp_enable"},
            {"k": &"brlp_r", "l": "Post Brilliance R", "lo": -3.0, "hi": 0.0, "d": -1.25, "st": 0.03, "under": &"brlp_enable"},
            {"k": &"brlp_g", "l": "Post Brilliance G", "lo": -3.0, "hi": 0.0, "d": -1.25, "st": 0.03, "under": &"brlp_enable"},
            {"k": &"brlp_b", "l": "Post Brilliance B", "lo": -3.0, "hi": 0.0, "d": -0.25, "st": 0.03, "under": &"brlp_enable"},
        ],
    },
    {
        "title": "Hue Shift",
        "rows":
        [
            {"k": &"oklab_hue", "l": "Oklab hue", "d": true, "kind": "check"},
            {"k": &"hs_rgb_enable", "l": "Enable Hueshift RGB", "d": true, "kind": "check"},
            {"k": &"hs_r", "l": "Hueshift R", "lo": 0.0, "hi": 1.0, "d": 0.6, "st": 0.01, "under": &"hs_rgb_enable"},
            {"k": &"hs_r_rng", "l": "Hueshift R Range", "lo": 0.0, "hi": 2.0, "d": 0.6, "st": 0.02, "under": &"hs_rgb_enable"},
            {"k": &"hs_g", "l": "Hueshift G", "lo": 0.0, "hi": 1.0, "d": 0.35, "st": 0.01, "under": &"hs_rgb_enable"},
            {"k": &"hs_g_rng", "l": "Hueshift G Range", "lo": 0.0, "hi": 2.0, "d": 1.0, "st": 0.02, "under": &"hs_rgb_enable"},
            {"k": &"hs_b", "l": "Hueshift B", "lo": 0.0, "hi": 1.0, "d": 0.66, "st": 0.01, "under": &"hs_rgb_enable"},
            {"k": &"hs_b_rng", "l": "Hueshift B Range", "lo": 0.0, "hi": 4.0, "d": 1.0, "st": 0.02, "under": &"hs_rgb_enable"},
            {"k": &"hs_cmy_enable", "l": "Enable Hueshift CMY", "d": true, "kind": "check"},
            {"k": &"hs_c", "l": "Hueshift C", "lo": 0.0, "hi": 1.0, "d": 0.25, "st": 0.01, "under": &"hs_cmy_enable"},
            {"k": &"hs_c_rng", "l": "Hueshift C Range", "lo": 0.0, "hi": 1.0, "d": 1.0, "st": 0.01, "under": &"hs_cmy_enable"},
            {"k": &"hs_m", "l": "Hueshift M", "lo": 0.0, "hi": 1.0, "d": 0.0, "st": 0.01, "under": &"hs_cmy_enable"},
            {"k": &"hs_m_rng", "l": "Hueshift M Range", "lo": 0.0, "hi": 1.0, "d": 1.0, "st": 0.01, "under": &"hs_cmy_enable"},
            {"k": &"hs_y", "l": "Hueshift Y", "lo": 0.0, "hi": 1.0, "d": 0.0, "st": 0.01, "under": &"hs_cmy_enable"},
            {"k": &"hs_y_rng", "l": "Hueshift Y Range", "lo": 0.0, "hi": 1.0, "d": 1.0, "st": 0.01, "under": &"hs_cmy_enable"},
            {"k": &"hc_enable", "l": "Enable Hue Contrast", "d": true, "kind": "check"},
            {"k": &"hc_r", "l": "Hue Contrast R", "lo": 0.0, "hi": 2.0, "d": 1.0, "st": 0.02, "under": &"hc_enable"},
            {"k": &"hc_r_rng", "l": "Hue Contrast R Range", "lo": 0.0, "hi": 1.0, "d": 0.3, "st": 0.01, "under": &"hc_enable"},
        ],
    },
]

## The parameter block's slots, in the order `opendrt.gmacs` reads them. The
## kernel's own constants carry the same names, and `pack` is the writing half.
const ORDER := [
    &"tn_lp",
    &"tn_gb",
    &"pt_hdr",
    &"tn_lg",
    &"tn_con",
    &"tn_sh",
    &"tn_toe",
    &"tn_off",
    &"tn_hcon_enable",
    &"tn_hcon",
    &"tn_hcon_pv",
    &"tn_hcon_st",
    &"tn_lcon_enable",
    &"tn_lcon",
    &"tn_lcon_w",
    &"tn_lcon_pc",
    &"cwp",
    &"cwp_lm",
    &"rs_sa",
    &"rs_rw",
    &"rs_bw",
    &"pt_enable",
    &"pt_lml",
    &"pt_lml_r",
    &"pt_lml_g",
    &"pt_lml_b",
    &"pt_lmh",
    &"pt_lmh_r",
    &"pt_lmh_b",
    &"ptl_enable",
    &"ptl_c",
    &"ptl_m",
    &"ptl_y",
    &"ptm_enable",
    &"ptm_low",
    &"ptm_low_rng",
    &"ptm_low_st",
    &"ptm_high",
    &"ptm_high_rng",
    &"ptm_high_st",
    &"brl_enable",
    &"brl",
    &"brl_r",
    &"brl_g",
    &"brl_b",
    &"brl_rng",
    &"brl_st",
    &"brl_c",
    &"brl_m",
    &"brl_y",
    &"brlp_enable",
    &"brlp",
    &"brlp_r",
    &"brlp_g",
    &"brlp_b",
    &"hc_enable",
    &"hc_r",
    &"hc_r_rng",
    &"hs_rgb_enable",
    &"hs_r",
    &"hs_r_rng",
    &"hs_g",
    &"hs_g_rng",
    &"hs_b",
    &"hs_b_rng",
    &"hs_cmy_enable",
    &"hs_c",
    &"hs_c_rng",
    &"hs_m",
    &"hs_m_rng",
    &"hs_y",
    &"hs_y_rng",
]

## How many floats the block holds, which the kernel's own constant repeats.
const SETTINGS_FLOATS := 72

## The DCTL's seven look presets as the difference from Standard, so a number
## here reads against the line of `OpenDRT.dctl` v1.1.0 it came from. The row
## "Creative White" is filled like every other, since here the preset writes the
## row rather than the DCTL's own row standing in front of these.
const LOOK_DIFFERENCES := [
    {},
    {
        "tn_con": 1.05,
        "tn_toe": 0.1,
        "tn_off": 0.01,
        "tn_lcon_enable": true,
        "tn_lcon": 1.5,
        "tn_lcon_w": 0.2,
        "pt_lml_r": 0.45,
        "pt_lmh_r": 0.25,
        "ptm_low": 1.0,
        "ptm_low_rng": 0.4,
        "ptm_high_rng": 0.66,
        "ptm_high_st": 0.6,
        "brlp": 0.0,
        "brlp_r": -1.7,
        "brlp_g": -2.0,
        "brlp_b": -0.5,
        "hs_r_rng": 0.8,
        "hs_c": 0.15,
    },
    {
        "tn_con": 1.6,
        "tn_toe": 0.01,
        "tn_off": 0.01,
        "tn_lcon_enable": true,
        "tn_lcon": 0.25,
        "tn_lcon_w": 0.75,
        "rs_sa": 0.25,
        "pt_lml": 0.15,
        "pt_lml_r": 0.5,
        "pt_lml_g": 0.15,
        "pt_lml_b": 0.1,
        "pt_lmh": 0.25,
        "pt_lmh_r": 0.15,
        "pt_lmh_b": 0.15,
        "ptl_c": 0.05,
        "ptl_y": 0.05,
        "ptm_low": 0.5,
        "ptm_low_rng": 0.5,
        "ptm_high_rng": 0.5,
        "ptm_high_st": 0.5,
        "brl": -1.0,
        "brl_r": -2.0,
        "brl_g": -2.0,
        "brl_b": 0.0,
        "brl_rng": 0.25,
        "brl_st": 0.25,
        "brlp": -1.0,
        "brlp_r": -0.5,
        "brlp_g": -0.25,
        "brlp_b": -0.25,
        "hc_r_rng": 0.4,
        "hs_r_rng": 1.15,
        "hs_g": 0.8,
        "hs_g_rng": 1.25,
        "hs_b": 0.6,
        "hs_c": 0.25,
        "hs_c_rng": 0.25,
        "hs_m": 0.25,
        "hs_m_rng": 0.5,
        "hs_y": 0.35,
        "hs_y_rng": 0.5,
    },
    {
        "tn_con": 1.5,
        "tn_off": 0.003,
        "tn_lcon_enable": true,
        "tn_lcon": 0.4,
        "tn_lcon_w": 0.5,
        "pt_lml": 0.5,
        "pt_lml_r": 1.0,
        "pt_lml_g": 0.0,
        "pt_lml_b": 0.5,
        "pt_lmh": 0.15,
        "pt_lmh_r": 0.15,
        "pt_lmh_b": 0.15,
        "ptl_c": 0.05,
        "ptl_m": 0.06,
        "ptl_y": 0.05,
        "ptm_low": 0.8,
        "ptm_low_rng": 0.5,
        "ptm_low_st": 0.4,
        "ptm_high_rng": 0.4,
        "ptm_high_st": 0.4,
        "brl_r": -1.25,
        "brl_g": -1.25,
        "brl_b": -0.25,
        "brl_rng": 0.3,
        "brl_st": 0.5,
        "brlp": -0.5,
        "brlp_r": -1.25,
        "brlp_g": -1.25,
        "brlp_b": -0.5,
        "hc_r_rng": 0.4,
        "hs_r": 0.5,
        "hs_r_rng": 0.8,
        "hs_b": 0.5,
        "hs_b_rng": 1.0,
        "hs_c": 0.25,
        "hs_y": 0.25,
    },
    {
        "tn_con": 1.15,
        "tn_toe": 0.04,
        "tn_off": 0.006,
        "tn_hcon_pv": 0.0,
        "tn_hcon_st": 0.5,
        "tn_lcon_enable": true,
        "tn_lcon": 0.5,
        "tn_lcon_w": 2.0,
        "cwp": 1,
        "rs_sa": 0.25,
        "rs_rw": 0.2,
        "rs_bw": 0.5,
        "pt_lml": 0.0,
        "pt_lml_r": 0.5,
        "pt_lml_g": 0.15,
        "pt_lml_b": 0.1,
        "pt_lmh": 0.0,
        "pt_lmh_r": 0.1,
        "pt_lmh_b": 0.0,
        "ptl_c": 0.05,
        "ptl_m": 0.08,
        "ptl_y": 0.05,
        "ptm_low": 0.8,
        "ptm_low_rng": 0.35,
        "ptm_high": -0.9,
        "ptm_high_rng": 0.5,
        "ptm_high_st": 0.3,
        "brl": -3.0,
        "brl_r": 0.0,
        "brl_g": 0.0,
        "brl_b": 1.0,
        "brl_rng": 0.8,
        "brl_st": 0.15,
        "brlp": -1.0,
        "brlp_r": -1.0,
        "brlp_g": -1.0,
        "brlp_b": 0.0,
        "hc_r": 0.5,
        "hc_r_rng": 0.25,
        "hs_r": 0.6,
        "hs_r_rng": 1.0,
        "hs_g": 0.35,
        "hs_g_rng": 2.0,
        "hs_b": 0.5,
        "hs_b_rng": 1.5,
        "hs_c": 0.35,
        "hs_m": 0.25,
        "hs_y": 0.35,
        "hs_y_rng": 0.5,
    },
    {
        "tn_con": 1.6,
        "tn_toe": 0.01,
        "tn_off": 0.008,
        "tn_hcon_enable": true,
        "tn_hcon": 0.25,
        "tn_hcon_pv": 0.0,
        "tn_hcon_st": 1.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.0,
        "tn_lcon_w": 0.75,
        "cwp": 3,
        "rs_sa": 0.2,
        "pt_lml": 0.15,
        "pt_lml_r": 0.0,
        "pt_lml_g": 0.0,
        "pt_lml_b": 0.0,
        "pt_lmh": 0.0,
        "pt_lmh_r": 0.0,
        "pt_lmh_b": 0.0,
        "ptl_c": 0.05,
        "ptl_y": 0.05,
        "ptm_low": 0.25,
        "ptm_low_rng": 0.25,
        "ptm_low_st": 0.8,
        "ptm_high_rng": 0.6,
        "ptm_high_st": 0.25,
        "brl": -2.0,
        "brl_r": -2.0,
        "brl_g": -2.0,
        "brl_b": 0.0,
        "brl_rng": 0.35,
        "brl_st": 0.35,
        "brlp": 0.0,
        "brlp_r": -1.0,
        "brlp_g": -1.0,
        "brlp_b": -1.0,
        "hc_r_rng": 0.25,
        "hs_r": 0.7,
        "hs_r_rng": 1.33,
        "hs_g": 1.0,
        "hs_g_rng": 2.0,
        "hs_b": 0.75,
        "hs_b_rng": 2.0,
        "hs_c": 1.0,
        "hs_c_rng": 0.5,
        "hs_m": 1.0,
        "hs_m_rng": 1.0,
        "hs_y": 1.0,
        "hs_y_rng": 0.765,
    },
    {
        "tn_con": 1.8,
        "tn_toe": 0.001,
        "tn_off": 0.015,
        "tn_lcon_enable": true,
        "tn_lcon": 1.0,
        "tn_lcon_w": 1.0,
        "cwp": 5,
        "pt_lml": 0.0,
        "pt_lml_r": 0.5,
        "pt_lml_g": 0.0,
        "pt_lml_b": 0.15,
        "pt_lmh": 0.25,
        "pt_lmh_r": 0.25,
        "pt_lmh_b": 0.0,
        "ptl_c": 0.05,
        "ptl_m": 0.06,
        "ptl_y": 0.05,
        "ptm_low": 0.4,
        "ptm_low_rng": 0.35,
        "ptm_low_st": 0.66,
        "ptm_high": -0.6,
        "ptm_high_rng": 0.45,
        "ptm_high_st": 0.45,
        "brl": -2.0,
        "brl_r": -4.5,
        "brl_g": -3.0,
        "brl_b": -4.0,
        "brl_rng": 0.35,
        "brl_st": 0.3,
        "brlp": 0.0,
        "brlp_r": -2.0,
        "brlp_g": -1.0,
        "brlp_b": -0.5,
        "hc_r_rng": 0.35,
        "hs_r": 0.66,
        "hs_r_rng": 1.0,
        "hs_g": 0.5,
        "hs_g_rng": 2.0,
        "hs_b": 0.85,
        "hs_b_rng": 2.0,
        "hs_c": 0.0,
        "hs_m": 0.25,
        "hs_y": 0.66,
        "hs_y_rng": 0.66,
    },
]

## The DCTL's fourteen tonescale presets, as the difference from Standard, each
## cutting across whatever look preset is in force. Nought is its
## "USE LOOK PRESET" and writes nothing.
const TONESCALE_DIFFERENCES := [
    {},
    {
        "tn_con": 1.4,
        "tn_sh": 0.5,
        "tn_toe": 0.003,
        "tn_off": 0.005,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": false,
        "tn_lcon": 0.0,
        "tn_lcon_w": 0.5
    },
    {
        "tn_con": 1.66,
        "tn_sh": 0.5,
        "tn_toe": 0.003,
        "tn_off": 0.005,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": false,
        "tn_lcon": 0.0,
        "tn_lcon_w": 0.5
    },
    {
        "tn_con": 1.4,
        "tn_sh": 0.5,
        "tn_toe": 0.003,
        "tn_off": 0.005,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.0,
        "tn_lcon_w": 0.5
    },
    {
        "tn_con": 1.05,
        "tn_sh": 0.5,
        "tn_toe": 0.1,
        "tn_off": 0.01,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.5,
        "tn_lcon_w": 0.2
    },
    {
        "tn_con": 1.6,
        "tn_sh": 0.5,
        "tn_toe": 0.01,
        "tn_off": 0.01,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": true,
        "tn_lcon": 0.25,
        "tn_lcon_w": 0.75
    },
    {
        "tn_con": 1.5,
        "tn_sh": 0.5,
        "tn_toe": 0.003,
        "tn_off": 0.003,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": true,
        "tn_lcon": 0.4,
        "tn_lcon_w": 0.5
    },
    {
        "tn_con": 1.15,
        "tn_sh": 0.5,
        "tn_toe": 0.04,
        "tn_off": 0.006,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 0.0,
        "tn_hcon_st": 0.5,
        "tn_lcon_enable": true,
        "tn_lcon": 0.5,
        "tn_lcon_w": 2.0
    },
    {
        "tn_con": 1.6,
        "tn_sh": 0.5,
        "tn_toe": 0.01,
        "tn_off": 0.008,
        "tn_hcon_enable": true,
        "tn_hcon": 0.25,
        "tn_hcon_pv": 0.0,
        "tn_hcon_st": 1.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.0,
        "tn_lcon_w": 0.75
    },
    {
        "tn_con": 1.8,
        "tn_sh": 0.5,
        "tn_toe": 0.001,
        "tn_off": 0.015,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.0,
        "tn_lcon_w": 1.0
    },
    {
        "tn_con": 1.0,
        "tn_sh": 0.35,
        "tn_toe": 0.02,
        "tn_off": 0.0,
        "tn_hcon_enable": true,
        "tn_hcon": 0.55,
        "tn_hcon_pv": 0.0,
        "tn_hcon_st": 2.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.13,
        "tn_lcon_w": 1.0
    },
    {
        "tn_con": 1.15,
        "tn_sh": 0.5,
        "tn_toe": 0.04,
        "tn_off": 0.0,
        "tn_hcon_enable": false,
        "tn_hcon": 1.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 1.0,
        "tn_lcon_enable": false,
        "tn_lcon": 1.0,
        "tn_lcon_w": 0.6
    },
    {
        "tn_con": 1.5,
        "tn_sh": 0.5,
        "tn_toe": 0.003,
        "tn_off": 0.01,
        "tn_hcon_enable": true,
        "tn_hcon": 0.25,
        "tn_hcon_pv": 0.0,
        "tn_hcon_st": 4.0,
        "tn_lcon_enable": true,
        "tn_lcon": 1.0,
        "tn_lcon_w": 1.0
    },
    {
        "tn_con": 1.2,
        "tn_sh": 0.5,
        "tn_toe": 0.02,
        "tn_off": 0.0,
        "tn_hcon_enable": false,
        "tn_hcon": 0.0,
        "tn_hcon_pv": 1.0,
        "tn_hcon_st": 1.0,
        "tn_lcon_enable": false,
        "tn_lcon": 0.0,
        "tn_lcon_w": 0.6
    },
]


## Every row of the table by key, which is also the store's declaration order.
static func rows_by_key() -> Dictionary[StringName, Dictionary]:
    var out: Dictionary[StringName, Dictionary] = {}
    for group: Dictionary in GROUPS:
        for row: Dictionary in group["rows"]:
            out[row["k"]] = row
    return out


## What Standard holds every parameter at: the table's own defaults.
static func defaults() -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {}
    var table := rows_by_key()
    for key: StringName in table:
        out[String(key)] = (table[key] as Dictionary)["d"]
    return out


## The values *index*'s look preset writes, the whole set rather than the
## difference, so a painter who moves a slider and then picks a preset gets the
## preset's own number back for every row the preset names.
##
## The parameter block's own rows and no others: the Oklab check is this port's
## and not the DCTL's, so a preset must not move it, or the same preset would
## hand two painters different numbers depending on a switch it never touches.
static func look_values(index: int) -> Dictionary[String, Variant]:
    var out := defaults()
    for name: String in out.keys():
        if not ORDER.has(StringName(name)):
            out.erase(name)
    if index <= 0 or index >= LOOK_DIFFERENCES.size():
        return out
    for name: String in LOOK_DIFFERENCES[index]:
        out[name] = LOOK_DIFFERENCES[index][name]
    return out


## The values *index*'s tonescale preset writes, and nothing at all for its
## first entry, which is the DCTL's own "USE LOOK PRESET".
static func tonescale_values(index: int) -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {}
    if index <= 0 or index >= TONESCALE_DIFFERENCES.size():
        return out
    for name: String in TONESCALE_DIFFERENCES[index]:
        out[name] = TONESCALE_DIFFERENCES[index][name]
    return out


## The parameter block `opendrt.gmacs` reads, from *values* by the row's key:
## SETTINGS_FLOATS floats in `ORDER`, each a toggle as nought or one and a
## choice as its index, and a key the record does not name at Standard's own.
static func pack(values: Dictionary) -> PackedFloat32Array:
    var held := defaults()
    for name: String in held:
        if values.has(name):
            held[name] = values[name]
        elif values.has(StringName(name)):
            held[name] = values[StringName(name)]
    var out := PackedFloat32Array()
    for key: StringName in ORDER:
        var value: Variant = held[String(key)]
        if value is bool:
            out.append(1.0 if value else 0.0)
        else:
            out.append(float(value))
    return out


## Whether every slot `ORDER` names is a row, and the block is as long as the
## kernel reads. Asked by the filter's suite, which is where a row renamed
## without a slot would otherwise be found by a wrong picture.
static func is_complete() -> bool:
    var table := rows_by_key()
    if ORDER.size() != SETTINGS_FLOATS:
        return false
    for key: StringName in ORDER:
        if not table.has(key):
            return false
    return true


## The OpenDRT rows on *ui*, bound to *store*: the two preset rows, then every
## group the table names, in its own order. Answers the rows by key, so the
## filter can hang a rule or a sentence on one.
##
## A section per group and a row of the section's own kinds rather than
## `ui.slider(...)`, because the six widget names all land on one unnamed group
## and the note asks for the DCTL's five groups with their headings. A row made
## this way is named and bound here rather than by `SaDialog._bind_rows`, which
## binds only the rows the six names made. The three kinds are read inline
## rather than in a helper of their own: a section is a `SaPageSection`, an
## inner file of `ui/page`, and a module may name only that package's door.
static func declare_rows(ui: SaDialog, store: SaFilter.Store) -> Dictionary[StringName, SaPageRow]:
    var rows: Dictionary[StringName, SaPageRow] = {}
    var under_of: Dictionary[StringName, StringName] = {}
    var presets := ui.section("Preset")
    var preset_rows := [
        {"key": &"look_preset", "label": "Look Preset", "choices": LOOKS},
        {"key": &"tonescale_preset", "label": "Tonescale Preset", "choices": TONESCALES},
    ]
    for spec: Dictionary in preset_rows:
        var key: StringName = spec["key"]
        var choices: Array = spec["choices"]
        store.declare_choice(key, 0, _ids(choices))
        var picked := presets.choice(String(spec["label"]), choices)
        picked.value = 0
        rows[key] = bound(picked, store, key)
    for group: Dictionary in GROUPS:
        var block := ui.section(String(group["title"]))
        for spec: Dictionary in group["rows"]:
            var key: StringName = spec["k"]
            var row: SaPageRow
            var kind := String(spec.get("kind", "slider"))
            if kind == "check":
                store.declare_value(key, bool(spec["d"]))
                row = bound(block.toggle(String(spec["l"])), store, key)
            elif kind == "choice":
                store.declare_choice(key, int(spec["d"]), _ids(spec["choices"]))
                var picked := block.choice(String(spec["l"]), spec["choices"])
                picked.value = int(spec["d"])
                row = bound(picked, store, key)
            else:
                store.declare_number(key, float(spec["d"]), float(spec["lo"]), float(spec["hi"]))
                row = bound(
                    block.slider(String(spec["l"]), float(spec["lo"]), float(spec["hi"])).step(float(spec["st"])), store, key
                )
            rows[row.key] = row
            if spec.has("under"):
                under_of[row.key] = spec["under"]
    for key: StringName in under_of:
        var deciding: SaPageRow = rows.get(under_of[key])
        if deciding != null:
            deciding.hides(rows[key], true)
    return rows


## *row* named *key* and bound to *store*, which is the whole of what a row of
## this set is. Public because the filter binds its own Method and Paper rows
## the same way.
static func bound(row: SaPageRow, store: SaFilter.Store, key: StringName) -> SaPageRow:
    row.named(key)
    row.target = store
    row.property = NodePath(String(key))
    row.value = store.read(key)
    return row


## The ids a bare label list makes: each entry its own index.
static func _ids(choices: Array) -> Array:
    var out: Array = []
    for index in choices.size():
        out.append(index)
    return out
