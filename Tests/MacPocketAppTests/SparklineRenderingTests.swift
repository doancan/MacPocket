import AppKit
import Charts
import SwiftUI
import XCTest
@testable import MacPocketApp

@MainActor final class SparklineRenderingTests: XCTestCase {
    func testRenderersProduceNonemptyImagesWithMatchingDimensions() throws {
        let benchmark = ProcessInfo.processInfo.environment["MACPOCKET_SPARKLINE_BENCHMARK"] == "1"
        let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/performance/sparklines")
        if benchmark { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
        var rows: [[String: Any]] = []
        for reference in [true, false] {
            var elapsed: [Double] = []
            let renderer = ImageRenderer(content: content(reference: reference, phase: 0))
            renderer.scale = 2
            let iterations = benchmark ? 45 : 2
            var firstPixels: Data?
            for iteration in 0..<iterations {
                let start = ProcessInfo.processInfo.systemUptime
                renderer.content = content(reference: reference, phase: iteration)
                let image = try XCTUnwrap(renderer.cgImage)
                let duration = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                XCTAssertEqual(image.width, 720); XCTAssertEqual(image.height, 288)
                if iteration == 0 {
                    firstPixels = image.dataProvider?.data as Data?
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let ink = (0..<image.width).contains { x in
                        guard let pixel = bitmap.colorAt(x: x, y: 40)?.usingColorSpace(.deviceRGB) else { return false }
                        return pixel.blueComponent - pixel.redComponent > 0.02
                    }
                    XCTAssertTrue(ink, "Sparkline must contain rendered colored pixels")
                    if benchmark {
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            .write(to: destination.appendingPathComponent(reference ? "reference.png" : "optimized.png"))
                    }
                }
                if iteration == iterations - 1 {
                    XCTAssertNotEqual(image.dataProvider?.data as Data?, firstPixels, "A new sample must change the rendered graph")
                }
                if iteration >= 5 { elapsed.append(duration) }
            }
            if benchmark {
                let sorted = elapsed.sorted()
                rows.append(["renderer":reference ? "SwiftCharts" : "Canvas", "iterations":sorted.count,
                    "medianMS":sorted[sorted.count / 2], "p95MS":sorted[Int(Double(sorted.count - 1) * 0.95)], "samplesMS":elapsed])
            }
        }
        if benchmark {
            let report: [String: Any] = ["measurements": rows, "boundary":"ImageRenderer content update through synchronous CGImage generation",
                "charts":3,"samplesPerChart":60,"scale":2,"configuration":"Debug XCTest","networkRequests":false]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: destination.appendingPathComponent("benchmark.json"))
        }
    }

    private func content(reference: Bool, phase: Int) -> AnyView {
        AnyView(VStack(spacing: 12) {
            graph(reference: reference, values: values(phase).map { $0 * 100 }, floor: 0, ceiling: 100)
            graph(reference: reference, values: values(phase + 7).map { -100 + $0 * 80 }, floor: -100, ceiling: -20)
            graph(reference: reference, values: values(phase + 13).map { $0 * 250 }, floor: 0, ceiling: nil)
        }.frame(width: 360).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    }
    @ViewBuilder private func graph(reference: Bool, values: [Double], floor: Double, ceiling: Double?) -> some View {
        if reference { ReferenceSparkline(values: values, floor: floor, ceiling: ceiling).frame(height: 40) }
        else { PocketSparkline(values: values, color: .blue, ceiling: ceiling, floor: floor).frame(height: 40) }
    }
    private func values(_ phase: Int) -> [Double] {
        (0..<60).map { index in 0.5 + 0.35 * sin(Double(index + phase) * 0.23) + 0.1 * sin(Double(index) * 0.71) }
    }
}

/// The previous production renderer, retained only as the benchmark's fixed comparison.
private struct ReferenceSparkline: View {
    let values: [Double]
    let floor: Double
    let ceiling: Double?
    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("Örnek", index), yStart: .value("Değer", floor), yEnd: .value("Değer", value))
                    .foregroundStyle(LinearGradient(colors: [Color.blue.opacity(0.28), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Örnek", index), y: .value("Değer", value))
                    .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .chartYScale(domain: floor...max(floor + 1, ceiling ?? max(1, values.max() ?? 1)))
            .accessibilityHidden(true)
    }
}
