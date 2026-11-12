"""The table of the fold's suite: every convolution of U²-NetP folded by PyTorch.

SPDX-License-Identifier: GPL-3.0-or-later

Why it is here: it is no test but the recipe of the reference files the suites
read, kept so they can be made again. The gate never runs it, it needs PyTorch.

    python make_reference.py <u2netp.pth>

Loads the authors' weights with `torch.load`, the trusted way since the file's
hash is the one the module checks, and folds each batch norm into the
convolution before it in the state dictionary with PyTorch's own
`torch.nn.utils.fusion.fuse_conv_bn_weights`, at the epsilon U-2-Net's
`nn.BatchNorm2d(out_ch)` has, PyTorch's default of 1e-5. For each of the 119
convolutions, in the dictionary's order, it writes the shape, and the sum, the
first and the last value of the folded weights and of the folded bias, the sums
taken in float64 over the float32 values, to `u2netp_folded.json` beside
itself. The suite holds Sara's buffer to that table.
"""

import json
import os
import sys

import torch
from torch.nn.utils.fusion import fuse_conv_bn_weights

HERE = os.path.dirname(os.path.abspath(__file__))
EPSILON = 1e-5


def summary(tensor):
    flat = tensor.detach().reshape(-1)
    return {"sum": float(flat.double().sum()), "first": float(flat[0]), "last": float(flat[-1])}


def main(path):
    state = torch.load(path, map_location="cpu", weights_only=True)
    names = list(state.keys())
    rows = []
    i = 0
    while i < len(names):
        name = names[i]
        if not (name.endswith(".weight") and state[name].dim() == 4):
            i += 1
            continue
        prefix = name[: -len(".weight")]
        weight = state[name]
        bias = state[prefix + ".bias"]
        following = names[i + 2] if i + 2 < len(names) else ""
        if following.endswith(".weight") and following[: -len(".weight")] + ".running_var" in state:
            norm = following[: -len(".weight")]
            weight, bias = fuse_conv_bn_weights(
                weight,
                bias,
                state[norm + ".running_mean"],
                state[norm + ".running_var"],
                EPSILON,
                state[norm + ".weight"],
                state[norm + ".bias"],
            )
        rows.append({"name": prefix, "shape": list(weight.shape), "weight": summary(weight), "bias": summary(bias)})
        i += 2
    with open(os.path.join(HERE, "u2netp_folded.json"), "w", encoding="utf-8") as out:
        json.dump({"torch": torch.__version__, "epsilon": EPSILON, "convolutions": rows}, out, indent=1)
        out.write("\n")
    print(len(rows), "convolutions,", sum(1 for n in names if n.endswith(".running_var")), "norms")


if __name__ == "__main__":
    main(sys.argv[1])
