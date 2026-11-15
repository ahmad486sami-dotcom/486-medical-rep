import Foundation

/// A plain spreadsheet: a title line, a "prepared by" line, then a bordered table.
struct SheetTable {
    var title: String
    var subtitle: String
    var headers: [String]
    var rows: [[String]]
    var widths: [Double] = []
}

/// Writes a minimal, real .xlsx file (Excel / Numbers / WhatsApp preview open it).
enum XLSX {
    static func write(_ table: SheetTable, fileName: String) throws -> URL {
        let files: [(String, String)] = [
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", rootRels),
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", workbookRels),
            ("xl/styles.xml", styles),
            ("xl/worksheets/sheet1.xml", sheet(table))
        ]
        let zip = Zip.make(files.map { ($0.0, Data($0.1.utf8)) })
        let safe = fileName.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe + ".xlsx")
        try? FileManager.default.removeItem(at: url)
        try zip.write(to: url, options: .atomic)
        return url
    }

    static func esc(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // Drop control characters Excel rejects (keep tab/newline).
                if ch.value < 0x20 && ch != "\n" && ch != "\t" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    static func col(_ i: Int) -> String {
        var n = i + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(Character(UnicodeScalar(UInt8(65 + r)))) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func cell(_ r: Int, _ c: Int, _ text: String, style: Int) -> String {
        "<c r=\"\(col(c))\(r)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(text))</t></is></c>"
    }

    static func sheet(_ t: SheetTable) -> String {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        x += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        x += "<cols>"
        for i in 0..<t.headers.count {
            let w = i < t.widths.count ? t.widths[i] : 16
            x += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>"
        }
        x += "</cols><sheetData>"
        x += "<row r=\"1\">" + cell(1, 0, t.title, style: 3) + "</row>"
        x += "<row r=\"2\">" + cell(2, 0, t.subtitle, style: 0) + "</row>"
        var r = 4
        x += "<row r=\"\(r)\">"
        for (i, h) in t.headers.enumerated() { x += cell(r, i, h, style: 2) }
        x += "</row>"
        for row in t.rows {
            r += 1
            x += "<row r=\"\(r)\">"
            for i in 0..<t.headers.count {
                x += cell(r, i, i < row.count ? row[i] : "", style: 1)
            }
            x += "</row>"
        }
        x += "</sheetData></worksheet>"
        return x
    }

    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    static let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    /// Styles: 0 plain, 1 bordered cell, 2 bold bordered header, 3 bold title.
    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/><bgColor indexed="64"/></patternFill></fill></fills>
    <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color auto="1"/></left><right style="thin"><color auto="1"/></right><top style="thin"><color auto="1"/></top><bottom style="thin"><color auto="1"/></bottom><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="4">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}

/// Tiny ZIP writer (stored, no compression) — enough for .xlsx.
enum Zip {
    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    static func make(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let hour: Int = comps.hour ?? 0
        let minute: Int = comps.minute ?? 0
        let second: Int = (comps.second ?? 0) / 2
        let year: Int = max((comps.year ?? 2026) - 1980, 0)
        let month: Int = comps.month ?? 1
        let day: Int = comps.day ?? 1
        let timeBits: Int = (hour << 11) | (minute << 5) | second
        let dateBits: Int = (year << 9) | (month << 5) | day
        let dosTime = UInt16(truncatingIfNeeded: timeBits)
        let dosDate = UInt16(truncatingIfNeeded: dateBits)

        for (name, content) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(content)
            let size = UInt32(content.count)
            let offset = UInt32(out.count)

            var local: [UInt8] = []
            local += le32(0x04034b50)
            local += le16(20); local += le16(0x0800); local += le16(0)
            local += le16(dosTime); local += le16(dosDate)
            local += le32(crc); local += le32(size); local += le32(size)
            local += le16(UInt16(nameData.count)); local += le16(0)
            out.append(contentsOf: local)
            out.append(nameData)
            out.append(content)

            var cd: [UInt8] = []
            cd += le32(0x02014b50)
            cd += le16(20); cd += le16(20); cd += le16(0x0800); cd += le16(0)
            cd += le16(dosTime); cd += le16(dosDate)
            cd += le32(crc); cd += le32(size); cd += le32(size)
            cd += le16(UInt16(nameData.count)); cd += le16(0); cd += le16(0)
            cd += le16(0); cd += le16(0); cd += le32(0)
            cd += le32(offset)
            central.append(contentsOf: cd)
            central.append(nameData)
        }

        let cdOffset = UInt32(out.count)
        out.append(central)
        var end: [UInt8] = []
        end += le32(0x06054b50)
        end += le16(0); end += le16(0)
        end += le16(UInt16(files.count)); end += le16(UInt16(files.count))
        end += le32(UInt32(central.count)); end += le32(cdOffset)
        end += le16(0)
        out.append(contentsOf: end)
        return out
    }
}
