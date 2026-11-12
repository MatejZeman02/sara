# The Welcome picture

The picture across the top of the Welcome window, read by `WelcomePicture`
(`ui/welcome/welcome_picture.gd`).

A picture is two files in this folder: `<major>.<minor>.png`, and
`<major>.<minor>.json` beside it with a `title` and a `credit`. The folder is
listed by its `.json` files, because a pack holds those under their own names
and a listing of the pictures is full of import sidecars. The window shows the
picture for the running version's major and minor, or the newest when there is
none, so a patch release keeps its minor's picture.

The shipped picture is 3 to 1 at twice the band's logical size at the window's
opening width, so it is sharp at an interface scale of 2 and the mipmaps of its
import keep it clean at 1. Each file needs its own `.import` with the mipmaps on.

## Lights

A picture may come in lights, the same painting at another hour and season,
which its sidecar lists under `variants`:

```json
{
    "title": "Over the ridges",
    "credit": "Painted in Sara",
    "variants": [
        {"file": "0.18-dawn.png", "hour": 6, "season": "winter"},
        {"file": "0.18-dawn-summer.png", "hour": 6, "season": "summer"},
        {"file": "0.18-day.png", "hour": 13}
    ]
}
```

A `file` is a bare name in the same folder and an `hour` the local hour the
light shows at its fullest, from 0 up to but not 24, minutes as a fraction. A
`season` is `spring`, `summer`, `autumn` or `winter`, and a light with none is
every season's. A sidecar with no list is the one picture `<major>.<minor>.png`.
A light may name a `sun` height in degrees and a `side`, `rising` or `setting`,
in place of an `hour`, and a sidecar whose every light does fades by the sun
where the painter lives. How the lights are picked and faded is in
`ui/welcome/lights/picture_lights.gd`.

## Parts

A light may come in `parts`, listed by the light's file, so its clouds drift:

```json
"parts": {
    "0.18-dusk.png": {"back": "0.18-dusk-back.png", "clouds": "0.18-dusk-clouds.png",
            "land": "0.18-dusk-land.png", "rows": [0, 212], "origin": 185, "seam": 180}
}
```

The `clouds` are a strip as wide as the light that repeats in X, over the band's
`rows`, its first column standing at the light's `origin` with no drift, so its
seam falls where the light has the fewest clouds. The `land` stands in front
over the same rows, transparent over the sky, and the `back` is the sky behind
them in those rows and the whole light above and below. An overlay an entry
names `"beneath": "clouds"` (the stars) goes between the back and the clouds.
The `seam` is how many columns at each end of the strip fade into the strip
moved by half its width, which only the suites read. At a drift of naught the
parts are the light as exported, and a light with no parts is shown as its file.

A light may carry a body, its sun or its moon:

```json
"body": {"file": "0.18-dusk-sun.png", "kind": "sun", "box": [317, 0],
         "at": [819.5, 224.5], "sets": 277.7, "over_clouds": false}
```

The file is the body cut to its `box`, whose corner stands at `box` in the
light, `at` is the middle of its disc and `sets` the row that middle goes down
to before the ridge hides the whole disc. It is laid over the back and the
overlays under the clouds, or over the strip when `over_clouds` is set, and
under the land either way. The body's picture holds the whole of a screened
sun's glow and the back the sky without it, so a body moved takes its glow
along. Its `reflection`, the ground near its place with the body's light on it,
is a picture of its own, laid over the light last, after the land, and moved
sideways as far as the body is from its painted place:

```json
"reflection": {"file": "0.18-dusk-reflection.png", "box": [644, 255]}
```

The body and its reflection are shown as much as the body stands above where it
sets, so two lights fading show one sun and one glitter and nothing is left of
a body that has set. `scripts/export_welcome_bodies.py` cuts both. The sidecar's
`overlays` are laid by chance (`ui/welcome/overlays`).

## In a debug build

The folder, hour, month, zone, locale and version come from
`SARA_WELCOME_PICTURES`, `SARA_WELCOME_HOUR`, `SARA_WELCOME_MONTH`,
`SARA_WELCOME_ZONE`, `SARA_WELCOME_LOCALE` and `SARA_WELCOME_VERSION`, and the
clouds' drift and the overlays' chance from `SARA_WELCOME_ROLL`, so a
scenario's shot is the same at any date and place.
