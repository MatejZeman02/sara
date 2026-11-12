## The OpenDRT DCTL's own formula, written out again in GDScript so the
## Tonemap's suite can read the kernel's numbers against something that is not
## the kernel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A transcription of `transform` in Jed Smith's `OpenDRT.dctl` v1.1.0, section
## by section and in its own order, with its five fixed settings written in
## rather than read from a combo box: Rec.709 primaries with a linear transfer
## in, the sRGB Display encoding, its bright surround, and its clamp on. The
## DCTL's last step is that display's 2.2 power and this does not take it,
## because `opendrt.gmacs` does not and a document stores linear light, so what
## it answers is the display-referred light OpenDRT forms.
##
## **Oklab's hue is not here.** This is the DCTL's own arithmetic and the DCTL
## has no such switch: it reads its hue angle from its own opponent space. The
## suite reads the kernel against this with `oklab_hue` off, which is the branch
## the kernel's header says computes the DCTL's numbers.
##
## The one row the kernel carries that the DCTL's transform does not is Contrast
## Low Per Channel, off at every preset and every default, so the DCTL's own
## branch is the only one written here.
##
## The parameters arrive by the DCTL's own names, the ones the row table keeps.
extends RefCounted

const Params = preload("res://modules/sara-base-modules/base/usual/opendrt_parameters.gd")

const SQRT3 := 1.7320508075688772935
const PI := 3.14159265358979
## The DCTL's own rotation of its hue angle, so that red reads nought.
const HUE_RED_ROTATION := 1.10714931
## The sRGB Display preset's surround, which its `ts_p` divides by.
const SURROUND := 2.0
## The DCTL's window widths, in radians squared, the Gaussian's variance.
const HUE_WIDTH_RGB := 0.66
const HUE_WIDTH_CMY := 0.5


## The DCTL's rendering space: Rec.709 in and P3-D65 to render in, the two
## matrices of `_rec709_to_xyz` and `_xyz_to_p3d65` in the order its `transform`
## takes them, and the way back.
##
## The Tonemap's suite hands the kernel a colour in this space's own hue, since
## the six Brilliance windows read the hue of the ratio and the ratio is this
## space's, so the peaks of a hue sweep land where the windows are centred
## rather than a matrix away from it.
static func render_space_from_rec709(v: Vector3) -> Vector3:
    return _xyz_to_p3d65() * (_rec709_to_xyz() * v)


static func rec709_from_render_space(v: Vector3) -> Vector3:
    return _xyz_to_rec709() * (_p3d65_to_xyz() * v)


