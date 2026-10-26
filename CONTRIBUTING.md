# Contributing to SasNotch

Thanks for helping. Bug reports, fixes, translations and feature ideas are all welcome.

## Build it

You need an Apple Silicon Mac with macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). A full Xcode install is optional.

```sh
git clone https://github.com/Rsunthar2027/SasNotch.git
cd SasNotch
./build.sh --dev            # builds "SasNotch (Developer)" into build/stage.noindex
./build.sh --dev --install  # installs it in /Applications and opens it
./build.sh --test           # runs the unit tests
```

The Developer variant has its own bundle ID, so it runs beside a released copy without sharing settings or permissions. The first `--dev` build creates a local "SasNotch Self-Signed" certificate (`Tools/setup-signing.sh`) so that permissions you grant survive rebuilds.

To work in Xcode, open `Package.swift`. Xcode builds and runs the code, but releases come from `build.sh`, which assembles and signs the app bundle.

## Where things live

| Path | What it holds |
|---|---|
| `Sources/SasNotch/App` | App delegate, menu bar item, feature runtime |
| `Sources/SasNotch/Core` | Settings keys, feature catalog, localized strings |
| `Sources/SasNotch/Services/Notch` | The island: window, hover and pin handling, its services |
| `Sources/SasNotch/Services/LiveActivities` | Focus, camera and microphone dots, weather |
| `Sources/SasNotch/UI` | SwiftUI views, including `UI/Notch` and `UI/Settings` |
| `Tests` | Unit tests, run by `./build.sh --test` |
| `Branding` | The sasquatch SVGs; `Tools/MakeIcon.swift` exports every icon from them |
| `Tools` | Signing, packaging, appcast and secrets-scan scripts |

## Pull requests

- Keep each pull request to one change, and say in the description what you tested.
- Run `./build.sh --dev` and `./build.sh --test` before you push. Both must finish with no warnings.
- Run `./Tools/scan-secrets.sh`. Never commit certificates, keys, tokens or paths into your home folder.
- New files start with the GPL header used across the codebase. If you change a file that came from Vorssaint or Atoll, keep its copyright lines.
- A user-facing change gets a line in `CHANGELOG.md` under `[Unreleased]`.

## Releases

Maintainers release by pushing a version tag such as `v1.2.0`. `.github/workflows/release.yml` builds, signs, packages the `.zip` and `.dmg`, writes the Sparkle appcast and publishes the GitHub Release.

## License

By contributing you agree that your work is released under the GNU General Public License v3.0 or later, like the rest of SasNotch.
