import Foundation

/// Common domain service for parsing and sanitizing quick capture text across
/// the main app, widgets, and App Intents.
public enum QuickCaptureService {
    /// Splits raw input by newlines, trims whitespace from each line,
    /// strips bullet markers (-, *, •) or numbered prefixes (1., 1), etc.),
    /// and filters out empty lines.
    public static func parseTodoLines(_ text: String) -> [String] {
        parseTodoLines(from: text)
    }

    public static func parseTodoLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { stripBulletOrPrefix($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    /// Trims leading and trailing whitespace and newlines for memo text.
    public static func cleanMemoText(_ text: String) -> String {
        cleanMemoText(from: text)
    }

    public static func cleanMemoText(from text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripBulletOrPrefix(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let bullets: [Character] = ["-", "*", "•", "⁃", "◦", "▪", "▫", "‣"]
        if let first = trimmed.first, bullets.contains(first) {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }

        if let match = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            trimmed = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }

        return trimmed
    }
}