## The display-referred Rec.709 light the DCTL's `transform` answers to *rgb*,
## scene-linear Rec.709 light, with the DCTL's inverse display EOTF left off.
static func display_light(rgb: Vector3, values: Dictionary) -> Vector3:
    var held := Params.defaults()
    for name: String in held:
        if values.has(name):
            held[name] = values[name]
    var tn_lp := _f(held, "tn_lp")
    var tn_gb := _f(held, "tn_gb")
    var pt_hdr := _f(held, "pt_hdr")
    var tn_lg := _f(held, "tn_lg")
    var tn_con := _f(held, "tn_con")
    var tn_sh := _f(held, "tn_sh")
    var tn_toe := _f(held, "tn_toe")
    var tn_off := _f(held, "tn_off")
    var tn_hcon := _f(held, "tn_hcon")
    var tn_hcon_pv := _f(held, "tn_hcon_pv")
    var tn_hcon_st := _f(held, "tn_hcon_st")
    var tn_lcon := _f(held, "tn_lcon")
    var tn_lcon_w := _f(held, "tn_lcon_w")
    var cwp := int(_f(held, "cwp"))
    var cwp_lm := _f(held, "cwp_lm")
    var rs_sa := _f(held, "rs_sa")
    var rs_rw := _f(held, "rs_rw")
    var rs_bw := _f(held, "rs_bw")
    var pt_lml := _f(held, "pt_lml")
    var pt_lml_r := _f(held, "pt_lml_r")
    var pt_lml_g := _f(held, "pt_lml_g")
    var pt_lml_b := _f(held, "pt_lml_b")
    var pt_lmh := _f(held, "pt_lmh")
    var pt_lmh_r := _f(held, "pt_lmh_r")
    var pt_lmh_b := _f(held, "pt_lmh_b")
    var ptl_c := _f(held, "ptl_c")
    var ptl_m := _f(held, "ptl_m")
    var ptl_y := _f(held, "ptl_y")
    var ptm_low := _f(held, "ptm_low")
    var ptm_low_rng := _f(held, "ptm_low_rng")
    var ptm_low_st := _f(held, "ptm_low_st")
    var ptm_high := _f(held, "ptm_high")
    var ptm_high_rng := _f(held, "ptm_high_rng")
    var ptm_high_st := _f(held, "ptm_high_st")
    var brl := _f(held, "brl")
    var brl_r := _f(held, "brl_r")
    var brl_g := _f(held, "brl_g")
    var brl_b := _f(held, "brl_b")
    var brl_rng := _f(held, "brl_rng")
    var brl_st := _f(held, "brl_st")
    var brlp := _f(held, "brlp")
    var brlp_r := _f(held, "brlp_r")
    var brlp_g := _f(held, "brlp_g")
    var brlp_b := _f(held, "brlp_b")
    var hc_r := _f(held, "hc_r")
    var hc_r_rng := _f(held, "hc_r_rng")
    var hs_r := _f(held, "hs_r")
    var hs_r_rng := _f(held, "hs_r_rng")
    var hs_g := _f(held, "hs_g")
    var hs_g_rng := _f(held, "hs_g_rng")
    var hs_b := _f(held, "hs_b")
    var hs_b_rng := _f(held, "hs_b_rng")
    var hs_c := _f(held, "hs_c")
    var hs_c_rng := _f(held, "hs_c_rng")
    var hs_m := _f(held, "hs_m")
    var hs_m_rng := _f(held, "hs_m_rng")
    var hs_y := _f(held, "hs_y")
    var hs_y_rng := _f(held, "hs_y_rng")

    # Tonescale constraint calculations, which the DCTL says should be
    # pre-calculated and cannot be.
    var ts_x1 := pow(2.0, 6.0 * tn_sh + 4.0)
    var ts_y1 := tn_lp / 100.0
    var ts_x0 := 0.18 + tn_off
    var ts_y0 := tn_lg / 100.0 * (1.0 + tn_gb * log(ts_y1) / log(2.0))
    var ts_s0 := _toe_quadratic(ts_y0, tn_toe, 1)
    # The sRGB Display preset's own surround compensation.
    var ts_p := tn_con / (1.0 + SURROUND * 0.05)
    var ts_s10 := ts_x0 * (pow(ts_s0, -1.0 / tn_con) - 1.0)
    var ts_m1 := ts_y1 / pow(ts_x1 / (ts_x1 + ts_s10), tn_con)
    var ts_m2 := _toe_quadratic(ts_m1, tn_toe, 1)
    var ts_s := ts_x0 * (pow(ts_s0 / ts_m2, -1.0 / tn_con) - 1.0)
    var ts_dsc := 100.0 / tn_lp
    var pt_cmp_lf := pt_hdr * minf(1.0, (tn_lp - 100.0) / 900.0)
    var s_lp100 := ts_x0 * (pow(tn_lg / 100.0, -1.0 / tn_con) - 1.0)
    var ts_s1 := ts_s * pt_cmp_lf + s_lp100 * (1.0 - pt_cmp_lf)

    # A Rec.709 document's linear light is the DCTL's in_gamut 5 and in_oetf 0,
    # and its display gamut is the sRGB Display preset's Rec.709.
    var out := _xyz_to_p3d65() * (_rec709_to_xyz() * rgb)

    # Rendering space: desaturate to control the scale of the colour volume.
    var rs_w := Vector3(rs_rw, 1.0 - rs_rw - rs_bw, rs_bw)
    out = Vector3.ONE * (out.dot(rs_w) * rs_sa) + out * (1.0 - rs_sa)
    out += Vector3(tn_off, tn_off, tn_off)

    var tsn := _hypot3(out) / SQRT3
    out = _safe_div3(out, tsn)

    var opp := _opponent(out)
    var ach_d := _hypot2(opp) / 2.0
    ach_d = 1.25 * _toe_quadratic(ach_d, 0.25, 0)
    # Hue angle, rotated so that red reads nought.
    var hue := fmod(atan2(opp.x, opp.y) + PI + HUE_RED_ROTATION, 2.0 * PI)
    var ha_rgb := _rgb_windows(hue, false)
    var ha_rgb_hs := _rgb_windows(hue, true)
    var ha_cmy := _cmy_windows(hue)

    # Brilliance, the DCTL's sum of three windows.
    if _on(held, "brl_enable"):
        var brl_tsf := pow(tsn / (tsn + 1.0), 1.0 - brl_rng)
        var brl_exf := (brl + brl_r * ha_rgb.x + brl_g * ha_rgb.y + brl_b * ha_rgb.z) * pow(ach_d, 1.0 / brl_st)
        tsn *= pow(2.0, brl_exf * (brl_tsf if brl_exf < 0.0 else 1.0 - brl_tsf))

    # Contrast Low, the DCTL's branch.
    if _on(held, "tn_lcon_enable"):
        var lcon_m := pow(2.0, -tn_lcon)
        var lcon_w := tn_lcon_w / 4.0
        lcon_w *= lcon_w
        tsn *= _toe_cubic(ts_x0, lcon_m, lcon_w, 1) / ts_x0
        tsn = _toe_cubic(tsn, lcon_m, lcon_w, 0)

    # Contrast High.
    if _on(held, "tn_hcon_enable"):
        tsn = _contrast_high(tsn, pow(2.0, tn_hcon), tn_hcon_pv, tn_hcon_st, 0)

    # Hyperbolic compression, whose three results the rest of the transform
    # reads.
    var tsn_pt := _hyperbolic(tsn, ts_s1, ts_p)
    var tsn_const := _hyperbolic(tsn, s_lp100, ts_p)
    tsn = _hyperbolic(tsn, ts_s, ts_p)

    # Hue Contrast R.
    if _on(held, "hc_enable"):
        var hc_ts := 1.0 - tsn_const
        var hc_c := hc_ts * (1.0 - ach_d) + ach_d * (1.0 - hc_ts)
        hc_c *= ach_d * ha_rgb.x
        hc_ts = pow(hc_ts, 1.0 / hc_r_rng)
        var hc_f := hc_r * (hc_c - 2.0 * hc_c * hc_ts) + 1.0
        out = Vector3(out.x, out.y * hc_f, out.z * hc_f)

    # Hue Shift, RGB by the purity compress tonescale and CMY by its
    # complement.
    if _on(held, "hs_rgb_enable"):
        var hs_rgb := Vector3(
            ha_rgb_hs.x * ach_d * pow(tsn_pt, 1.0 / hs_r_rng),
            ha_rgb_hs.y * ach_d * pow(tsn_pt, 1.0 / hs_g_rng),
            ha_rgb_hs.z * ach_d * pow(tsn_pt, 1.0 / hs_b_rng)
        )
        var hsf := Vector3(hs_rgb.x * hs_r, hs_rgb.y * -hs_g, hs_rgb.z * -hs_b)
        out += Vector3(hsf.z - hsf.y, hsf.x - hsf.z, hsf.y - hsf.x)
    if _on(held, "hs_cmy_enable"):
        var tsn_compl := 1.0 - tsn_pt
        var hs_cmy := Vector3(
            ha_cmy.x * ach_d * pow(tsn_compl, 1.0 / hs_c_rng),
            ha_cmy.y * ach_d * pow(tsn_compl, 1.0 / hs_m_rng),
            ha_cmy.z * ach_d * pow(tsn_compl, 1.0 / hs_y_rng)
        )
        var hsf_cmy := Vector3(hs_cmy.x * -hs_c, hs_cmy.y * hs_m, hs_cmy.z * hs_y)
        out += Vector3(hsf_cmy.z - hsf_cmy.y, hsf_cmy.x - hsf_cmy.z, hsf_cmy.y - hsf_cmy.x)

    # Purity Limit, low and high. The DCTL's transform never reads the switch,
    # so neither does this, and the kernel's off branch is its own addition.
    var pt_lml_p := (
        1.0 + 4.0 * (1.0 - tsn_pt) * (pt_lml + pt_lml_r * ha_rgb_hs.x + pt_lml_g * ha_rgb_hs.y + pt_lml_b * ha_rgb_hs.z)
    )
    var ptf := 1.0 - pow(tsn_pt, pt_lml_p)
    var pt_lmh_p := (1.0 - ach_d * (pt_lmh_r * ha_rgb_hs.x + pt_lmh_b * ha_rgb_hs.z)) * (1.0 - pt_lmh * ach_d)
    ptf = pow(ptf, pt_lmh_p)

    # Mid-Range Purity.
    if _on(held, "ptm_enable"):
        var ptm_low_f := 1.0
        if ptm_low_st != 0.0 and ptm_low_rng != 0.0:
            ptm_low_f = (1.0 + ptm_low * exp(-2.0 * ach_d * ach_d / ptm_low_st) * pow(1.0 - tsn_const, 1.0 / ptm_low_rng))
        var ptm_high_f := 1.0
        if ptm_high_st != 0.0 and ptm_high_rng != 0.0:
            ptm_high_f = (1.0 + ptm_high * exp(-2.0 * ach_d * ach_d / ptm_high_st) * pow(tsn_pt, 1.0 / (4.0 * ptm_high_rng)))
        ptf *= ptm_low_f * ptm_high_f

    # The ratios lerp to the peak achromatic by ptf, and back out of the
    # rendering space.
    out = out * ptf + Vector3.ONE * (1.0 - ptf)
    out = Vector3.ONE * (out.dot(rs_w) * rs_sa) - out
    out /= rs_sa - 1.0

    out = _display_gamut_whitepoint(out, tsn_const, cwp_lm, cwp)

    # Post Brilliance.
    if _on(held, "brlp_enable"):
        var brlp_ach_d := _hypot2(_opponent(out)) / 4.0
        brlp_ach_d = 1.1 * (brlp_ach_d * brlp_ach_d / (brlp_ach_d + 0.1))
        var brlp_ha := ach_d * ha_rgb
        var brlp_m := brlp + brlp_r * brlp_ha.x + brlp_g * brlp_ha.y + brlp_b * brlp_ha.z
        out *= Vector3.ONE * pow(2.0, brlp_m * brlp_ach_d * tsn)

    # Purity Compress Low.
    if _on(held, "ptl_enable"):
        out = Vector3(_softplus(out.x, ptl_c), _softplus(out.y, ptl_m), _softplus(out.z, ptl_y))

    # The tonescale's last two steps and the display scale, then the ratios are
    # multiplied back into a light.
    tsn *= ts_m2
    tsn = _toe_quadratic(tsn, tn_toe, 0)
    tsn *= ts_dsc
    # The DCTL's own clamp, which the kernel keeps in its Oklab-off branch.
    return (out * tsn).clamp(Vector3.ZERO, Vector3.ONE)


