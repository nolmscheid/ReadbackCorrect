// ReadbackEngine/PhraseBank/PhraseBankLoader.swift
// Loads phrase_bank.json from a bundle (test or app).

import Foundation

public enum PhraseBankLoader {
    /// Locates phrase_bank.json in the given bundle and decodes to [PhraseCase].
    /// Tries: resource "phrase_bank" ofType "json", then "fixtures/phrase_bank.json", then "PhraseBank/phrase_bank.json".
    public static func loadFromBundle(_ bundle: Bundle) throws -> [PhraseCase] {
        let decoder = JSONDecoder()
        if let url = bundle.url(forResource: "phrase_bank", withExtension: "json", subdirectory: nil),
           let data = try? Data(contentsOf: url) {
            return try decoder.decode([PhraseCase].self, from: data)
        }
        if let url = bundle.url(forResource: "phrase_bank", withExtension: "json", subdirectory: "fixtures"),
           let data = try? Data(contentsOf: url) {
            return try decoder.decode([PhraseCase].self, from: data)
        }
        if let resourceURL = bundle.resourceURL {
            let fixtures = resourceURL.appendingPathComponent("fixtures", isDirectory: true).appendingPathComponent("phrase_bank.json")
            if let data = try? Data(contentsOf: fixtures) {
                return try decoder.decode([PhraseCase].self, from: data)
            }
            let phraseBank = resourceURL.appendingPathComponent("PhraseBank", isDirectory: true).appendingPathComponent("phrase_bank.json")
            if let data = try? Data(contentsOf: phraseBank) {
                return try decoder.decode([PhraseCase].self, from: data)
            }
        }
        throw NSError(domain: "PhraseBankLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "phrase_bank.json not found in bundle"])
    }
}
