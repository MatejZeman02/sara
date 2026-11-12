#!/usr/bin/env python3
"""Where the hue ring's chroma comes from.

The ring in ``shaders/ui/okhsv_picker.gdshader`` draws one chroma at every hue
along a lightness profile that peaks at yellow and dips at the hue opposite,
and at every hue the most chroma the sRGB gamut holds at that lightness. This
walks the profile in whole degrees and prints that chroma every thirty
degrees with its floor and its ceiling, the numbers the suite and the shader's
comment quote. Change the profile's three numbers in the shader, its twin in
``utils/okhsv_conversions.gd`` and here together, and rerun. The floor is also
what one chroma for every hue would have to be, the circle from above, which
is pastel at every hue.
"""
import math

BASE_L = 0.65
LIFT_AT_YELLOW = 0.20
DIP_OPPOSITE = 0.07


def oklab_to_linear(lightness: float, a: float, b: float) -> tuple[float, float, float]:
    l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    s_ = lightness - 0.0894841775 * a - 1.291485548 * b
    l, m, s = l_**3, m_**3, s_**3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    )


def linear_to_oklab(r: float, g: float, b: float) -> tuple[float, float, float]:
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


YELLOW_HUE = math.atan2(*reversed(linear_to_oklab(1.0, 1.0, 0.0)[1:]))


def ring_lightness(hue: float) -> float:
    c = math.cos(hue - YELLOW_HUE)
    towards, away = (1.0 + c) / 2.0, (1.0 - c) / 2.0
    return BASE_L + LIFT_AT_YELLOW * towards * towards - DIP_OPPOSITE * away * away


def in_gamut(lightness: float, chroma: float, hue: float) -> bool:
    return all(-1e-6 <= x <= 1.0 + 1e-6 for x in oklab_to_linear(lightness, chroma * math.cos(hue), chroma * math.sin(hue)))


def max_chroma(lightness: float, hue: float) -> float:
    low, high = 0.0, 0.5
    for _ in range(40):
        mid = (low + high) / 2.0
        low, high = (mid, high) if in_gamut(lightness, mid, hue) else (low, mid)
    return low


def main() -> None:
    print("yellow's hue %.4f of the turn, lit to L %.3f, the opposite dipped to L %.3f" % (
        (YELLOW_HUE / math.tau) % 1.0, ring_lightness(YELLOW_HUE), ring_lightness(YELLOW_HUE + math.pi)))
    held = [(max_chroma(ring_lightness(math.radians(d)), math.radians(d)), d) for d in range(360)]
    print("chroma every thirty degrees: " + " ".join("%d:%.3f" % (d, c) for c, d in held[::30]))
    print("floor %.4f at hue %d degrees, ceiling %.4f at hue %d degrees" % (min(held) + max(held)))


if __name__ == "__main__":
    main()
