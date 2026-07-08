import Foundation
import SVGToOmniGraffleKit

let version = "0.1.0"

let usage = """
Usage: svg2og [options] <input.svg>

Converts a Mermaid-exported SVG for clean import into OmniGraffle.

Options:
  -o, --output <file>   Output file (default: <input>-omnigraffle.svg)
      --no-labels       Keep <foreignObject> HTML labels as-is
      --no-tspans       Keep em-positioned <tspan> rows as-is
      --no-rects        Keep zero-size <rect/> placeholders
  -V, --version         Show version
  -h, --help            Show this help
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("svg2og: \(message)\n".utf8))
    exit(1)
}

var options = MermaidSVGTransformer.Options()
var inputPath: String?
var outputPath: String?

var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "-V", "--version":
        print("svg2og \(version)")
        exit(0)
    case "-o", "--output":
        guard !arguments.isEmpty else { fail("\(argument) requires a file argument") }
        outputPath = arguments.removeFirst()
    case "--no-labels":
        options.convertHTMLLabels = false
    case "--no-tspans":
        options.flattenTSpans = false
    case "--no-rects":
        options.removeEmptyRects = false
    default:
        if argument.hasPrefix("-") { fail("unknown option: \(argument)\n\n\(usage)") }
        guard inputPath == nil else { fail("multiple input files given") }
        inputPath = argument
    }
}

guard let inputPath else { fail("no input file\n\n\(usage)") }
let input = URL(fileURLWithPath: inputPath)
let output = outputPath.map(URL.init(fileURLWithPath:))
    ?? input.deletingPathExtension().appendingPathExtension("omnigraffle.svg")

do {
    try MermaidSVGTransformer(options: options).transform(fileAt: input, to: output)
    print("Wrote \(output.path)")
} catch {
    fail("\(error)")
}
