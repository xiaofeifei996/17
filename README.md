# QQ 净化 · 复读功能改造（双击 → "+1" 按钮）

> **编译产物**：`QQ 净化复读+1按钮.dylib`（Mach-O arm64，88KB）
> 由 GitHub Actions（Theos + iPhoneOS16.5 SDK）自动编译，构建仓库：`https://github.com/xiaofeifei996/17`
> arm64 架构在 arm64e（A12+）设备上同样可用。推送任意提交即自动重新构建，产物在 Actions 的 Artifact 中。

## 一、原 dylib 分析结论

对上传的 `QQ 净化（修复闪退.dylib`（Mach-O arm64e，464KB）逆向分析后，确认：

- 这是用 **Theos 编译的 iOS 插件**，构建路径为设备上的 `/var/mobile/q/.theos/`，复读模块源文件为 `Repeater.xm.mm`。
- 复读（Repeater）模块由以下部分组成：
  - 钩子 `UIViewController viewDidAppear:`：仅在类名含 `AIOChat` / `NTAIOChatTable` 的聊天页生效，1.5s 节流 + 0.2s 延迟后扫描 cell 类；
  - 扫描所有继承自 `NTBaseAIO.NTAIOBaseCellView`（及 `NTAIOCellView` 子树）的 cell 类，钩住其 `layoutViewWithViewModel:` / `layoutSubviews` / `unbindViewModel`，把消息记录（`OCMsgRecord`）绑定到 cell 上；
  - `QQRepeaterGestureTarget`：给每个 cell 挂 `UITapGestureRecognizer`（**双击触发**）；
  - 复读执行：查重（同一消息 0.65 秒内只触发一次、跳过自己发的消息），然后调用 `OCIKernelMsgService forwardMsg:srcContact:dstContacts:msgAttributeInfos:cb:`，把该消息的 `msgId` 以 `NSNumber` 装进数组转发回当前会话（`OCContact ContactWithChatType:peerUid:guildId:`）。
- 开关为设置项 `QQCK.repeater`。

**为什么不能直接改 dylib**：dylib 是已编译的 arm64e 机器码（带指针认证/链式修复），无法在二进制层面"凭空"新增按钮 UI 代码——必须回到源码用 Theos 重新编译。因此本次交付的是改好的 `Repeater.xm` 源文件，替换你工程里的同名文件后重打包即可。

## 二、本次改动（Repeater.xm）

| 原版 | 改造版 |
|---|---|
| 双击消息触发复读 | 每条消息气泡旁显示 **"+1" 圆角小按钮**，点击即复读 |
| `QQRepeaterGestureTarget` + 双击手势 | `QQRepeaterButtonTarget` + `UIButton`（已移除全部手势代码） |
| 按钮位置 | 自动定位：根据气泡（`content` → `BubbleView`）位置，别人的消息放气泡右侧、自己的消息放气泡左侧，垂直居中 |
| 按钮显隐 | 布局时刷新：能找到消息记录才显示，cell 复用/解绑时自动隐藏 |
| 按钮外观 | 30×30 圆形，"+1"，浅灰半透明底 + 蓝色文字，自动适配深色模式 |
| 防嵌套重复 | 祖先/子孙视图已有按钮时不再创建，避免嵌套 cell 上出现重复按钮 |
| 其余逻辑 | **完全保留原版**：`QQCK.repeater` 开关、消息记录查找链、0.65s 防抖、跳过自己消息、`forwardMsg` 转发调用、内核服务缓存、设置变更重扫描 |

## 三、如何使用

1. 用新 `Repeater.xm` 替换你 Theos 工程（`/var/mobile/q/`）里的同名文件；
2. 正常 `make` / 打包安装即可，无需改动工程里其他文件；
3. 源文件依赖的三个外部符号与原版相同（在 Core 公共文件中定义）：
   - `BOOL QQCKEnabled(NSString *key)`
   - `NSString * const QQCKRepeaterKey`（值 `QQCK.repeater`）
   - `NSString * const QQCKSettingsChangedNotification`（值 `QQCK.settingsChanged`）

   若你的工程里这几个符号命名略有出入，改文件顶部 3 行 `extern` 声明即可。

## 四、注意事项

- QQ 新版本若调整 cell 类名（`NTAIOBaseCellView` 等）或 `forwardMsg` 签名，需要同步更新——这一点与原版行为一致；
- 按钮点击与消息点击互不干扰（UIControl 优先响应）；
- 复读仍受 0.65 秒防抖限制，连点 "+1" 不会刷屏；
- 建议先在小号群验证一遍再日常使用。
