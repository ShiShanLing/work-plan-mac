# 工作计划（SwiftUI）

一款面向 **macOS** 的**本地提醒与例行事项**小工具：用系统通知帮你记住一次性事项、重复习惯，以及在指定时段内按间隔提醒；数据保存在本机，并支持**桌面小组件**快速扫一眼今日安排。

### 缘起

一开始只是想在 Mac 上找一款 **不用订阅、也不要太重** 的小工具：能帮我 **按点提醒**、把 **日常工作节奏** 落在时间表上，最好 **少绑账号、少折腾**。转了一圈，要么功能堆成「全能 GTD」用不上，要么免费档处处受限。于是干脆自己做一个：**够用就好**——定时节点、例行习惯、工作时段里按时敲一下，数据留在本机，心里也踏实。若你也在找类似定位的东西，可以试试看合不合手。

**GitHub 仓库**：[https://github.com/ShiShanLing/work-plan-mac](https://github.com/ShiShanLing/work-plan-mac)  
**下载安装包**：[Releases · ShiShanLing/work-plan-mac](https://github.com/ShiShanLing/work-plan-mac/releases)

---

## 适合谁

- 想要**轻量、不绑账号**的待办 / 提醒，不想要复杂项目管理功能。  
- 需要 **「每天 / 每周 / 每 N 天」** 等例行节奏，又不想交给纯云端服务。  
- 希望有一块 **日历月视图**，把「定时提醒」和「例行任务」叠在日期格子里（类似在月历上看分布）。  
- 需要在某段**固定时间窗口**里，按小时（或可配置间隔）重复提醒自己喝水、起来活动、闭环一小步等「时段任务」。

---

## 功能一览

| 模块 | 说明 |
|------|------|
| **定时提醒** | 一次性提醒：按日期与时间触发；支持完成勾选、按日分组、已完成历史与搜索。 |
| **例行任务** | 重复节奏：**每天、每 N 天、每周、每月、每年**；未来一段时间内的待办按日期展开浏览，并与系统通知联动。 |
| **时段提醒** | 设定**开始 / 结束**（可跨午夜「次日」）；在时段内由**本地通知**分段提醒；可在通知上标记今日完成以取消余下提醒（需定期打开应用续排通知队列，系统对本地通知数量有限制）。 |
| **日历** | **月历**汇总「定时提醒」与「例行任务」在每一天上的分布（**不含**时段提醒）；可切换查看未完成 / 已完成，点选某日查看当天条目。 |
| **桌面小组件** | **今日任务**类小组件：与主应用共享数据（App Group），展示即将发生的一条/今日相关预告；可从小组件**深链回应用**完成部分操作。 |

其他细节：

- **通知权限**：若系统关闭通知，应用内会提示并支持跳转系统设置；数据仍会保存在本机。  
- **数据存储**：使用本机 JSON 等方式持久化，**不上传业务数据到开发者服务器**（本仓库为客户端形态，无自建账号云同步说明）。  
- **界面**：SwiftUI，多 Tab 导航；启动时有简短过渡，默认窗口约 960×720，可缩放（有最小尺寸限制）。

---

## 相关页面

### 定时提醒，设置某个时间系统通知提醒，可以在系统的通知中选择一小时后提醒，或者标记完成

<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/e10d90405f704915b3a17222ae48fa8b~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775118561&x-orig-sign=YJzUTuQWvKH%2FIsUZjM2BLlSZn6g%3D" alt="image.png" width="70%" />


<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/f5225eb6bff442439b10604fa8bd3a77~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775119184&x-orig-sign=S2kxBcOBJn5%2Fwe4FgbLkOpFgSj8%3D" alt="image.png" width="70%" />

### 例行任务。可以设置每天、每N天、每周、每月、每年提醒的几点几分发送系统通知，可以设置跳过周末提醒。


<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/8ec2802e0c9e48a3a822bc919f713372~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775118744&x-orig-sign=gwq1mNjdkI%2Fc85Yq%2Fg%2BKA3QT%2BpM%3D" alt="image.png" width="70%" />


### 时段任务。每隔多少分钟提醒，可以在通知中选择不再提醒。


<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/25a88f67bb7043ae82e85bcfb3b7eb63~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775118945&x-orig-sign=gZADsntCd%2B5o9RlFfow9VyQ5EdU%3D" alt="image.png" width="70%" />


<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/c51ae2d06d094737b525374a09ca23b3~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775119145&x-orig-sign=YA717LLchRpnMYYGa3uUVw8TFXI%3D" alt="image.png" width="70%" />

### 日历中可以查看哪一天有什么任务，并且可以标记完成或者删除任务，也可以添加新的```定时任务```。

<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/093bf4e10ed845d4be7b92631edfb489~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775119325&x-orig-sign=4mBBbhXtHBuXIBD1wefvyVoc6Bo%3D" alt="image.png" width="70%" />


<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/816994fc06754c869f0a4d6bcd20814d~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775119352&x-orig-sign=t2r5K8Esh3S5LDl3e6scPG08bGo%3D" alt="image.png" width="70%" />


<img src="https://p0-xtjj-private.juejin.cn/tos-cn-i-73owjymdk6/c535eecd2439476e87fc406eb19f842c~tplv-73owjymdk6-jj-mark-v1:0:0:0:0:5o6Y6YeR5oqA5pyv56S-5Yy6IEAg55-z5bGx5bKt:q75.awebp?policy=eyJ2bSI6MywidWlkIjoiMTY0NDUyNTEyNTEyMjEzNSJ9&rk3s=e9ecf3d6&x-orig-authkey=f32326d3454f2ac7e96d3d06cdbb035152127018&x-orig-expires=1775119378&x-orig-sign=mX%2BeUO1P7CYk1ZyRSLCGBe7%2FxYE%3D" alt="image.png" width="70%" />

## 系统要求

- **macOS**（建议与 Xcode 工程中的部署目标一致，当前工程面向较新的 macOS SDK 构建，具体以 Release 构建为准）。  
- 允许在**系统设置**中为应用开启**通知**，以获得完整提醒体验。

---

## 获取安装包

- 打开仓库 [Releases](https://github.com/ShiShanLing/work-plan-mac/releases)，下载对应版本的 **`.zip`**（内含 `.app`）。  
- 若同版本附带 **`.sha256`** 文件，可用 `shasum -a 256 -c xxx.zip.sha256` 校验压缩包完整性。

克隆源码：`git clone https://github.com/ShiShanLing/work-plan-mac.git`  
本地可自行 `xcodebuild` 或使用仓库内脚本（见 `package.json` / `scripts/`）构建与发版说明。

---

## 技术栈（给开发者 / 读者）

- **SwiftUI**、**Observation**（`@Observable` 等）  
- **UserNotifications**：本地通知调度与授权  
- **WidgetKit** + **App Group**：桌面小组件与主应用数据共享  
- 部分逻辑置于 **MiniToolsCore**（Swift Package），便于测试与复用  

---







## 反馈与参与（公开项目）

本仓库为 **公开** 项目，欢迎一起变好。

- 遇到 **Bug**、有功能想法或使用上的疑问：请到 [**Issues**](https://github.com/ShiShanLing/work-plan-mac/issues) 发帖说明（尽量带 **macOS 版本、应用版本、复现步骤**，有截图或录屏更好）。  
- 若你 **熟悉 Swift / SwiftUI** 并愿意改代码：**欢迎提交 Pull Request** 修复问题或改进实现；若不确定方向，也可以先在 Issue 里简单说一下打算改什么，避免和维护者想法冲突。

感谢每一位愿意反馈或贡献时间的人。

---

## 创作说明

本项目的 **代码与文档在编写过程中使用了 AI 辅助**（例如对话式编程助手、大模型等），用于生成、修改与整理部分内容。**最终仍由维护者审阅、在本地构建测试并决定是否采纳**；若你发现因 AI 辅助导致的疏漏或质量问题，欢迎在 [Issues](https://github.com/ShiShanLing/work-plan-mac/issues) 指出。

---

## 许可证与作者

若仓库根目录另有 `LICENSE`，以该文件为准。  

项目工程内署名为「石山岭」；对外宣介可直接放仓库链接：<https://github.com/ShiShanLing/work-plan-mac> 与 [Releases](https://github.com/ShiShanLing/work-plan-mac/releases)。
