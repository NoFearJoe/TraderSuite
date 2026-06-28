import Testing
import Core
@testable import ExchangeKit

@Suite("Exchange registry")
struct ExchangeRegistryTests {

    @Test("Register and resolve an adapter")
    func registerAndResolve() async {
        let registry = ExchangeRegistry()
        await registry.register(MoexAdapter())

        let adapter = await registry.adapter(for: .moex)
        #expect(adapter != nil)
        #expect(adapter?.exchangeID == .moex)

        let exchanges = await registry.registeredExchanges
        #expect(exchanges == [.moex])
    }

    @Test("MOEX currency is RUB")
    func moexCurrency() {
        #expect(ExchangeID.moex.currencyCode == "RUB")
    }
}
