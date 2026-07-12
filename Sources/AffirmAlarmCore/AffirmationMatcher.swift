import Foundation

public enum AffirmationMatcher {
    public static func matches(transcript: String, target: String) -> Bool {
        normalize(transcript) == normalize(target)
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let alphanumericAndSpaces = lowered.unicodeScalars.map { scalar -> Character in
            (CharacterSet.alphanumerics.contains(scalar) || scalar == " ") ? Character(scalar) : " "
        }
        let collapsed = String(alphanumericAndSpaces)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }
}
