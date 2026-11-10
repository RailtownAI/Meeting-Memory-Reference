import SwiftUI

/// Settings window — lets the user paste and store the Gemini and rail engine keys in the
/// Keychain. Opened from the app menu's Settings… item (⌘,). Deliberately a separate copy
/// of the iOS settings screen so the two UIs can diverge later.
struct WBMacOSSettingsView: View {
    @State private var viewModel = WBMacOSSettingsViewModel()

    var body: some View {
        List {
            Text("Keys are stored securely in your Mac's keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Gemini") {
                keyRow(
                    title: "API Key",
                    hint: "Google AI Studio API key",
                    text: $viewModel.geminiKey,
                    isSet: viewModel.isGeminiKeySet
                )
            }

            Section("Railtown Conductr") {
                keyRow(
                    title: "API Key",
                    hint: "Base64 key from the Conductr dashboard",
                    text: $viewModel.railtownConductrKey,
                    isSet: viewModel.isRailtownConductrKeySet
                )
            }

            Section("Railengine — Whiteboard") {
                keyRow(
                    title: "PAT (retrieval)",
                    hint: "ENGINE_PAT",
                    text: $viewModel.enginePATWhiteboard,
                    isSet: viewModel.isEnginePATWhiteboardSet
                )
                // The Mac writes whiteboard records too — editing action items re-ingests
                // the record — so it needs the ingestion token as well as the read PAT.
                keyRow(
                    title: "Token (ingestion)",
                    hint: "ENGINE_TOKEN",
                    text: $viewModel.engineTokenWhiteboard,
                    isSet: viewModel.isEngineTokenWhiteboardSet
                )
            }

            Section("Railengine — Calendar") {
                keyRow(
                    title: "PAT (retrieval)",
                    hint: "ENGINE_PAT",
                    text: $viewModel.enginePATCalendar,
                    isSet: viewModel.isEnginePATCalendarSet
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Save") {
                    viewModel.saveAll()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.hasUnsavedChanges)
            }
            .padding(.spacingXL)
            .background(.bar)
        }
        .frame(width: 480, height: 460)
        .task {
            viewModel.load()
        }
    }

    @ViewBuilder
    private func keyRow(
        title: String,
        hint: String,
        text: Binding<String>,
        isSet: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacingMD) {
            HStack {
                Text(title)
                    .font(.headline)
                if isSet && text.wrappedValue.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            SecureField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
        .padding(.vertical, .spacingXS)
    }
}

#Preview {
    WBMacOSSettingsView()
}
