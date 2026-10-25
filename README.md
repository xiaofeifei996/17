# GanJi v117 — County Search Fallback Fix

- Adds Qingxiu District (青秀区, Nanning, Guangxi; administrative code 450103) to the local county fallback so direct county-name search can work when the remote administrative feed is incomplete.
- Improves place-result matching by checking normalized title, subtitle, and full address text, while retaining city/province disambiguation for duplicate county names.
- Keeps the no-bundled-108-markets behavior and existing gathers API flow.

Validation: source-level checks and ZIP integrity only; Xcode/iPhone runtime validation has not been performed.


## v118 全国县区行政区划加载

- 行政区划优先从民政部国家地名信息库接口加载。
- 官方服务不可用时，尝试从 `province-city-china` 公共数据集加载全国省、市、县区层级数据。
- 加载时会校验县区条目数量（至少 2,500 条），避免误把不完整响应当作全国数据。
- `Shared/regions.json` 仍是离线兜底快照，不代表全国县区完整数据；首次完整加载需要网络。
- 行政区划覆盖不等于圩日 API 覆盖，圩日记录仍以接口实际返回为准。


## v119 苹果简约风 UI
- 全局主色调整为 iOS 系统蓝、系统文字与浅灰分组背景。
- 底部 Dock 改为纯白系统背景，顶部使用细分隔线，选中项为系统蓝，未选中项使用次级文字色。
- 保留原有页面结构、导航行为、搜索与地区选择逻辑。

## v120 界面中文与信息展示优化
- 清理主页、附近圩日列表中可见的英文装饰标题与英文日期分组标签。
- “附近圩日”标题改为深色文字，提高浅色界面上的对比度。
- 主页增加今日生肖、日干支与农历日期信息。
- 收藏列表的取消收藏按钮统一为附近圩日列表使用的圆形心形按钮样式。
- 日期标题固定使用简体中文格式，避免跟随设备语言显示英文。

## v122 圩日列表显示生肖与日干支
- 在主页今日安排、明日预告、后日预告的每一条圩日记录中，增加对应开圩日期的生肖、日干支和农历日期。
- 信息根据每条圩日记录的实际开圩日期计算，而不是只显示今天的日历信息。
- 列表中的地区文字加深，增强可读性。