## The value of *name* as the float the DCTL's arithmetic reads, a toggle as
## nought or one.
static func _f(values: Dictionary, name: String) -> float:
    var value: Variant = values.get(name)
    if value is bool:
        return 1.0 if value else 0.0
    return float(value)


static func _on(values: Dictionary, name: String) -> bool:
    return _f(values, name) > 0.5


static func _safe_pow(a: float, p: float) -> float:
    if a <= 0.0:
        return a
    return pow(a, p)


static func _safe_div(a: float, b: float) -> float:
    if b == 0.0:
        return 0.0
    return a / b


static func _safe_div3(a: Vector3, b: float) -> Vector3:
    return Vector3(_safe_div(a.x, b), _safe_div(a.y, b), _safe_div(a.z, b))


static func _hypot2(v: Vector2) -> float:
    return sqrt(maxf(0.0, v.x * v.x + v.y * v.y))


static func _hypot3(v: Vector3) -> float:
    return sqrt(maxf(0.0, v.x * v.x + v.y * v.y + v.z * v.z))


static func _hyperbolic(x: float, s: float, p: float) -> float:
    return _safe_pow(x / (x + s), p)


static func _toe_quadratic(x: float, toe: float, inv: int) -> float:
    if toe == 0.0:
        return x
    if inv == 0:
        return _safe_pow(x, 2.0) / (x + toe)
    return (x + sqrt(x * (4.0 * toe + x))) / 2.0


