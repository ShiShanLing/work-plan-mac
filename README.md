# 开发说明

环境、工程结构、构建与发版。**不描述产品功能**；用户使用说明见 [Releases](https://github.com/ShiShanLing/work-plan-mac/releases) 等处。

---

## 环境与工具

| 项目 | 说明 |
|------|------|
| **macOS** | **14.0+**（`MACOSX_DEPLOYMENT_TARGET = 14.0`）。 |
| **Xcode** | 建议 App Store 最新稳定版；打开 `MiniTools-SwiftUI.xcodeproj`。 |
| **Git** | 必需。 |
| **Node.js** | 可选：仅用于执行根目录 `package.json` 中的 `npm run …`，**无需** `npm install`。 |
| **GitHub CLI** | 本地发版：`brew install gh`，`gh auth login`（需对本仓库有 Release 写入能力）。运行脚本前若找不到 `gh`，注意 PATH 需包含 `/opt/homebrew/bin` 或 `/usr/local/bin`。 |

---

## 工程结构（改代码前先看）

| 路径 / 目标 | 作用 |
|-------------|------|
| **`MiniTools-SwiftUI.xcodeproj`** | 主 Xcode 工程。 |
| **Scheme `MiniTools-SwiftUI`** | 主 macOS 应用；日常 **⌘R** 选 **My Mac**。 |
| **`MiniToolsWidgets/`** | Widget Extension；与主应用共用 **App Group**：`group.com.MiniTools.www.MiniTools-SwiftUI`（见 `AppGroup.swift`、`WidgetSharedModels.swift`）。改 Bundle ID / Capabilities 时必须三处一致，否则小组件读不到容器数据。 |
| **`MiniToolsCore/`** | Swift Package，可单测：`swift test` 或 `npm run core:test`。 |

---

## 构建与测试

```bash
# 验证能编过（等同 npm run mac:build）
xcodebuild -scheme MiniTools-SwiftUI -project MiniTools-SwiftUI.xcodeproj -destination 'platform=macOS' build
```

```bash
cd MiniToolsCore && swift test
```

常用别名（仓库根目录）：

| 命令 | 含义 |
|------|------|
| `npm run mac:build` | 上表 `xcodebuild` |
| `npm run core:test` | `MiniToolsCore` 单测 |
| `npm run clean:caches` | 交互清理构建缓存 |
| `npm run clean:caches:yes` | 同上，跳过确认 |

**签名**：Debug 日常开发按本机 Team 即可；**Release / Archive** 需本机 Apple ID 与 Xcode 签名与主应用、Extension **同一 Team**，且勾选 App Group 等能力。

---

## 发版（维护者）

**推荐路径：本机构建 + `gh` 上传 Release**

1. 编辑 `scripts/release-local-gh.sh` 顶部 **`VERSION`**（必须以 `v` 开头）、`COMMIT_MSG`、`BRANCH`。  
2. 执行 `npm run release:local` 或 `bash scripts/release-local-gh.sh`。  
3. 已存在同名 GitHub Release 时脚本会失败，须换新版本号。  
4. 上传成功后脚本会清理 `package/`、部分 DerivedData 等；**本次** `MiniTools-SwiftUI-${VERSION}.zip` 留在仓库根。`.app` 的 **PRODUCT_NAME** 为「工作计划.app」；zip 命名保留 `MiniTools-SwiftUI-…` 与历史 Release 一致。

**与 CI 的关系**

- `.github/workflows/release-macos.yml` 在推送 **`v*`** tag 时触发，但 **仅当** 仓库 Actions 变量 **`USE_CLOUD_RELEASE === true`** 且配齐工作流文件头注释中的 **Secrets** 才会真正跑 Job。  
- **仅用本地脚本发版时，勿将 `USE_CLOUD_RELEASE` 设为 `true`**，否则推送 tag 仍可能触发云端，与本地流程重复或冲突。详情见 `release-local-gh.sh` 与工作流内注释。

**仅推 tag（不自带出包）**

- `npm run release` / `scripts/release.sh`：提交、推分支、打并推 tag。未启用云端 CI 或未配置 Secrets 时，仍须本地打包或网页上传。

---

## 克隆

```bash
git clone https://github.com/ShiShanLing/work-plan-mac.git
cd work-plan-mac
```

远程仓库目录名以实际为准；本地文件夹名可不同。

---

## 协作与协议

- **Issue / PR**：[GitHub Issues](https://github.com/ShiShanLing/work-plan-mac/issues)。提交 PR 时尽量说明影响范围（主应用 / Widget / Core）。  
- **许可证**：以仓库根目录 `LICENSE` 为准（若有）。
