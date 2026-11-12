"""The fixtures of the fold's suite, made with PyTorch, and the fold they must give.

SPDX-License-Identifier: GPL-3.0-or-later

Why it is here: it is no test but the recipe of the reference files the suites
read, kept so they can be made again. The gate never runs it, it needs PyTorch.

Run from anywhere with a Python that has torch and numpy:

    python make_fixtures.py

It writes, beside itself:

- `fixture_legacy.pth`, one 3 by 3 convolution and the batch norm after it,
  saved in the legacy format of PyTorch before 1.6, the format of
  `u2netp.pth`, with running statistics that are not the defaults so the fold
  has something to move,
- `fixture_fold.json`, that convolution's weights and bias folded here, in
  float64 and rounded to float32 once, which the suite reads Sara's buffer
  against,
- `fixture_zip.pth`, the same state dictionary in the zip format PyTorch has
  saved since 1.6, which the reader refuses,
- `fixture_global.pth`, the legacy format with a pickle that names
  `posix system`, which the reader refuses before it runs a single opcode.

The names follow U-2-Net's `REBNCONV`, `conv_s1` and then `bn_s1`.
"""

import collections
import json
import os

import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
# The epsilon U-2-Net's norms have, PyTorch's default, since `model/u2net.py`
# builds `nn.BatchNorm2d(out_ch)` with no epsilon of its own.
EPSILON = 1e-5


class Command:
    """An object whose pickle names `os.system`, so loading it would run a
    command. Only a reader that runs what it reads does."""

    def __reduce__(self):
        return (os.system, ("echo the fixture's command ran",))


def main():
    torch.manual_seed(399)
    conv = torch.nn.Conv2d(3, 4, 3, padding=1)
    norm = torch.nn.BatchNorm2d(4)
    with torch.no_grad():
        norm.weight.copy_(torch.tensor([1.5, -0.75, 0.25, 2.0]))
        norm.bias.copy_(torch.tensor([0.1, -0.2, 0.3, -0.4]))
        norm.running_mean.copy_(torch.tensor([0.05, -0.5, 1.25, 0.0]))
        norm.running_var.copy_(torch.tensor([0.5, 2.0, 0.01, 1.0]))
    state = collections.OrderedDict()
    for name, value in conv.state_dict().items():
        state["stage1.rebnconvin.conv_s1." + name] = value
    for name, value in norm.state_dict().items():
        state["stage1.rebnconvin.bn_s1." + name] = value
    torch.save(state, os.path.join(HERE, "fixture_legacy.pth"), _use_new_zipfile_serialization=False)
    torch.save(state, os.path.join(HERE, "fixture_zip.pth"))
    bad = collections.OrderedDict(state)
    bad["stage1.rebnconvin.bn_s1.extra"] = Command()
    torch.save(bad, os.path.join(HERE, "fixture_global.pth"), _use_new_zipfile_serialization=False)

    w = conv.weight.detach().double().numpy()
    b = conv.bias.detach().double().numpy()
    scale = norm.weight.detach().double().numpy() / np.sqrt(norm.running_var.double().numpy() + EPSILON)
    folded_w = (w * scale[:, None, None, None]).astype(np.float32)
    folded_b = ((b - norm.running_mean.double().numpy()) * scale + norm.bias.detach().double().numpy()).astype(np.float32)
    fold = {
        "name": "stage1.rebnconvin.conv_s1",
        "shape": list(folded_w.shape),
        "epsilon": EPSILON,
        "weight": [float(x) for x in folded_w.reshape(-1)],
        "bias": [float(x) for x in folded_b],
    }
    with open(os.path.join(HERE, "fixture_fold.json"), "w", encoding="utf-8") as out:
        json.dump(fold, out, indent=1)
        out.write("\n")


if __name__ == "__main__":
    main()
