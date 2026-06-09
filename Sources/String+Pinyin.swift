import Foundation

extension String {
    /// Converts Chinese characters to Pinyin with phonetic tone marks.
    /// Example: "上海" -> "shàng hǎi"
    func toPinyin() -> String? {
        return self.applyingTransform(.mandarinToLatin, reverse: false)
    }
    
    /// Checks if the string contains any Chinese characters.
    var containsChineseCharacters: Bool {
        return unicodeScalars.contains { scalar in
            let value = scalar.value
            // Common CJK Unified Ideographs: 4E00–9FFF
            // CJK Extension A: 3400–4DBF
            // CJK Compatibility Ideographs: F900–FAFF
            return (value >= 0x4E00 && value <= 0x9FFF) ||
                   (value >= 0x3400 && value <= 0x4DBF) ||
                   (value >= 0xF900 && value <= 0xFAFF)
        }
    }
}
