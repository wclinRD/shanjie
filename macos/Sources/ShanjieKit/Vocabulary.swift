import AppKit

/// Vocabulary management UI: a merged view of the custom vocabulary (custom_vocab.tsv) and the
/// learned pick records (learning.tsv, S4). Every row carries its source; adding and importing
/// still operate on the custom vocabulary, and removing routes to the right store (custom remove /
/// learning forget, s4-learning.md section 1.5). Learned words are shown here only, never logged
/// (R2).
@MainActor
public final class VocabularyManager: NSObject {
    /// One row of the merged view.
    struct Row {
        enum Source {
            case custom
            case memory
        }

        var source: Source
        var reading: String
        var word: String
        /// memory rows only; empty / 0 for custom rows.
        var context = ""
        var weight = 0.0
        var day: Int64 = 0
    }

    private let engine: CoreEngine
    private var rows: [Row] = []
    private var selectedIndex: Int? = nil

    public let window: NSWindow
    private let tableView: NSTableView
    private let addTextField: NSTextField
    private let wordField: NSTextField
    private let addButton: NSButton
    private let removeButton: NSButton

    /// The merged list is sorted by reading, then word, then source (custom first): the entries of
    /// one reading sit together, so the user can compare the custom and learned words side by side.
    private static func sortRows(_ rows: [Row]) -> [Row] {
        rows.sorted { a, b in
            if a.reading != b.reading { return a.reading < b.reading }
            if a.word != b.word { return a.word < b.word }
            let aRank = a.source == .custom ? 0 : 1
            let bRank = b.source == .custom ? 0 : 1
            return aRank < bRank
        }
    }

    /// YYYY-MM-DD of a "days since 1970-01-01" learning day (s4-learning.md section 4).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    internal init(engine: CoreEngine) {
        self.engine = engine

        // ~640 pt wide so the five columns (來源 | reading | word | context | weight+day) fit.
        let contentRect = NSRect(x: 0, y: 0, width: 640, height: 400)
        self.window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.window.title = "自訂詞彙與選字記憶"
        self.window.titlebarAppearsTransparent = true
        self.window.isMovableByWindowBackground = true
        self.window.collectionBehavior = [.transient, .auxiliary]

        let scrollView = NSScrollView(frame: NSRect(x: 12, y: 60, width: 616, height: 300))
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        self.tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 604, height: 280))
        self.tableView.headerView = nil
        self.tableView.allowsMultipleSelection = true
        // Memory rows show the weight and its day on two lines.
        self.tableView.rowHeight = 34
        scrollView.documentView = self.tableView

        let addRow = NSStackView(frame: NSRect(x: 12, y: 16, width: 408, height: 36))
        addRow.orientation = .horizontal
        addTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        addTextField.placeholderString = "讀音 (例如：ㄅㄚˇ-ㄅㄚˇ)"
        addTextField.isBezeled = true
        addTextField.drawsBackground = true

        self.wordField = NSTextField(frame: NSRect(x: 248, y: 0, width: 160, height: 28))
        self.wordField.placeholderString = "詞彙 (例如：把手)"
        self.wordField.isBezeled = true
        self.wordField.drawsBackground = true

        addRow.addArrangedSubview(addTextField)
        addRow.addArrangedSubview(self.wordField)

        self.addButton = NSButton(frame: NSRect(x: 428, y: 16, width: 80, height: 28))
        self.addButton.title = "新增"

        self.removeButton = NSButton(frame: NSRect(x: 516, y: 16, width: 80, height: 28))
        self.removeButton.title = "刪除"

        let bottomView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 50))
        bottomView.addSubview(scrollView)
        bottomView.addSubview(addRow)
        bottomView.addSubview(self.addButton)
        bottomView.addSubview(self.removeButton)

        self.window.contentView = bottomView

        super.init()

        // Set delegates and targets after super.init
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.addButton.target = self
        self.addButton.action = #selector(addWord)
        self.removeButton.target = self
        self.removeButton.action = #selector(removeWord)
    }

    @objc func addWord() {
        let reading = addTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reading.isEmpty else { return }
        let word = self.wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        let code = engine.customVocabAdd(reading: reading, word: word)
        if code == 0 {
            loadWords()
            addTextField.stringValue = ""
            self.wordField.stringValue = ""
        } else {
            showErrorMessage("新增失敗：詞彙已存在或格式錯誤")
        }
    }

    @objc func removeWord() {
        guard let index = selectedIndex, index >= 0, index < rows.count else { return }
        let row = rows[index]
        // Route by source: custom rows remove from the custom store, memory rows forget the learned
        // record (s4-learning.md section 1.5).
        let code: Int32
        switch row.source {
        case .custom:
            code = engine.customVocabRemove(reading: row.reading, word: row.word)
        case .memory:
            code = engine.learningForget(reading: row.reading, word: row.word)
        }
        if code == 0 {
            loadWords()
        } else {
            showErrorMessage("刪除失敗")
        }
    }

    private func loadWords() {
        var merged: [Row] = []
        merged += engine.customVocabListAll().map {
            Row(source: .custom, reading: $0.reading, word: $0.word)
        }
        merged += engine.learningListAll().map {
            Row(source: .memory, reading: $0.reading, word: $0.word,
                context: $0.context, weight: $0.weight, day: $0.day)
        }
        self.rows = Self.sortRows(merged)
        self.tableView.reloadData()
    }

    private func showErrorMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "錯誤"
        alert.informativeText = message
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }

    func importKeykeyFile(path: String) {
        let code = engine.customVocabImportKeykey(path: path)
        if code == 0 {
            loadWords()
        } else {
            showErrorMessage("匯入失敗：檔案格式錯誤或無法讀取")
        }
    }

    func importCinFile(path: String) {
        let code = engine.customVocabImportCin(path: path)
        if code == 0 {
            loadWords()
        } else {
            showErrorMessage("匯入失敗：檔案格式錯誤或無法讀取")
        }
    }
}

