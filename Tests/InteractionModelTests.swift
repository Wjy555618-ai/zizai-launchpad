import AppKit
import Foundation

@main
struct InteractionModelTests {
    static func main() {
        testContentFitting()
        testResponsiveGroupHeader()
        testStableDragTranslation()
        testPointerAnchoredZoom()
        testViewportVisibility()
        testEightWayResize()
        testInsertionNormalization()
        testLibraryAppInsertion()
        testSafeReordering()
        testSearchMatching()
        print("交互模型测试通过：内容适配、鼠标锚点缩放、视口辅助功能、紧凑标题响应、八方向缩放、安全换序和即时模糊搜索均符合统一规则。")
    }

    private static func testViewportVisibility() {
        let viewport = CGSize(width: 1_200, height: 800)
        require(
            InteractionGeometry.isVisibleInViewport(
                center: CGPoint(x: 600, y: 400), viewport: viewport, margin: 72
            ),
            "视口内应用不应从辅助功能树隐藏"
        )
        require(
            InteractionGeometry.isVisibleInViewport(
                center: CGPoint(x: -60, y: 400), viewport: viewport, margin: 72
            ),
            "刚进入视口边缘的应用应保留辅助功能入口"
        )
        require(
            !InteractionGeometry.isVisibleInViewport(
                center: CGPoint(x: 1_400, y: 400), viewport: viewport, margin: 72
            ),
            "远离视口的应用不应成为 VoiceOver 幽灵元素"
        )
    }

    private static func testStableDragTranslation() {
        let screenTranslation = CGSize(width: 48, height: -36)
        let worldTranslation = InteractionGeometry.worldTranslation(
            fromScreen: screenTranslation,
            scale: 0.5
        )
        require(
            worldTranslation == CGSize(width: 96, height: -72),
            "50% 缩放下拖动位移没有保持稳定的指针比例"
        )

        let fallback = InteractionGeometry.worldTranslation(
            fromScreen: CGSize(width: 1, height: 1),
            scale: 0
        )
        require(
            fallback.width.isFinite && fallback.height.isFinite,
            "异常缩放值产生了非有限拖动位移"
        )
    }

    private static func testPointerAnchoredZoom() {
        let viewport = CGSize(width: 1_200, height: 800)
        let anchor = CGPoint(x: 930, y: 170)
        let oldOffset = CGSize(width: 140, height: -60)
        let oldScale: CGFloat = 0.52
        let newScale: CGFloat = 1.12

        let worldBefore = canvasWorldPoint(
            below: anchor,
            offset: oldOffset,
            scale: oldScale,
            viewport: viewport
        )
        let newOffset = InteractionGeometry.anchoredCanvasOffset(
            currentOffset: oldOffset,
            oldScale: oldScale,
            newScale: newScale,
            anchor: anchor,
            viewport: viewport
        )
        let worldAfter = canvasWorldPoint(
            below: anchor,
            offset: newOffset,
            scale: newScale,
            viewport: viewport
        )
        require(approximatelyEqual(worldBefore.x, worldAfter.x), "缩放后鼠标下方的横向画布坐标发生漂移")
        require(approximatelyEqual(worldBefore.y, worldAfter.y), "缩放后鼠标下方的纵向画布坐标发生漂移")

        let restoredOffset = InteractionGeometry.anchoredCanvasOffset(
            currentOffset: newOffset,
            oldScale: newScale,
            newScale: oldScale,
            anchor: anchor,
            viewport: viewport
        )
        require(approximatelyEqual(restoredOffset.width, oldOffset.width), "往返缩放没有恢复横向偏移")
        require(approximatelyEqual(restoredOffset.height, oldOffset.height), "往返缩放没有恢复纵向偏移")
    }

