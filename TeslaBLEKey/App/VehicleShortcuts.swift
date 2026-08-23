import AppIntents

private enum ShortcutError: LocalizedError {
    case commandFailed

    var errorDescription: String? {
        "车辆没有确认操作，请靠近车辆并打开小特蓝牙钥匙后重试。"
    }
}

struct LockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "锁定 Tesla"
    static var description = IntentDescription("通过本地蓝牙锁定已配对车辆。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = VehicleController()
        try await controller.connect()
        await controller.lock()
        guard controller.lastSuccessAction == .lock else { throw ShortcutError.commandFailed }
        controller.disconnect()
        return .result(dialog: "车辆已锁定")
    }
}

struct FlashVehicleLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tesla 闪灯"
    static var description = IntentDescription("通过本地蓝牙让已配对车辆闪灯。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = VehicleController()
        try await controller.connect()
        await controller.flashLights()
        guard controller.lastSuccessAction == .flash else { throw ShortcutError.commandFailed }
        controller.disconnect()
        return .result(dialog: "车辆已闪灯")
    }
}

struct HonkVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Tesla 鸣笛"
    static var description = IntentDescription("通过本地蓝牙让已配对车辆鸣笛。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let controller = VehicleController()
        try await controller.connect()
        await controller.honk()
        guard controller.lastSuccessAction == .horn else { throw ShortcutError.commandFailed }
        controller.disconnect()
        return .result(dialog: "车辆已鸣笛")
    }
}

struct TeslaVehicleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockVehicleIntent(),
            phrases: ["用 \(.applicationName) 锁车", "让 \(.applicationName) 锁定车辆"],
            shortTitle: "锁车",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: FlashVehicleLightsIntent(),
            phrases: ["用 \(.applicationName) 闪灯", "让 \(.applicationName) 找车"],
            shortTitle: "闪灯",
            systemImageName: "light.beacon.max"
        )
        AppShortcut(
            intent: HonkVehicleIntent(),
            phrases: ["用 \(.applicationName) 鸣笛"],
            shortTitle: "鸣笛",
            systemImageName: "speaker.wave.2.fill"
        )
    }
}