static func _toe_cubic(x: float, m: float, w: float, inv: int) -> float:
    if m == 1.0:
        return x
    var x2 := x * x
    if inv == 0:
        return x * (x2 + m * w) / (x2 + w)
    var p0 := x2 - 3.0 * m * w
    var p1 := 2.0 * x2 + 27.0 * w - 9.0 * m * w
    var p2 := pow(sqrt(x2 * p1 * p1 - 4.0 * p0 * p0 * p0) / 2.0 + x * p1 / 2.0, 1.0 / 3.0)
    return p0 / (3.0 * p2) + p2 / 3.0 + x / 3.0


static func _contrast_high(x: float, p: float, pv: float, pv_lx: float, inv: int) -> float:
    var x0 := 0.18 * pow(2.0, pv)
    if x < x0 or p == 1.0:
        return x
    var o := x0 - x0 / p
    var s0 := pow(x0, 1.0 - p) / p
    var x1 := x0 * pow(2.0, pv_lx)
    var k1 := p * s0 * pow(x1, p) / x1
    var y1 := s0 * pow(x1, p) + o
    if inv == 1:
        return (x - y1) / k1 + x1 if x > y1 else pow((x - o) / s0, 1.0 / p)
    return k1 * (x - x1) + y1 if x > x1 else s0 * pow(x, p) + o


