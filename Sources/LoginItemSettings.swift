import AppKit
import Combine
import ServiceManagement

protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

private final class SystemLoginItemService: LoginItemServicing {
    private let service = SMAppService.mainApp

    var status: SMAppService.Status { service.status }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let service: any LoginItemServicing

    init(service: any LoginItemServicing = SystemLoginItemService()) {
        self.service = service
        status = service.status
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    func setRequested(_ requested: Bool) {
        errorMessage = nil
        do {
            if requested {
                guard status == .notRegistered || status == .notFound else {
                    refresh()
                    return
                }
                try service.register()
            } else {
                guard status == .enabled || status == .requiresApproval else {
                    refresh()
                    return
                }
                try service.unregister()
            }
        } catch {
            errorMessage =
                requested
                ? "无法开启登录时自动打开：\(error.localizedDescription)"
                : "无法关闭登录时自动打开：\(error.localizedDescription)"
            status = service.status
            return
        }
        refresh()
    }

    func refresh() {
        status = service.status
        if status == .enabled || status == .notRegistered {
            errorMessage = nil
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
