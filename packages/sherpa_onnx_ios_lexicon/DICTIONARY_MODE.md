# Physical iOS dictionary mode

App-owned fork of sherpa_onnx_ios 1.13.8, using the same opt-in dictionary patch as the Mac. Source commit: 11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf (https://github.com/k2-fsa/sherpa-onnx). Original model and Michael voice unchanged.

Built for physical iOS arm64 only, minimum iOS 13. No simulator slice is shipped; simulator builds are not supported by this local package. Source package cache is unchanged.

ONNX Runtime static dependency 1.28.2 from https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip. Native build uses two jobs, static dependencies, shared C API. See dictionary-mode.patch and build-device.sh.

Binary SHA-256: 8f8cd3d8ac885f1343bc6f9f07c1dfb6c1af17a0a63bf95358bf1fef195cadc6
