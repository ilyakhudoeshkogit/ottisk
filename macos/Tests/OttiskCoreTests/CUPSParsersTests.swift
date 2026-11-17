import XCTest
@testable import OttiskCore

final class CUPSParsersTests: XCTestCase {
    func testPrinterStatusIdlePrintingDisabled() {
        let out = """
        printer Canon_MF3010 is idle.  enabled since Fri Nov 13 10:00:00 2026
        printer Office-Laser now printing Office-Laser-17.  enabled since Fri Nov 13 09:00:00 2026
        \tSending data to printer.
        printer Old_HP disabled since Thu Nov 12 18:00:00 2026 -
        \tPaused
        """
        let p = CUPSParsers.parsePrinterStatus(out)
        XCTAssertEqual(p.map(\.name), ["Canon_MF3010", "Office-Laser", "Old_HP"])
        XCTAssertEqual(p[0].stateCode, 3)
        XCTAssertEqual(p[1].stateCode, 4)
        XCTAssertEqual(p[1].currentJobID, "Office-Laser-17")
        XCTAssertEqual(p[1].message, "Sending data to printer.")
        XCTAssertEqual(p[2].stateCode, 5)
        XCTAssertEqual(p[2].message, "Paused")
    }

    func testPrinterStatusLongForm() {
        let out = """
        printer Canon_MF3010 is idle.  enabled since Fri Nov 13 10:00:00 2026
        \tForm mounted:
        \tContent types: any
        \tPrinter types: unknown
        \tDescription: Canon MF3010
        \tAlerts: media-empty-error toner-low-warning
        \tLocation: Заславль
        \tConnection: direct
        """
        let p = CUPSParsers.parsePrinterStatus(out)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].description, "Canon MF3010")
        XCTAssertEqual(p[0].location, "Заславль")
        XCTAssertEqual(p[0].alerts, ["media-empty-error", "toner-low-warning"])
        XCTAssertNil(p[0].message)
    }

    func testDefaultDestination() {
        XCTAssertEqual(CUPSParsers.parseDefaultDestination("system default destination: Canon_MF3010\n"), "Canon_MF3010")
        XCTAssertNil(CUPSParsers.parseDefaultDestination("no system default destination\n"))
    }

    func testDeviceURIs() {
        let out = """
        device for Canon_MF3010: usb://Canon/MF3010?serial=0000A1B2C3D4
        device for Office-Laser: ipp://192.168.1.20/ipp/print
        """
        let map = CUPSParsers.parseDeviceURIs(out)
        XCTAssertEqual(map["Canon_MF3010"], "usb://Canon/MF3010?serial=0000A1B2C3D4")
        XCTAssertEqual(map["Office-Laser"], "ipp://192.168.1.20/ipp/print")
    }

    func testAccepting() {
        let out = """
        Canon_MF3010 accepting requests since Fri Nov 13 10:00:00 2026
        Old_HP not accepting requests since Thu Nov 12 18:00:00 2026 -
        \tRejecting Jobs
        """
        XCTAssertEqual(CUPSParsers.parseAccepting(out), ["Canon_MF3010": true, "Old_HP": false])
    }

    func testJobs() {
        let out = """
        Canon_MF3010-41         ilya            102400   Fri Nov 13 10:00:00 2026
        Office-Laser-7          ilya              2048   Fri Nov 13 10:01:12 2026
        """
        let jobs = CUPSParsers.parseJobs(out, activeJobIDs: ["Canon_MF3010-41"])
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].printer, "Canon_MF3010")
        XCTAssertEqual(jobs[0].number, 41)
        XCTAssertEqual(jobs[0].sizeBytes, 102400)
        XCTAssertEqual(jobs[0].dateText, "Fri Nov 13 10:00:00 2026")
        XCTAssertTrue(jobs[0].isActive)
        XCTAssertEqual(jobs[1].printer, "Office-Laser")
        XCTAssertEqual(jobs[1].number, 7)
        XCTAssertFalse(jobs[1].isActive)
    }

    func testSplitJobID() {
        XCTAssertNil(CUPSParsers.splitJobID("nojob"))
        XCTAssertNil(CUPSParsers.splitJobID("-5"))
        XCTAssertEqual(CUPSParsers.splitJobID("A-B-C-12")?.0, "A-B-C")
    }

    func testRequestID() {
        XCTAssertEqual(CUPSParsers.parseRequestID("request id is Canon_MF3010-42 (1 file(s))\n"), "Canon_MF3010-42")
        XCTAssertNil(CUPSParsers.parseRequestID("lp: Unsupported document-format"))
    }

    func testOptionList() {
        let out = """
        PageSize/Media Size: Letter *A4 Legal A5 Env10
        Resolution/Resolution: *600dpi 300dpi
        CNTonerSaving/Toner Save: *False True
        ColorModel: *Gray
        """
        let o = CUPSParsers.parseOptionList(out)
        XCTAssertEqual(o.count, 4)
        XCTAssertEqual(o[0].key, "PageSize")
        XCTAssertEqual(o[0].label, "Media Size")
        XCTAssertEqual(o[0].defaultChoice, "A4")
        XCTAssertEqual(o[0].choices, ["Letter", "A4", "Legal", "A5", "Env10"])
        XCTAssertEqual(o[3].key, "ColorModel")
        XCTAssertEqual(o[3].label, "ColorModel")
    }

    func testKeyValuesWithQuotesAndEscapes() {
        let out = "copies=1 device-uri=usb://Canon/MF3010?serial=123 printer-info='Canon MF3010' printer-location=Office\\ 2 printer-make-and-model=\"Canon MF3010\" printer-state=3 printer-state-reasons=media-empty-error,toner-low-warning printer-is-accepting-jobs=true printer-is-shared=false"
        let kv = CUPSParsers.parseKeyValues(out)
        XCTAssertEqual(kv["printer-info"], "Canon MF3010")
        XCTAssertEqual(kv["printer-location"], "Office 2")
        XCTAssertEqual(kv["printer-make-and-model"], "Canon MF3010")
        XCTAssertEqual(kv["printer-state"], "3")
        XCTAssertEqual(kv["device-uri"], "usb://Canon/MF3010?serial=123")

        let printer = CUPSParsers.printer(named: "Canon_MF3010", attributes: kv, isDefault: true)
        XCTAssertTrue(printer.isUSB)
        XCTAssertTrue(printer.looksLikeMF3010)
        XCTAssertEqual(printer.stateReasons, ["media-empty-error", "toner-low-warning"])
        XCTAssertEqual(printer.condition, .paperOut)
        XCTAssertEqual(printer.displayName, "Canon MF3010")
    }
}

