# 西瓜老师·个人工作台

一个浏览器本地优先的个人工作台，包含：

- 月历与按月任务
- 全年十二个月总览与每月计划
- 今天的一句话 AI 任务提取
- 收件箱与按小时展开的日程；支持拖入、移动、重叠任务并列和边缘拉伸时长
- 对话生成日记与历史搜索
- DeepSeek 任务提取与日记整理
- JSON 数据导入与导出

## iOS App

仓库中的 `ios/XiguaWorkbench.xcodeproj` 是按 Apple Human Interface Guidelines 重新开发的 iPhone / iPad 原生版本，使用 SwiftUI、SwiftData 和 Keychain，不依赖网页容器。使用方式见 `ios/README.md`。

## 本地运行

```bash
npm install
npm run dev
```

打开 `http://localhost:3000`。

## 原生 macOS 桌面版

`macos-app/` 是按照苹果桌面应用结构重新开发的 SwiftUI 原生工程，不是网页套壳。它包含原生侧边栏、工具栏、菜单与快捷键，原生任务/月历/年历/日程/待办箱/日记/周简报，以及标准 macOS 设置窗口。

工程启用了 App Sandbox、Hardened Runtime、用户选择文件权限和独立 Application Support 数据目录；JSON 导入兼容现有网页工作台导出的备份。

使用 Xcode 打开：

```text
macos-app/XiguaWorkbench.xcodeproj
```

直接生成本机测试版：

```bash
npm run mac:build
```

完成后可在 `release/` 中找到 `西瓜老师工作台.app` 和 ZIP 安装包。当前部署目标为 macOS 14 及以上版本，Release 构建由 Xcode 编译并进行本机临时签名。

如需分发给其他人或提交 Mac App Store，需要在 Xcode 中选择自己的 Apple Developer Team，创建 Archive，并使用 Developer ID 公证或 App Store Connect 正式签名。临时签名构建只用于当前 Mac 验收。

## 数据与隐私

任务、日记、AI 对话和 DeepSeek API Key 默认保存在当前浏览器的
`localStorage`。API Key 不会写入源码，也不会包含在导出的 JSON 备份里。

如果清理浏览器数据，本地记录可能消失，请定期在设置中导出备份。

DeepSeek 通过浏览器直接访问其 Chat Completions API。某些网络或浏览器策略可能会
阻止直接请求；发生这种情况时，页面会提示检查网络或密钥。

AI 只能整理用户明确提供的内容。AI 生成的日记只会进入草稿，必须由用户确认并主动保存。
