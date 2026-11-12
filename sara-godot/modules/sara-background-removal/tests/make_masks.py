"""The reference inputs and masks of the masks suite, made with U-2-Net's own code.

SPDX-License-Identifier: GPL-3.0-or-later

Why it is here: it is no test but the recipe of the reference files the suites
read, kept so they can be made again. The gate never runs it, it needs PyTorch.

    python make_masks.py <U-2-Net checkout> <u2netp.pth> <photographs>

<U-2-Net checkout> is `xuebinqin/U-2-Net` at `ac7e1c817`, and <photographs> the
folder of the `fetch.py` script, `p1.jpg` to `p5.jpg` from Wikimedia Commons.
Needs PyTorch, scikit-image and Pillow.

Each photograph goes through the reference test's own preparation,
`RescaleT(320)` and then `ToTensorLab(flag=0)` from `data_loader.py`, with one
step between them: the rescaled picture is rounded to 8 bits a channel, the
form it is kept in, and `ToTensorLab` runs on that rounded picture. The
network then runs on its tensor, on the CPU in float32, so the tensor the suite
makes of the kept picture is the very input the reference saw. The mask kept
is the first output, the sigmoid of the fused `d0`, as the network gives it and
with no `normPRED`. A sixth picture, a flat grey of 128 at 1,600 by 1,067, is
the photograph with no subject.

Each picture is one file beside this one, `reference_<name>.bin`, gzip of the
rescaled picture's 3 × 320 × 320 bytes, channel after channel and row after
row, and then the mask's 320 × 320 values as 16 bit integers, little-endian,
the mask times 65,535 and rounded, so a kept value is within 7.7e-6 of the
network's. Both together are about a third of the floats they stand for.
`reference_masks.json` holds what the masks measure: each one's share of
texels between 0.05 and 0.95, its smallest and largest value, and the share of
the `normPRED` mask resized to the photograph, the number tabled.
"""

import gzip
import json
import os
import sys
import types

import numpy as np
import torch
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 320
GREY = (1067, 1600, 128)


def reference_transforms():
    """`RescaleT` and `ToTensorLab` of the reference's `data_loader.py`, which
    imports torchvision and matplotlib at its top though neither transform
    uses them, so a module stands in for each that is missing."""
    for missing in ("torchvision", "matplotlib", "matplotlib.pyplot"):
        try:
            __import__(missing)
        except ImportError:
            stand_in = types.ModuleType(missing)
            stand_in.transforms = stand_in.utils = stand_in.pyplot = stand_in
            sys.modules[missing] = stand_in
    from data_loader import RescaleT, ToTensorLab

    return RescaleT, ToTensorLab


def sample(picture):
    label = np.zeros(picture.shape[0:2] + (1,))
    return {"imidx": np.array([0]), "image": picture, "label": label}


def rescaled(picture):
    """The picture through `RescaleT(320)`, floats from 0 to 1."""
    return reference_transforms()[0](SIZE)(sample(picture))["image"]


def prepared(picture):
    """The tensor `ToTensorLab(flag=0)` makes of a rescaled picture, its
    scaling by the picture's largest value and the ImageNet mean and deviation,
    in float64 as the reference leaves it."""
    return reference_transforms()[1](flag=0)(sample(picture))["image"].numpy()


def soft_share(mask):
    return float(((mask > 0.05) & (mask < 0.95)).mean())


def main(reference, weights, photographs):
    sys.path.insert(0, reference)
    from model import U2NETP
    from skimage import io

    torch.set_num_threads(4)
    network = U2NETP(3, 1)
    network.load_state_dict(torch.load(weights, map_location="cpu", weights_only=True))
    network.eval()
    pictures = [("p%d" % n, os.path.join(photographs, "p%d.jpg" % n)) for n in range(1, 6)]
    pictures.append(("grey", None))
    table = {"torch": torch.__version__, "size": SIZE, "pictures": {}}
    for name, path in pictures:
        if path is None:
            picture = np.full(GREY[0:2] + (3,), GREY[2], dtype=np.uint8)
        else:
            picture = io.imread(path)
        resized = np.round(rescaled(picture) * 255.0).astype(np.uint8)
        tensor = prepared(resized / 255.0)
        with torch.no_grad():
            mask = network(torch.from_numpy(tensor).float().unsqueeze(0))[0][0, 0].numpy()
        kept = np.round(mask.astype(np.float64) * 65535.0).astype("<u2")
        with open(os.path.join(HERE, "reference_%s.bin" % name), "wb") as out:
            out.write(gzip.compress(resized.transpose((2, 0, 1)).tobytes() + kept.tobytes(), 9, mtime=0))
        stretched = (mask - mask.min()) / (mask.max() - mask.min())
        big = np.asarray(
            Image.fromarray((stretched * 255).astype(np.uint8)).resize(
                (picture.shape[1], picture.shape[0]), Image.BILINEAR
            )
        ) / 255.0
        table["pictures"][name] = {
            "soft": soft_share(mask),
            "lowest": float(mask.min()),
            "highest": float(mask.max()),
            "soft_stretched_full_size": soft_share(big),
        }
        print(name, table["pictures"][name])
    with open(os.path.join(HERE, "reference_masks.json"), "w", encoding="utf-8") as out:
        json.dump(table, out, indent=1)
        out.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
