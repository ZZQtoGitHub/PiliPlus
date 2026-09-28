# tool/

仓库辅助工具，不参与应用构建，也不被打包进产物。

## jnigen.dart — 生成 Android JNI 绑定

run `dart run tool/jnigen.dart`

输入 `android/app/src/main/java`，输出 `lib/utils/android/bindings.g.dart`。
不要手改生成文件，应修改 Java 输入后重新生成（见 [开发者路线图 §12.2](../docs/DEVELOPER_ROADMAP.md)）。

## ua-view.sh — 在终端查看架构知识图谱

只读、离线，不需要浏览器 / 网络 / LLM，只需要 Node ≥ 18。
直接读取 [Understand-Anything](https://github.com/Egonex-AI/Understand-Anything) 生成的图谱。

```bash
tool/ua-view.sh overview                  # 总览：10 个架构分层 + 11 步学习导览
tool/ua-view.sh search <关键词>            # 搜索节点（名称 / 摘要 / 标签 / 路径）
tool/ua-view.sh file <节点ID|源码路径>      # 查看节点职责与上下游依赖
tool/ua-view.sh help                      # 完整用法
```

示例：

```bash
tool/ua-view.sh search 账号
tool/ua-view.sh file lib/http/init.dart              # 直接给源码路径即可
tool/ua-view.sh file class:lib/services/account_service.dart:AccountService
```

图谱来源按顺序取第一个存在的：

1. `docs/knowledge-graph/knowledge-graph.json`（已提交的正式产物）
2. `.ua/knowledge-graph.json`（本地工作目录）

可用环境变量 `UA_GRAPH=<路径>` 覆盖。运行时无需位于仓库根目录。

> 图谱只覆盖架构主干（53 个文件），不是全量代码地图：它能回答「主干模块之间如何协作」，
> 不能回答「某个边角功能在哪实现」。详见 [架构知识图谱说明](../docs/knowledge-graph/README.md)。
