import AppKit

/// Custom vocabulary management UI (ChiaKey integration).
/// Provides a window for viewing, adding, and removing custom words.
@MainActor
public final class VocabularyManager: NSObject {
    private let engine: CoreEngine
    private var words: [(reading: String, word: String)] = []
    private var selectedWord: (reading: String, word: String)? = nil

    public let window: NSWindow
    private let tableView: NSTableView
    private let addTextField: NSTextField
    private let addButton: NSButton
    private let removeButton: NSButton

    init(engine: CoreEngine) {
        self.engine = engine

        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 400)
        self.window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.window.title = "自訂詞彙"
        self.window.titlebarAppearsTransparent = true
        self.window.isMovableByWindowBackground = true
        self.window.collectionBehavior = [.transient, .auxiliary]

        let scrollView = NSScrollView(frame: NSRect(x: 12, y: 60, width: 456, height: 300))
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        self.tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 440, height: 280))
        self.tableView.headerView = nil
        self.tableView.allowsMultipleSelection = true
        scrollView.documentView = self.tableView

        let addRow = NSStackView(frame: NSRect(x: 12, y: 16, width: 456, height: 36))
        addRow.orientation = .horizontal
        addTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        addTextField.placeholderString = "讀音 (例如：ㄅㄚˇ-ㄅㄚˇ)"
        addTextField.isBezeled = true
        addTextField.drawsBackground = true

        let wordField = NSTextField(frame: NSRect(x: 270, y: 0, width: 140, height: 28))
        wordField.placeholderString = "詞彙 (例如：把手)"
        wordField.isBezeled = true
        wordField.drawsBackground = true

        addRow.addArrangedSubview(addTextField)
        addRow.addArrangedSubview(wordField)

        self.addButton = NSButton(frame: NSRect(x: 320, y: 16, width: 80, height: 28))
        self.addButton.title = "新增"

        self.removeButton = NSButton(frame: NSRect(x: 408, y: 16, width: 80, height: 28))
        self.removeButton.title = "刪除"

        let bottomView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 50))
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
        let wordField = addTextField.superview?.subviews[1] as? NSTextField
        let word = wordField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !word.isEmpty else { return }

        let code = engine.customVocabAdd(reading: reading, word: word)
        if code == 0 {
            loadWords()
            addTextField.stringValue = ""
            (addTextField.superview?.subviews[1] as? NSTextField)?.stringValue = ""
        } else {
            showErrorMessage("新增失敗：詞彙已存在或格式錯誤")
        }
    }

    @objc func removeWord() {
        guard let selected = selectedWord else { return }
        let code = engine.customVocabRemove(reading: selected.reading, word: selected.word)
        if code == 0 {
            loadWords()
        } else {
            showErrorMessage("刪除失敗")
        }
    }

    private func loadWords() {
        // Load from engine (custom_vocab.tsv)
        // The engine returns words for a specific reading; we need to fetch all.
        // For now, just show the loaded words from the tableView's data source.
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
        return words.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let reading = words[row].reading
        let word = words[row].word

        let cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        cellView.textField?.stringValue = reading

        let wordCell = NSTableCellView(frame: NSRect(x: 220, y: 0, width: 220, height: 28))
        wordCell.textField?.stringValue = word

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 28))
        container.addSubview(cellView)
        container.addSubview(wordCell)

        return container
    }
}

extension VocabularyManager: NSTableViewDelegate {
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let row = tableView.selectedRow
        if row >= 0 && row < words.count {
            selectedWord = words[row]
        } else {
            selectedWord = nil
        }
    }
}

/// Menu entries for custom vocabulary management (S3b section 13.2).
public enum VocabularyMenuEntry {
    case showManager
    case importKeykey(String)
    case importCin(String)
}
