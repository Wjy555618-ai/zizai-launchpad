import AppKit
import CoreServices

enum LaunchPresentationAction: Equatable {
    case present
    case suppress
    case none
}

struct LaunchPresentationState: Equatable {
    private enum Phase: Equatable {
        case interactive
        case suppressingLoginLaunch
        case silentLoginReady
    }

    private var phase: Phase

    init(isLoginItemLaunch: Bool) {
        phase = isLoginItemLaunch ? .suppressingLoginLaunch : .interactive
    }

    var isSilentLoginLaunch: Bool {
        phase != .interactive
    }

    mutating func applicationDidFinishLaunching() -> LaunchPresentationAction {
        phase == .interactive ? .present : .suppress
    }

    mutating func applicationDidBecomeActive() -> LaunchPresentationAction {
        switch phase {
        case .interactive:
            return .present
        case .suppressingLoginLaunch:
            return .suppress
        case .silentLoginReady:
            phase = .interactive
            return .present
        }
    }

    mutating func silentSuppressionDidSettle() {
        guard phase == .suppressingLoginLaunch else { return }
        phase = .silentLoginReady
    }

    mutating func userRequestedPresentation() -> LaunchPresentationAction {
        phase = .interactive
        return .present
    }
}

enum LoginItemLaunchDetector {
    static func isLoginItemLaunch(
        event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> Bool {
        guard let event,
            event.eventClass == AEEventClass(kCoreEventClass),
            event.eventID == AEEventID(kAEOpenApplication)
        else {
            return false
        }

        // The launch Apple event historically used both forms below. The SDK
        // contract defines the direct key by presence, not by its Boolean value.
        if event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil {
            return true
        }

        guard let propertyData = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return propertyData.descriptorType == DescType(keyAELaunchedAsLogInItem)
            || propertyData.typeCodeValue == DescType(keyAELaunchedAsLogInItem)
    }
}
