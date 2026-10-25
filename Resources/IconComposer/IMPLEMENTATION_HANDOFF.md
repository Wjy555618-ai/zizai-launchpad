# Icon Composer 实施交接

使用本目录的已验证图层，为“自在启动台”维护正式的 macOS Liquid Glass 应用图标。

开始前必须运行：

```zsh
/bin/zsh ./verify_package.sh
```

以 `START_HERE.md` 和 `ICON_COMPOSER_MANIFEST.json` 为唯一实施契约。四个前景 SVG 来自已经确认的原始设计，不得重绘、改变比例、移动相对位置或替换颜色。

使用当前稳定版 Icon Composer：

1. 打开并继续维护 `../AppIcon.icon`，不要创建平行的主图标文件。
2. 用 Canvas 保持 `00-background-reference.svg` 所描述的白色到 `#F1F1F1` 背景。
3. 保持 `01`–`04` 为四个独立 Group，不得合并成一张位图。
4. 为四个 Group 使用一致且克制的 Liquid Glass 参数，不添加与品牌无关的装饰。
5. 验证 macOS Default、Dark、Mono/Clear/Tinted，以及 16px、32px、64px、Finder 和 Dock 尺寸。
6. 确认 Xcode Target 仅使用 `AppIcon.icon` 作为正式主图标来源。
7. 若使用 Icon Composer 27 保存，运行 `verify_package.sh` 检查并移除 `icon.json` 顶层非空 `features` 标记；稳定版 Xcode 26 会因该预览标记崩溃，而各 Group 的正式材质参数必须保留。
8. 在真实 Mac 上构建、安装并刷新系统图标缓存后完成可见验收。

交付记录至少应包含：

- 最终 `AppIcon.icon` 文件及其版本；
- Icon Composer 各外观和关键尺寸预览；
- Xcode Target 图标配置；
- 已安装应用在 Finder、Dock 和应用内标题区的检查结果；
- 构建、签名和图标资源检查结果；
- 尚未解决的限制及其影响。

图标工程交接不授权提交 App Store；提交行为需要发布负责人另行确认。
