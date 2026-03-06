import SwiftUI

struct AssistantPanelView: View {
    @ObservedObject var tasksViewModel: TasksViewModel
    @ObservedObject var activityViewModel: ActivityLogViewModel
    let onClose: () -> Void
    let onAddTask: () -> Void
    let onEditTask: (TaskRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assistant")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Tasks, backlog, and activity")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add Task", action: onAddTask)
                    .buttonStyle(.borderedProminent)

                Button(action: onClose) {
                    Image(systemName: "sidebar.trailing")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 22) {
                    panelSection("Current Tasks", tasksViewModel.currentTasks)
                    panelSection("Backlog", tasksViewModel.backlogTasks)
                    activitySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private func panelSection(_ title: String, _ tasks: [TaskRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            if tasks.isEmpty {
                Text("No items")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
            } else {
                ForEach(tasks) { task in
                    TaskPanelRow(
                        task: task,
                        onEdit: { onEditTask(task) },
                        onRunNow: { tasksViewModel.runNow(task: task); activityViewModel.load() },
                        onPause: { tasksViewModel.pause(task: task); activityViewModel.load() },
                        onResume: { tasksViewModel.resume(task: task); activityViewModel.load() },
                        onComplete: { tasksViewModel.complete(task: task); activityViewModel.load() },
                        onReinitialize: { tasksViewModel.reinitialize(task: task); activityViewModel.load() }
                    )
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Log")
                .font(.headline)
                .foregroundStyle(.secondary)

            if activityViewModel.events.isEmpty {
                Text("No recent activity")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
            } else {
                ForEach(activityViewModel.events.prefix(20)) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.message)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
            }
        }
    }
}

private struct TaskPanelRow: View {
    let task: TaskRecord
    let onEdit: () -> Void
    let onRunNow: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onComplete: () -> Void
    let onReinitialize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        StatusCapsule(text: task.state.rawValue)
                        if let nextRun = task.nextRun {
                            Text(nextRun.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button("Open", action: onEdit)
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Run", action: onRunNow)
                    .buttonStyle(.borderedProminent)

                if task.state == .paused || task.state == .error || task.state == .completed {
                    Button("Resume", action: onResume)
                        .buttonStyle(.bordered)
                } else {
                    Button("Pause", action: onPause)
                        .buttonStyle(.bordered)
                }

                Button("Done", action: onComplete)
                    .buttonStyle(.bordered)

                if task.state == .error {
                    Button("Reinit", action: onReinitialize)
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct StatusCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}
