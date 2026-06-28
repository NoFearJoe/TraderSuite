# TraderSuite — guidance for Claude Code

iOS + macOS app (SwiftUI, Swift 6) that helps futures traders size positions.
First exchange: MOEX. Architecture is exchange-pluggable from day one.

## Build & test

- Logic lives in the local SwiftPM package `TraderSuiteKit`.
- Run tests: `cd TraderSuiteKit && swift test` (or Cmd+U in Xcode).
- The app target itself is an Xcode Multiplatform App (see `App/` + README); the
  `.xcodeproj` is created in Xcode and is not checked in by the scaffold.
- This code uses Apple frameworks (SwiftUI/SwiftData) — it only compiles on macOS
  with the Swift 6 toolchain / Xcode. Do not assume it builds on Linux CI.

## Module graph

```
Core         (no deps)        domain models + calculation engine
ExchangeKit  -> Core          exchange adapter protocol, registry, MoexAdapter (ISS)
Persistence  -> Core          SwiftData models + container (CloudKit-ready)
Features     -> Core,         SwiftUI screens + @Observable view models
                ExchangeKit,
                Persistence
App          -> Features      @main, injects ModelContainer
```

## Conventions (do not regress)

- Swift 6 language mode, full data-race safety. Public domain types are `Sendable`.
- ALL monetary math uses `Decimal`, never `Double`. Round to the contract tick.
- The calculation engine (`Core`) is pure and deterministic — no I/O, no UI. Keep it
  that way and cover changes with tests.
- Networking goes in actors (`ISSClient`). Parsing is pure and lives apart from the
  network so it stays unit-testable (`MoexParsing`).
- SwiftData models keep CloudKit rules: default values, no `.unique`, optional
  relationships (so sync can be switched on without a migration).
- Rollover/expiration is exchange-agnostic: resolve the front contract via
  `ExchangeAdapter.frontInstrument(family:)` (symbol + expiration) and
  `InstrumentSelection.frontContract`; never reach into MOEX-specific parsing
  from `Features`. Date math for expiry uses Europe/Moscow to match ISS dates.
- System side effects (notifications) sit behind a `Sendable` protocol seam
  (`NotificationScheduling`) so view models stay testable; the real impl wraps
  `UNUserNotificationCenter`, tests/previews use the no-op variant.
- UI follows MVVM: `@Observable @MainActor` view models hold the input/parse
  logic and stay free of SwiftUI, so they're unit-tested in `FeaturesTests`.
  Shared dependencies (stores, `SpecProvider`, registry, active deposit) live in
  `AppEnvironment`, injected via `.environment(...)`. Number input is parsed with
  `parseDecimal` (tolerates comma + grouping spaces); money math stays `Decimal`.
- Persistence access goes through `@MainActor` stores (`DepositStore`,
  `WatchlistStore`, `SpecCache`) over a `ModelContext` — never touch SwiftData
  from Core/ExchangeKit. Stores take exchange identity as a raw string
  (`ExchangeID.rawValue`); `Persistence` does not depend on `ExchangeKit`.
- CloudKit sync is OFF by default (`PersistenceContainer.make` →
  `CloudKitMode.disabled`) so local ad-hoc-signed builds work; enabling it needs
  the iCloud entitlement + a Development Team.
- GOTCHA: a SwiftData `ModelContext` does NOT retain its `ModelContainer`. Keep
  the container alive for as long as any context/store derived from it is in use
  (the app holds it in `@main`; tests store it as a suite property) — otherwise
  `save()` traps with SIGTRAP.
- Minimal formatting in user-facing copy; UI strings are RU (localization RU/EN later).

## Status

- Phase 0 (foundation): DONE — module scaffold, app entry, Swift 6.
- Phase 1 (calculation engine): DONE — position sizing, averaging, R:R, breakeven; tested.
- Phase 2 (MOEX data layer): DONE — `MoexAdapter` over ISS API, parsing tested.
- Phase 3 (persistence + CloudKit): DONE — SwiftData stores (`DepositStore`,
  `WatchlistStore`, `SpecCache`), CloudKit-opt-in container, and the
  `SpecProvider` cache-first seam (Features) wiring the cache to live adapters.
  Covered by `PersistenceTests` + `FeaturesTests`.
- Phase 4 (UI: calc + averaging screens, deposit management): DONE — live calc,
  averaging and deposits tabs over `AppEnvironment`; view models in `Features`
  tested. Watchlist tab is still a Phase 5 placeholder.
- Phase 5 (watchlist, expiration notifications, auto-rollover): DONE — watchlist
  track an instrument family + active front contract (`WatchlistViewModel`),
  expiration status is computed in `ExpirationPolicy`, expired contracts auto-roll
  via `ExchangeAdapter.frontInstrument`, and local reminders are scheduled through
  the `NotificationScheduling` seam. Tested in `FeaturesTests`/`ExchangeKitTests`.
- Phase 6 (StoreKit 2 subscription + paywall gating): NEXT.
- Phase 7 (localization RU/EN, dark mode, macOS polish).
- Phase 8 (test coverage, TestFlight, App Store).

## Domain rules that matter

Position sizing (per lot, round-trip commission included):
```
riskMoney   = deposit * riskPercent
lossPerLot  = adverseTicks(entry, stop) * stepPrice
riskPerLot  = lossPerLot + commissionRoundTrip
lotsByRisk  = floor(riskMoney / riskPerLot)
lotsByMargin= floor(deposit / initialMargin)
recommended = min(lotsByRisk, lotsByMargin)
```

Averaging: a single common stop on all legs; budget grows per leg.
```
positionCount = existing.count + 1        // OPEN ASSUMPTION: counts the NEW leg too
riskBudget    = deposit * riskPercent * positionCount
newLots       = floor((riskBudget - existingRiskAtStop) / riskPerNewLot)   // margin-capped
```
A leg in profit at the common stop contributes NEGATIVE risk (frees budget). Do not
"fix" this. The `positionCount` definition is unconfirmed with the product owner —
flag before changing it.

## Verified MOEX ISS field mapping (FORTS `securities` block)

```
symbol             <- SECID
family             <- ASSETCODE
displayName        <- SHORTNAME
minStep            <- MINSTEP
stepPrice          <- STEPPRICE
initialMargin (ГО) <- INITIALMARGIN
exchangeFeePerSide <- BUYSELLFEE
expiration         <- LASTTRADEDATE   (YYYY-MM-DD, Europe/Moscow)
```
ISS JSON is a dict of blocks, each with `columns` + `data`. Numbers are decoded as
`Decimal`. All FORTS contracts are dated (perpetual support is for future exchanges).

## Adding a new exchange

Conform a new type to `ExchangeAdapter`, add a case to `ExchangeID`, register it in
`ExchangeRegistry`. No changes to `Core` or `Features` should be required.
