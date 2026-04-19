import SwiftUI

struct SessionView: View {
    @Environment(SessionManager.self) private var session
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Angles display
                anglesSection

                Spacer()

                // Live transcript
                if session.isActive {
                    Text(session.transcriptPreview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                // Status
                Text(session.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                // Session button
                sessionButton
                    .padding(.bottom, 48)
            }
            .navigationTitle("WhisperFlow")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Angles Display

    @ViewBuilder
    private var anglesSection: some View {
        if let emission = session.latestEmission {
            VStack(spacing: 20) {
                Text(emission.topic.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(1.5)

                ForEach(emission.angles, id: \.self) { angle in
                    Text(angle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeOut(duration: 0.3), value: emission.id)
            .padding(.horizontal, 32)
        } else if session.isActive {
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.variableColor.iterative, isActive: session.isActive)

                Text("Listening for the right moment…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)

                Text("Tap to start a session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Session Button

    private var sessionButton: some View {
        Button {
            if session.isActive {
                session.stop()
            } else {
                Task { await session.start() }
            }
        } label: {
            Circle()
                .fill(session.isActive ? Color.red : Color.blue)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: session.isActive ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
                .shadow(color: session.isActive ? .red.opacity(0.3) : .blue.opacity(0.3), radius: 12)
        }
    }
}
