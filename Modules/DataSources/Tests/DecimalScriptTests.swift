import Foundation
import Quotas
import Testing
@testable import DataSources

/// `jsonDecimal` and `decimalCents` — money a script reads stays exact.
@Suite
struct DecimalScriptTests {
    private func read(_ body: String, script: String) throws -> UsageSnapshot {
        let definition = DataSourceDefinition(kind: "api", fetch: .http(HTTPRequest(url: "https://acme.test")),
                                              mapping: .script(ScriptMapping(file: "money.js")))
        let source = DataSources.make(definition, providerId: "acme", scripts: { _ in script })
        return try source.read(Response(text: body))
    }

    @Test
    func `jsonDecimal keeps a number's exact digits`() throws {
        let usage = try read(#"{"balance": 0.1000000000000000055511151231257827}"#, script: """
        function read(response) {
          var balance = jsonDecimal(response.text).balance;
          return { quotas: [{ type: 'model', name: 'Balance', left: { money: balance, currency: 'USD' } }] };
        }
        """)
        #expect(usage.quotas.first?.left == .money(Money(Decimal(string: "0.1000000000000000055511151231257827")!, currency: "USD"), of: nil))
    }

    @Test(arguments: [("12.345", "12.35"), ("12.344", "12.34"), ("-0.004", "0.00"), ("1e2", "100.00"), ("99.995", "100.00")])
    func `decimalCents rounds half up without a float`(_ amount: String, _ cents: String) throws {
        let usage = try read("{}", script: """
        function read() {
          return { quotas: [{ type: 'model', name: 'Balance', left: { money: decimalCents('\(amount)'), currency: 'USD' } }] };
        }
        """)
        #expect(usage.quotas.first?.left == .money(Money(Decimal(string: cents)!, currency: "USD"), of: nil))
    }

    @Test(arguments: [("1234567", "0.000003", "3.703701"), ("0.1", "0.2", "0.02"), ("-2.5", "4", "-10"), ("1e6", "1.5", "1500000")])
    func `decimalMultiply multiplies exactly`(_ a: String, _ b: String, _ product: String) throws {
        let usage = try read("{}", script: """
        function read() {
          return { quotas: [{ type: 'model', name: 'Cost', left: { money: decimalMultiply('\(a)', '\(b)'), currency: 'USD' } }] };
        }
        """)
        #expect(usage.quotas.first?.left == .money(Money(Decimal(string: product)!, currency: "USD"), of: nil))
    }

    @Test(arguments: [("0.1", "0.2", "0.3"), ("1.005", "-0.005", "1"), ("12", "0.000001", "12.000001")])
    func `decimalAdd adds exactly`(_ a: String, _ b: String, _ sum: String) throws {
        let usage = try read("{}", script: """
        function read() {
          return { quotas: [{ type: 'model', name: 'Cost', left: { money: decimalAdd('\(a)', '\(b)'), currency: 'USD' } }] };
        }
        """)
        #expect(usage.quotas.first?.left == .money(Money(Decimal(string: sum)!, currency: "USD"), of: nil))
    }
}