    private static func canvasWorldPoint(
        below anchor: CGPoint,
        offset: CGSize,
        scale: CGFloat,
        viewport: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (anchor.x - viewport.width / 2 - offset.width) / scale,
            y: (anchor.y - viewport.height / 2 - offset.height) / scale
        )
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.000_1
    }

    private static func testResponsiveGroupHeader() {
        require(
            InteractionGeometry.showsGroupHeader(
                forScreenSize: CGSize(width: 360, height: 300),
                scale: 1
            ),
            "正常尺寸分组不应隐藏标题栏"
        )
        require(
            !InteractionGeometry.showsGroupHeader(
                forScreenSize: CGSize(width: 270, height: 210),
                scale: 0.75
            ),
            "紧凑宽度下应隐藏标题栏"
        )
        require(
            !InteractionGeometry.showsGroupHeader(
                forScreenSize: CGSize(width: 420, height: 180),
                scale: 0.60
            ),
            "紧凑高度下应隐藏标题栏"
        )
        require(
            InteractionGeometry.showsUnifiedGroupHeaders(atScale: 1),
            "正常缩放下所有分组应统一显示标题栏"
        )
        require(
            !InteractionGeometry.showsUnifiedGroupHeaders(atScale: 0.78),
            "紧凑缩放下所有分组应统一隐藏标题栏"
        )
    }

    private static func testContentFitting() {
        for count in [1, 2, 4, 5, 9, 10, 16, 23] {
            let size = InteractionGeometry.fittedGroupSize(for: count)
            let frame = CGRect(origin: .zero, size: size)
            require(
                InteractionGeometry.capacity(of: frame) >= count,
                "\(count) 个应用的适配尺寸容量不足"
            )
            require(
                size.width >= InteractionGeometry.minimumGroupWidth
                    && size.height >= InteractionGeometry.minimumGroupHeight,
                "适配尺寸小于操作下限"
            )
        }

        require(
            InteractionGeometry.fittedGroupSize(for: 1).width
                < InteractionGeometry.fittedGroupSize(for: 9).width,
            "小分组不应保留与大分组相同的空白宽度"
        )
    }

    private static func testEightWayResize() {
        let source = CGRect(x: 100, y: 100, width: 400, height: 300)
        let delta = CGSize(width: 40, height: 30)
        let expected: [ResizeHandle: CGRect] = [
            .top: CGRect(x: 100, y: 130, width: 400, height: 270),
            .bottom: CGRect(x: 100, y: 100, width: 400, height: 330),
            .left: CGRect(x: 140, y: 100, width: 360, height: 300),
            .right: CGRect(x: 100, y: 100, width: 440, height: 300),
            .topLeft: CGRect(x: 140, y: 130, width: 360, height: 270),
            .topRight: CGRect(x: 100, y: 130, width: 440, height: 270),
            .bottomLeft: CGRect(x: 140, y: 100, width: 360, height: 330),
            .bottomRight: CGRect(x: 100, y: 100, width: 440, height: 330),
        ]

        for handle in ResizeHandle.allCases {
            require(
                handle.resizedFrame(from: source, translation: delta) == expected[handle],
                "\(handle) 缩放结果错误"
            )
        }
    }

    private static func testInsertionNormalization() {
        require(
            InteractionGeometry.normalizedInsertionIndex(
                movingFrom: 1,
                proposed: 4,
                itemCount: 5
            ) == 3,
            "从前向后移动时未扣除原位置"
        )
        require(
            InteractionGeometry.normalizedInsertionIndex(
                movingFrom: 4,
                proposed: 1,
                itemCount: 5
            ) == 1,
            "从后向前移动时错误偏移"
        )
    }

    private static func testLibraryAppInsertion() {
        let group = AppDragGroupFrame(
            groupID: "group-a",
            frame: CGRect(x: 0, y: 0, width: 620, height: 420)
        )
        let frames = [
            AppDragItemFrame(
                appID: "a", groupID: "group-a", index: 0, frame: CGRect(x: 40, y: 100, width: 120, height: 110)),
            AppDragItemFrame(
                appID: "b", groupID: "group-a", index: 1, frame: CGRect(x: 176, y: 100, width: 120, height: 110)),
            AppDragItemFrame(
                appID: "c", groupID: "group-a", index: 2, frame: CGRect(x: 312, y: 100, width: 120, height: 110)),
            AppDragItemFrame(
                appID: "d", groupID: "group-a", index: 3, frame: CGRect(x: 40, y: 224, width: 120, height: 110)),
        ]

        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 305, y: 155),
                appFrames: frames,
                groupFrames: [group],
                excluding: "a"
            ) == AppDragInsertion(groupID: "group-a", index: 2),
            "图标间隙没有解析为稳定插入位置"
        )
        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 390, y: 155),
                appFrames: frames,
                groupFrames: [group],
                excluding: "a"
            ) == AppDragInsertion(groupID: "group-a", index: 3),
            "应用右半区域没有解析为其后方插入位置"
        )
        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 390, y: 155),
                appFrames: frames,
                groupFrames: [],
                excluding: "a"
            ) == AppDragInsertion(groupID: "group-a", index: 3),
            "可见应用卡片不应因惰性容器几何尚未更新而失去投放能力"
        )
        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 560, y: 360),
                appFrames: frames,
                groupFrames: [group],
                excluding: "a"
            ) == nil,
            "分组无关空白区不应被误判为移到末尾"
        )
        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 470, y: 155),
                appFrames: frames,
                groupFrames: [group],
                excluding: "a"
            ) == AppDragInsertion(groupID: "group-a", index: 3),
            "最后一项旁边的明确落点应支持追加"
        )
        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 700, y: 155),
                appFrames: frames,
                groupFrames: [group],
                excluding: "a"
            ) == nil,
            "分组外松手应取消移动"
        )

        let emptyGroup = AppDragGroupFrame(
            groupID: "group-empty",
            frame: CGRect(x: 700, y: 0, width: 360, height: 300)
        )
        require(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 820, y: 180),
                appFrames: frames,
                groupFrames: [group, emptyGroup],
                excluding: "a"
            ) == AppDragInsertion(groupID: "group-empty", index: 0),
            "空分组应接受第一个应用"
        )
    }

    private static func testSafeReordering() {
        let ids = ["a", "b", "c", "d"]
        require(
            InteractionGeometry.reorderedIDs(ids, movingID: "b", toInsertionIndex: 2) == ids,
            "相邻同位置投放不应删除分组"
        )
        require(
            InteractionGeometry.reorderedIDs(ids, movingID: "b", toInsertionIndex: 4) == ["a", "c", "d", "b"],
            "向后移动分组的插入位置错误"
        )
        require(
            InteractionGeometry.reorderedIDs(ids, movingID: "d", toInsertionIndex: 1) == ["a", "d", "b", "c"],
            "向前移动分组的插入位置错误"
        )
        require(
            InteractionGeometry.reorderedIDs(ids, movingID: "missing", toInsertionIndex: 0) == ids,
            "未知分组不应改变顺序"
        )

        let frames = [
            AppDragGroupFrame(groupID: "a", frame: CGRect(x: 0, y: 0, width: 400, height: 180)),
            AppDragGroupFrame(groupID: "b", frame: CGRect(x: 0, y: 200, width: 400, height: 180)),
            AppDragGroupFrame(groupID: "c", frame: CGRect(x: 0, y: 400, width: 400, height: 180)),
            AppDragGroupFrame(groupID: "d", frame: CGRect(x: 0, y: 600, width: 400, height: 180)),
        ]
        let adjacentInsertion = InteractionGeometry.groupInsertionIndex(
            at: CGPoint(x: 100, y: 220),
            groupFrames: frames,
            orderedGroupIDs: ids,
            movingGroupID: "a"
        )
        require(
            adjacentInsertion == 2
                && InteractionGeometry.reorderedIDs(
                    ids,
                    movingID: "a",
                    toInsertionIndex: adjacentInsertion ?? 0
                ) == ["b", "a", "c", "d"],
            "拖到相邻分组本体必须产生可感知重排"
        )
    }

    private static func testSearchMatching() {
        let weChat = ApplicationSearchDocument(
            userFacingTerms: ["微信", "WeChat", "即时沟通"],
            technicalTerms: ["com.tencent.xinWeChat"]
        )
        let messages = ApplicationSearchDocument(
            userFacingTerms: ["信息", "Messages", "短信", "iMessage"],
            technicalTerms: ["com.apple.MobileSMS"]
        )
        let codex = ApplicationSearchDocument(
            userFacingTerms: ["Codex", "OpenAI Codex", "代码助手"],
            technicalTerms: ["com.openai.codex"]
        )
        require(ApplicationSearchPolicy.match(query: "信", document: weChat) != nil, "中文单字没有命中微信")
        require(ApplicationSearchPolicy.match(query: "信", document: messages) != nil, "中文单字没有命中信息/短信")
        require(ApplicationSearchPolicy.match(query: "wec", document: weChat) != nil, "英文连续片段没有命中 WeChat")
        require(ApplicationSearchPolicy.match(query: "wct", document: weChat)?.tier == .fuzzy, "英文模糊子序列没有命中 WeChat")
        require(ApplicationSearchPolicy.match(query: "o", document: codex) != nil, "英文单字没有命中 Codex")
        require(ApplicationSearchPolicy.match(query: "cdx", document: codex)?.tier == .fuzzy, "英文字母子序列没有命中 Codex")
        require(ApplicationSearchPolicy.match(query: "notion", document: weChat) == nil, "无关关键词被错误命中")
        if let exact = ApplicationSearchPolicy.match(query: "微信", document: weChat),
            let fuzzy = ApplicationSearchPolicy.match(query: "wct", document: weChat)
        {
            require(exact < fuzzy, "精确匹配没有优先于模糊匹配")
        } else {
            require(false, "搜索测试缺少必要匹配")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("交互模型测试失败：\(message)\n".utf8))
            exit(1)
        }
    }
}
