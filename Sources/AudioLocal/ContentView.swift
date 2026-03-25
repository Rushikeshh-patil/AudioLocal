import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header
                composerCard
                editorCard
            }
            .layoutPriority(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            inspectorCard
                .frame(minWidth: 320, idealWidth: 340, maxWidth: 360, maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Article Audio")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Generate speech and save the final audio to Audiobookshelf or any folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if model.usesKokoroInCurrentMode || !model.lastKokoroDevice.isEmpty {
                    statusChip(model.kokoroDeviceBadgeText, highlighted: model.isKokoroGPUActive)
                }

                if !model.lastBackend.isEmpty {
                    statusChip(model.lastBackend)
                }
            }
        }
    }

    private var composerCard: some View {
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

                Text(model.providerMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 12) {
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
                            Text(model.isGenerating ? "Generating..." : "Create Audio File")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canGenerate || model.isGenerating)
                    .keyboardShortcut(.defaultAction)

                    Button("Reveal in Finder") {
                        model.revealLastFile()
                    }
                    .disabled(model.lastSavedPath.isEmpty)
                }

                Spacer()

                Text("\(model.articleBody.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.shouldShowProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(model.progressTitle)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if !model.progressDetail.isEmpty {
                            Text(model.progressDetail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: model.generationProgress, total: 1.0)
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.statusMessage)
                    .font(.subheadline.weight(.medium))

                if !model.lastSavedPath.isEmpty {
                    Text(model.lastSavedPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .cardStyle(colorScheme: colorScheme)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Text")
                    .font(.headline)
                Spacer()
                Text("Scrollable editor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .cardStyle(colorScheme: colorScheme)
    }

    private var inspectorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.headline)

            settingsSection(title: "Kokoro (Default)") {
                TextField("Python executable", text: $model.kokoroPythonPath)
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

                inspectorRow(label: "Device") {
                    Text(model.kokoroDeviceDetail)
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
        .cardStyle(colorScheme: colorScheme)
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
