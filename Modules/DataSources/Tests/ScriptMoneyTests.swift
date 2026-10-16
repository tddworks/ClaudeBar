import Foundation
import Quotas
import Testing
@testable import DataSources

@Suite
struct ScriptMoneyTests {
    private func read(_ output: String) throws -> UsageSnapshot {
        let definition = DataSourceDefinition(kind: "api", fetch: .http(HTTPRequest(url: "https://example.test")),
                                              mapping: .script(ScriptMapping(file: "balance.js")))
        let source = DataSources.make(definition, providerId: "example", scripts: { _ in "function read() { return \(output); }" })
        return try source.read(Response(text: "{}"))
    }

    @Test
    func `should show an exact balance without a made-up percentage when a script reports money`() throws {
        let usage = try read(#"{quotas:[{type:'model',name:'Balance',left:{money:'1234567890.123456789',currency:'CNY'}}]}"#)
        let quota = try #require(usage.quotas.first)
        #expect(quota.left == .money(Money(Decimal(string: "1234567890.123456789")!, currency: "CNY"), of: nil))
        #expect(quota.percentLeft == nil)
        #expect(quota.window == nil)
    }

    @Test
    func `should show money left of its ceiling as a percentage when a script reports both`() throws {
        let usage = try read(#"{quotas:[{type:'model',name:'Credits',left:{money:'12.50',of:'50',currency:'USD'}}]}"#)
        #expect(usage.quotas.first?.left == .money(Money(Decimal(string: "12.50")!, currency: "USD"), of: Money(50, currency: "USD")))
        #expect(usage.quotas.first?.percentLeft == 25)
    }

    @Test
    func `should show a cost with each line exact against the user's budget`() throws {
        let usage = try read(#"{quotas:[],cost:{used:'4.10',limit:'10',lines:[{label:'Claude Sonnet 4',used:'3.70',detail:'1.2M tokens'},{label:'Nova Pro',used:'0.40'}]}}"#)
        let cost = try #require(usage.costUsage)
        #expect(cost.totalCost == Decimal(string: "4.10")!)
        #expect(cost.budget == 10)
        #expect(cost.lines == [CostLine(label: "Claude Sonnet 4", amount: Decimal(string: "3.70")!, detail: "1.2M tokens"),
                               CostLine(label: "Nova Pro", amount: Decimal(string: "0.40")!)])
        #expect(usage.quotas.isEmpty)
    }

    @Test
    func `should group a quota under the name the script gives it`() throws {
        let usage = try read(#"{quotas:[{type:'time',name:'Kimi 5h',percentRemaining:40,group:'Kimi'},{type:'time',name:'Solo',percentRemaining:9}]}"#)
        #expect(usage.quotas.map(\.group) == ["Kimi", nil])
    }

    @Test
    func `should show a group with nothing to measure with its note`() throws {
        let usage = try read(#"{quotas:[{type:'time',name:'Kimi 5h',percentRemaining:40,group:'Kimi'}],notes:[{group:'Copilot · me',text:'No usage reported'}]}"#)
        #expect(usage.quotaGroups.map(\.title) == ["Kimi", "Copilot · me"])
        #expect(usage.quotaGroups.last?.note == "No usage reported")
    }

    @Test
    func `should keep showing the percentage a script reports`() throws {
        let usage = try read(#"{quotas:[{type:'session',percentRemaining:37}]}"#)
        #expect(usage.quotas.first?.left == .share(37))
    }

    @Test(arguments: [#"{type:'model',name:'Balance'}"#, #"{type:'model',name:'Balance',percentRemaining:50,left:{money:'1'}}"#, #"{type:'model',name:'Balance',left:{money:'nope'}}"#])
    func `should refuse a missing, ambiguous or invalid amount`(_ quota: String) {
        #expect(throws: DataSourceError.self) { try read("{quotas:[\(quota)]}") }
    }
}
