import Foundation

enum ShellCommandTokenizer {
    static func split(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false
        var hasToken = false

        for character in command {
            if isEscaping {
                current.append(character)
                hasToken = true
                isEscaping = false
                continue
            }

            if character == "\\", quote != "'" {
                isEscaping = true
                hasToken = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                hasToken = true
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                hasToken = true
                continue
            }

            if character.isShellWhitespace {
                if hasToken {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }

            current.append(character)
            hasToken = true
        }

        if isEscaping {
            current.append("\\")
        }
        if hasToken {
            tokens.append(current)
        }
        return tokens
    }

    static func join(_ tokens: [String]) -> String {
        tokens.map(quoteIfNeeded).joined(separator: " ")
    }

    private static func quoteIfNeeded(_ token: String) -> String {
        guard !token.isEmpty else { return "''" }
        if token.unicodeScalars.allSatisfy({ safeUnquotedScalars.contains($0) }) {
            return token
        }
        return "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let safeUnquotedScalars = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_-./:=,@%+"))
}

private extension Character {
    var isShellWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