static func _softplus(x: float, s: float) -> float:
    if x > 10.0 * s or s < 1e-4:
        return x
    return s * log(maxf(0.0, 1.0 + exp(x / s)))


static func _opponent(rgb: Vector3) -> Vector2:
    return Vector2(rgb.x - rgb.z, rgb.y - (rgb.x + rgb.z) / 2.0)


static func _gauss_window(x: float, w: float) -> float:
    return exp(-x * x / w)


static func _hue_offset(h: float, o: float) -> float:
    return fmod(h - o + PI, 2.0 * PI) - PI


## The DCTL's two hue window sets, in its own opponent hue angle.
static func _rgb_windows(hue: float, shifted: bool) -> Vector3:
    if shifted:
        return Vector3(
            _gauss_window(_hue_offset(hue, -0.4), HUE_WIDTH_RGB),
            _gauss_window(_hue_offset(hue, 4.3), HUE_WIDTH_RGB),
            _gauss_window(_hue_offset(hue, 2.5), HUE_WIDTH_RGB)
        )
    return Vector3(
        _gauss_window(_hue_offset(hue, 0.1), HUE_WIDTH_RGB),
        _gauss_window(_hue_offset(hue, 4.3), HUE_WIDTH_RGB),
        _gauss_window(_hue_offset(hue, 2.3), HUE_WIDTH_RGB)
    )


static func _cmy_windows(hue: float) -> Vector3:
    return Vector3(
        _gauss_window(_hue_offset(hue, 3.3), HUE_WIDTH_CMY),
        _gauss_window(_hue_offset(hue, 1.3), HUE_WIDTH_CMY),
        _gauss_window(_hue_offset(hue, -1.15), HUE_WIDTH_CMY)
    )


## The DCTL's `display_gamut_whitepoint` at its Rec.709 row, which is the row
## the sRGB Display preset picks.
static func _display_gamut_whitepoint(rgb: Vector3, tsn: float, cwp_lm: float, cwp: int) -> Vector3:
    var neutral := _p3d65_to_xyz() * rgb
    var aligned := _cat_d65_to_creative_white(cwp) * neutral
    var mix := pow(maxf(tsn, 0.0), 2.0 * cwp_lm)
    var mixed := aligned * mix + neutral * (1.0 - mix)
    var rendered := _xyz_to_rec709() * mixed
    var norm := _rec709_white_norm(cwp)
    return rendered * (norm * mix + 1.0 - mix)


