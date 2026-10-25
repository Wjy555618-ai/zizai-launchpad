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
