import CoreFoundation
import Foundation

public enum FilenameEncoding {
    public static func nsStringEncoding(for option: FilenameEncodingOption) -> String.Encoding {
        switch option {
        case .auto, .utf8:
            return .utf8
        case .gb18030:
            let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        case .big5:
            let cf = CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        case .shiftJIS:
            let cf = CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        case .eucKR:
            let cf = CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        case .cp437:
            let cf = CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
    }

    public static func encode(_ string: String, option: FilenameEncodingOption) -> (data: Data, isUTF8: Bool) {
        if option == .utf8 || option == .auto {
            return (Data(string.utf8), true)
        }
        let enc = nsStringEncoding(for: option)
        if let data = string.data(using: enc) {
            return (data, false)
        }
        return (Data(string.utf8), true)
    }

    public static func decode(
        _ data: Data,
        hasUTF8Flag: Bool,
        unicodeExtraPath: String? = nil,
        preferred: FilenameEncodingOption = .auto
    ) -> String {
        if let unicodeExtraPath, preferred == .auto || preferred == .utf8 {
            return unicodeExtraPath
        }
        if preferred != .auto {
            let enc = nsStringEncoding(for: preferred)
            if let decoded = String(data: data, encoding: enc) {
                return decoded
            }
        }
        if hasUTF8Flag, let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // Pure ASCII fast path
        if data.allSatisfy({ $0 < 0x80 }), let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        // Valid multi-byte UTF-8 without bit 11 set
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // Score CJK legacy Windows codepages (fixes garbled Chinese/Japanese/Korean ZIP names from Windows)
        let candidates: [(FilenameEncodingOption, Int)] = [
            (.gb18030, scoreGBK(data)),
            (.shiftJIS, scoreShiftJIS(data)),
            (.big5, scoreBig5(data)),
            (.eucKR, 1),
            (.cp437, 0)
        ]
        for (opt, _) in candidates.sorted(by: { $0.1 > $1.1 }) {
            if let decoded = String(data: data, encoding: nsStringEncoding(for: opt)) {
                return decoded
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func scoreGBK(_ data: Data) -> Int {
        var score = 0
        var i = 0
        let bytes = [UInt8](data)
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if i + 1 < bytes.count, b >= 0x81 && b <= 0xFE {
                let b2 = bytes[i + 1]
                if (b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFE) {
                    // Boost common GB2312 Chinese character block (0xB0..0xF7, 0xA1..0xFE)
                    score += (b >= 0xB0 && b <= 0xF7 && b2 >= 0xA1 && b2 <= 0xFE) ? 4 : 2
                    i += 2
                } else {
                    score -= 3
                    i += 1
                }
            } else {
                score -= 3
                i += 1
            }
        }
        return score
    }

    private static func scoreBig5(_ data: Data) -> Int {
        var score = 0
        var i = 0
        let bytes = [UInt8](data)
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if i + 1 < bytes.count, b >= 0xA1 && b <= 0xF9 {
                let b2 = bytes[i + 1]
                if (b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0xA1 && b2 <= 0xFE) {
                    score += 2
                    i += 2
                } else {
                    score -= 3
                    i += 1
                }
            } else {
                score -= 3
                i += 1
            }
        }
        return score
    }

    private static func scoreShiftJIS(_ data: Data) -> Int {
        var score = 0
        var i = 0
        let bytes = [UInt8](data)
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                i += 1
            } else if b >= 0xA1 && b <= 0xDF {
                // Half-width katakana
                score += 1
                i += 1
            } else if i + 1 < bytes.count, (b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xFC) {
                let b2 = bytes[i + 1]
                if (b2 >= 0x40 && b2 <= 0x7E) || (b2 >= 0x80 && b2 <= 0xFC) {
                    score += 2
                    i += 2
                } else {
                    score -= 3
                    i += 1
                }
            } else {
                score -= 3
                i += 1
            }
        }
        return score
    }
}
