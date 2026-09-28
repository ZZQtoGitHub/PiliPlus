#!/usr/bin/env bash
#
# ua-view.sh — 在终端查看 Understand-Anything 为 PiliPlus 生成的知识图谱
#
# 只读、离线：不需要浏览器、不需要网络、不需要 LLM，只解析
# docs/knowledge-graph/knowledge-graph.json。
#
# 运行 `tool/ua-view.sh help` 查看完整用法。
#
# 图谱数据来源（按顺序取第一个存在的）：
#   1. docs/knowledge-graph/knowledge-graph.json   已提交的正式产物
#   2. .ua/knowledge-graph.json                    本地工作目录
# 也可用环境变量 UA_GRAPH 显式指定其他路径。

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

GRAPH_CANDIDATES=(
  "$REPO_ROOT/docs/knowledge-graph/knowledge-graph.json"
  "$REPO_ROOT/.ua/knowledge-graph.json"
)

usage() {
  cat <<'EOF'
ua-view.sh — 在终端查看 Understand-Anything 生成的知识图谱

用法:
  tool/ua-view.sh overview                 总览：架构分层 + 学习导览
  tool/ua-view.sh search <关键词>           搜索节点（名称 / 摘要 / 标签 / 路径）
  tool/ua-view.sh file <节点ID|源码路径>     查看节点的职责与上下游依赖
  tool/ua-view.sh help                     显示本帮助

示例:
  tool/ua-view.sh overview
  tool/ua-view.sh search 账号
  tool/ua-view.sh search AccountManager
  tool/ua-view.sh file lib/http/init.dart
  tool/ua-view.sh file file:lib/http/init.dart

参数说明:
  <关键词>   任意中英文片段，大小写不敏感；可搜中文，如「播放」「弹幕」
  <节点ID>   形如 file:... / class:... / function:...
             也可直接写源码路径，脚本会自动补上 file: 前缀

数据来源（按顺序取第一个存在的）:
  docs/knowledge-graph/knowledge-graph.json
  .ua/knowledge-graph.json
  可用环境变量 UA_GRAPH 指定其他路径。

依赖: node (>= 18)

提示: 图谱只覆盖架构主干（53 个文件），不是全量代码地图。
      它能回答「主干模块之间如何协作」，不能回答「某个边角功能在哪实现」。
      详见 docs/knowledge-graph/README.md。
EOF
}

die() { printf '错误：%s\n' "$*" >&2; exit 1; }

# ── 定位图谱文件 ─────────────────────────────────────────────────

GRAPH="${UA_GRAPH:-}"
if [ -n "$GRAPH" ]; then
  # 显式指定时不再回退，路径写错就直接报错，避免静默用了别的图谱。
  [ -f "$GRAPH" ] || die "UA_GRAPH 指定的图谱文件不存在: $GRAPH"
else
  for candidate in "${GRAPH_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then GRAPH="$candidate"; break; fi
  done

  if [ -z "$GRAPH" ]; then
    {
      echo "错误：找不到知识图谱文件。已尝试以下路径："
      printf '  %s\n' "${GRAPH_CANDIDATES[@]}"
      echo "请先运行 Understand-Anything 的 /understand 生成图谱，"
      echo "或用 UA_GRAPH=<路径> 显式指定图谱文件。"
    } >&2
    exit 1
  fi
fi

command -v node >/dev/null 2>&1 || die "未找到 node，本脚本需要 Node.js (>= 18)。"

# ── 总览：分层 + 导览 ────────────────────────────────────────────

