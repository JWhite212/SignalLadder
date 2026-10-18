import Foundation

/// A rules file at `version` holding `rules`, each a rule's JSON object as
/// written, joined with commas (#95). It was once written out in eight places.
func rulesFile(version: Int, _ rules: String...) -> Data {
    Data("{\"version\": \(version), \"rules\": [\(rules.joined(separator: ", "))]}".utf8)
}
