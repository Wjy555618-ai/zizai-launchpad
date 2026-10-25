import AppKit
import CoreServices
import Foundation
import ServiceManagement

private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var registrationError: Error?
    var unregistrationError: Error?
    private(set) var registrationCount = 0
    private(set) var unregistrationCount = 0
    private(set) var settingsOpenCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registrationCount += 1
        if let registrationError { throw registrationError }
        status = .enabled
    }

    func unregister() throws {
        unregistrationCount += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }

    func openSystemSettings() {
        settingsOpenCount += 1
    }
}

private struct ExpectedFailure: LocalizedError {
    var errorDescription: String? { "模拟失败" }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

@main
@MainActor
enum LoginItemSettingsAudit {
    static func main() {
        let launchOnly = ProcessInfo.processInfo.environment["ZIZAI_AUDIT_SCOPE"] == "launch"
        testDefaultOffAndExplicitEnable()
        testExplicitDisable()
        testApprovalState()
        testFailureIsVisible()
        testSettingsRoute()
        testLaunchEventDetection()
        testSilentLoginPresentationLifecycle()
        testInteractiveLaunchPresentationLifecycle()
        if launchOnly {
            print("启动架构验收通过：登录项开关、Apple Event 识别与静默启动状态机均正常。")
            return
        }
        testApplicationFolderAuthorizationLifecycle()
        testInvalidApplicationFolderBookmarkRecovery()
        print("设置验收通过：登录启动默认不注册且只响应用户显式开关；登录项启动静默准备，用户主动打开时恢复窗口；应用文件夹授权支持只读书签、重启恢复、移除授权和失效恢复。")
    }

    private static func testDefaultOffAndExplicitEnable() {
        // A never-before-registered ad-hoc or App Store build can initially report
        // notFound. It is still a valid first-run state: registration is attempted
        // only after the user turns the switch on.
        let service = FakeLoginItemService(status: .notFound)
        let manager = LoginItemManager(service: service)
        require(!manager.isRequested, "首次初始化错误开启了登录项")
        require(service.registrationCount == 0, "初始化期间静默注册了登录项")
        manager.setRequested(true)
        require(manager.isRequested, "用户开启后没有进入已请求状态")
        require(service.registrationCount == 1, "用户开启后没有执行一次注册")
    }

    private static func testExplicitDisable() {
        let service = FakeLoginItemService(status: .enabled)
        let manager = LoginItemManager(service: service)
        manager.setRequested(false)
        require(!manager.isRequested, "用户关闭后仍显示已开启")
        require(service.unregistrationCount == 1, "用户关闭后没有执行一次取消注册")
    }