OVERVIEW_JS=$(cat <<'JS'
const g = require(process.argv[1]);
const p = g.project || {};
console.log("图谱     : " + process.argv[1]);
console.log("项目     : " + (p.name || "?") + "  |  " + (p.frameworks || []).join(", "));
if (p.gitCommitHash) console.log("绑定提交 : " + String(p.gitCommitHash).slice(0, 7));
console.log("\n架构分层（共 " + g.layers.length + " 层）:");
g.layers.forEach((l, i) => {
  console.log("  " + String(i + 1).padStart(2) + ". " + l.name + "  [" + l.nodeIds.length + " 节点]");
  if (l.description) console.log("      " + l.description);
});
console.log("\n学习导览（共 " + g.tour.length + " 步）:");
g.tour.forEach(s => console.log("  " + String(s.order).padStart(2) + ". " + s.title));
console.log("\n规模: " + g.nodes.length + " 节点 / " + g.edges.length + " 边");
console.log("下一步: tool/ua-view.sh search <关键词>   或   tool/ua-view.sh file <节点ID>");
JS
)

# ── 搜索节点 ─────────────────────────────────────────────────────

SEARCH_JS=$(cat <<'JS'
const g = require(process.argv[1]);
const q = process.argv[2];
const needle = q.toLowerCase();
const hits = g.nodes.filter(n => [
  n.name, n.summary, (n.tags || []).join(" "), n.filePath || "", n.id
].join(" ").toLowerCase().includes(needle));

if (hits.length === 0) {
  console.log('没有匹配 "' + q + '" 的节点。');
  console.log("试试更短的关键词，或先看 tool/ua-view.sh overview 了解分层。");
  process.exit(0);
}

const LIMIT = 15;
console.log("命中 " + hits.length + " 个节点（关键词: " + q + "）" +
  (hits.length > LIMIT ? "，仅显示前 " + LIMIT + " 个" : "") + "\n");
hits.slice(0, LIMIT).forEach(n => {
  console.log("[" + n.type + "]  " + n.id);
  console.log("       " + n.name + " — " +
    String(n.summary || "").replace(/\s+/g, " ").slice(0, 90));
});
if (hits.length > LIMIT) {
  console.log("\n（共 " + hits.length + " 个，请换更精确的关键词）");
}
JS
)

# ── 单节点详情 + 依赖 ────────────────────────────────────────────

FILE_JS=$(cat <<'JS'
const g = require(process.argv[1]);
const raw = process.argv[2];

let id = raw;
if (!g.nodes.some(n => n.id === id)) {
  const guess = "file:" + raw.replace(/^\.?\//, "");
  if (g.nodes.some(n => n.id === guess)) id = guess;
}

const n = g.nodes.find(x => x.id === id);
if (!n) {
  console.log("未找到节点: " + raw);
  console.log("提示: 用 `tool/ua-view.sh search <关键词>` 查到正确 id 后再试。");
  process.exit(1);
}

console.log(n.name + "  [" + n.type + "]" + (n.complexity ? "  复杂度: " + n.complexity : ""));
console.log("id   : " + n.id);
if (n.filePath) console.log("文件 : " + n.filePath);
if (n.tags && n.tags.length) console.log("标签 : " + n.tags.join(" / "));
console.log("\n" + (n.summary || "(无摘要)"));

const out = g.edges.filter(e => e.source === id);
const inc = g.edges.filter(e => e.target === id);

console.log("\n依赖 -> (" + out.length + ")");
if (out.length === 0) console.log("   (无)");
out.forEach(e => console.log("   -> " + e.target + "  (" + e.type + ")"));

console.log("\n被依赖 <- (" + inc.length + ")");
if (inc.length === 0) console.log("   (无)");
inc.forEach(e => console.log("   <- " + e.source + "  (" + e.type + ")"));
JS
)

# ── 分发 ─────────────────────────────────────────────────────────

case "${1:-help}" in
  overview|o)
    node -e "$OVERVIEW_JS" "$GRAPH"
    ;;
  search|s)
    [ $# -ge 2 ] || die "search 需要一个关键词。例如: tool/ua-view.sh search 账号"
    node -e "$SEARCH_JS" "$GRAPH" "$2"
    ;;
  file|f)
    [ $# -ge 2 ] || die "file 需要一个节点 ID 或源码路径。例如: tool/ua-view.sh file lib/http/init.dart"
    node -e "$FILE_JS" "$GRAPH" "$2"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    printf '错误：未知命令 %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
