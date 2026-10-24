# 赶集日记 v34 — 三级滚轮地区选择

本版本把原来的“搜索地区列表”改成接近用户截图的三列滚轮选择器：

- 左列：省份 / 直辖市 / 自治区
- 中列：城市
- 右列：区县
- 点“确定”后使用选中的地区代码请求圩日数据
- 保留现有地图、日期筛选、集市列表、动态查询与缓存
- 行政区划数据优先通过现有行政区划服务加载；服务不可用时仅展示项目内已知地区作为离线回退

## 构建

项目使用 `project.yml`，GitHub Actions 工作流会通过 XcodeGen 生成 `GanJi.xcodeproj` 并调用 `xcodebuild`。

请提交完整项目后运行 GitHub Actions。当前工作环境未安装 Xcode，未在本地完成 iOS SDK 编译验证。

## 数据说明

全国三级行政区划由 App 打开地区选择器时尝试从行政区划服务加载，因此首次加载需要网络。行政区划代码可用于选择地区，但某个地区是否存在圩日数据，仍取决于赶集数据接口的实际返回。

## v47 修复
- 地图页 Dock 仅在地图页显示，主页/收藏页显示自己的 Dock，避免两套 Dock 重叠造成闪动和点击区域冲突。


## v49 修改
- 地图页 Dock 保持显示；在 Dock 正上方新增“地区搜索 / 当前地区 / 切换地区”入口，点击打开省、市、县区选择器。
- 保留原有集市关键词搜索框，地区搜索与 Dock 不再使用重复 Dock。


## v50 修改
- App 启动默认显示主页（`homeTab = .home`），不再默认进入地图页。
- 地区选择弹窗仍默认关闭（`showRegionPicker = false`），只有用户点击地区搜索/切换地区时才打开。


## v53 Dock 闪动修复
- 将 Dock 提取为所有一级页面共用的单一 SwiftUI 视图，避免点击“地图”时旧 Dock 消失、新 Dock 重新创建导致的闪动。
- 地图页搜索与地区入口仍显示在 Dock 上方；主页、收藏、地区页面共用同一 Dock。
- 未进行 Xcode 编译验证。


## v54 地图并入地区栏
- 底部 Dock 删除独立的“地图”标签。
- 点击“地区”直接显示地图、集市搜索和地区选择入口。
- Dock 保留“主页｜收藏｜地区”三个一级入口，地图搜索功能仍保留在地区页面。
- 未进行 Xcode 编译验证。
\n\n## 地图选中集市可见性修复\n- 点击底部集市列表时自动收起列表面板，给地图腾出更多可视空间。\n- 地图定位时将中心点向南偏移，使选中的集市标记显示在面板上方的可视区域中。\n- 说明：此补丁已修改 Swift 源码，但当前环境未安装 Xcode，未完成 iOS 编译验证。\n

## 地图定位偏移再次上调
- 将选中集市时的地图中心纬度偏移系数从 0.22 调整为 0.38，使集市标记在屏幕上显示得更靠上。
- 仍未在本地完成 Xcode 编译和真机验证。

## 地图定位偏移系数调整至 0.5
- 将选中集市时的地图中心纬度偏移系数从 0.38 增加到 0.5，使选中标记显示得更靠上。
- 未进行 Xcode 编译和真机验证。


## v62：全国地点优先搜索（基于本源码包修改）
- 地图页搜索框使用 MapKit 地点建议，输入至少两个字符后展示地点名称与地址副标题。
- 点击建议后解析地点，再尝试按省、市、区县名称匹配项目已加载的全国区划列表；匹配成功时调用原有 `areacode` 市集接口。
- 镇/乡通常不是原市集接口的查询层级，因此会尝试匹配其所属区县；匹配不可靠时显示提示，不会伪造区划代码。
- MapKit 搜索结果不是完整的全国乡镇名录，不保证列出所有同名镇；结果需要联网，且依赖 Apple 地图服务。
- 本次仅改动 `GanJi/ContentView.swift` 并新增 `GanJi/PlaceSearchModel.swift`。未在本地使用 Xcode 编译或真机验证。


## v62 build-fix

- Fixed the Swift key path in the place suggestion list (`\.offset`).
- Moved `PlaceSearchModel` into `GanJi/ContentView.swift` so XcodeGen compiles it even if a previously generated project did not register the new source file.
- Re-run GitHub Actions after uploading the complete ZIP contents. This source fix has not been confirmed by a successful remote build yet.


## v86 搜索区域灰色背景透明化
- 将地图页底部 130pt 的灰色遮罩改为透明，避免遮住地图。
- 将键盘弹出时覆盖全屏的灰色背景改为透明。
- 将共享底部 Dock 的系统分组灰底改为透明。
- 搜索输入框自身的浅蓝色胶囊背景保留，确保文字可读。
- iOS 系统键盘本身的灰色外观由系统控制，此修改只处理 App 内部背景。
