# 自在启动台当前产品工程验证记录

当前质量判定方法已统一收口到仓库根目录的 `QUALITY_REPORT.md`。实际测试数字、环境和源码指纹不再手工复制到文档，而是在完整门槛通过后写入 `.artifacts.noindex/quality-evidence.json`。

本文件只保留为历史证据路径的稳定入口，避免旧的应用数量、哈希和运行结论继续漂移。以后不得在这里复制另一份独立质量数据；产品事实以 `CURRENT_PRODUCT_BASELINE.md` 为准，门槛规则以 `QUALITY_REPORT.md` 为准，当次结果以机器生成证据为准。
