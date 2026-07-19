import Foundation

/// One timed lyric line (net-new — Song Gen does not parse LRC).
struct LRCLine: Equatable, Identifiable {
    let index: Int
    var id: Int { index }
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    /// Strip markdown fences / leading chatter and keep LRC-looking lines.
    static func extractLRCBlock(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip ``` / ```lrc fences
        if text.hasPrefix("```") {
            if let firstNL = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNL)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Keep only lines that look like LRC (or blank between them)
        let lines = text.components(separatedBy: .newlines)
        let kept = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            return t.hasPrefix("[")
        }
        return kept.joined(separator: "\n")
    }

    /// Parse LRC lines: `[mm:ss.xx]text` (xx optional, 1–3 digits).
    static func parse(_ raw: String) -> [LRCLine] {
        let block = extractLRCBlock(raw)
        let pattern = #"^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        var result: [LRCLine] = []
        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
                  match.numberOfRanges >= 5,
                  let minR = Range(match.range(at: 1), in: trimmed),
                  let secR = Range(match.range(at: 2), in: trimmed),
                  let textR = Range(match.range(at: 4), in: trimmed)
            else { continue }

            let minutes = Double(trimmed[minR]) ?? 0
            let seconds = Double(trimmed[secR]) ?? 0
            var frac: Double = 0
            if match.range(at: 3).location != NSNotFound,
               let fracR = Range(match.range(at: 3), in: trimmed) {
                let fracStr = String(trimmed[fracR])
                let padded = fracStr.count >= 2
                    ? fracStr
                    : fracStr.padding(toLength: 2, withPad: "0", startingAt: 0)
                // Interpret as hundredths (2 digits) or milliseconds (3)
                if fracStr.count <= 2 {
                    frac = (Double(padded.prefix(2)) ?? 0) / 100.0
                } else {
                    frac = (Double(fracStr.prefix(3)) ?? 0) / 1000.0
                }
            }
            let time = minutes * 60 + seconds + frac
            let text = String(trimmed[textR]).trimmingCharacters(in: .whitespaces)
            result.append(LRCLine(index: result.count, time: time, text: text))
        }
        return result
    }

    /// Serialize lines back to LRC string.
    static func format(_ lines: [LRCLine]) -> String {
        lines.map { line in
            let totalCs = Int((line.time * 100).rounded())
            let mm = totalCs / 6000
            let ss = (totalCs % 6000) / 100
            let cs = totalCs % 100
            return String(format: "[%02d:%02d.%02d]%@", mm, ss, cs, line.text)
        }.joined(separator: "\n")
    }

    /// Build evenly spaced template lyrics from word pairs within duration.
    static func templateLyrics(
        words: [String],
        duration: Double = LifePathSongConfig.songDurationSeconds,
        minLines: Int = LifePathSongConfig.lyricsLineTargetMin
    ) -> String {
        let usable = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !usable.isEmpty else {
            return "[00:02.00]la la"
        }

        var pairs: [String] = []
        var i = 0
        while i < usable.count {
            if i + 1 < usable.count {
                pairs.append("\(usable[i]) \(usable[i + 1])")
                i += 2
            } else {
                pairs.append(usable[i])
                i += 1
            }
        }
        // Repeat to reach min lines
        if pairs.count < minLines {
            var expanded = pairs
            var k = 0
            while expanded.count < minLines {
                expanded.append(pairs[k % pairs.count])
                k += 1
            }
            pairs = expanded
        }
        // Cap
        if pairs.count > LifePathSongConfig.lyricsLineTargetMax {
            pairs = Array(pairs.prefix(LifePathSongConfig.lyricsLineTargetMax))
        }

        let start: Double = 2.0
        let end = max(start + 1, duration - 0.5)
        let step = pairs.count > 1 ? (end - start) / Double(pairs.count - 1) : 0

        var lines: [LRCLine] = []
        for (idx, text) in pairs.enumerated() {
            let t = start + step * Double(idx)
            lines.append(LRCLine(index: idx, time: t, text: text))
        }
        return format(lines)
    }
}
