# Independent depth proof of concept

This is a Linux-only, standalone C++ validation. It is not included by the root
build and does not modify the Shell or the platform daemon. It downloads one
pinned model and one pinned ONNX Runtime C++ release into the ignored `.build/`
directory. Inference never uploads images. It requires CMake, a C++20 compiler,
OpenCV development libraries, OpenSSL development libraries, `curl`, and
`sha256sum`; it does not require Python.

```sh
bash experiments/depth-poc/run.sh /absolute/path/to/wallpaper.jpg
```

## Pinned artifact and provenance

| Item | Value |
| --- | --- |
| Model | Depth Anything V2 Small (ViT-S) |
| ONNX artifact | `fabio-sim/Depth-Anything-ONNX` release `v2.0.0`, `depth_anything_v2_vits_dynamic.onnx` |
| Model SHA256 | `46c4e8eeda3a27f34701831b6a2ec7753d7b38779b215acb5633424703deed8f` |
| ONNX Runtime | Official Linux x64 release `1.30.0` |
| Runtime archive SHA256 | `a5ed5a3cac51fbb2e90da632ae43d19212faaa20e76484e62bcb7c23ddb3b3fd` |
| Contract | `da2-vits-dynamic-aspect518-rgb-imagenet-cubic-uint16-v1` |

The model is from a community ONNX export that the original Depth Anything V2
project lists under ONNX support. It is a validation candidate, not yet a
project-owned release. The Small model is marked Apache-2.0 by its authors.
Preserve attribution and license information when republishing it.

## Exact input and output contract

1. Decode the image as 8-bit, three-channel BGR with OpenCV. This PoC does not
   account for EXIF orientation, ICC profiles, alpha or HDR content.
2. Convert BGR to RGB. Set scale to `max(518/source_width,
   518/source_height)`, then round each scaled dimension to the nearest
   multiple of 14 with a minimum of 518. Resize using OpenCV `INTER_CUBIC`.
   Divide by 255 and apply ImageNet channel means `[0.485, 0.456, 0.406]`
   and standard deviations `[0.229, 0.224, 0.225]`.
3. Feed float32 NCHW tensor `[1,3,H,W]` to the CPU execution provider, where
   `H` and `W` are the computed dimensions divisible by 14.
   Reject any model with another input signature. Require float32 output
   `[1,H,W]`.
4. Resize the raw depth to the decoded image size with OpenCV `INTER_CUBIC`.
   Reject non-finite and constant outputs. Linearly normalize the result to
   `[0,65535]` per image and round to unsigned 16-bit grayscale PNG. Higher
   values represent a stronger near-depth response. These are **relative**
   values, not distance units.
5. Hash the source file bytes. Cache key is SHA256(source SHA256 + model SHA256
   + contract string). Save `depth.png` and `metadata.json` under `.build/ai-depth-poc/cache/<key>/`.

The dynamic ONNX artifact preserves the source aspect ratio. The generated PNG
is a data artifact; GPU texture precision and any spatial rendering remain
separate work. This PoC creates a new ONNX session per process; a resident
service should retain the session for repeated inference.

## Validation performed

On the development machine, the CLI generated a 2048×1362 16-bit grayscale PNG
from the upstream `assets/examples/demo01.jpg` using the pinned dynamic model
and CPU runtime. It also generated original-size 16-bit PNGs from 5120×2880
landscape and 1440×2960 portrait Plasma wallpapers. A repeated call hit the
cache. A modified model file was rejected by the SHA256 check (checked with the
static export during initial validation). Results are in `.build/ai-depth-poc/`,
which is ignored by Git.
