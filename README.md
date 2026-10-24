# GanJi — 赶集日记 v1.4.0

基于 v102 源码继续开发的现代简洁 iOS 赶集应用。项目使用 SwiftUI、MapKit、CoreLocation 和 XcodeGen。

## 本版调整

- 首页改为更接近 iOS 原生风格的标题区、日期信息和搜索框。
- 首页保留「今日圩日 / 明日圩日 / 后日圩日」三日分组。
- 首页列表不显示收藏按钮；收藏操作仍可在地区/集市浏览页面使用。
- 首页的收藏圩市列表跨地区显示，不受地图/地区页当前选择地区影响。
- 保留地图、地点搜索、地区选择、收藏持久化、圩市详情入口、农历/圩日计算和 Widget 资源。
- 版本号更新为 1.4.0 (28)。

## GitHub Actions 编译

1. 将 ZIP 解压后，把项目全部文件上传到你自己的 GitHub 仓库根目录（不要只上传 `GanJi` 文件夹）。
2. 确认仓库包含 `.github/workflows/build.yml`、`project.yml`、`GanJi/`、`Shared/`、`Widget/` 和 `Tests/`。
3. 推送到 `main` 分支，或打开仓库的 **Actions → Build GanJi → Run workflow** 手动运行。
4. 工作流会在 macOS runner 上安装 XcodeGen、运行圩日/农历回归测试、生成 Xcode 工程并构建 Release iOS App。
5. 成功后打开该次工作流运行记录，在 **Artifacts** 下载 `GanJi-ipa`，其中是未签名 IPA。

### 安装提示

该工作流输出的是未签名 IPA，不能保证可直接点开安装。实际安装到 iPhone 通常需要使用自己的 Apple 开发者签名，或使用你已有的侧载工具签名安装。此环境未运行完整 Xcode iOS 构建，因此请以 GitHub Actions 的实际构建日志为最终编译结果。

## 本地验证

在 macOS 安装 Xcode 与 XcodeGen 后运行：

```bash
swiftc Shared/LunarCalendar.swift Shared/MarketData.swift Tests/ScheduleTests.swift -o /tmp/ganji-tests
/tmp/ganji-tests
xcodegen generate
xcodebuild -project GanJi.xcodeproj -scheme GanJi -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
