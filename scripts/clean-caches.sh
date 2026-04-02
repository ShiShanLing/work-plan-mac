#!/usr/bin/env bash
# 清理本机与本项目相关的「缓存 / 构建产物 / 重复的 App Group 数据」。
#
# 用法（仓库根目录）：
#   bash scripts/clean-caches.sh                # 默认：合并 App Group json 后删除 MiniToolsData-debug；再清构建与 DerivedData
#   bash scripts/clean-caches.sh -y             # 同上，不暂停「按回车」
#   bash scripts/clean-caches.sh --debug-wins   # 合并时两份都在：一律以 debug 文件覆盖 canonical（小组件总像 debug 时用）
#   bash scripts/clean-caches.sh --build-only   # 只删 build/ReleaseDerived 与 DerivedData，不碰任务数据
#   bash scripts/clean-caches.sh --wipe-tasks   # 清空所有任务 JSON（ destructive，需输入 YES）
#
# 跑完后建议：killall WidgetKitExtension 2>/dev/null || true
# 再打开应用，让小组件重新拉时间轴。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GROUP_BASE="${HOME}/Library/Group Containers/group.com.MiniTools.www.MiniTools-SwiftUI"
DEBUG_WINS=0
BUILD_ONLY=0
WIPE_TASKS=0
SKIP_PROMPT=0

for arg in "$@"; do
  case "$arg" in
    --debug-wins) DEBUG_WINS=1 ;;
    --build-only) BUILD_ONLY=1 ;;
    --wipe-tasks) WIPE_TASKS=1 ;;
    -y | --yes) SKIP_PROMPT=1 ;;
    *)
      echo "未知参数: $arg"
      exit 1
      ;;
  esac
done

json_nonempty() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local t
  t="$(LC_ALL=C tr -d '[:space:]' <"$f" 2>/dev/null || true)"
  [[ -n "$t" && "$t" != "[]" ]]
}

mtime() {
  if [[ -f "$1" ]]; then
    stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

merge_group_json() {
  local name="$1"
  local canon="$GROUP_BASE/MiniToolsData/$name"
  local dbg="$GROUP_BASE/MiniToolsData-debug/$name"
  [[ -f "$dbg" ]] || return 0
  mkdir -p "$GROUP_BASE/MiniToolsData"
  if [[ ! -f "$canon" ]]; then
    cp -f "$dbg" "$canon"
    echo "  已复制: $name（仅 debug 侧存在）"
    return 0
  fi
  if [[ "$DEBUG_WINS" -eq 1 ]]; then
    cp -f "$dbg" "$canon"
    echo "  已覆盖: $name（--debug-wins）"
    return 0
  fi
  local mc md
  mc="$(mtime "$canon")"
  md="$(mtime "$dbg")"
  if ! json_nonempty "$canon" && json_nonempty "$dbg"; then
    cp -f "$dbg" "$canon"
    echo "  已用 debug 补全: $name（canonical 为空/[]）"
  elif [[ "$md" -gt "$mc" ]]; then
    cp -f "$dbg" "$canon"
    echo "  已用较新 debug 覆盖: $name"
  else
    echo "  保留 canonical: $name"
  fi
}

echo "=== [1/4] 退出应用 ==="
if [[ "$SKIP_PROMPT" -eq 0 ]]; then
  echo "请先 ⌘Q 退出「工作计划」。按回车继续…"
  read -r _
fi

if [[ "$BUILD_ONLY" -ne 1 ]]; then
  if [[ "$WIPE_TASKS" -eq 1 ]]; then
    echo "=== [2/4] 清空任务数据（--wipe-tasks）==="
    echo "将删除 Group Container 下 MiniToolsData / MiniToolsData-debug 与 ~/Library/Application Support/MiniTools-SwiftUI"
    echo "输入 YES 确认:"
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
      echo "已取消。"
      exit 1
    fi
    rm -rf "$GROUP_BASE/MiniToolsData" "$GROUP_BASE/MiniToolsData-debug" 2>/dev/null || true
    rm -rf "${HOME}/Library/Application Support/MiniTools-SwiftUI" 2>/dev/null || true
    echo "  已删除任务相关目录。"
  else
    echo "=== [2/4] App Group：合并 json 并删除 MiniToolsData-debug ==="
    if [[ -d "$GROUP_BASE" ]]; then
      for f in one_time_reminders.json recurring_tasks.json hourly_window_tasks.json; do
        merge_group_json "$f"
      done
      rm -rf "$GROUP_BASE/MiniToolsData-debug"
      echo "  已移除目录: MiniToolsData-debug"
    else
      echo "  无 Group Container 目录，跳过。"
    fi
  fi
else
  echo "=== [2/4] 跳过 App Group（--build-only）==="
fi

echo "=== [3/4] 仓库内 build/ReleaseDerived ==="
rm -rf "$ROOT/build/ReleaseDerived"
rm -f "$ROOT/build/last-local-release-xcodebuild.log" 2>/dev/null || true
echo "  已清理"

echo "=== [4/4] Xcode DerivedData（MiniTools-SwiftUI*）==="
shopt -s nullglob
found=0
for d in "${HOME}/Library/Developer/Xcode/DerivedData"/MiniTools-SwiftUI-*; do
  echo "  删除: $d"
  rm -rf "$d"
  found=1
done
shopt -u nullglob
[[ "$found" -eq 1 ]] || echo "  （无匹配目录）"

echo ""
echo "完成。建议执行："
echo "  killall WidgetKitExtension 2>/dev/null || true"
echo "然后重新打开「工作计划」；数据仅在 MiniToolsData/*.json 。"
