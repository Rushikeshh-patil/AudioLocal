import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedImportedChapterID: ImportedChapter.ID?

    var body: some View {
        Group {
            if model.isBookWorkspaceMode {
                bookWorkspace
            } else {
                articleWorkspace
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    private var articleWorkspace: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                articleHeader
                articleComposerCard
                articleEditorCard
            }
            .layoutPriority(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            settingsPane(scrollable: true)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bookWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            bookWorkspaceHeader

            HSplitView {
                bookOrganizerPane
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380, maxHeight: .infinity, alignment: .topLeading)

                bookEditorPane
                    .layoutPriority(1)
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if model.isSettingsInspectorVisible {
                    settingsPane(scrollable: true)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bookWorkspaceFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var articleHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Article Audio")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Generate speech and save the final audio to Audiobookshelf or any folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadgeRow
        }
    }

    private var articleComposerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.headline)
                TextField("Article title", text: $model.articleTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Engine")
                    .font(.headline)
                Picker("Provider", selection: $model.providerMode) {
                    ForEach(AppModel.ProviderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Text(model.providerModeDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(model.importButtonTitle) {
                    model.importEPUB()
                }
                .buttonStyle(.bordered)
                .disabled(model.isGenerating || model.isImportingBook)

                if model.isImportingBook {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Text("Import an EPUB to switch into the chapter workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                Button {
                    Task {
                        await model.generateAudio()
                    }
                } label: {
                    HStack {
                        if model.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.isGenerating ? "Generating..." : model.generateSingleButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canGenerate || model.isGenerating || model.isImportingBook)
                .keyboardShortcut(.defaultAction)

                Button("Reveal in Finder") {
                    model.revealLastFile()
                }
                .disabled(model.lastSavedPath.isEmpty)

                Spacer()

                Text("\(model.articleBody.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusBlock
        }
        .cardStyle(colorScheme: colorScheme)
    }

    private var articleEditorCard: some View {
        editorTextPane(
            title: "Text",
            detail: "Scrollable editor",
            showSelectionMeta: false,
            showEditorActions: false
        )
        .layoutPriority(1)
        .cardStyle(colorScheme: colorScheme)
    }

    private var bookWorkspaceHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Imported Book")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Book title", text: $model.articleTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .textFieldStyle(.plain)

                HStack(spacing: 10) {
                    if let author = model.importedBookAuthorName {
                        Label(author, systemImage: "person.text.rectangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Label(model.importedBookSourceName, systemImage: "book.closed")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(model.importedBookSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                statusBadgeRow

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        bookHeaderButtonRow
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 10) {
                            Button(model.importButtonTitle) {
                                model.importEPUB()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isGenerating || model.isImportingBook)

                            Button(model.bookWorkspaceSettingsButtonTitle) {
                                model.toggleSettingsInspector()
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Clear Book") {
                            model.clearImportedBook()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isGenerating || model.isImportingBook)
                    }
                }

                if model.isImportingBook {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(model.importedBookOrganizerSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle(colorScheme: colorScheme)
    }

    private var bookOrganizerPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chapter Organizer")
                    .font(.headline)
                Spacer()
                Text(model.chapterListStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Search chapters", text: $model.chapterSearchQuery)
                .textFieldStyle(.roundedBorder)

            Picker("Filter", selection: $model.chapterFilterMode) {
                ForEach(AppModel.ChapterFilterMode.allCases) { filterMode in
                    Text(filterMode.title).tag(filterMode)
                }
            }
            .pickerStyle(.segmented)

            organizerSelectionActions
            organizerReorderActions

            if !model.canDragReorderImportedChapters && model.visibleImportedChapterCount > 0 {
                Text("Drag reorder is available in the `All` view with search cleared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if model.visibleImportedChapters.isEmpty {
                    emptyChapterListState
                } else {
                    chapterList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .cardStyle(colorScheme: colorScheme)
    }

    private var bookEditorPane: some View {
        editorTextPane(
            title: model.selectedImportedChapterTitle,
            detail: model.selectedImportedChapterDetail,
            showSelectionMeta: true,
            showEditorActions: true
        )
        .cardStyle(colorScheme: colorScheme)
    }

    private var bookWorkspaceFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    footerActionButtons
                    Spacer()
                    footerSummaryBlock(alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 10) {
                    footerActionButtons
                    footerSummaryBlock(alignment: .leading)
                }
            }

            statusBlock
        }
        .cardStyle(colorScheme: colorScheme)
    }

    private var chapterList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(model.visibleImportedChapters) { chapter in
                    chapterRow(chapter)
                        .modifier(ImportedChapterDragModifier(
                            chapter: chapter,
                            model: model,
                            draggedChapterID: $draggedImportedChapterID
                        ))
                }
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(editorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var emptyChapterListState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No Chapters Match")
                .font(.headline)
            Text("Adjust the search text or filter to bring chapters back into view.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(editorBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private func chapterRow(_ chapter: ImportedChapter) -> some View {
        let isSelected = model.selectedImportedChapterID == chapter.id
        let chapterNumber = chapterNumberLabel(for: chapter)

        return HStack(alignment: .top, spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { chapter.isIncluded },
                    set: { model.setImportedChapter(chapter.id, included: $0) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(chapterNumber)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    if chapter.hasEdits {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(colorScheme == .dark ? 0.28 : 0.14)))
                    }
                }

                Text(chapter.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(Self.wordCountText(chapter.wordCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if model.canDragReorderImportedChapters {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10) : chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : borderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            model.selectImportedChapter(chapter.id)
        }
    }

    private func editorTextPane(
        title: String,
        detail: String,
        showSelectionMeta: Bool,
        showEditorActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showSelectionMeta, let selectedChapter = model.selectedImportedChapter {
                    Toggle(
                        "Include",
                        isOn: Binding(
                            get: { selectedChapter.isIncluded },
                            set: { model.setImportedChapter(selectedChapter.id, included: $0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Button("Revert to Imported") {
                        model.revertSelectedImportedChapterText()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canRevertSelectedImportedChapter)
                }
            }

            if showEditorActions, model.selectedImportedChapter == nil {
                VStack(spacing: 10) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No Chapter Selected")
                        .font(.headline)
                    Text("Select a visible chapter from the organizer to edit its text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(editorBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
            } else {
                TextEditor(text: $model.articleBody)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(editorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bookHeaderButtonRow: some View {
        Group {
            Button(model.importButtonTitle) {
                model.importEPUB()
            }
            .buttonStyle(.bordered)
            .disabled(model.isGenerating || model.isImportingBook)

            Button(model.bookWorkspaceSettingsButtonTitle) {
                model.toggleSettingsInspector()
            }
            .buttonStyle(.bordered)

            Button("Clear Book") {
                model.clearImportedBook()
            }
            .buttonStyle(.bordered)
            .disabled(model.isGenerating || model.isImportingBook)
        }
    }

    private var organizerSelectionActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                organizerSelectionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Select All") {
                        model.selectAllImportedChapters()
                    }
                    .buttonStyle(.bordered)

                    Button("Select None") {
                        model.selectNoImportedChapters()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Reset Order") {
                    model.resetImportedChapterOrder()
                }
                .buttonStyle(.bordered)
                .disabled(!model.canResetImportedChapterOrder)
            }
        }
    }

    private var organizerSelectionButtons: some View {
        Group {
            Button("Select All") {
                model.selectAllImportedChapters()
            }
            .buttonStyle(.bordered)

            Button("Select None") {
                model.selectNoImportedChapters()
            }
            .buttonStyle(.bordered)

            Button("Reset Order") {
                model.resetImportedChapterOrder()
            }
            .buttonStyle(.bordered)
            .disabled(!model.canResetImportedChapterOrder)
        }
    }

    private var organizerReorderActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                organizerReorderButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Top") {
                        model.moveSelectedImportedChapterToTop()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canMoveSelectedImportedChapterUp)

                    Button("Up") {
                        model.moveSelectedImportedChapterUp()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canMoveSelectedImportedChapterUp)
                }

                HStack(spacing: 8) {
                    Button("Down") {
                        model.moveSelectedImportedChapterDown()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canMoveSelectedImportedChapterDown)

                    Button("Bottom") {
                        model.moveSelectedImportedChapterToBottom()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canMoveSelectedImportedChapterDown)
                }
            }
        }
    }

    private var organizerReorderButtons: some View {
        Group {
            Button("Top") {
                model.moveSelectedImportedChapterToTop()
            }
            .buttonStyle(.bordered)
            .disabled(!model.canMoveSelectedImportedChapterUp)

            Button("Up") {
                model.moveSelectedImportedChapterUp()
            }
            .buttonStyle(.bordered)
            .disabled(!model.canMoveSelectedImportedChapterUp)

            Button("Down") {
                model.moveSelectedImportedChapterDown()
            }
            .buttonStyle(.bordered)
            .disabled(!model.canMoveSelectedImportedChapterDown)

            Button("Bottom") {
                model.moveSelectedImportedChapterToBottom()
            }
            .buttonStyle(.bordered)
            .disabled(!model.canMoveSelectedImportedChapterDown)
        }
    }

    private var footerActionButtons: some View {
        Group {
            Button {
                Task {
                    await model.generateAudio()
                }
            } label: {
                HStack {
                    if model.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.isGenerating ? "Generating..." : model.generateSingleButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canGenerate || model.isGenerating || model.isImportingBook)
            .keyboardShortcut(.defaultAction)

            Button(model.generateFullAudiobookTitle) {
                Task {
                    await model.generateFullAudiobook()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!model.canGenerateFullAudiobook || model.isGenerating || model.isImportingBook)

            Button("Reveal in Finder") {
                model.revealLastFile()
            }
            .buttonStyle(.bordered)
            .disabled(model.lastSavedPath.isEmpty)
        }
    }

    private func footerSummaryBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(model.footerSaveSummary)
                .font(.caption.weight(.semibold))
            Text(model.footerSelectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsPane(scrollable: Bool) -> some View {
        Group {
            if scrollable {
                ScrollView {
                    settingsPaneContent
                }
            } else {
                settingsPaneContent
            }
        }
        .cardStyle(colorScheme: colorScheme)
    }

    private var settingsPaneContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.headline)

            settingsSection(title: "Local Engine") {
                inspectorRow(label: "Model") {
                    Picker("Local model", selection: $model.localModel) {
                        ForEach(AppModel.LocalModel.allCases) { localModel in
                            Text(localModel.title).tag(localModel)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(model.selectedLocalModelDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let footnote = model.localModelFootnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.localModel == .kokoro {
                    TextField("Kokoro Python executable", text: $model.kokoroPythonPath)
                        .textFieldStyle(.roundedBorder)

                    inspectorRow(label: "Voice") {
                        Picker("Kokoro voice", selection: $model.kokoroVoice) {
                            ForEach(KokoroVoiceCatalog.groupedVoices, id: \.group) { group in
                                Section(group.group) {
                                    ForEach(group.voices) { voice in
                                        Text(voice.displayName)
                                            .tag(voice.id)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)

                        Text(model.kokoroVoice)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.2fx", model.kokoroSpeed))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.kokoroSpeed, in: 0.8...1.4, step: 0.05)
                    }
                } else {
                    TextField("Voxtral Python executable", text: $model.voxtralPythonPath)
                        .textFieldStyle(.roundedBorder)

                    inspectorRow(label: "Model ID") {
                        TextField("Voxtral MLX model", text: $model.voxtralModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    inspectorRow(label: "Voice") {
                        Picker("Voxtral voice", selection: $model.voxtralVoice) {
                            ForEach(VoxtralVoiceCatalog.groupedVoices, id: \.group) { group in
                                Section(group.group) {
                                    ForEach(group.voices) { voice in
                                        Text(voice.displayName)
                                            .tag(voice.id)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)

                        Text(model.voxtralVoice)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                inspectorRow(label: "Device") {
                    Text(model.localDeviceDetail)
                        .foregroundStyle(.secondary)
                }
            }

            settingsSection(title: "Gemini (Optional)") {
                SecureField("Gemini API key", text: $model.geminiAPIKey)
                    .textFieldStyle(.roundedBorder)

                inspectorRow(label: "Model") {
                    TextField("Gemini model", text: $model.geminiModel)
                        .textFieldStyle(.roundedBorder)
                }

                inspectorRow(label: "Voice") {
                    Picker("Gemini voice", selection: $model.geminiVoice) {
                        ForEach(GeminiVoiceCatalog.allVoices) { voice in
                            Text(voice.displayName)
                                .tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(model.geminiVoice)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            settingsSection(title: "Storage") {
                Picker("Location", selection: $model.saveLocationMode) {
                    ForEach(AppModel.SaveLocationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                inspectorRow(label: "Format") {
                    Picker("Output format", selection: $model.exportFormat) {
                        ForEach(AudioExportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(model.exportFormat.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.saveLocationMode == .customFolder {
                    Button(model.saveLocationButtonTitle) {
                        model.chooseCustomSaveDirectory()
                    }
                    .buttonStyle(.bordered)

                    Text(model.customSaveDirectoryDisplay)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                inspectorRow(label: "Output") {
                    Text(model.saveLocationPreview)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                Text(model.saveLocationDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(primaryStatusText)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if !model.progressDetail.isEmpty {
                    Text(model.progressDetail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if model.shouldShowProgress {
                ProgressView(value: model.generationProgress, total: 1.0)
                    .controlSize(.small)
            }

            if secondaryStatusText != primaryStatusText {
                Text(secondaryStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.lastSavedPath.isEmpty {
                Text(model.lastSavedPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }

    private var statusBadgeRow: some View {
        HStack(spacing: 8) {
            if model.usesLocalEngineInCurrentMode || !model.lastLocalDevice.isEmpty {
                statusChip(model.localDeviceBadgeText, highlighted: model.isLocalGPUActive)
            }

            if !model.lastBackend.isEmpty {
                statusChip(model.lastBackend)
            }
        }
    }

    private func chapterNumberLabel(for chapter: ImportedChapter) -> String {
        guard let importedBook = model.importedBook,
              let index = importedBook.chapters.firstIndex(where: { $0.id == chapter.id }) else {
            return "Chapter"
        }

        return "Chapter \(index + 1)"
    }

    private static func wordCountText(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk words", Double(count) / 1_000)
        }

        return "\(count) words"
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .background(editorBackground.opacity(colorScheme == .dark ? 0.45 : 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func inspectorRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func statusChip(_ title: String, highlighted: Bool = false) -> some View {
        let tint = highlighted ? Color(nsColor: .systemGreen) : Color.secondary

        return Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(highlighted ? tint.opacity(colorScheme == .dark ? 0.18 : 0.12) : chipBackground)
            )
    }

    private var editorBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    private var chipBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08)
    }

    private var primaryStatusText: String {
        if model.shouldShowProgress, !model.progressTitle.isEmpty {
            return model.progressTitle
        }

        return model.statusMessage
    }

    private var secondaryStatusText: String {
        model.statusMessage
    }
}

private extension View {
    func cardStyle(colorScheme: ColorScheme) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.78 : 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08), lineWidth: 1)
            )
    }
}

private struct ImportedChapterDragModifier: ViewModifier {
    let chapter: ImportedChapter
    let model: AppModel
    @Binding var draggedChapterID: ImportedChapter.ID?

    func body(content: Content) -> some View {
        if model.canDragReorderImportedChapters {
            content
                .onDrag {
                    draggedChapterID = chapter.id
                    return NSItemProvider(object: chapter.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ImportedChapterDropDelegate(
                        targetChapter: chapter,
                        model: model,
                        draggedChapterID: $draggedChapterID
                    )
                )
        } else {
            content
        }
    }
}

private struct ImportedChapterDropDelegate: DropDelegate {
    let targetChapter: ImportedChapter
    let model: AppModel
    @Binding var draggedChapterID: ImportedChapter.ID?

    func dropEntered(info: DropInfo) {
        guard model.canDragReorderImportedChapters,
              let draggedChapterID,
              draggedChapterID != targetChapter.id else {
            return
        }

        model.moveImportedChapter(draggedChapterID, to: targetChapter.id)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard model.canDragReorderImportedChapters else {
            return DropProposal(operation: .cancel)
        }

        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedChapterID = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        model.canDragReorderImportedChapters
    }
}
