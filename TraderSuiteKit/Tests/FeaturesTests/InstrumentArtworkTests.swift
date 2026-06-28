import Testing
@testable import Features

@Suite("InstrumentArtwork")
struct InstrumentArtworkTests {
    @Test("Crypto families resolve to branded, non-fallback artwork")
    func cryptoFamilies() {
        for code in ["BTC", "mbt", "Bitcoin"] {
            let art = InstrumentArtwork.forFamily(code)
            #expect(!art.isFallback)
            #expect(art.systemName == "bitcoinsign")
            #expect(art.title != nil)
        }
        for code in ["ETH", "met", "Ethereum"] {
            let art = InstrumentArtwork.forFamily(code)
            #expect(!art.isFallback)
            #expect(art.systemName == "diamond.fill")
            #expect(art.title != nil)
        }
    }

    @Test("Metals keep their distinct material tints")
    func metalTints() {
        let gold = InstrumentArtwork.forFamily("GOLD")
        let silver = InstrumentArtwork.forFamily("SILVER")
        let copper = InstrumentArtwork.forFamily("COPPER")
        #expect(!gold.isFallback)
        // Each metal reads with its own colour rather than sharing a system tint.
        #expect(gold.tint != silver.tint)
        #expect(silver.tint != copper.tint)
    }

    @Test("Unknown codes still fall back")
    func fallback() {
        #expect(InstrumentArtwork.forFamily("ZZZ").isFallback)
    }
}
