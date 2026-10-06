import CShanjie

/// One output of the core, copied into Swift values in the call that received it; the C output is
/// freed before this is returned (docs/contracts/s3b.md section 7).
///
/// R2: this holds user input. It is deliberately not an `Error` and not `CustomStringConvertible`
/// or `CustomDebugStringConvertible`, so it cannot reach a crash report or a log by description.
struct CoreOutput {
    var handled: Bool
    var commit: String
    var preedit: String
    var cursorUTF16: Int
    var candidates: [String]
    var selected: Int
    /// s3b2 section 8.2: 0 = collapsed single row, > 0 = expanded grid with this many columns.
    var columns: Int
    /// Position of `candidates[0]` in the whole list, and the whole list's length (scroll bar).
    var first: Int
    var total: Int
    /// Quick add prompt text shown when the user enters quick add mode (Ctrl+Enter).
    var quickAddPrompt: String?
}

/// The result of a core call: an output, or the non-zero C ABI return code (carries no input).
enum CoreResult {
    case ok(CoreOutput)
    case failed(Int32)
}

/// One learned record (S4 section 4 / shanjie.h learning_list_all), copied out of the C output
/// before it is freed. R2: these are learned words; never log them.
struct LearningEntry {
    var context: String
    var reading: String
    var word: String
    var weight: Double
    var day: Int64
}

/// Owns one `ShanjieEngine` handle. Every call is on the main thread (IMK's callback thread), as
/// the handle is not thread-safe (s3a section 6).
@MainActor
final class CoreEngine {
    private let handle: OpaquePointer

    private init(handle: OpaquePointer) { self.handle = handle }

    /// `shanjie_engine_new`; on failure returns the code and nothing is allocated.
    static func make(dataDir: String, layout: UInt32) -> (CoreEngine?, Int32) {
        var out: OpaquePointer?
        let code = shanjie_engine_new(dataDir, layout, &out)
        guard code == 0, let out else { return (nil, code == 0 ? 4 : code) }
        return (CoreEngine(handle: out), 0)
    }

    isolated deinit { shanjie_engine_free(handle) }

    func loadLM(path: String) -> Int32 { shanjie_engine_load_lm(handle, path) }

    /// s3e: replace the punctuation alternatives; 0 on success, 2 on an invalid table (kept as before).
    func setPunctuation(_ table: String) -> Int32 { shanjie_engine_set_punctuation(handle, table) }

    // S4 (docs/contracts/s4-learning.md sections 2-4); each returns the C ABI code.

    /// `nil` means no left context (NULL).
    func setLeftContext(_ text: String?) -> Int32 {
        guard let text else { return shanjie_engine_set_left_context(handle, nil) }
        return text.withCString { shanjie_engine_set_left_context(handle, $0) }
    }

    func setLearning(_ enabled: Bool) -> Int32 { shanjie_engine_set_learning(handle, enabled ? 1 : 0) }

    func learningOpen(dir: String) -> Int32 { shanjie_engine_learning_open(handle, dir) }

    func learningClear() -> Int32 { shanjie_engine_learning_clear(handle) }

    /// bit0: a full rewrite of the learning file failed and no full rewrite or clear has succeeded
    /// since (S4 section 4; a failed append that falls back to a successful rewrite does not set it).
    /// `nil` on a non-zero code.
    func learningStatus() -> UInt32? {
        var flags: UInt32 = 0
        return shanjie_engine_learning_status(handle, &flags) == 0 ? flags : nil
    }

    /// `learning_list_all` (shanjie.h): every record currently in memory, in store order. A record
    /// holding an interior NUL would make the whole call fail (code 4); a non-zero code returns [].
    func learningListAll() -> [LearningEntry] {
        var outHandle: OpaquePointer?
        let code = shanjie_engine_learning_list_all(handle, &outHandle)
        guard code == 0, let outHandle else { return [] }
        defer { shanjie_learning_output_free(outHandle) }

        let count = Int(shanjie_learning_output_count(outHandle))
        var entries: [LearningEntry] = []
        for i in 0..<count {
            let index = UInt32(i)
            let context = shanjie_learning_output_context(outHandle, index).map { String(cString: $0) } ?? ""
            let reading = shanjie_learning_output_reading(outHandle, index).map { String(cString: $0) } ?? ""
            let word = shanjie_learning_output_word(outHandle, index).map { String(cString: $0) } ?? ""
            entries.append(LearningEntry(
                context: context, reading: reading, word: word,
                weight: shanjie_learning_output_weight(outHandle, index),
                day: shanjie_learning_output_day(outHandle, index)))
        }
        return entries
    }

    /// `learning_forget` (shanjie.h): forgets `word` for `reading` under every context key, the same
    /// rule as ⌘⌫ on a highlighted candidate (s4-learning.md section 1.5). 0 on success; non-zero
    /// codes per shanjie.h (1 NULL, 2 not UTF-8, 3 the full rewrite failed).
    func learningForget(reading: String, word: String) -> Int32 {
        return reading.withCString { readingPtr in
            word.withCString { wordPtr in
                shanjie_engine_learning_forget(handle, readingPtr, wordPtr)
            }
        }
    }

