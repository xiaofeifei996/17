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
