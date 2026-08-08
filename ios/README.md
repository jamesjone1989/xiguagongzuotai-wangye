# 西瓜老师·个人工作台 iOS

这是按 Apple Human Interface Guidelines 重新开发的原生 SwiftUI 工作台，不依赖网页容器。

## 打开与运行

1. 用 Xcode 打开 `XiguaWorkbench.xcodeproj`。
2. 选择 `XiguaWorkbench` scheme 和一台 iPhone 模拟器或已签名的真机。
3. 点击运行。

最低系统版本为 iOS 17。任务、日记和月度计划使用 SwiftData 保存在设备中；DeepSeek API Key 和跨平台同步码使用 iOS 钥匙串保存。

## 与网页版同步

1. 在 iPhone 的“今天”页点右上角设置，进入“跨设备同步”。
2. 生成同步码并复制，点“保存并立即同步”。
3. 打开网页版“设置 → 跨设备同步”，粘贴同一个同步码并点“立即同步”。

完成一次配对后，任务、待办箱、月度便签和日记会在 App 启动、回到前台和内容修改后自动合并。网络不可用时仍可继续使用本机数据，恢复联网后再同步；DeepSeek API Key 始终只保存在各自设备中。

## 已实现

- 参考 GitHub 仓库 xiguagongzuotai-wangye 重做的暖纸张、西瓜红、深绿墨色手账视觉
- 5 个稳定顶层入口：今天、计划、日程、周报、日记；设置收进今天页右上角
- 今日页自然语言收集、8:00—22:00 时间线、待办箱和拖动改时间
- 年度十二月概览、完整月历、月度便签和按日任务
- 日记先对话收集事实、细节、感受和意义，再生成可确认的草稿
- SwiftData 本地持久化
- 与网页版通过同步码双向合并，并保留本地优先的离线使用方式
- DeepSeek 任务整理与日记润色
- Keychain 密钥保存
- JSON 数据导入与导出
- Dynamic Type、VoiceOver 语义、44pt 触控目标和 SF Symbols

同步服务复用网页版现有的 Cloudflare D1 数据库，不依赖 iCloud 或 CloudKit。
