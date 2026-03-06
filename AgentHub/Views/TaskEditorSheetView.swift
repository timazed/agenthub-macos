import AppKit
import SwiftUI

struct TaskEditorSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskRecord
    private let isNew: Bool
    let onSave: (TaskRecord, Bool) -> Void
    let onCancel: () -> Void

    init(task: TaskRecord?, onSave: @escaping (TaskRecord, Bool) -> Void, onCancel: @escaping () -> Void) {
        let now = Date()
        let value = task ?? TaskRecord(
            id: UUID(),
            title: "",
            instructions: "",
            scheduleType: .manual,
            scheduleValue: "",
            state: .scheduled,
            codexThreadId: nil,
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: now,
            updatedAt: now,
            lastRun: nil,
            nextRun: nil,
            lastError: nil
        )
        _draft = State(initialValue: value)
        self.isNew = task == nil
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.11),
                    Color(red: 0.06, green: 0.06, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isNew ? "Add Task" : "Edit Task")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                    Text("Background work stays attached to the assistant and runs with the default persona.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                formCard

                HStack {
                    Spacer()
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        onSave(draft, isNew)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue.opacity(0.9))
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            labeledField("Title") {
                TextField("Bondi rental monitor", text: $draft.title)
            }

            labeledField("Instructions") {
                TextEditor(text: $draft.instructions)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(12)
                    .background(inputBackground)
            }

            labeledField("Runtime Mode") {
                Picker("Runtime Mode", selection: $draft.runtimeMode) {
                    Text("Chat-only").tag(RuntimeMode.chatOnly)
                    Text("Task").tag(RuntimeMode.task)
                }
                .pickerStyle(.segmented)
            }

            labeledField("External Directory") {
                HStack(spacing: 12) {
                    TextField("Optional absolute path", text: Binding(
                        get: { draft.externalDirectoryPath ?? "" },
                        set: { draft.externalDirectoryPath = $0.isEmpty ? nil : $0 }
                    ))
                    .disabled(draft.runtimeMode == .chatOnly)

                    Button("Choose…") {
                        if let path = pickDirectory() {
                            draft.externalDirectoryPath = path
                        }
                    }
                    .disabled(draft.runtimeMode == .chatOnly)
                }
            }

            HStack(spacing: 16) {
                labeledField("Schedule") {
                    Picker("Schedule", selection: $draft.scheduleType) {
                        Text("Manual").tag(TaskScheduleType.manual)
                        Text("Every N Minutes").tag(TaskScheduleType.intervalMinutes)
                        Text("Daily HH:mm").tag(TaskScheduleType.dailyAtHHMM)
                    }
                }

                labeledField("Value") {
                    TextField(draft.scheduleType == .dailyAtHHMM ? "08:00" : "60", text: $draft.scheduleValue)
                        .disabled(draft.scheduleType == .manual)
                }
            }
        }
        .textFieldStyle(.plain)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(inputBackground)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
