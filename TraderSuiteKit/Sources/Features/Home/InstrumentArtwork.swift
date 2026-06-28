import SwiftUI

/// A locally-generated icon and human-readable name for an instrument family,
/// used when grouping search results and when the exchange supplies no artwork
/// of its own: an SF Symbol + tint + title chosen from the instrument family.
///
/// Covers the popular MOEX FORTS families — oil, gas, precious/industrial metals,
/// currencies, indices, agriculture and blue-chip equities — plus CME crypto
/// (Bitcoin, Ether), and falls back to a neutral chart glyph and the raw family
/// code for anything unrecognised.
struct InstrumentArtwork: Equatable {
    let systemName: String
    let tint: Color
    /// Human-readable instrument name, or `nil` to fall back to the family code.
    let title: String?
    /// One-line description of the underlying, or `nil` when unknown.
    let summary: String?
    /// `true` when the family code is unrecognised — callers may render a letter placeholder instead.
    let isFallback: Bool

    private init(_ systemName: String, _ tint: Color, _ title: String? = nil, _ summary: String? = nil, isFallback: Bool = false) {
        self.systemName = systemName
        self.tint = tint
        self.title = title
        self.summary = summary
        self.isFallback = isFallback
    }

    /// A display title for a family: the friendly name when known, else the code.
    static func displayName(forFamily family: String) -> String {
        forFamily(family).title ?? family
    }

