import Foundation

@main
@MainActor
enum UIRuntimeAuditMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            fail("缺少审计命令")
        }

        switch command {
        case "tab-content":
            TabContentPerformanceAudit.run()
        case "tooltip":
            TooltipLayeringAudit.run()
        case "canvas":
            CanvasInteractionPerformanceAudit.run()
        case "render":
            VisualRenderAudit.run(arguments: Array(arguments.dropFirst()))
        default:
            fail("未知审计命令：\(command)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("界面运行时验收失败：\(message)\n".utf8))
        exit(2)
    }
}

/// Runtime audits never mutate the operator's applications. They still build
/// the same dependency graph as production so missing coordinator injection
/// fails during audit construction instead of being hidden by test-only view
/// branches.
@MainActor
final class AuditApplicationRemovalAuthorizer: ApplicationRemovalAuthorizing {
    var removalErrorMessage: String? { nil }

    func hasRemovalAuthorization(for _: URL) -> Bool { false }

    func authorizeRemoval(folder _: URL, containing _: URL) -> Bool { false }

    func beginRemovalAccess(for _: URL) -> URL? { nil }

    func endRemovalAccess(_: URL) {}

    func reportRemovalSelectionError(_: Error) {}
}
