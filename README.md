# svg-to-omnigraffle

Convert SVG diagrams exported from [Mermaid](https://mermaid.js.org) so they import cleanly into [OmniGraffle](https://www.omnigroup.com/omnigraffle) — with all text labels present, correctly positioned, and without stray artifacts.

## The Problem

Mermaid exports SVG with `htmlLabels: true` by default, which renders every node label as a `<foreignObject>` element containing embedded HTML (`<div><span><p>…`). Browsers render this fine, but OmniGraffle's SVG importer has no HTML engine and silently drops these elements — you get a diagram of empty boxes.

Three specific OmniGraffle quirks are handled:

1. **`<foreignObject>` is ignored** — all HTML-based node labels vanish.
1. **`x`/`y` on `<tspan>` are ignored** — Mermaid positions edge and cluster labels with em-based tspan offsets, so those labels render one line too high. OmniGraffle also honors CSS `text-anchor: middle` but ignores the same setting as an XML attribute, shifting labels horizontally.
1. **Zero-size `<rect/>` placeholders render as dots** — Mermaid leaves empty `<rect/>` elements inside label groups; browsers draw nothing, OmniGraffle draws a visible point in every shape.

The converter rewrites all labels as plain, absolutely-positioned SVG `<text>` elements and removes the degenerate rects. Everything else (shapes, edges, markers, styles) is left untouched.

## Quick Start

Say you exported `architecture.svg` from Mermaid (mermaid.live, `mmdc`, or Mermaid Chart). To make it OmniGraffle-compatible:

```bash
svg2og architecture.svg -o architecture-omnigraffle.svg
```

Then in OmniGraffle: **File ▸ Open** (or drag the file in) and pick `architecture-omnigraffle.svg`. Labels, multi-line text, and edge labels ("primary"/"backup" and friends) all come through.

Without `-o`, output goes to `<input>.omnigraffle.svg`.

## Installation

Requires macOS with Xcode (the converter uses Foundation's `XMLDocument`).

```bash
git clone https://github.com/kigster/svg-to-omnigraffle.git
cd svg-to-omnigraffle
just setup     # verifies the Swift toolchain
just install   # builds release binary, installs to /usr/local/bin/svg2og
```

Or without `just`:

```bash
swift build -c release
cp .build/release/svg2og /usr/local/bin/
```

## Usage

```
Usage: svg2og [options] <input.svg>

Options:
  -o, --output <file>   Output file (default: <input>.omnigraffle.svg)
      --no-labels       Keep <foreignObject> HTML labels as-is
      --no-tspans       Keep em-positioned <tspan> rows as-is
      --no-rects        Keep zero-size <rect/> placeholders
  -h, --help            Show this help
```

Each transformation can be disabled independently — useful if a different tool in your pipeline already handles one of them.

## Using the Library

The conversion logic lives in the `SVGToOmniGraffleKit` target:

```swift
import SVGToOmniGraffleKit

var options = MermaidSVGTransformer.Options()
options.removeEmptyRects = false                     // opt out per transform

let transformer = MermaidSVGTransformer(options: options)
try transformer.transform(fileAt: inputURL, to: outputURL)

// or Data-to-Data:
let svgData = try transformer.transform(inputData)
```

## Alternative: Fix It at the Source

If you control the Mermaid config, exporting with HTML labels disabled avoids the `foreignObject` problem entirely:

```
---
config:
  flowchart:
    htmlLabels: false
---
flowchart TD
  ...
```

The tspan-positioning and dot-artifact quirks still apply, so running the converter is useful even then.

## Development

```bash
just build     # debug build
just test      # run the test suite
just run Resources/html-labels.svg   # convert the sample fixture
```

Sample Mermaid exports for experimenting live in `Resources/`.
