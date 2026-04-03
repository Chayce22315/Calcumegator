# Calcumegator

**By Pixelated Studios and NextStop.**

---

## Important: unsigned builds and GitHub Actions

**This app is unsigned and is meant to be built on GitHub Actions** (see [`.github/workflows/build.yml`](.github/workflows/build.yml)). The canonical way to produce an installable artifact is to push to this repository and download the workflow artifact (`Calcumegator.ipa`).

Do not commit an `.xcodeproj` to Git. Generate the Xcode project locally with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # macOS
xcodegen generate
open Calcumegator.xcodeproj
```

The workflow runs `xcodegen generate`, then an **unsigned** `xcodebuild` for generic iOS device, packages `Payload/Calcumegator.app` into **`Calcumegator.ipa`**, and uploads it as a downloadable artifact.

**Limitations:** Unsigned `.ipa` files are for internal or advanced distribution only. They are **not** a replacement for TestFlight or App Store distribution without proper code signing and provisioning.

---

## Local AI models (future)

Bundled Core ML assets will live under `Models/Free`, `Models/Pro`, and `Models/Ultra` (23 models planned).

---

## License

See repository license (if any).
