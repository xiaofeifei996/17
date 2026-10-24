# 赶集日记 · GanJi 1.4.0

基于原 GanJi v102 源码的现代简约版重构。保留原始集市接口、离线缓存、农历/圩期计算、地区切换、地图标注、附近距离、日期筛选、地点搜索、收藏与 WidgetKit 桌面小组件。

## 项目结构

- `GanJi/`：SwiftUI iOS 主应用、地图与地点搜索、定位、网络 API、收藏状态和 App 图标。
- `Shared/`：集市数据模型、农历/圩期算法、随包数据 `markets.json`、行政区数据 `regions.json`。主应用和小组件共用。
- `Widget/`：WidgetKit 小组件与背景资源。
- `Tests/`：集市数据和日历规则回归检查。
- `GanJi.xcodeproj/`：可直接在 macOS 的 Xcode 中打开的项目。
- `project.yml`：XcodeGen 项目描述，供 CI 或开发者重新生成工程。

## 打开和运行

1. 在 macOS 上用 Xcode 打开 `GanJi.xcodeproj`。
2. 选择 `GanJi` scheme 和 iOS Simulator 或已连接的 iPhone。
3. 首次在设备上运行时，允许定位权限以计算附近距离；拒绝定位后仍可按地区浏览。
4. 网络接口为 `https://api.ganjirili.com/gathers`。网络失败时优先使用该地区缓存，其次使用包内数据。

如果想用 XcodeGen 重新生成工程：

```sh
brew install xcodegen
xcodegen generate
```

## 本次改动

- 更新主页层级、日期提示卡、卡片圆角、间距、字体与配色，统一为现代简约的浅色界面。
- 优化集市列表的选中状态与信息层级，并调整地图面板默认高度。
- 为地区请求加入请求序号保护：快速切换地区时，较晚返回的旧请求不会覆盖当前地区结果。
- 保留 API 的字段映射和缓存行为，不将未知圩期编码猜测成固定规则。
- 将版本更新为 `1.4.0 (28)`。

## 验证情况

在本交付环境中已运行：

- `swiftc -frontend -parse` 对主应用、共享代码和 Widget Swift 源码进行语法解析。
- `swiftc Shared/LunarCalendar.swift Shared/MarketData.swift Tests/ScheduleTests.swift -o /tmp/ganji-tests && /tmp/ganji-tests`，通过数据解码、ID 唯一性、72 组本地日期/时间一致性和农历回归检查。
- `plutil -lint GanJi.xcodeproj/project.pbxproj`，项目文件格式检查通过。

当前环境不是 macOS，没有 Apple SDK、Xcode 或 iOS Simulator，因此尚未执行真正的 iOS SDK 编译、签名、设备运行、地图/定位权限流程、真实 API 联调和 Widget 安装验证。请在 macOS Xcode 中完成最终构建与设备测试。
