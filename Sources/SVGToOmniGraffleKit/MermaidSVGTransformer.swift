import Foundation

/// Transforms a Mermaid-exported SVG so it imports cleanly into OmniGraffle.
///
/// OmniGraffle's SVG importer has three relevant quirks:
///  1. `<foreignObject>` (Mermaid's `htmlLabels: true` output) is dropped entirely.
///  2. `x`/`y` on `<tspan>` are ignored, so em-based multi-row tspans collapse.
///  3. Zero-size `<rect/>` placeholders render as visible dots.
///
/// It honors CSS `text-anchor: middle` (but not the presentation attribute), so
/// generated labels place `x` at the intended center and center-anchor there.
public struct MermaidSVGTransformer {

    public struct Options {
        /// Replace `<foreignObject>` HTML labels with native `<text>` elements.
        public var convertHTMLLabels = true
        /// Flatten em-positioned `<tspan>` rows into absolute `<text>` elements.
        public var flattenTSpans = true
        /// Remove zero-width `<rect/>` placeholders.
        public var removeEmptyRects = true

        public init() {}
    }

    static let fontFamily = "Barlow Condensed, arial, sans-serif"
    static let fontSize = "14px"
    static let fill = "#28253D"
    static let lineHeight = 21.0  // line-height 1.5 * 14px
    static let baseline = 15.0    // (lineHeight - fontSize) / 2 + ascent

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Transforms SVG data in place and returns the serialized result.
    public func transform(_ data: Data) throws -> Data {
        let document = try XMLDocument(data: data, options: .nodePreserveAll)
        guard let root = document.rootElement() else {
            throw TransformError.notAnSVGDocument
        }
        if options.convertHTMLLabels { convertForeignObjectLabels(in: root) }
        if options.flattenTSpans { flattenEMTSpans(in: root) }
        if options.removeEmptyRects { removeZeroSizeRects(in: root) }
        return document.xmlData(options: .nodePrettyPrint)
    }

    public func transform(fileAt input: URL, to output: URL) throws {
        let result = try transform(Data(contentsOf: input))
        try result.write(to: output)
    }

    public enum TransformError: Error, CustomStringConvertible {
        case notAnSVGDocument

        public var description: String {
            switch self {
            case .notAnSVGDocument: return "input is not a well-formed SVG document"
            }
        }
    }

    // MARK: - Transformations

    /// Mermaid (`htmlLabels: true`) renders node labels as
    /// `<foreignObject><div><span><p>text<br/>text</p>...`. Replace each with
    /// one `<text>` per line, centered on the measured label width.
    private func convertForeignObjectLabels(in root: XMLElement) {
        for foreignObject in elements(in: root, localName: "foreignObject") {
            guard
                let parent = foreignObject.parent as? XMLElement,
                let width = doubleAttribute(foreignObject, "width")
            else { continue }

            let lines = textLines(of: foreignObject)
            parent.removeChild(at: foreignObject.index)
            for (row, line) in lines.enumerated() {
                parent.addChild(makeText(
                    line,
                    x: width / 2,
                    y: Double(row) * Self.lineHeight + Self.baseline
                ))
            }
        }
    }

    /// Edge and cluster labels use `<text y="-10.1"><tspan y="-0.1em" dy="1.1em">`
    /// rows of word-level tspans. Replace each such `<text>` with one absolute
    /// `<text>` per row; the parent transform already sits at the label center.
    private func flattenEMTSpans(in root: XMLElement) {
        for text in elements(in: root, localName: "text") {
            let outerRows = (text.children ?? []).compactMap { child -> XMLElement? in
                guard
                    let element = child as? XMLElement,
                    element.localName == "tspan",
                    element.attribute(forName: "dy")?.stringValue?.contains("em") == true
                else { return nil }
                return element
            }
            guard !outerRows.isEmpty, let parent = text.parent as? XMLElement else { continue }

            let rows = outerRows
                .map { collectText(of: $0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            parent.removeChild(at: text.index)
            for (row, content) in rows.enumerated() {
                // First baseline: (y = -0.1em + dy = 1.1em) * 14px = 14.
                parent.addChild(makeText(content, x: 0, y: 14 + Double(row) * Self.lineHeight))
            }
        }
    }

    /// Attribute-less `<rect/>` placeholders and empty `background` rects have
    /// no size; OmniGraffle draws them as dots. Drop any rect without a
    /// positive width.
    private func removeZeroSizeRects(in root: XMLElement) {
        for rect in elements(in: root, localName: "rect") {
            let width = doubleAttribute(rect, "width") ?? 0
            if width <= 0, let parent = rect.parent as? XMLElement {
                parent.removeChild(at: rect.index)
            }
        }
    }

    // MARK: - Helpers

    private func elements(in root: XMLElement, localName: String) -> [XMLElement] {
        var found: [XMLElement] = []
        var stack: [XMLElement] = [root]
        while let element = stack.popLast() {
            if element.localName == localName { found.append(element) }
            stack.append(contentsOf: (element.children ?? []).compactMap { $0 as? XMLElement })
        }
        return found
    }

    private func doubleAttribute(_ element: XMLElement, _ name: String) -> Double? {
        element.attribute(forName: name)?.stringValue.flatMap(Double.init)
    }

    /// Concatenated text content of a node, depth first.
    private func collectText(of node: XMLNode) -> String {
        if node.kind == .text { return node.stringValue ?? "" }
        return (node.children ?? []).map(collectText).joined()
    }

    /// Text content split into lines at `<br/>` boundaries.
    private func textLines(of node: XMLNode) -> [String] {
        var lines: [String] = []
        var current = ""

        func walk(_ node: XMLNode) {
            if let element = node as? XMLElement, element.localName == "br" {
                lines.append(current)
                current = ""
                return
            }
            if node.kind == .text { current += node.stringValue ?? "" }
            (node.children ?? []).forEach(walk)
        }

        walk(node)
        lines.append(current)
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func makeText(_ content: String, x: Double, y: Double) -> XMLElement {
        let text = XMLElement(name: "text", stringValue: content)
        let attributes = [
            ("x", format(x)),
            ("y", format(y)),
            ("font-family", Self.fontFamily),
            ("font-size", Self.fontSize),
            ("fill", Self.fill),
            ("text-anchor", "middle"),
        ]
        for (name, value) in attributes {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = value
            text.addAttribute(attribute)
        }
        return text
    }

    private func format(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%g", value)
    }
}
