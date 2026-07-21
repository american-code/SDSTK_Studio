# SDSTK Studio

A universal iPad + Mac canvas app for visual data-science workflows, built on the [SDSTK](https://github.com/american-code/SwiftSci) Swift data-science stack.

Drag-and-drop nodes — Data, Transform, Model, Visualize, Score, Export — connect into pipelines that run locally on-device. Workflows save as `.sdstkflow` documents; trained expert bundles export as `.mbexpert` packages.

## Requirements

- Xcode 26+ (iOS 26 / macOS 26 SDK)
- iOS 26.0+ or macOS 26.0+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- SDSTK (SwiftSci) checked out as a sibling directory:

```
parent/
  SDSTKStudio/   ← this repo
  Downloads/
    SwiftSci/    ← SDSTK source (required sibling path)
```

## Build

```bash
cd SDSTKStudio
xcodegen generate
open SDSTKStudio.xcodeproj
```

GPU-accelerated nodes (Neural Network, Backend Benchmark) use [mlx-swift](https://github.com/ml-explore/mlx-swift). The Metal shader library is compiled natively by Xcode — no network access or manual steps required.

## License

SDSTK Studio is dual-licensed:

**Open-source:** [GNU Affero General Public License v3.0 or later](LICENSE) (AGPL-3.0-or-later). Free to use, modify, and distribute under AGPL terms — including the requirement that any deployed service using this code make its source available.

**Commercial:** A commercial license is available for use cases where AGPL terms are not suitable (proprietary products, closed-source derivatives, SaaS without source disclosure). Contact [jmelton@americancode.org](mailto:jmelton@americancode.org) for pricing and terms.

See [NOTICE](NOTICE) for the full copyright notice.
