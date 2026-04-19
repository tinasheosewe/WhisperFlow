import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API Key") {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    LabeledContent("Gate Model", value: "claude-haiku-4-5")
                    LabeledContent("Angle Model", value: "claude-sonnet-4-6")
                    LabeledContent("Prompt Version", value: Prompts.version)
                }

                Section {
                    Text("Your API key is stored locally on this device. Conversations are processed in RAM only and never saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
