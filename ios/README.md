# 西瓜老师·个人工作台 iOS

这是按 Apple Human Interface Guidelines 重新开发的原生 SwiftUI 工作台，不依赖网页容器。

## 打开与运行

1. 用 Xcode 打开 `XiguaWorkbench.xcodeproj`。
2. 选择 `XiguaWorkbench` scheme 和一台 iPhone 模拟器或已签名的真机。
3. 点击运行。

最低系统版本为 iOS 17。任务、日记和月度计划使用 SwiftData 保存在设备中；DeepSeek API Key 使用 iOS 钥匙串保存。

## 已实现

- 5 个稳定顶层入口：今天、日历、待办、日记、设置
- SwiftData 本地持久化
- 原生日历、全年月份概览、月度计划和本周简报
- 系统表单式任务与日记编辑
- DeepSeek 任务整理与日记润色
- Keychain 密钥保存
- JSON 数据导入与导出
- Dynamic Type、深色模式、VoiceOver 语义和 SF Symbols

跨设备 iCloud 同步需要在确定 Apple Developer Team 与 CloudKit Container 后再启用，当前版本不会伪装成已同步状态。