# The DCTL's own matrices, in its own column order. Only the rows the kernel
# also carries are here: Rec.709 and P3-D65 through XYZ, the five creative
# white conversions from D65, and Rec.709's normalisation factors.


static func _rec709_to_xyz() -> Basis:
    return Basis(
        Vector3(0.412390799265959229, 0.212639005871510217, 0.0193308187155918181),
        Vector3(0.357584339383878125, 0.71516867876775625, 0.119194779794626018),
        Vector3(0.180480788401834347, 0.0721923153607337414, 0.950532152249661033)
    )


static func _xyz_to_rec709() -> Basis:
    return Basis(
        Vector3(3.24096994190452348, -0.969243636280879506, 0.0556300796969936354),
        Vector3(-1.53738317757009435, 1.87596750150771996, -0.20397695888897649),
        Vector3(-0.498610760293003552, 0.0415550574071755843, 1.05697151424287816)
    )


static func _p3d65_to_xyz() -> Basis:
    return Basis(
        Vector3(0.486570948648216151, 0.228974564069748754, -4.0e-17),
        Vector3(0.265667693169093004, 0.691738521836506193, 0.0451133818589026167),
        Vector3(0.198217285234362467, 0.079286914093744984, 1.04394436890097575)
    )


static func _xyz_to_p3d65() -> Basis:
    return Basis(
        Vector3(2.49349691194142542, -0.829488969561574696, 0.0358458302437844531),
        Vector3(-0.93138361791912383, 1.76266406031834655, -0.0761723892680418041),
        Vector3(-0.402710784450716841, 0.0236246858419435941, 0.956884524007687309)
    )


static func _cat_d65_to_creative_white(cwp: int) -> Basis:
    if cwp == 0:
        return Basis(
            Vector3(0.95703423023223877, -0.0179296955466270447, 0.00127589143812656403),
            Vector3(-0.0247171502560377121, 0.990019857883453369, 0.00427919067442417058),
            Vector3(0.0624028593301773071, 0.0248119533061981201, 1.29345715045928955)
        )
    if cwp == 1:
        return Basis(
            Vector3(0.981001079082489014, -0.00843488052487373352, 0.000552809564396739006),
            Vector3(-0.0116619253531098366, 0.996506094932556152, 0.00179840810596942902),
            Vector3(0.0265614092350006104, 0.0105696544051170349, 1.12374722957611084)
        )
    if cwp == 3:
        return Basis(
            Vector3(1.01182246208190918, 0.00561682833358645439, -0.000335735734552145004),
            Vector3(0.00778879318386316299, 1.00150644779205322, -0.0010509500280022619),
            Vector3(-0.0157783031463623047, -0.00628517568111419678, 0.927366673946380615)
        )
    if cwp == 4:
        return Basis(
            Vector3(1.02585089206695557, 0.0129133854061365128, -0.000719940289855003032),
            Vector3(0.0179439820349216461, 1.00214779376983643, -0.00218106806278228803),
            Vector3(-0.0332137793302536011, -0.0132421031594276428, 0.84868013858795166)
        )
    if cwp == 5:
        return Basis(
            Vector3(1.04257404804229736, 0.0221935361623764038, -0.00116488314233720303),
            Vector3(0.03089117631316185, 1.00185668468475342, -0.00342052709311246915),
            Vector3(-0.052812620997428894, -0.0210737623274326324, 0.761789083480834961)
        )
    return Basis()


static func _rec709_white_norm(cwp: int) -> float:
    if cwp == 0:
        return 0.744192699063
    if cwp == 1:
        return 0.873470832146
    if cwp == 3:
        return 0.955936992163
    if cwp == 4:
        return 0.905671332781
    if cwp == 5:
        return 0.850004385027
    return 1.0