    private static func testApprovalState() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)
        require(manager.isRequested, "需要系统批准时开关状态与用户请求不一致")
        manager.setRequested(true)
        require(service.registrationCount == 0, "待系统批准状态被重复注册")
    }

    private static func testFailureIsVisible() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registrationError = ExpectedFailure()
        let manager = LoginItemManager(service: service)
        manager.setRequested(true)
        require(!manager.isRequested, "注册失败却显示已开启")
        require(manager.errorMessage?.contains("模拟失败") == true, "注册失败信息被状态刷新吞掉")
    }

    private static func testSettingsRoute() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)
        manager.openSystemSettings()
        require(service.settingsOpenCount == 1, "待批准状态没有系统设置恢复路径")
    }

    private static func testLaunchEventDetection() {
        let manualEvent = makeOpenApplicationEvent()
        require(
            !LoginItemLaunchDetector.isLoginItemLaunch(event: manualEvent),
            "普通打开被错误识别为登录项启动"
        )

        let directEvent = makeOpenApplicationEvent()
        directEvent.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: AEKeyword(keyAELaunchedAsLogInItem)
        )
        require(
            LoginItemLaunchDetector.isLoginItemLaunch(event: directEvent),
            "没有识别直接的登录项启动标记"
        )

        let propertyEvent = makeOpenApplicationEvent()
        propertyEvent.setParam(
            NSAppleEventDescriptor(typeCode: DescType(keyAELaunchedAsLogInItem)),
            forKeyword: AEKeyword(keyAEPropData)
        )
        require(
            LoginItemLaunchDetector.isLoginItemLaunch(event: propertyEvent),
            "没有识别属性数据形式的登录项启动标记"
        )
    }

    private static func testSilentLoginPresentationLifecycle() {
        var state = LaunchPresentationState(isLoginItemLaunch: true)
        require(state.applicationDidFinishLaunching() == .suppress, "登录项启动时弹出了窗口")
        require(state.applicationDidBecomeActive() == .suppress, "首次激活抢占了焦点")
        state.silentSuppressionDidSettle()
        require(state.isSilentLoginLaunch, "静默准备完成后丢失了后台状态")
        require(state.userRequestedPresentation() == .present, "用户主动打开时没有显示窗口")
        require(!state.isSilentLoginLaunch, "用户打开后仍被当作后台启动")
    }

    private static func testInteractiveLaunchPresentationLifecycle() {
        var state = LaunchPresentationState(isLoginItemLaunch: false)
        require(state.applicationDidFinishLaunching() == .present, "用户主动启动时没有显示窗口")
        require(state.applicationDidBecomeActive() == .present, "用户重新激活时没有恢复窗口")
    }

    private static func makeOpenApplicationEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    private static func testApplicationFolderAuthorizationLifecycle() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-folder-access-\(UUID().uuidString)", isDirectory: true)
        let selectedFolder = root.appendingPathComponent("Applications", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        } catch {
            fail("无法创建文件夹授权测试目录：\(error.localizedDescription)")
        }

        let scannedRoots = LockedValue<[URL]>([])
        let authorizationService = TestApplicationFolderAuthorizationService()
        let manager = ApplicationFolderAccess(
            storageDirectory: root,
            authorizationService: authorizationService
        ) { roots in
            scannedRoots.set(roots)
            return []
        }
        require(!manager.hasStoredAuthorization, "首次启动时静默生成了文件夹授权")
        require(manager.authorize(folder: selectedFolder), "用户选择后没有保存只读授权")
        _ = manager.scanApplications()
        require(
            scannedRoots.value.map(\.standardizedFileURL.path) == [selectedFolder.standardizedFileURL.path],
            "扫描时没有使用用户明确授权的文件夹"
        )

        let restoredRoots = LockedValue<[URL]>([])
        let restarted = ApplicationFolderAccess(
            storageDirectory: root,
            authorizationService: authorizationService
        ) { roots in
            restoredRoots.set(roots)
            return []
        }
        _ = restarted.scanApplications()
        require(restarted.hasUsableAuthorization, "重启后没有恢复安全范围授权")
        require(
            restoredRoots.value.map(\.standardizedFileURL.path) == [selectedFolder.standardizedFileURL.path],
            "重启后恢复了错误的应用文件夹"
        )

        restarted.revokeAuthorization()
        require(!restarted.hasStoredAuthorization, "移除授权后仍保留安全范围书签")
        restoredRoots.set([selectedFolder])
        _ = restarted.scanApplications()
        require(restoredRoots.value.isEmpty, "移除授权后仍扫描用户文件夹")
    }

    private static func testInvalidApplicationFolderBookmarkRecovery() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-invalid-bookmark-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("not-a-bookmark".utf8).write(
                to: root.appendingPathComponent("应用文件夹授权.bookmark"),
                options: .atomic
            )
        } catch {
            fail("无法准备失效书签样本：\(error.localizedDescription)")
        }

        let rootsReceived = LockedValue<[URL]>([])
        let manager = ApplicationFolderAccess(
            storageDirectory: root,
            authorizationService: TestApplicationFolderAuthorizationService()
        ) { roots in
            rootsReceived.set(roots)
            return []
        }
        _ = manager.scanApplications()
        require(rootsReceived.value.isEmpty, "失效书签导致未授权目录进入扫描")
        require(manager.errorMessage != nil, "失效书签没有给出可恢复错误")
        require(!manager.hasStoredAuthorization, "失效书签没有被清理")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("设置验收失败：\(message)\n".utf8))
        exit(1)
    }
}
