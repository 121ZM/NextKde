{
    lib,
    stdenv,
    cmake,
    kdePackages,
    opencv,
    onnxruntime,
    src,
}:

stdenv.mkDerivation {
    pname = "kos-platform";
    version = "unstable";
    src = "${src}/platform";

    # The standalone AI library is kept beside `platform/` in the source
    # tree, while this derivation builds the platform subdirectory alone.
    postPatch = ''
      cp -r ${src}/liquid-ai liquid-ai
    '';

    nativeBuildInputs = [
        cmake
        kdePackages.extra-cmake-modules
    ];

    buildInputs = [
        kdePackages.qtbase
        kdePackages.qtdeclarative
        kdePackages.kiconthemes
        kdePackages.kglobalaccel
        kdePackages.kio
        opencv
        onnxruntime
    ];

    cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
    dontWrapQtApps = true;

    meta = with lib; {
        description = "KOS platform integration daemon (D-Bus bridge for KWin, network, audio, etc.)";
        homepage = "https://gitee.com/xiaoyintx_ciallo/test";
        license = licenses.gpl3;
        platforms = platforms.linux;
    };
}