    // Custom vocabulary (ChiaKey integration)

    func customVocabOpen(dir: String) -> Int32 { shanjie_engine_custom_vocab_open(handle, dir) }

    func customVocabAdd(reading: String, word: String) -> Int32 {
        return reading.withCString { readingPtr in
            word.withCString { wordPtr in
                shanjie_engine_custom_vocab_add(handle, readingPtr, wordPtr)
            }
        }
    }

    func customVocabRemove(reading: String, word: String) -> Int32 {
        return reading.withCString { readingPtr in
            word.withCString { wordPtr in
                shanjie_engine_custom_vocab_remove(handle, readingPtr, wordPtr)
            }
        }
    }

    func customVocabFind(reading: String) -> [String] {
        var outHandle: OpaquePointer?
        let code = shanjie_engine_custom_vocab_find(handle, reading, &outHandle)
        guard code == 0, let outHandle else {
            return []
        }
        defer { shanjie_custom_vocab_free(outHandle) }

        let count = Int(shanjie_custom_vocab_output_count(outHandle))
        var words: [String] = []
        for i in 0..<count {
            if let wordPtr = shanjie_custom_vocab_output_word(outHandle, UInt32(i)) {
                words.append(String(cString: wordPtr))
            }
        }
        return words
    }

    func customVocabListAll() -> [(reading: String, word: String)] {
        var outHandle: OpaquePointer?
        let code = shanjie_engine_custom_vocab_list_all(handle, &outHandle)
        guard code == 0, let outHandle else {
            return []
        }
        defer { shanjie_custom_vocab_free(outHandle) }

        let count = Int(shanjie_custom_vocab_output_count(outHandle))
        var words: [(reading: String, word: String)] = []
        for i in 0..<count {
            if let pairPtr = shanjie_custom_vocab_output_word(outHandle, UInt32(i)) {
                let pair = String(cString: pairPtr)
                if let tabIndex = pair.firstIndex(of: "\t") {
                    let reading = String(pair[..<tabIndex])
                    let word = String(pair[(pair.index(after: tabIndex))...])
                    words.append((reading: reading, word: word))
                }
            }
        }
        return words
    }

    func customVocabImportKeykey(path: String) -> Int32 {
        return path.withCString { shanjie_engine_custom_vocab_import_keykey(handle, $0) }
    }

    func customVocabImportCin(path: String) -> Int32 {
        return path.withCString { shanjie_engine_custom_vocab_import_cin(handle, $0) }
    }

    func key(_ key: ShanjieKey) -> CoreResult {
        var out: UnsafeMutablePointer<ShanjieOutput>?
        return Self.take(shanjie_engine_key(handle, key, &out), out)
    }

    /// s3b2 section 8.2 mouse pick: `index` is a position in the last output's candidates. Code 2
    /// when the candidates are closed or `index` is outside that output (state unchanged).
    func pick(_ index: UInt32) -> CoreResult {
        var out: UnsafeMutablePointer<ShanjieOutput>?
        return Self.take(shanjie_engine_pick(handle, index, &out), out)
    }

    /// mode 0 commits the composition then clears, 1 discards.
    func reset(mode: UInt32) -> CoreResult {
        var out: UnsafeMutablePointer<ShanjieOutput>?
        return Self.take(shanjie_engine_reset(handle, mode, &out), out)
    }

    /// profile 0 chat, 1 formal.
    func setProfile(_ profile: UInt32) -> CoreResult {
        var out: UnsafeMutablePointer<ShanjieOutput>?
        return Self.take(shanjie_engine_set_profile(handle, profile, &out), out)
    }

    /// Copies every field into Swift values, then frees the C output at once.
    private static func take(_ code: Int32, _ out: UnsafeMutablePointer<ShanjieOutput>?) -> CoreResult {
        guard code == 0, let out else {
            shanjie_output_free(out)  // NULL on a non-zero code (s3a section 6); freeing NULL is a no-op
            return .failed(code == 0 ? 4 : code)
        }
        defer { shanjie_output_free(out) }
        let o = out.pointee
        var candidates: [String] = []
        if let list = o.candidates {
            for i in 0..<Int(o.candidate_count) {
                if let c = list[i] { candidates.append(String(cString: c)) }
            }
        }
        let quickAddPrompt = o.quick_add_prompt == nil ? nil : String(cString: o.quick_add_prompt)
        return .ok(CoreOutput(
            handled: o.handled != 0,
            commit: String(cString: o.commit),
            preedit: String(cString: o.preedit),
            cursorUTF16: Int(o.cursor_utf16),
            candidates: candidates,
            selected: Int(o.candidate_selected),
            columns: Int(o.candidate_columns),
            first: Int(o.candidate_first),
            total: Int(o.candidate_total),
            quickAddPrompt: quickAddPrompt
        ))
    }
}
