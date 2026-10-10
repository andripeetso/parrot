import Foundation

/// Fills a dictation's `TranscriptionContext` from the dictionary: the example
/// sentence for the active language as the prompt, and the canonical spellings
/// as the vocabulary. In Automatic the language is unknown until the engine
/// hears it, so every example sentence goes along and the engine picks the one
/// for the language it settled on.
package struct DictionaryContext {
    package let store: DictionaryStore
    /// The language being spoken, when known. Without it the prompt is left
    /// to the engine, from `examples`.
    package let language: String?
    /// The example sentences, by language code, from `settings.json`
    /// (`dictionary.examples`).
    package let examples: [String: String]

    package init(store: DictionaryStore, language: String?, examples: [String: String] = [:]) {
        self.store = store
        self.language = language
        self.examples = examples
    }

    package func context() -> TranscriptionContext {
        TranscriptionContext(
            language: language,
            prompt: UserDictionary(examples: examples).example(for: language),
            vocabulary: store.current().dictionary.vocabulary,
            examples: language == nil ? examples : [:]
        )
    }

    /// The example sentences saved in `settings.json`, read directly for
    /// tools that run without a `SettingsStore` (which is `@MainActor`), such
    /// as `parrot-bench`. Empty when the file is missing or doesn't parse.
    package static func savedExamples() -> [String: String] {
        savedExamples(in: Paths.settingsFile)
    }

    package static func savedExamples(in file: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(DictionaryOnly.self, from: data)
        else { return [:] }
        return settings.dictionary.examples
    }

    /// The one key of `settings.json` the engine reads, so it decodes no
    /// other feature's settings. A missing key is the default, as in the
    /// full settings value.
    private struct DictionaryOnly: Decodable {
        package var dictionary = DictionarySettings()

        package init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dictionary = try c.decodeIfPresent(DictionarySettings.self, forKey: .dictionary) ?? DictionarySettings()
        }

        private enum CodingKeys: String, CodingKey { case dictionary }
    }

    /// The language a model will hear, when that is certain without a
    /// setting: a single-language model such as `whisper-base.en`. Nil for
    /// multilingual models, whose language comes from the Language setting or
    /// detection: an example sentence in the wrong language drags the decoder
    /// into it (#23).
    package static func knownLanguage(of model: TranscriptionModel) -> String? {
        guard model.languages.count == 1, let only = model.languages.first, only != "multi" else { return nil }
        return only
    }

    /// The language `model` will be told to expect: its only language, or
    /// the Language setting `setting` if the model supports it. Nil for
    /// Automatic.
    package static func language(of model: TranscriptionModel, setting: String?) -> String? {
        if let only = knownLanguage(of: model) { return only }
        if let code = setting?.lowercased(), model.isMultilingual, model.supportedLanguages.contains(code) { return code }
        return nil
    }
}
