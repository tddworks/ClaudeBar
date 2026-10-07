import Foundation
import Testing
@testable import Domain

@Suite
struct ExtensionMetricTests {
    @Test
    func `should keep every detail of an extension's metric, from label to progress`() {
        let metric = ExtensionMetric(
            label: "API Calls",
            value: "1,234",
            unit: "Requests",
            icon: "arrow.up.arrow.down",
            color: "#4CAF50",
            delta: MetricDelta(vs: "Yesterday", value: "+200", percent: 19.3),
            progress: 0.65
        )

        #expect(metric.label == "API Calls")
        #expect(metric.value == "1,234")
        #expect(metric.unit == "Requests")
        #expect(metric.icon == "arrow.up.arrow.down")
        #expect(metric.color == "#4CAF50")
        #expect(metric.delta?.vs == "Yesterday")
        #expect(metric.delta?.value == "+200")
        #expect(metric.delta?.percent == 19.3)
        #expect(metric.progress == 0.65)
    }

    @Test
    func `should leave a metric's icon, colour, change and progress empty when only label, value and unit are given`() {
        let metric = ExtensionMetric(
            label: "Requests",
            value: "42",
            unit: "Total"
        )

        #expect(metric.label == "Requests")
        #expect(metric.value == "42")
        #expect(metric.unit == "Total")
        #expect(metric.icon == nil)
        #expect(metric.color == nil)
        #expect(metric.delta == nil)
        #expect(metric.progress == nil)
    }

    @Test
    func `should read every detail of a metric an extension reports`() throws {
        let json = """
        {
            "label": "Cost",
            "value": "$10.26",
            "unit": "Spent",
            "icon": "dollarsign.circle.fill",
            "color": "#FFEB3B",
            "delta": {
                "vs": "Mar 16",
                "value": "-$701.58",
                "percent": 98.6
            },
            "progress": 0.82
        }
        """

        let metric = try JSONDecoder().decode(ExtensionMetric.Reported.self, from: json.data(using: .utf8)!).metric

        #expect(metric.label == "Cost")
        #expect(metric.value == "$10.26")
        #expect(metric.unit == "Spent")
        #expect(metric.icon == "dollarsign.circle.fill")
        #expect(metric.color == "#FFEB3B")
        #expect(metric.delta?.vs == "Mar 16")
        #expect(metric.delta?.value == "-$701.58")
        #expect(metric.delta?.percent == 98.6)
        #expect(metric.progress == 0.82)
    }

    @Test
    func `should read a metric an extension reports without its optional details`() throws {
        let json = """
        {
            "label": "Tokens",
            "value": "8.3M",
            "unit": "Used"
        }
        """

        let metric = try JSONDecoder().decode(ExtensionMetric.Reported.self, from: json.data(using: .utf8)!).metric

        #expect(metric.label == "Tokens")
        #expect(metric.delta == nil)
        #expect(metric.progress == nil)
    }

    @Test
    func `should keep what a metric's change compares with, by how much and in percent`() {
        let delta = MetricDelta(vs: "Mar 16", value: "-$701.58", percent: 98.6)

        #expect(delta.vs == "Mar 16")
        #expect(delta.value == "-$701.58")
        #expect(delta.percent == 98.6)
    }

    @Test
    func `should read a metric's change without a percent when the extension gives none`() throws {
        let json = """
        {
            "vs": "Yesterday",
            "value": "+5"
        }
        """

        let delta = try JSONDecoder().decode(MetricDelta.Reported.self, from: json.data(using: .utf8)!).delta

        #expect(delta.vs == "Yesterday")
        #expect(delta.value == "+5")
        #expect(delta.percent == nil)
    }
}