extension VocabularyManager: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < rows.count else { return nil }
        let entry = rows[row]

        // No header row (the window's existing style); columns are fixed x positions:
        //   來源 | reading | word | context | weight + day
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 604, height: 34))
        let labelFont = NSFont.systemFont(ofSize: 12)
        let secondaryFont = NSFont.systemFont(ofSize: 11)

        // 來源: 自訂 / 記憶, color-coded to tell the two stores apart at a glance.
        let source = NSTextField(labelWithString: entry.source == .custom ? "自訂" : "記憶")
        source.frame = NSRect(x: 4, y: 8, width: 42, height: 18)
        source.font = secondaryFont
        source.textColor = entry.source == .custom ? .systemBlue : .systemGreen
        source.lineBreakMode = .byTruncatingTail
        container.addSubview(source)

        // A programmatic NSTableCellView has no textField, so each label is built explicitly.
        let reading = NSTextField(labelWithString: entry.reading)
        reading.frame = NSRect(x: 50, y: 8, width: 160, height: 18)
        reading.font = labelFont
        reading.lineBreakMode = .byTruncatingTail
        container.addSubview(reading)

        let word = NSTextField(labelWithString: entry.word)
        word.frame = NSRect(x: 214, y: 8, width: 160, height: 18)
        word.font = labelFont
        word.lineBreakMode = .byTruncatingTail
        container.addSubview(word)

        // Memory-only columns: context (前文) and weight with its day on two lines. The learning
        // file's context key is "" (global) or "^" (sentence start) or up to 2 Han characters
        // (s4-learning.md section 4); the empty key is shown in words so the cell is never blank.
        if entry.source == .memory {
            let contextText: String
            switch entry.context {
            case "": contextText = "（全域）"
            case "^": contextText = "（句首）"
            default: contextText = entry.context
            }
            let context = NSTextField(labelWithString: contextText)
            context.frame = NSRect(x: 378, y: 8, width: 130, height: 18)
            context.font = secondaryFont
            context.lineBreakMode = .byTruncatingTail
            container.addSubview(context)

            let weight = NSTextField(labelWithString: String(format: "%.2f", entry.weight))
            weight.frame = NSRect(x: 512, y: 2, width: 88, height: 15)
            weight.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            weight.lineBreakMode = .byTruncatingTail
            container.addSubview(weight)

            let day = NSTextField(labelWithString: Self.dayFormatter.string(
                from: Date(timeIntervalSince1970: TimeInterval(entry.day) * 86400)))
            day.frame = NSRect(x: 512, y: 18, width: 88, height: 13)
            day.font = NSFont.systemFont(ofSize: 9)
            day.textColor = .secondaryLabelColor
            day.lineBreakMode = .byTruncatingTail
            container.addSubview(day)
        }

        return container
    }
}

extension VocabularyManager: NSTableViewDelegate {
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let row = tableView.selectedRow
        if row >= 0 && row < rows.count {
            selectedIndex = row
        } else {
            selectedIndex = nil
        }
    }
}

/// Menu entries for custom vocabulary management (S3b section 13.2).
public enum VocabularyMenuEntry {
    case showManager
    case importKeykey(String)
    case importCin(String)
}