    /// Pick artwork for an instrument family code (MOEX `ASSETCODE`, e.g. "BR",
    /// "GOLD", "Si"). Matching is case-insensitive.
    static func forFamily(_ family: String) -> InstrumentArtwork {
        switch family.uppercased() {
        // Energy
        case "BR", "BRM", "BRENT":
            return .init("drop.fill", .primary,
                String(localized: "instrument_brent_oil"),
                String(localized: "instrument_brent_oil_desc"))
        case "CL", "WTI", "OIL":
            return .init("drop.fill", .primary,
                String(localized: "instrument_wti_oil"),
                String(localized: "instrument_wti_oil_desc"))
        case "NG", "GAS", "NATGAS":
            return .init("flame.fill", .blue,
                String(localized: "instrument_natural_gas"),
                String(localized: "instrument_natural_gas_desc"))

        // Precious & industrial metals
        case "GC", "GOLD", "GOLDM", "GLDRUBTOM", "GD", "GLD":
            return .init("seal.fill", .gold,
                String(localized: "instrument_gold"),
                String(localized: "instrument_gold_desc"))
        // NOTE: "SI" is also MOEX's USD/RUB family code — see the Currencies section below.
        // CME silver (product code SI) therefore shows a dollar icon; cosmetic limitation.
        case "SILV", "SV", "SVM", "SLVRUBTOM", "SILVER", "SLV":
            return .init("seal.fill", .silver,
                String(localized: "instrument_silver"),
                String(localized: "instrument_silver_desc"))
        case "PLT", "PLTM", "PLATINUM", "PL", "PLM":
            return .init("seal.fill", .platinum,
                String(localized: "instrument_platinum"),
                String(localized: "instrument_platinum_desc"))
        case "PA", "PD", "PLD", "PALLADIUM":
            return .init("seal.fill", .palladium,
                String(localized: "instrument_palladium"),
                String(localized: "instrument_palladium_desc"))
        case "HG", "CU", "COPPER":
            return .init("seal.fill", .copper,
                String(localized: "instrument_copper"),
                String(localized: "instrument_copper_desc"))

        // Crypto — CME
        case "BTC", "MBT", "XBT", "BITCOIN":
            return .init("bitcoinsign", .bitcoin,
                String(localized: "instrument_bitcoin"),
                String(localized: "instrument_bitcoin_desc"))
        case "ETH", "MET", "ETHER", "ETHEREUM":
            return .init("diamond.fill", .ethereum,
                String(localized: "instrument_ethereum"),
                String(localized: "instrument_ethereum_desc"))

        // Currencies — MOEX
        // "SI" is MOEX's ASSETCODE for USD/RUB futures (e.g. SiH26).
        case "SI", "USD", "USDRUB", "USDRUBTOM":
            return .init("dollarsign", .green,
                String(localized: "instrument_usd_rub"),
                String(localized: "instrument_usd_rub_desc"))
        case "EU", "EURRUB", "EURRUBTOM":
            return .init("eurosign", .blue,
                String(localized: "instrument_eur_rub"),
                String(localized: "instrument_eur_rub_desc"))
        case "CNY", "CNYRUBTOM", "YUAN", "CR", "UCNY", "MOEXCNY":
            return .init("yensign", .red,
                String(localized: "instrument_cny_rub"),
                String(localized: "instrument_cny_rub_desc"))

        // Currencies — FX (CME 6x codes + MOEX aliases)
        case "6E", "ED", "EUR", "EURUSD":
            return .init("eurosign", .blue,
                String(localized: "instrument_eur_usd"),
                String(localized: "instrument_eur_usd_desc"))
        case "6B", "GBPU", "GBP", "BP":
            return .init("sterlingsign", .indigo,
                String(localized: "instrument_gbp_usd"),
                String(localized: "instrument_gbp_usd_desc"))
        case "JP", "JPY":
            return .init("yensign", .pink,
                String(localized: "instrument_jpy_rub"),
                String(localized: "instrument_jpy_rub_desc"))
        case "6J":
            return .init("yensign", .pink,
                String(localized: "instrument_jpy_usd"),
                String(localized: "instrument_jpy_usd_desc"))

        // Indices — MOEX
        case "RTS", "RTSM", "RI", "RTSI":
            return .init("chart.line.uptrend.xyaxis", .indigo,
                String(localized: "instrument_rts_index"),
                String(localized: "instrument_rts_index_desc"))
        case "MIX", "MIXM", "MX", "MXI", "IMOEX":
            return .init("chart.bar.fill", .purple,
                String(localized: "instrument_moex_index"),
                String(localized: "instrument_moex_index_desc"))

        // Indices — CME US equity index futures
        case "ES", "MES":
            return .init("chart.line.uptrend.xyaxis", .blue,
                String(localized: "instrument_sp500"),
                String(localized: "instrument_sp500_desc"))
        case "NQ", "MNQ":
            return .init("chart.line.uptrend.xyaxis", .cyan,
                String(localized: "instrument_nasdaq100"),
                String(localized: "instrument_nasdaq100_desc"))
        case "RTY":
            return .init("chart.line.uptrend.xyaxis", .orange,
                String(localized: "instrument_russell2000"),
                String(localized: "instrument_russell2000_desc"))
        case "YM":
            return .init("chart.bar.fill", .indigo,
                String(localized: "instrument_dow_jones"),
                String(localized: "instrument_dow_jones_desc"))

        // US Treasuries (CBOT)
        case "ZB":
            return .init("building.columns.fill", .blue,
                String(localized: "instrument_tbond30y"),
                String(localized: "instrument_tbond30y_desc"))
        case "ZN":
            return .init("building.columns.fill", .teal,
                String(localized: "instrument_tnote10y"),
                String(localized: "instrument_tnote10y_desc"))

        // Indices — Eurex
        case "FESX":
            return .init("chart.line.uptrend.xyaxis", .blue,
                String(localized: "instrument_eurostoxx50"),
                String(localized: "instrument_eurostoxx50_desc"))
        case "FDAX":
            return .init("chart.bar.fill", .red,
                String(localized: "instrument_dax"),
                String(localized: "instrument_dax_desc"))
        case "FDXS":
            return .init("chart.bar.fill", .orange,
                String(localized: "instrument_dax_mini"),
                String(localized: "instrument_dax_desc"))

        // German yield curve — Eurex
        case "FGBL":
            return .init("building.columns.fill", .indigo,
                String(localized: "instrument_bund"),
                String(localized: "instrument_bund_desc"))
        case "FGBM":
            return .init("building.columns.fill", .purple,
                String(localized: "instrument_bobl"),
                String(localized: "instrument_bobl_desc"))
        case "FGBS":
            return .init("building.columns.fill", .teal,
                String(localized: "instrument_schatz"),
                String(localized: "instrument_schatz_desc"))

        // SGX — Asian international futures
        case "CN":
            return .init("chart.bar.fill", .red,
                String(localized: "instrument_china_a50"),
                String(localized: "instrument_china_a50_desc"))
        case "NK":
            return .init("chart.line.uptrend.xyaxis", .pink,
                String(localized: "instrument_nikkei225"),
                String(localized: "instrument_nikkei225_desc"))
        case "FEF":
            return .init("cube.fill", .brown,
                String(localized: "instrument_iron_ore"),
                String(localized: "instrument_iron_ore_desc"))

        // Agriculture
        case "ZW", "W", "WHEAT":
            return .init("leaf.fill", .green,
                String(localized: "instrument_wheat"),
                String(localized: "instrument_wheat_desc"))
        case "SUGR", "SUGAR", "SU":
            return .init("leaf.fill", .pink,
                String(localized: "instrument_sugar"),
                String(localized: "instrument_sugar_desc"))
        case "ZC", "CORN":
            return .init("leaf.fill", .yellow,
                String(localized: "instrument_corn"),
                String(localized: "instrument_corn_desc"))

        // Blue-chip equities — MOEX
        case "SBRF", "SBER", "SBPR", "GAZR", "GAZP", "LKOH", "ROSN",
             "VTBR", "GMKN", "MGNT", "MTSI", "AFLT", "YNDX", "TATN", "NLMK":
            return .init("building.columns.fill", .teal)

        // Fallback
        default:
            return .init("chart.line.uptrend.xyaxis", .gray, isFallback: true)
        }
    }
}

/// Material- and brand-accurate tints for instruments whose real-world colour has
/// no close SwiftUI system equivalent (metals read as washed-out yellows/grays
/// otherwise; crypto has well-known brand colours).
private extension Color {
    static let gold      = Color(red: 0.83, green: 0.69, blue: 0.22) // #D4AF37 metallic gold
    static let silver    = Color(red: 0.75, green: 0.75, blue: 0.75) // #C0C0C0 metallic silver
    static let platinum  = Color(red: 0.60, green: 0.64, blue: 0.67) // brushed platinum grey
    static let palladium = Color(red: 0.72, green: 0.75, blue: 0.78) // pale steely palladium
    static let copper    = Color(red: 0.72, green: 0.45, blue: 0.20) // #B87333 copper
    static let bitcoin   = Color(red: 0.97, green: 0.58, blue: 0.10) // #F7931A Bitcoin orange
    static let ethereum  = Color(red: 0.38, green: 0.49, blue: 0.92) // #627EEA Ethereum blue
}
