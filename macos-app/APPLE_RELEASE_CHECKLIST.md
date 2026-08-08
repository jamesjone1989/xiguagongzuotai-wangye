# 苹果发布检查清单

## 已完成

- SwiftUI 原生 macOS App，不嵌入 WebView。
- 使用 `NavigationSplitView`、原生工具栏、菜单、快捷键、Sheet 与独立 Settings Scene。
- 支持浅色、深色及跟随系统外观。
- 支持 VoiceOver 可读标签、键盘操作、系统字体与可缩放窗口。
- 数据写入 App Sandbox 的 Application Support 容器。
- JSON 导入与导出通过系统文件选择器授权。
- 已启用 App Sandbox、Hardened Runtime、用户选择文件读写和出站网络权限。
- 已配置唯一 Bundle ID、版本号、版权、应用分类与完整 App Icon。
- Release 构建、临时签名、签名校验和 ZIP 完整性检查均通过。

## 正式分发前需要开发者账号完成

1. 在 Xcode 的 Signing & Capabilities 中选择 Apple Developer Team。
2. 确认 Bundle ID `com.jiangzhichao.xigua-workbench` 在账号中可用；如已占用，改为自己的反向域名标识。
3. 如需跨设备自动同步，创建 iCloud/CloudKit Container，并为 Target 增加 iCloud Capability。
4. Product → Archive，先在 Organizer 中执行 Validate App。
5. Mac App Store：上传至 App Store Connect；站外分发：使用 Developer ID 签名并提交 Apple 公证。
6. 完成隐私说明、支持网址、营销截图、App Store 描述与年龄分级。

## 当前原生 1.0 范围

- 已原生实现：今天、月历、年历、日程、待办箱、任务编辑、完成状态、日记、周简报、设置、JSON 迁移。
- 尚未接入：CloudKit 自动同步、DeepSeek 原生客户端。现有网页工作台的数据可先导出 JSON，再从原生版“设置 → 数据”导入。
