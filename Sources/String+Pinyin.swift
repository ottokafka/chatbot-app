import Foundation

extension Unicode.Scalar {
    /// CJK Unified Ideographs (4E00–9FFF) + Ext A (3400–4DBF) + Compatibility (F900–FAFF).
    /// Single source of truth for ideograph detection used by `String.containsChineseCharacters`
    /// and practice scaffold CJK run extraction.
    var isCJKIdeograph: Bool {
        let value = value
        return (value >= 0x4E00 && value <= 0x9FFF)
            || (value >= 0x3400 && value <= 0x4DBF)
            || (value >= 0xF900 && value <= 0xFAFF)
    }
}

extension String {
    /// Converts Chinese characters to Pinyin with phonetic tone marks.
    /// Example: "上海" -> "shàng hǎi"
    func toPinyin() -> String? {
        return self.applyingTransform(.mandarinToLatin, reverse: false)
    }
    
    /// Checks if the string contains any Chinese characters.
    var containsChineseCharacters: Bool {
        return unicodeScalars.contains { $0.isCJKIdeograph }
    }
    
    /// Checks if the string contains any Japanese characters (Hiragana or Katakana).
    var containsJapaneseCharacters: Bool {
        return unicodeScalars.contains { scalar in
            let value = scalar.value
            return (value >= 0x3040 && value <= 0x309F) ||
                   (value >= 0x30A0 && value <= 0x30FF)
        }
    }
    
    /// Checks if the string contains any Latin letters (standard English alphabet).
    var containsLatinCharacters: Bool {
        return unicodeScalars.contains { scalar in
            let value = scalar.value
            return (value >= 0x0041 && value <= 0x005A) || // A-Z
                   (value >= 0x0061 && value <= 0x007A)    // a-z
        }
    }
    
    /// Detects the language tag ("zh-Hans", "ja", "en") using fallback character checks.
    func detectedLanguage() -> String {
        if containsChineseCharacters {
            return "zh-Hans"
        }
        if containsJapaneseCharacters {
            return "ja"
        }
        if containsLatinCharacters {
            return "en"
        }
        return "en"
    }
    
    /// Returns true if the language is Chinese.
    func isChinese() -> Bool {
        return containsChineseCharacters || detectedLanguage() == "zh-Hans"
    }
}
