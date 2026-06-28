import Testing
import Foundation
import Core
@testable import ExchangeKit

@Suite("MOEX parsing")
struct MoexParsingTests {

    // Sample ISS payload (numbers chosen to be exact; values are illustrative).
    private let sampleJSON = """
    {
      "securities": {
        "columns": ["SECID","SHORTNAME","ASSETCODE","LASTTRADEDATE","MINSTEP","STEPPRICE","INITIALMARGIN","BUYSELLFEE"],
        "data": [
          ["SiH6","Si-3.26","Si","2026-03-19",1,1,15000,1],
          ["SiM6","Si-6.26","Si","2026-06-18",1,1,15500,2],
          ["BRK6","BR-5.26","BR","2026-04-30",1,7,12000,3]
        ]
      }
    }
    """

    private func decode(_ json: String) throws -> ISSDocument {
        try JSONDecoder().decode(ISSDocument.self, from: Data(json.utf8))
    }

    @Test("Parses the instrument list")
    func parsesInstruments() throws {
        let doc = try decode(sampleJSON)
        let instruments = MoexParsing.parseInstruments(doc)
        #expect(instruments.count == 3)
        #expect(instruments.first?.symbol == "SiH6")
        #expect(instruments.first?.family == "Si")
        #expect(instruments.allSatisfy { !$0.isPerpetual })
    }

    @Test("Parses a contract spec with margin and fee")
    func parsesSpec() throws {
        let doc = try decode(sampleJSON)
        let spec = try MoexParsing.parseSpec(doc, symbol: "SiM6")
        #expect(spec.minStep == 1)
        #expect(spec.stepPrice == 1)
        #expect(spec.initialMargin == 15500)
        #expect(spec.exchangeFeePerSide == 2)
    }

    @Test("Missing required fields throws")
    func missingFieldsThrows() throws {
        let bad = """
        { "securities": { "columns": ["SECID"], "data": [["SiM6"]] } }
        """
        let doc = try decode(bad)
        #expect(throws: ExchangeError.self) {
            _ = try MoexParsing.parseSpec(doc, symbol: "SiM6")
        }
    }

    @Test("Front contract is the nearest non-expired one")
    func frontContract() throws {
        let doc = try decode(sampleJSON)
        let instruments = MoexParsing.parseInstruments(doc)
        let now = MoexParsing.parseDate("2026-06-14")!
        // SiH6 (2026-03-19) already expired; SiM6 (2026-06-18) is the front.
        let front = MoexParsing.frontContract(instruments, family: "Si", now: now)
        #expect(front?.symbol == "SiM6")
    }

    @Test("Date parsing")
    func dateParsing() {
        #expect(MoexParsing.parseDate("2026-06-18") != nil)
        #expect(MoexParsing.parseDate("nope") == nil)
    }
}
