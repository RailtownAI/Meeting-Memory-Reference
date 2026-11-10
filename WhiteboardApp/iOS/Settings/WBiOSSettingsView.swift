import SwiftUI
import WhiteboardCore

/// Settings tab — lets the user paste and store the Gemini and rail engine keys in the Keychain.
struct WBiOSSettingsView: View {
    @State private var viewModel = WBiOSSettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Keys are stored securely in your device's keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                keySection(
                    title: "Gemini API Key",
                    hint: "Google AI Studio API key",
                    text: $viewModel.geminiKey,
                    isSet: viewModel.isGeminiKeySet,
                    onSave: { viewModel.saveGeminiKey() }
                )

                analysisModelSection

                keySection(
                    title: "Railtown Conductr API Key",
                    hint: "Base64 key from the Conductr dashboard",
                    text: $viewModel.railtownConductrKey,
                    isSet: viewModel.isRailtownConductrKeySet,
                    onSave: { viewModel.saveRailtownConductrKey() }
                )

                keySection(
                    title: "Railengine - Token (ingestion)\nWhiteboard",
                    hint: "ENGINE_TOKEN",
                    text: $viewModel.engineTokenWhiteboard,
                    isSet: viewModel.isEngineTokenWhiteboardSet,
                    onSave: { viewModel.saveEngineTokenWhiteboard() }
                )

                keySection(
                    title: "Railengine - PAT (retrieval)\nWhiteboard",
                    hint: "ENGINE_PAT",
                    text: $viewModel.enginePATWhiteboard,
                    isSet: viewModel.isEnginePATWhiteboardSet,
                    onSave: { viewModel.saveEnginePATWhiteboard() }
                )

                keySection(
                    title: "Railengine - Token (ingestion)\nCalendar",
                    hint: "ENGINE_TOKEN",
                    text: $viewModel.engineTokenCalendar,
                    isSet: viewModel.isEngineTokenCalendarSet,
                    onSave: { viewModel.saveEngineTokenCalendar() }
                )

                keySection(
                    title: "Railengine - PAT (retrieval)\nCalendar",
                    hint: "ENGINE_PAT",
                    text: $viewModel.enginePATCalendar,
                    isSet: viewModel.isEnginePATCalendarSet,
                    onSave: { viewModel.saveEnginePATCalendar() }
                )

                deleteAllSection
            }
            .navigationTitle("Settings")
            .task {
                viewModel.load()
            }
            .alert("Delete All Data?", isPresented: $viewModel.isConfirmingDelete) {
                Button("Delete", role: .destructive) {
                    viewModel.confirmDeleteAll()
                }
                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("This permanently removes all whiteboard and calendar records from railengine and all photos from iCloud. Your device's Apple Calendar isn't affected. This can't be undone.")
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.deletePhase != nil },
            set: { presented in
                if !presented {
                    viewModel.dismissDeleteResult()
                }
            }
        )) {
            deleteModal
        }
    }

    private var deleteAllSection: some View {
        Section {
            Button("Delete All Data", role: .destructive) {
                viewModel.isConfirmingDelete = true
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Text("Removes all whiteboard and calendar records from railengine and all photos from iCloud. Your Apple Calendar isn't affected.")
        }
    }

    /// Locking modal shown during and after deletion — a spinner while deleting (no way out), then
    /// the per-store counts with an OK button.
    private var deleteModal: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            if let phase = viewModel.deletePhase {
                deleteCard(for: phase)
            }
        }
        .presentationBackground(.clear)
    }

    @ViewBuilder
    private func deleteCard(for phase: WBiOSSettingsViewModel.DeletePhase) -> some View {
        VStack(spacing: .spacingXL) {
            switch phase {
            case .deleting:
                ProgressView()
                    .controlSize(.large)
                Text("Deleting…")
                    .font(.headline)
            case .done(let result):
                Text("Deleted")
                    .font(.headline)
                VStack(alignment: .leading, spacing: .spacingSM) {
                    Text("Whiteboard records: \(result.whiteboardRecordsDeleted)")
                    Text("Calendar records: \(result.calendarRecordsDeleted)")
                    Text("iCloud photos: \(result.photosDeleted)")
                }
                .font(.subheadline)
                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: .spacingXXS) {
                        ForEach(result.errors, id: \.self) { error in
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Button("OK") {
                    viewModel.dismissDeleteResult()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.spacing4XL)
        .frame(maxWidth: 320)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: .radiusLG))
    }

    /// Which Gemini model the capture-analysis agents run on — the title, summary, and action items
    /// read off a whiteboard, and the text recognized from it. macOS's answer/search agent keeps its
    /// built-in model, since this setting only exists on iOS.
    ///
    /// Not a `keySection`: that helper is built for write-only secrets (a `SecureField`, cleared on
    /// save), and this value has to stay legible so the user can see what they picked.
    private var analysisModelSection: some View {
        Section {
            Picker("Model", selection: $viewModel.analysisModelSelection) {
                ForEach(WBPreferences.analysisModelChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
                Text("Custom…").tag(WBiOSSettingsViewModel.customAnalysisModelTag)
            }
            if viewModel.isCustomAnalysisModelSelected {
                // Both modifiers are load-bearing: iOS otherwise capitalizes the first letter and
                // autocorrects a hyphenated model id into something that fails for a reason that has
                // nothing to do with what was typed.
                TextField(WBPreferences.defaultAnalysisModelID, text: $viewModel.customAnalysisModelID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Button("Save") {
                viewModel.saveAnalysisModel()
            }
            .disabled(!viewModel.canSaveAnalysisModel)
            Button("Use Default") {
                viewModel.resetAnalysisModel()
            }
            .disabled(!viewModel.hasAnalysisModelOverride)
        } header: {
            // Header and footer as closures, not `Section("title") { … } footer: { … }` — there is
            // no initializer taking a title string *and* a footer.
            Text("Gemini Model")
        } footer: {
            Text("Applies to the title, summary, and action items generated from a capture, and to reading the whiteboard's text.")
        }
    }

    @ViewBuilder
    private func keySection(
        title: String,
        hint: String,
        text: Binding<String>,
        isSet: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        Section(title) {
            HStack {
                SecureField(hint, text: text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if isSet && text.wrappedValue.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Button(isSet ? "Update" : "Save") {
                onSave()
            }
            .disabled(text.wrappedValue.isEmpty)
        }
    }
}

#Preview {
    WBiOSSettingsView()
}
