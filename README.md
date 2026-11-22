# MiHome（网页登录融合版）

> **品牌名 MiHome、包名 `com.mihome.client`、图标为米家风格浅蓝绿底白色 M 标志。
> 本工程 = **米居 MiJu**（基座，[SKL-666666/MiHome-Client](https://github.com/SKL-666666/MiHome-Client)，其本身基于 [MrCashmere/miha_hm](https://github.com/MrCashmere/miha_hm)「鸿米家」二次开发）+ **网页登录能力**（从本工作区的米家 HarmonyOS App 移植）融合而成的新 App。
> 两个上游均为 **GPL-3.0-or-later**，本工程沿用该许可（见 `LICENSE`）。

鸿蒙版米家移植 —— HarmonyOS NEXT 上的第三方米家客户端。**默认使用网页登录**：由小米官方页面完成账号密码 / 图形验证码 / 短信邮箱二次验证，App 只读取登录结果，不接触明文账号密码；同时保留扫码登录作为切换项。登录后即可管理家庭、房间与设备，控制米家生态里的智能硬件。UI 采用 HarmonyOS 7 雾玻璃 · 浅蓝绿设计语言：白底黑字卡片、轻描边、柔雾背景，素雅清爽。

## 🔀 本次融合的内容

| 来源 | 贡献 |
| --- | --- |
| 米居 MiJu（基座，79 个 ets 文件） | 完整的家庭/房间/设备列表、按 MIoT-Spec V2 动态渲染的设备详情与控制、本地智能场景、耗材、消息、备份恢复、外观主题、局域网发现等全部能力 |
| 本工作区米家 App（移植） | ArkWeb 网页登录（`WebLoginView.ets`）+ Cookie/跳转地址/extension-pragma 解析并注入米居 `MijiaAuthData`（`WebLoginService.ets`） |

- 登录页默认「网页登录」，可切「扫码登录」：`entry/src/main/ets/pages/LoginPage.ets`
- 网页登录页：`entry/src/main/ets/components/WebLoginView.ets`
- 凭据转换服务：`entry/src/main/ets/oauth/WebLoginService.ets`
- 注入点复用米居原生 `xiaomiDataService.setMijiaAuth()`，云签名/设备控制链路完全走米居成熟实现。

## 🎛 设备卡片与电器控制增强（本轮）

审查了各设备卡片/服务与详情页控制链路，修复了「菜单不全、状态不实时」的问题：

- **实时状态**：
  - 首页快捷开关 20s 轮询、详情页属性 15s 轮询（可在设置 `quickPollSeconds` / `detailPollSeconds` 调整，0 关闭），回页立即刷新；
  - 控制下发成功后发布 `property_changed` / `action_result` 事件并回读真值覆盖乐观更新，外部 App/物理按键改状态也能同步；
  - 传输层检查 `prop/set` 单项返回码，设备拒绝写入不再静默成功；失败回滚 + Toast 提示。
- **电器菜单**：
  - 统一 bool 判定（支持 bool / 1 / "1" / "true" 多种表示），按 spec `format` 下发正确类型，修复电源按钮颜色与状态反向；
  - 长按设备卡片新增「打开/关闭设备」快捷项；
  - 数值属性（温度/亮度/风速等）提交前做数字转换与合法性校验，保留 `uint`/`double` 格式语义；
  - 无取值范围的属性不再臆造 0–100 边界；动作参数增加 min/max 与整数校验。
- 自检 `verify/check_fusion.mjs` 覆盖上述能力及后续修复（当前 56 项）。

## 🪟 视觉重做与网页登录修复（最新）

- **图标**：重新生成浅蓝绿渐变 + 白色 M 盾牌，普通图标与自适应前景/背景同步（`tools/regenerate_icon.py`）。
- **视觉**：全局底色改为纯白；卡片/输入框保持白底黑字，补充 `#E2EDED` 浅描边（与「我的」页框线统一）与蓝绿半透明柔和阴影，与白底清晰分层；顶栏/开关/选中态保留浅蓝绿 `#3E9AA6`，保留轻模糊材质修饰器贴近 HarmonyOS 7 雾玻璃语言。
- **网页登录白屏**：注入 `__miSnapshot`，定时读取页面 URL、标题、正文、`document.cookie`、`extension-pragma`；即使小米回调页只显示 `ok`，也能自动识别完成并提取令牌。`onLoadIntercept` / `onPageEnd` / `progress=100` / 500ms 轮询四路兜底，底部「提取令牌」始终可用。
- **关闭按钮**：顶部保留状态栏安全高度，关闭按钮不再与状态栏重合；同时新增底部「返回登录方式」，网页白屏时也能退出。系统返回键同样可关闭网页层。
- **首页家庭选择**：家庭入口改为白底蓝绿房子图标（原先白图标白底不可见），选择面板改为覆盖层，不再依赖 `bindSheet`，点击必有响应。

## 🏠 首页家电卡 / 家庭选择 / 信息框线（最新）

- **首页家电卡**：按鸿米家 `deviceTileCard` 的竖向版式重做——透明底系统符号（不再垫圆角色块）、名称与在线状态点、右下角固定高度的电源开关、右上角可点星标；配色沿用本 App 的浅蓝绿 / 白底深墨，并修复了设备名「白底白字」。概览卡、场景卡、提醒卡同步加框。
- **家庭选择面板**：覆盖层根节点由 `HitTestMode.Block` 改为 `Default`，遮罩层仍用 `Block`；「全部设备」与每个家庭选项未选中也有淡框、选中态用主题色，点击即刻响应。
- **信息页**：云端消息、设备提醒、指标卡、设备明细行统一加圆角白框，框线颜色 `#E2EDED` 与「我的」页一致；消息标题由白字改为深墨色。
- 统一描边/阴影常量：`DesignTokens.ets` 的 `MijiaCardBorder` / `MijiaCardShadow`。

## 🧩 桌面卡片服务（最新）

- 新增 `MiHomeFormAbility` + `form_config.json`，支持 **1x2 / 2x2 / 2x4 / 4x4** 四种规格。
- 首页长按设备卡片 → **添加到桌面（卡片服务）** → 选择规格、内容（电源状态/在线状态/设备名称/型号/自定义文字）与卡片标题 → 打开系统卡片管理页放置。
- 卡片支持点击进入设备详情、刷新状态；App 设备列表加载与快捷开关切换后会把状态写入共享存储并调用 `formProvider.updateForm` 刷新已添加卡片。
- 相关文件：`entry/src/main/ets/entryformability/MiHomeFormAbility.ets`、`entry/src/main/ets/widget/pages/MiHomeDeviceCard.ets`、`entry/src/main/ets/services/CardFormService.ets`、`entry/src/main/ets/storage/CardConfigStore.ets`、`entry/src/main/ets/storage/CardStateStore.ets`。

### 网页登录工作原理
1. ArkWeb 打开小米官方 HTML 登录页（`serviceLogin`，不带 `_json`）。
2. 页内 document-start 钩子记录 `extension-pragma` 响应头（`ssecurity` 权威来源之一）。
3. 用户在官方页完成全部验证，跳到 `sts.api.io.mi.com`。
4. `WebCookieManager.fetchCookieSync` 跨 account/sts/api 域读取 Cookie；连同最终跳转地址 query 与 pragma 一起回传。
5. `buildWebAuth` 按「跳转地址 query > extension-pragma > Cookie」优先级取 `ssecurity/serviceToken/userId`，组装成米居 `MijiaAuthData` 并注入数据服务，随后加载设备。

> 为什么以网页登录为主：原生账号密码 + 2FA 收尾需要服务端现签、一次性的 `serviceLoginAuth2/end` 地址，自造会被拒（`code=10017`）。把这一步交回小米自己的网页 JS，协议风险归零。

## 🔨 构建（本机实测）

```bash
cd <ASCII 路径构建副本>
export PATH="$HOME/.workbuddy/binaries/hm-jre17/jdk-17.0.21+9-jre/bin:$PATH"
export JAVA_TOOL_OPTIONS='-Xmx256m -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -Xss512k -XX:ActiveProcessorCount=1'
export NODE_OPTIONS="--jitless --require=$(pwd)/tools/hvigor-fs-patch.cjs"
hvigorw assembleHap
```

产物（本地生成，**不随仓库提交**）：
- `outputs/MiHome-com.mihome.client-signed.hap` —— **包名 `com.mihome.client`、品牌 MiHome** 的调试包。签名证书与私钥由开发者本地保管，仓库内不含 `.p12` / `.p7b` / `.cer` 等任何签名材料，也不含口令。
- ⚠️ **真机安装诚实边界**：HarmonyOS 只信任华为官方根 CA 签发的调试证书。本地自签 CA 多数真机会以 `code:9568257 fail to verify pkcs7 file` 拒绝安装。要真机可装 `com.mihome.client`，**必须**用 DevEco Studio 登录华为开发者账号后 `File > Project Structure > Signing Configs > Automatically generate signature` 自动签名（AGC 会绑定 bundle-name + 开发者证书 + 设备 UDID）。
- 未签名产物由 `hvigorw assembleHap` 生成在 `entry/build/default/outputs/default/`，供自行签名。

自检：`node verify/check_fusion.mjs`（56 项，覆盖基座能力、网页登录、家庭选择、全局白底、首页家电卡、信息框线与卡片服务）。

> 📲 **怎么装到手机上？** → 看 **[《鸿蒙设备侧载 HAP 超详细指南》](docs/侧载安装指南.md)**：手机设置、hdc 命令行 / DevEco / 无线安装三种方式、常见报错逐条排查。
>
> ⚠️ **无线调试安装务必用安全方式**：不要直接 `hdc install -r xxx.hap`（实测会卡死并毒死设备端 hdcd，之后所有 `hdc shell` 报 `E002106/E001005`，只能重启设备无线调试恢复）。改用：
> ```
> hdc -t <手机IP>:<端口> file send xxx.hap /data/local/tmp/app.hap
> hdc -t <手机IP>:<端口> shell bm install -r -p /data/local/tmp/app.hap
> ```

## 📱 功能总览

### 设备与控制

- **设备列表**：按家庭 / 房间分组展示，支持搜索（名称 / 型号 / 房间）、排序（智能 / 名称 / 房间）、置顶收藏、隐藏离线设备、隐藏不想要的设备
- **首页快捷开关**：设备卡片右上角圆形电源按钮，绿灯=开启 / 灰灯=关闭或未知，一键直达不进详情页；状态持久化，冷启动秒显
- **设备详情页（对齐米家布局）**：
  - 电源卡占满整排（圆形大按钮 + 开关状态文字）
  - 模式 / 挡位选择整排磁贴，单行等宽摆放
  - 亮度 / 色温 / 温度等滑块调节 1×1 小卡
  - 当前温度 / 湿度 / 功率等只读数据合并为一张大卡
  - 不常用的角度 / 童锁 / 回正 / 厂商私有属性收纳进「更多功能」折叠区（类似米家扩展键，点击展开）
  - 「动作」页签集中展示设备动作（红外遥控设备的开关 / 风速 / 摆风等都在这里）
- **红外遥控设备适配**：自动识别红外虚拟设备（空调 / 风扇遥控），给出单向通信提示，指令经「动作」页签发送
- **spec 磁盘缓存**：设备能力定义首次联网拉取后落盘，之后详情页秒开、断网也能渲染
- **智能插座多路插孔**：排插多路开关独立展示（开关1 / 开关2…），用电信息（今日 / 近一月用电、当前功率）一目了然

### 智能与自动化

- 本地智能场景创建与管理（选择设备 → 设置动作 → 一键执行）
- 云端场景列表展示与一键执行
- 定时任务（周重复、整分触发）
- 智能分类（默认展示自动化）
- 场景动作参数编辑（开关 / 枚举 / 数值输入）

### 首页概览与提醒

- 概览卡片：温度 / 湿度 / PM2.5 范围统计 + 设备开启数量（仅取温度计、空气净化器等环境设备的数据，可一键关闭整组卡片）
- 信息提醒：电池电量、滤芯寿命等异常主动提醒
- 消息中心：米家消息轮询展示、已读标记、点击直达设备详情
- 耗材管理：滤芯等耗材余量展示
- 统计曲线：温湿度计历史趋势（时 / 天 / 月粒度切换）
- 设备状态异常告警（过载 / 高温等）

### 房间与家庭

- 多家庭切换，共享设备展示
- 房间管理：本地房间增删改，设备换房（云端房间自动映射为本地房间）
- **房间排序**：首页房间名长按拖动排序（跟手动画 + 平滑交换），持久化保存
- 首页自动刷新间隔可调（最小 30 秒）

### 外观与体验

- 深色模式全面适配
- 自定义背景图 / 蒙版、应用字体（自定义字体导入）、字号字重
- 沉浸光感适配、纯净开屏
- 全页面下拉刷新、骨架屏加载、开关乐观更新与动效、操作振动反馈
- 通知直达设备详情
- 数据备份与恢复

## ⚠️ 已知限制

- 第一次只能扫码登录，暂不支持账号密码登录
- 不能添加新设备（新设备请先用官方米家 App 配网绑定，之后即可在米居中使用）
- 红外遥控虚拟设备受单向通信限制，无法显示实时状态
- 目前仅支持手机

## 📲 安装方法

### 方式一：下载现成安装包（推荐）

1. 前往 [Releases](https://github.com/SKL-666666/MiHome-Client/releases)（或本仓库 `release/` 目录）下载 `miju-v1.2.0-signed.hap`
2. 安装到手机，任选其一：
   - **数据线 + 命令行**：开启手机开发者模式（设置 → 关于手机 → 连点版本号 7 次），打开 USB 调试后连接电脑，执行：
     ```bash
     hdc install -r miju-v1.2.0-signed.hap
     ```
     `hdc` 位于 DevEco Studio 的 SDK 目录：`<DevEco Studio>/sdk/default/openharmony/toolchains/hdc.exe`
   - **DevEco Studio**：用 DevEco Studio 打开任意工程后，通过 `File > Open` 直接打开 hap 文件弹窗安装，或把 hap 拖入设备窗口
   - **第三方侧载工具**：支持 hap 安装的桌面工具也可直接安装
3. 打开米居，用**米家 App 扫码**登录即可开始使用

> `unsigned` 版的 hap 仅供开发者自行签名后使用，普通用户请下载 `signed` 版。

### 方式二：从源码构建

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（需 HarmonyOS SDK，**API 26+**）
2. `git clone` 本仓库后用 DevEco Studio 打开工程，等待 Sync / ohpm 安装依赖完成
3. 配置签名：`File > Project Structure > Signing Configs` 勾选 `Automatically generate signature`（需登录华为开发者账号）
4. 连接手机，点击 Run ▶ 安装运行；或命令行打包：
   ```bash
   hvigorw --mode module -p module=entry@default -p product=default assembleHap
   ```
   产物位于 `entry/build/default/outputs/default/entry-default-signed.hap`
5. 首次登录：打开米居 → 扫码页面出现后用米家 App 扫描 → 确认登录

> 📖 更详细的图文步骤、无线安装、十大常见问题排查，见 **[侧载安装指南](docs/侧载安装指南.md)**。

## 🆕 更新日志

### v1.2.0

- 设备详情页全面重构：电源整排卡 / 模式挡位单行磁贴 / 滑块小卡 / 读数合并大卡 / 「更多功能」折叠区（对齐米家布局）
- 首页设备卡片新增快捷开关按钮（绿灯 / 灰灯，状态持久化，冷启动立即可见）
- 首页房间名支持长按拖动排序（跟手动画 + 平滑交换 + 持久化）
- 首页温湿度概览只统计温度计 / 空气净化器等环境设备，显示范围而非平均值；可在设置中关闭概览卡片
- 红外遥控设备（空调 / 风扇遥控）识别与交互适配，动作集中在「动作」页签
- 设备 spec 磁盘缓存：详情页秒开，断网不白屏
- 多主电源收敛、重名开关消歧、小众设备标签汉化（灭蚊灯 / 插座 / 净化器等词条大量补充）
- 创建智能选设备时显示「家庭 · 房间」；管理设备弹窗显示当前房间并支持选择云端房间
- 音箱音量 / 麦克风禁用上移到详情页明面
- 图表仅温湿度计展示；About 页精简，版本更新至 1.2.0

### v1.1.0

- 修复浅色模式下「设备提醒」等文字不可见的问题
- 修复设备页刷新按钮不停旋转的问题
- 智能页默认展示自动化场景
- 首页房间名在浅色模式下改为白色文字
- 主题色彩全面响应式适配
- 版本号更新至 1.1.0，About 页补充版本特性 / 致谢 / 开源许可

## 🙏 致谢

- [MrCashmere/miha_hm](https://github.com/MrCashmere/miha_hm)（项目基础）

## ⚠️ 免责声明

本项目仅供学习交流，与小米官方无关。使用本项目产生的账号、设备与数据安全风险请自行承担。米家及相关名称版权归其各自所有者所有。

## 📄 许可证

本项目以 **GPL v3** 协议开源发布，详见 `LICENSE`。