final class StatusTests: XCTestCase {
    func testConditions() {
        func c(_ code: Int?, _ r: [String], accepting: Bool = true, msg: String? = nil) -> PrinterCondition {
            PrinterStatusInterpreter.condition(stateCode: code, reasons: r, message: msg, accepting: accepting)
        }
        XCTAssertEqual(c(3, []), .ready)
        XCTAssertEqual(c(3, ["none"]), .ready)
        XCTAssertEqual(c(4, []), .printing)
        XCTAssertEqual(c(3, ["toner-low-warning"]), .tonerLow)
        XCTAssertEqual(c(4, ["toner-low-report"]), .printing)
        XCTAssertEqual(c(5, ["paused"]), .paused)
        XCTAssertEqual(c(3, ["media-jam-error"]), .paperJam)
        XCTAssertEqual(c(3, ["offline-report"]), .offline)
        XCTAssertEqual(c(3, ["cover-open-error"]), .coverOpen)
        XCTAssertEqual(c(5, [], msg: "Unable to open device"), .error("Unable to open device"))
        XCTAssertEqual(c(3, [], accepting: false), .paused)
        XCTAssertEqual(c(nil, []), .unknown)
        XCTAssertTrue(PrinterCondition.tonerLow.isUsable)
        XCTAssertFalse(PrinterCondition.paperOut.isUsable)
    }
}
