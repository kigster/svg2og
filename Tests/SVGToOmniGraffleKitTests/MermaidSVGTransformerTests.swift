import XCTest
@testable import SVGToOmniGraffleKit

final class MermaidSVGTransformerTests: XCTestCase {

    /// Minimal Mermaid-shaped fixture: an htmlLabels node (two lines, with a
    /// placeholder rect), an em-tspan edge label with background rect, and a
    /// normal rect that must survive.
    let fixture = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
      <g class="node">
        <rect class="basic" x="-50" y="-20" width="100" height="40"/>
        <g class="label" transform="translate(-40, -14)">
          <rect/>
          <foreignObject width="80" height="42">
            <div xmlns="http://www.w3.org/1999/xhtml">
              <span class="nodeLabel"><p>Load Balancer A<br />nginx + haproxy</p></span>
            </div>
          </foreignObject>
        </g>
      </g>
      <g class="edgeLabel" transform="translate(100, 50)">
        <g class="label">
          <rect class="background" x="-29.3" y="-1.5" width="58.6" height="21"/>
          <text y="-10.1" text-anchor="middle">
            <tspan x="0" y="-0.1em" dy="1.1em">
              <tspan class="text-inner-tspan">primary</tspan>
            </tspan>
          </text>
        </g>
      </g>
      <g class="empty-label"><rect class="background" style="stroke: none"/></g>
    </svg>
    """

    func transformed(_ options: MermaidSVGTransformer.Options = .init()) throws -> XMLDocument {
        let data = try MermaidSVGTransformer(options: options).transform(Data(fixture.utf8))
        return try XMLDocument(data: data)
    }

    func texts(in document: XMLDocument) throws -> [XMLElement] {
        try document.nodes(forXPath: "//*[local-name()='text']").compactMap { $0 as? XMLElement }
    }

    // MARK: - foreignObject conversion

    func testConvertsForeignObjectToOneTextPerLine() throws {
        let document = try transformed()

        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='foreignObject']").count, 0)

        let labels = try texts(in: document).filter { $0.stringValue?.contains("nginx") == true
            || $0.stringValue?.contains("Load Balancer") == true }
        XCTAssertEqual(labels.map(\.stringValue), ["Load Balancer A", "nginx + haproxy"])

        // Centered on half the measured foreignObject width (80 / 2).
        XCTAssertEqual(labels[0].attribute(forName: "x")?.stringValue, "40")
        XCTAssertEqual(labels[0].attribute(forName: "text-anchor")?.stringValue, "middle")
        // Baselines: 15, then +21 line height.
        XCTAssertEqual(labels[0].attribute(forName: "y")?.stringValue, "15")
        XCTAssertEqual(labels[1].attribute(forName: "y")?.stringValue, "36")
    }

    // MARK: - tspan flattening

    func testFlattensEMTSpansToAbsoluteText() throws {
        let document = try transformed()

        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tspan']").count, 0)

        let edge = try XCTUnwrap(texts(in: document).first { $0.stringValue == "primary" })
        // Parent transform is the center, so x = 0; baseline = (−0.1 + 1.1)em × 14px.
        XCTAssertEqual(edge.attribute(forName: "x")?.stringValue, "0")
        XCTAssertEqual(edge.attribute(forName: "y")?.stringValue, "14")
    }

    // MARK: - zero-size rect removal

    func testRemovesOnlyZeroSizeRects() throws {
        let document = try transformed()
        let rects = try document.nodes(forXPath: "//*[local-name()='rect']")
            .compactMap { $0 as? XMLElement }

        XCTAssertEqual(rects.count, 2)
        XCTAssertTrue(rects.allSatisfy {
            Double($0.attribute(forName: "width")?.stringValue ?? "0") ?? 0 > 0
        })
    }

    // MARK: - option flags

    func testDisabledTransformationsLeaveInputAlone() throws {
        var options = MermaidSVGTransformer.Options()
        options.convertHTMLLabels = false
        options.flattenTSpans = false
        options.removeEmptyRects = false
        let document = try transformed(options)

        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='foreignObject']").count, 1)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tspan']").count, 2)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='rect'][not(@width)]").count, 2)
    }

    func testRejectsMalformedInput() {
        XCTAssertThrowsError(try MermaidSVGTransformer().transform(Data("not svg".utf8)))
    }
}
