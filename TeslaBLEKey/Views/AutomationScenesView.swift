import SwiftUI

struct AutomationScenesView: View {
    @Environment(VehicleController.self) private var vehicle
    @State private var editingScene: VehicleController.AutomationScene?

    var body: some View {
        List {
            Section {
                ForEach(vehicle.automationScenes) { scene in
                    Button { Task { await vehicle.runScene(scene) } } label: {
                        HStack(spacing: 14) {
                            Image(systemName: scene.symbol).frame(width: 34, height: 34).background(AppTheme.raised, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scene.name).foregroundStyle(.primary)
                                Text(scene.actions.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(); Image(systemName: "play.fill").font(.caption)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .swipeActions { Button("编辑") { editingScene = scene }.tint(.gray) }
                }
                .onDelete(perform: vehicle.deleteScenes)
            } footer: {
                Text("动作通过当前车辆的本地蓝牙会话依次执行；中途失败时不会继续发送后续动作。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("自动化场景").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { editingScene = newScene } label: { Image(systemName: "plus") } }
        .sheet(item: $editingScene) { scene in SceneEditorView(scene: scene).environment(vehicle) }
    }

    private var newScene: VehicleController.AutomationScene {
        .init(id: UUID(), name: "新场景", symbol: "sparkles", actions: [.lock])
    }
}

private struct SceneEditorView: View {
    @Environment(VehicleController.self) private var vehicle
    @Environment(\.dismiss) private var dismiss
    @State var scene: VehicleController.AutomationScene

    var body: some View {
        NavigationStack {
            Form {
                TextField("场景名称", text: $scene.name)
                Section("动作顺序") {
                    ForEach(VehicleController.SceneAction.allCases) { action in
                        Toggle(action.title, isOn: Binding(
                            get: { scene.actions.contains(action) },
                            set: { enabled in
                                if enabled { scene.actions.append(action) }
                                else { scene.actions.removeAll { $0 == action } }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("编辑场景").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { vehicle.saveScene(scene); dismiss() }.disabled(scene.name.isEmpty || scene.actions.isEmpty)
                }
            }
        }.preferredColorScheme(.dark)
    }
}
