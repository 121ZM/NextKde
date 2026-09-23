#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 IMAGE" >&2
    exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work_dir="$repo_root/.build/ai-depth-poc"
model_dir="$work_dir/model"
runtime_dir="$work_dir/runtime"
model="$model_dir/depth_anything_v2_vits_dynamic.onnx"
archive="$runtime_dir/onnxruntime-linux-x64-1.30.0.tgz"
ort_root="$runtime_dir/onnxruntime-linux-x64-1.30.0"

mkdir -p "$model_dir" "$runtime_dir"
if [[ ! -f "$model" ]]; then
    curl -fL --retry 3 -o "$model" \
        https://github.com/fabio-sim/Depth-Anything-ONNX/releases/download/v2.0.0/depth_anything_v2_vits_dynamic.onnx
fi
printf '%s  %s\n' \
    46c4e8eeda3a27f34701831b6a2ec7753d7b38779b215acb5633424703deed8f \
    "$model" | sha256sum --check --status

if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 -o "$archive" \
        https://github.com/microsoft/onnxruntime/releases/download/v1.30.0/onnxruntime-linux-x64-1.30.0.tgz
fi
printf '%s  %s\n' \
    a5ed5a3cac51fbb2e90da632ae43d19212faaa20e76484e62bcb7c23ddb3b3fd \
    "$archive" | sha256sum --check --status
if [[ ! -d "$ort_root" ]]; then
    tar -xzf "$archive" -C "$runtime_dir"
fi

cmake -S "$repo_root/experiments/depth-poc" -B "$work_dir/build" -DORT_ROOT="$ort_root"
cmake --build "$work_dir/build" -j2
"$work_dir/build/depth-poc" "$model" "$1" "$work_dir/cache"
