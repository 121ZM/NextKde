#pragma once

#include <filesystem>
#include <string>

namespace LiquidAI {

class ModelManager final {
public:
    bool ensureDepthAnythingV2Small(std::filesystem::path *path,
                                    std::string *error) const;

    static constexpr const char *modelId = "depth-anything-v2-small-vits-onnx-v1";
    static constexpr const char *modelSha256 =
        "46c4e8eeda3a27f34701831b6a2ec7753d7b38779b215acb5633424703deed8f";
    static constexpr const char *modelUrl =
        "https://github.com/fabio-sim/Depth-Anything-ONNX/releases/download/v2.0.0/depth_anything_v2_vits_dynamic.onnx";
};

} // namespace LiquidAI
