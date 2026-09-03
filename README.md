# SDSTK Studio

A universal iPad + Mac canvas app for visual data-science workflows, built on the [SDSTK](https://github.com/american-code/SDSTK) Swift data-science stack.

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

> `Generated/SDSTKStudio-Info.plist` and `SDSTKStudio.xcodeproj` are both produced by
> `xcodegen generate` from `project.yml`. They are committed so the project opens without a
> toolchain step, which means **they go stale if you add a source file or change project.yml and
> forget to regenerate**. Run `xcodegen generate` before committing either kind of change.

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

### Dual licensing and App Store distribution

This project is offered under **two** licenses, at your option:

1. **AGPL-3.0-or-later** — the terms in `LICENSE`. Use, modify and redistribute
   freely, provided derivative works and network-served modifications are made
   available under the same terms.
2. **A commercial license** — for anyone who cannot accept the AGPL's copyleft
   or source-disclosure obligations. Contact jmelton@americancode.org.

Binaries distributed through the Apple App Store are released under the
commercial license, **not** the AGPL. This is deliberate: Apple's terms of
service impose usage and device restrictions that the GPL family forbids adding
to a covered work, so an AGPL binary cannot be distributed there. As sole
copyright holder, American Code can and does license the App Store build
separately. Every third-party component this project depends on is MIT,
Apache-2.0 or BSD-3-Clause (see `NOTICE`), so none of them restricts that.

Nothing here changes your rights to the source in this repository, which remain
AGPL-3.0-or-later.
