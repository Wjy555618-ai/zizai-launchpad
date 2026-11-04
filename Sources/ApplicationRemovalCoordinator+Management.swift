import Foundation

enum ApplicationManagementTrigger {
    case longPress
    case accessibility
    case removalRequest
}

enum ApplicationManagementEndReason {
    case explicit
    case outsideInteraction
    case inactivity
    case navigation
    case lifecycle
}

enum ApplicationManagementPolicy {
    static let inactivityTimeout: TimeInterval = 30

    static func inactivityTimeout(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        #if DEBUG
            if ZizaiLaunchConfiguration.launchMode(environment: environment) == .uiTesting,
                let rawValue = environment[ZizaiLaunchConfiguration.uiTestManagementTimeoutEnvironmentKey],
                let value = TimeInterval(rawValue),
                value > 0
            {
                return value
            }
        #endif
        return inactivityTimeout
    }
}

@MainActor
extension ApplicationRemovalCoordinator {
    func beginManagement(trigger: ApplicationManagementTrigger = .accessibility) {
        if !isManaging {
            transition(to: .entering)
            schedulePhaseTransition(
                from: .entering,
                to: .active,
                after: ApplicationManagementMotion.entryDuration
            )
        }
        interactionRevision &+= 1
        ignoresNextPointerUp = trigger == .longPress
        refreshInactivityTimer()
    }

    func endManagement(reason: ApplicationManagementEndReason = .explicit) {
        // Alerts, the system authorization panel, and an in-flight recycle are
        // one modal flow. Window focus changes or the global pointer monitor
        // must not tear down half of that state machine.
        guard !hasBlockingInteraction else { return }
        guard isManagementPresented, managementPhase != .exiting else { return }

        phaseTransitionTask?.cancel()
        if reason.animatesVisualExit {
            transition(to: .exiting)
            schedulePhaseTransition(
                from: .exiting,
                to: .inactive,
                after: ApplicationManagementMotion.exitDuration
            )
        } else {
            transition(to: .inactive)
        }
        interactionRevision &+= 1
        ignoresNextPointerUp = false
        inactivityTask?.cancel()
        inactivityTask = nil
    }

    /// The window-level input monitor observes pointer-up before SwiftUI routes
    /// that event to a button. Deferring the decision by one run-loop turn lets
    /// a removal or Done action claim the same event by changing the revision.
    /// The pointer-up that completes the entry long press is consumed once so
    /// management does not immediately close after it opens.
    func endAfterUnclaimedPointerInteraction() {
        guard isManaging else { return }
        if ignoresNextPointerUp {
            ignoresNextPointerUp = false
            noteActivity()
            return
        }

        let observedRevision = interactionRevision
        DispatchQueue.main.async { [weak self] in
            guard let self,
                self.isManaging,
                self.interactionRevision == observedRevision,
                !self.hasBlockingInteraction
            else { return }
            self.endManagement(reason: .outsideInteraction)
        }
    }

    func noteActivity() {
        guard isManaging else { return }
        interactionRevision &+= 1
        refreshInactivityTimer()
    }

    func refreshInactivityTimer() {
        inactivityTask?.cancel()
        inactivityTask = nil
        guard isManaging, !hasBlockingInteraction else { return }

        let observedRevision = interactionRevision
        let timeout = managementInactivityNanoseconds
        inactivityTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled,
                let self,
                self.isManaging,
                self.interactionRevision == observedRevision,
                !self.hasBlockingInteraction
            else { return }
            self.endManagement(reason: .inactivity)
        }
    }

    private func transition(to phase: ApplicationManagementPhase) {
        transitionManagementPhase(to: phase)
    }

    private func schedulePhaseTransition(
        from expectedPhase: ApplicationManagementPhase,
        to nextPhase: ApplicationManagementPhase,
        after duration: TimeInterval
    ) {
        phaseTransitionTask?.cancel()
        let nanoseconds = UInt64(duration * 1_000_000_000)
        phaseTransitionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled,
                let self,
                self.managementPhase == expectedPhase
            else { return }
            self.transition(to: nextPhase)
            self.phaseTransitionTask = nil
        }
    }
}
