# 自在工作台 Icon Composer 图层包

这个文件夹用于在装有最新版 Xcode / Icon Composer 的 Mac 上生成正式的 Liquid Glass 应用图标。

## 结论先行

- 不需要重新绘制 Logo。
- `01`–`04` 是从原始 SVG 几何中无损提取的四个独立前景层。
- 四个前景层均使用相同的 `1024 × 1024` 画布和原始坐标，导入后会自动对齐。
- 前景层使用纯色、不透明图形，不包含预制模糊、阴影、滤镜或外轮廓遮罩，玻璃效果交给 Icon Composer。
- `00-background-reference.svg` 只用于复现背景；推荐直接在 Icon Composer 的 Canvas 中设置背景，而不是把它作为玻璃前景层。
- 最终文件位于 `../AppIcon.icon`，已经由 Icon Composer 生成并接入 Xcode；本文件夹保留原始四层素材、规则和验证脚本，作为后续可追溯编辑来源。

## 文件用途

| 文件 | 用途 |
| --- | --- |
| `00-background-reference.svg` | 当前白色到 `#F1F1F1` 的背景参考 |
| `01-red-square.svg` | 红色方块独立层 |
| `02-blue-triangle.svg` | 蓝色三角独立层 |
| `03-yellow-square.svg` | 黄色方块独立层 |
| `04-green-circle.svg` | 绿色圆形独立层 |
| `05-flat-composite-preview.svg` | 四层合并后的平面几何预览，不要作为最终导入层 |
| `current-logo-reference.svg/png` | 当前已安装版本的视觉参考 |
| `IMPLEMENTATION_HANDOFF.md` | 与具体工具无关的工程实施与验收交接说明 |
| `ICON_COMPOSER_MANIFEST.json` | 机器可读的画布、颜色、几何和导入规则 |
| `verify_package.sh` | 本地完整性与结构检查 |
| `SHA256SUMS` | 文件哈希 |
| `../AppIcon.icon` | 已接入 Xcode Target 的最终 Liquid Glass 应用图标 |
| `../BrandMarkForeground.svg` | 仅供应用内品牌组件使用的紧凑透明四色前景；任何外观均不添加底色、描边或阴影 |

## Icon Composer 操作顺序

1. 在最新版 Xcode 中选择 `Xcode > Open Developer Tool > Icon Composer`。
2. 新建图标文档并命名为 `AppIcon`。
3. 在 Canvas 中设置背景：上部白色，画布中部开始向底部过渡到 `#F1F1F1`。
4. 分别导入 `01`、`02`、`03`、`04`，不要导入 `05` 作为正式图层。
5. 把四个图形分别放进四个独立 Group，保持原始坐标和尺寸，不要重新排版或重新绘制。
6. 为每个 Group 启用 Liquid Glass。以中等透明度、克制的高光和清晰轮廓为起点，避免强模糊和过重阴影。
7. 分别预览 macOS 的 Default、Dark 及工具中提供的 Mono/Clear/Tinted 外观，重点检查 16px、32px、64px 和 Dock 尺寸。
8. 保存为 `AppIcon.icon`。
   - Icon Composer 27 可能在 `icon.json` 顶层重新写入非空 `features`。该标记会令稳定版 Xcode 26 的 `actool` 崩溃，但删除标记不会删除各 Group 自身的折射、透明度和阴影参数。保存后必须运行 `verify_package.sh`，并在提交前移除该顶层标记。
9. 将 `AppIcon.icon` 加入 Xcode 工程；在 Target 的 `General > App Icons and Launch Screen` 中把 App Icon 设为 `AppIcon`。
10. 在真实 Mac 上检查 Finder、Dock、Spotlight、应用内标题区和 App Store 归档预览。

## 不允许发生的事情

- 不得重新画四个图形或改变几何比例。
- 不得预先裁圆角；系统负责最终遮罩。
- 不得把四层重新合并为一张 PNG 后冒充 Liquid Glass 图标。
- 不得同时让 `.icon` 和旧 Asset Catalog 成为两个互相竞争的主图标来源。
- 不得在应用内直接缩放正式 App Icon；界面品牌标识必须通过 `ZizaiBrandMark` 使用透明四色前景，浅色与深色模式都不得附加圆形底面。
- 不得只看 Icon Composer 画布就宣布完成，必须在真实 macOS 运行版中验收。

Apple 官方参考：

- https://developer.apple.com/design/human-interface-guidelines/app-icons/
- https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
- https://developer.apple.com/videos/play/wwdc2025/361/
