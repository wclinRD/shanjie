import AppKit
import CShanjie
import XCTest
@testable import ShanjieKit

/// S3b section 13.2 / Vocabulary.swift: the merged「自訂詞彙與選字記憶」view's data layer, through
/// the real C core and a temporary directory shared by the custom and learning stores.
///
/// VocabularyManager keeps `rows` and `loadWords()` private, so these tests cover the two stores it
/// merges (customVocabListAll + learningListAll), the source-routed removal
/// (customVocabRemove / learningForget), and build the manager on the same engine.
@MainActor
final class VocabularyTests: XCTestCase {
    private var resources: URL!

    override func setUp() async throws {
        resources = try XCTUnwrap(TestData.resources())
    }

    private func makeShell(learning: URL? = nil) -> Shell {
        let shell = Shell(resources: resources, panel: FakePanel(), isSecureInput: { false },
                          layoutStore: MemoryLayoutStore(), learningDirectory: learning, dialogs: FakeDialogs())
        XCTAssertNotNil(shell.engine)
        return shell
    }

    /// Types ㄋㄧˇ ㄏㄠˇ, picks the first two-character candidate and commits it (a two-character
    /// word learns under any context, s4-learning.md section 12); returns the learned word.
    @discardableResult
    private func teachTwoCharacterWord(_ c: Controller) throws -> String {
        c.session.activate()
        c.type("su3cl3 ")
        let items = c.panel.items
        let i = try XCTUnwrap(items.indices.dropFirst().first { items[$0].count == 2 })
        XCTAssertLessThan(i, 9, "the two-character candidate is not on the first page")
        c.type("\(i + 1)")
        c.press(Keys.enter)
        return items[i]
    }

    /// The merged view's two halves: the custom store answers the added word, the learning store
    /// answers the taught word, and the manager is built on the same engine.
    func testDataLayerServesCustomAndMemoryRows() throws {
        let dir = TestLearning.directory()
        let c = Controller(makeShell(learning: dir))
        let engine = try XCTUnwrap(c.session.shell.engine)

        XCTAssertEqual(engine.customVocabAdd(reading: "ㄅㄚˇ-ㄅㄚˇ", word: "把手"), 0)
        let word = try teachTwoCharacterWord(c)

        XCTAssertTrue(engine.customVocabListAll().contains { $0.reading == "ㄅㄚˇ-ㄅㄚˇ" && $0.word == "把手" },
                      "the custom half answers the added word")
        XCTAssertTrue(engine.learningListAll().contains { $0.word == word },
                      "the memory half answers the taught word")

        let manager = VocabularyManager(engine: engine)
        XCTAssertEqual(manager.window.title, "自訂詞彙與選字記憶")
    }

    /// Removal routes to the right store, as the view's delete does: custom rows leave through
    /// customVocabRemove, memory rows through learningForget; each touches only its own store.
    func testRemovalRoutesToTheRightStore() throws {
        let dir = TestLearning.directory()
        let c = Controller(makeShell(learning: dir))
        let engine = try XCTUnwrap(c.session.shell.engine)
        XCTAssertEqual(engine.customVocabAdd(reading: "ㄅㄚˇ-ㄅㄚˇ", word: "把手"), 0)
        let word = try teachTwoCharacterWord(c)
        let record = try XCTUnwrap(engine.learningListAll().first { $0.word == word })

        // Custom row: removed from the custom store; the learning store is untouched.
        XCTAssertEqual(engine.customVocabRemove(reading: "ㄅㄚˇ-ㄅㄚˇ", word: "把手"), 0)
        XCTAssertFalse(engine.customVocabListAll().contains { $0.word == "把手" })
        XCTAssertTrue(engine.learningListAll().contains { $0.word == word })

        // Memory row: forgotten; the custom store is untouched.
        XCTAssertEqual(engine.learningForget(reading: record.reading, word: record.word), 0)
        XCTAssertFalse(engine.learningListAll().contains { $0.word == word })
        XCTAssertFalse(engine.customVocabListAll().contains { $0.word == "把手" })
    }

    /// After a forget, the learning half of the merged data is updated at once: what loadWords()
    /// merges (learningListAll) no longer carries the forgotten word, while the custom half still
    /// serves its words.
    func testForgetUpdatesTheDataTheViewLoads() throws {
        let dir = TestLearning.directory()
        let c = Controller(makeShell(learning: dir))
        let engine = try XCTUnwrap(c.session.shell.engine)
        XCTAssertEqual(engine.customVocabAdd(reading: "ㄅㄚˇ-ㄅㄚˇ", word: "把手"), 0)
        let word = try teachTwoCharacterWord(c)
        let record = try XCTUnwrap(engine.learningListAll().first { $0.word == word })

        XCTAssertEqual(engine.learningForget(reading: record.reading, word: record.word), 0)
        XCTAssertFalse(engine.learningListAll().contains { $0.word == word },
                       "the memory half no longer carries the forgotten word")
        XCTAssertTrue(engine.customVocabListAll().contains { $0.reading == "ㄅㄚˇ-ㄅㄚˇ" && $0.word == "把手" },
                      "the custom half is unchanged by a forget")
    }
}