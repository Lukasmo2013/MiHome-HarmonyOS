#!/usr/bin/env node
/**
 * miha-fusion 融合工程结构自检。
 * 校验：以米居为基座的设备控制能力 + 从本 App 移植的网页登录链路都完整存在。
 */
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(process.cwd());
const read = (p) => {
  const full = path.join(ROOT, p);
  return fs.existsSync(full) ? fs.readFileSync(full, 'utf8') : '';
};
let pass = 0, fail = 0;
const ok = (cond, msg) => { if (cond) { pass++; console.log('[PASS] ' + msg); } else { fail++; console.log('[FAIL] ' + msg); } };

// 基座能力（米居 / 鸿米家）
const login = read('entry/src/main/ets/pages/LoginPage.ets');
const dataSvc = read('entry/src/main/ets/services/XiaomiDataService.ets');
const apiClient = read('entry/src/main/ets/cloud/MijiaApiClient.ets');
const homePage = read('entry/src/main/ets/pages/HomePage.ets');
const ctrl = read('entry/src/main/ets/controllers/DeviceController.ets');
const pages = read('entry/src/main/resources/base/profile/main_pages.json');
const routeMap = read('entry/src/main/resources/base/profile/route_map.json');

ok(login.includes('米家控制'), '基座：米居登录页存在');
ok(dataSvc.includes('setMijiaAuth') && dataSvc.includes('SecureMijiaAuthStorage'), '基座：凭据注入点 setMijiaAuth 存在');
ok(apiClient.includes('MijiaAuthData') && apiClient.includes('ssecurity'), '基座：云客户端签名链路存在');
ok(homePage.includes('device') || homePage.includes('设备'), '基座：首页设备清单存在');
ok(ctrl.includes('miotspec') || ctrl.includes('setProperty') || ctrl.includes('action'), '基座：设备控制器存在');
ok((pages.includes('HomePage') && pages.includes('RoomsPage'))
  && routeMap.includes('DeviceDetailPage'), '基座：设备详情页经 routerMap 注册');

// 移植能力（网页登录）
const view = read('entry/src/main/ets/components/WebLoginView.ets');
const svc = read('entry/src/main/ets/oauth/WebLoginService.ets');
const buildProfile = read('build-profile.json5');
const bundle = read('AppScope/app.json5');

ok(view.includes("from '@kit.ArkWeb'"), '移植：ArkWeb 引入');
ok(view.includes('Web({ src: this.initialUrl') && view.includes('controller'), '移植：Web 组件承载官方页');
ok(view.includes('fetchCookieSync'), '移植：WebCookieManager 跨域读 Cookie');
ok(view.includes('javaScriptOnDocumentStart') && view.includes('__miPragma'), '移植：extension-pragma 钩子');
ok(view.includes('sts.api.io.mi.com'), '移植：sts 跳转检测');
ok(view.includes('onHarvest'), '移植：回传 Cookie/pragma/最终地址');
ok(svc.includes('webLoginUrl') && svc.includes('serviceLogin'), '移植：官方登录页 URL 构造');
ok(svc.includes('buildWebAuth') && svc.includes('MijiaAuthData'), '移植：凭据转换为 MijiaAuthData');
ok(svc.includes("finalUrl") && svc.includes('ssecurity') && svc.includes('serviceToken'), '移植：最终地址 query 优先取值');
ok(svc.includes('pragmaSecurity'), '移植：extension-pragma 兜底取 ssecurity');
ok(login.includes('webMode') && login.includes('WebLoginView'), '移植：登录页默认网页登录');
ok(login.includes('setMijiaAuth'), '移植：网页登录注入基座数据服务');
ok(buildProfile.includes('"26.0.0"') && !buildProfile.includes('certpath'), '构建：API 26 且无签名配置');
ok(fs.existsSync(path.join(ROOT, 'tools/hvigor-fs-patch.cjs')), '构建：fs 补丁就位');
ok(bundle.includes('bundleName'), '配置：包名存在');
ok(bundle.includes('com.mihome.client'), '配置：包名为 com.mihome.client');
const appStr = read('AppScope/resources/base/element/string.json');
const entryStr = read('entry/src/main/resources/base/element/string.json');
ok(appStr.includes('MiHome') && entryStr.includes('MiHome'), '品牌：应用显示名为 MiHome');
ok(read('entry/src/main/ets/pages/AboutPage.ets').includes('莫洁安'), '品牌：版权信息为莫洁安');
// 签名材料（p12/p7b/cer）属隐私，不随仓库提交；仅当本地存在时才校验
if (fs.existsSync(path.join(ROOT, 'signing'))) {
  ok(fs.existsSync(path.join(ROOT, 'signing/mihome.p7b'))
    && fs.existsSync(path.join(ROOT, 'signing/app-cert-chain.cer')),
  '签名：本地自签材料就位（不入库）');
} else {
  ok(!fs.existsSync(path.join(ROOT, 'signing')),
    '签名：仓库不含任何密钥/证书材料（隐私合规）');
}

// 控制实时性与电器菜单增强
const boolUtil = read('entry/src/main/ets/utils/BoolValue.ets');
const detail = read('entry/src/main/ets/pages/DeviceDetailPage.ets');
const home = read('entry/src/main/ets/pages/HomePage.ets');
const transport = read('entry/src/main/ets/controllers/MijiaDeviceTransport.ets');
const propCtrl = read('entry/src/main/ets/components/PropertyControl.ets');
const capRend = read('entry/src/main/ets/components/CapabilityRenderer.ets');
const specModels = read('entry/src/main/ets/models/MIotSpecModels.ets');

ok(boolUtil.includes('asBool') && boolUtil.includes('boolWriteValue'), '控制：统一 bool 判定与按 format 写入');
ok(home.includes('asBool') && detail.includes('asBool'), '控制：卡片与详情页使用统一 bool 判定');
ok(ctrl.includes("publish('property_changed'") && ctrl.includes("publish('action_result'"), '实时：写操作发布变更/动作事件');
ok(detail.includes("subscribeEvent('property_changed'") && detail.includes("subscribeEvent('action_result'"), '实时：详情页订阅设备事件');
ok(detail.includes('startPolling') && detail.includes('onPageShow') && detail.includes('setInterval'), '实时：详情页属性轮询与回页刷新');
ok(home.includes('startQuickPoll') && home.includes('stopQuickPoll'), '实时：首页快捷开关轮询');
ok(detail.includes('controller.getProperty(') && home.includes('controller.getProperty('), '实时：写后回读真值覆盖乐观更新');
ok(transport.includes("code !== 0") && transport.includes('设备拒绝设置'), '可靠：传输层检查单项返回码');
ok(home.includes('showToast') && detail.includes('showToast'), '可靠：控制失败有 Toast 提示');
ok(home.includes('关闭设备') && home.includes('打开设备'), '菜单：长按菜单含设备开关控制');
ok(propCtrl.includes('Number(text)') && propCtrl.includes('请输入有效数字'), '电器：数值属性提交数字并校验');
ok(specModels.includes("'uint'") && specModels.includes("'double'"), '电器：保留 uint/double 格式语义');
ok(capRend.includes('MIN_SAFE_INTEGER') && capRend.includes('TEMPERATURE ? 16'), '电器：无范围属性不臆造 0-100');
ok(detail.includes('num < arg.min') && detail.includes('num > arg.max'), '电器：动作参数范围校验');

// 卡片服务（多规格 + 自定义内容 + 长按入口）
const formConfig = read('entry/src/main/resources/base/profile/form_config.json');
const formAbility = read('entry/src/main/ets/entryformability/MiHomeFormAbility.ets');
const formCard = read('entry/src/main/ets/widget/pages/MiHomeDeviceCard.ets');
const cardService = read('entry/src/main/ets/services/CardFormService.ets');
const moduleJson = read('entry/src/main/module.json5');

ok(formConfig.includes('"1*2"') && formConfig.includes('"2*2"')
  && formConfig.includes('"2*4"') && formConfig.includes('"4*4"'), '卡片：支持 1x2/2x2/2x4/4x4 四种规格');
ok(formConfig.includes('"uiSyntax": "arkts"') && formConfig.includes('"isDynamic": true'), '卡片：动态 ArkTS 卡片');
ok(formAbility.includes('onAddForm') && formAbility.includes('onUpdateForm'), '卡片：FormExtensionAbility 生命周期完整');
ok(formCard.includes("dimension === '4*4'") && formCard.includes('postCardAction'), '卡片：多尺寸 UI 与 router/message 交互');
ok(cardService.includes('openFormManager') && home.includes('添加到桌面（卡片服务）'), '卡片：长按菜单可打开卡片服务');
ok(moduleJson.includes('MiHomeFormAbility') && moduleJson.includes('$profile:form_config'), '卡片：module.json5 注册卡片扩展');

// 本轮修复：登录白屏 / 状态栏避让 / 家庭选择 / 全局白底
const iconButton = read('entry/src/main/ets/components/IconCircleButton.ets');
const designTokens = read('entry/src/main/ets/utils/DesignTokens.ets');
const appBackground = read('entry/src/main/ets/components/AppBackground.ets');

ok(view.includes('__miSnapshot') && view.includes('COOKIE=') && view.includes('PRAGMA='),
  '登录：注入页面快照，识别只显示 ok 的回调页');
ok(view.includes('statusBarHeight') && view.includes('返回登录方式'),
  '登录：关闭按钮避开状态栏并提供底部返回入口');
ok(iconButton.includes('@Prop buttonBackground') && homePage.includes('tint: HwColor.primary'),
  '首页：家庭入口图标改为白底蓝绿，清晰可见');
ok(homePage.includes('familySelectOverlay') && !homePage.includes('.bindSheet($$this.showFamilySheet'),
  '首页：家庭选择改用覆盖层，点击必有响应');
ok(designTokens.includes("background: '#FFFFFF'") && appBackground.includes("backgroundColor('#FFFFFF')"),
  '视觉：全局纯白底');
ok(designTokens.includes('MijiaCardBorder') && designTokens.includes('MijiaCardShadow'),
  '视觉：卡片描边与柔和阴影与白底区分');

// 本轮：首页家电卡借鉴鸿米家 / 家庭面板可点 / 信息页每条加框
const deviceCardStart = homePage.indexOf('deviceGridCard(device: XiaomiDevice)');
const deviceCardCode = homePage.slice(deviceCardStart, homePage.indexOf('homeTabContent()', deviceCardStart));
ok(deviceCardCode.includes('SymbolGlyph(this.deviceSymbol(device))')
  && deviceCardCode.includes('MijiaCardBorder')
  && !deviceCardCode.includes('fontColor(Color.White)'),
'首页：家电卡借鉴鸿米家竖版式（透明图标 + 右下开关 + 统一框线）');
ok(homePage.includes('// 面板本身必须可命中') && homePage.includes('.hitTestBehavior(HitTestMode.Default)'),
  '首页：家庭面板不再 Block，全部设备及各家庭选项可点');
ok(homePage.includes('width: selected ? 1.5 : 1')
  && homePage.includes('ALL_HOMES_ID ? 1.5 : 1'),
  '首页：家庭选项未选中也有淡框，选中态用主题色');
const msgCardStart = homePage.indexOf('cloudMessageCard(msg: MijiaMessageItem)');
const msgCardCode = homePage.slice(msgCardStart, homePage.indexOf('alertCard(alert:', msgCardStart));
ok(msgCardCode.includes('MijiaCardBorder') && msgCardCode.includes('MijiaOverviewCardText')
  && !msgCardCode.includes('fontColor(Color.White)'),
  '信息：每条消息加框且标题为深墨色');
ok(designTokens.includes("MijiaCardBorder: string = '#E2EDED'"),
  '视觉：框线颜色与「我的」页一致');

// ---- 卡片服务：设备为空 / 无可选项 的修复 ----
const cardFormAbilityCode = read('entry/src/main/ets/entryformability/MiHomeFormAbility.ets');
const cardStateStoreCode = read('entry/src/main/ets/storage/CardStateStore.ets');
const cardConfigStoreCode = read('entry/src/main/ets/storage/CardConfigStore.ets');
const cardFormServiceCode = read('entry/src/main/ets/services/CardFormService.ets');
const cardViewCode = read('entry/src/main/ets/widget/pages/MiHomeDeviceCard.ets');

ok(cardStateStoreCode.includes('static list(context: Context)') && cardStateStoreCode.includes('static first(context: Context)'),
  '卡片：状态库可枚举设备（list/first），供提供方回落');
ok(cardConfigStoreCode.includes('saveDefault') && cardConfigStoreCode.includes('readDefault')
  && cardConfigStoreCode.includes("DEFAULT_KEY: string = 'default_card'"),
  '卡片：默认配置可持久化（系统面板添加时回落）');
ok(cardFormAbilityCode.includes('CardConfigStore.readDefault') && cardFormAbilityCode.includes('CardStateStore.first')
  && cardFormAbilityCode.includes("value: '未选择设备'"),
  '卡片：无 customize 时回落到默认设备，且空态有引导文案');
ok(cardFormAbilityCode.includes("cfg.content === 'location'") && cardFormAbilityCode.includes('setFormNextRefreshTime'),
  '卡片：支持房间内容项与定时自刷新');
ok(cardFormAbilityCode.includes('预览态') && cardFormAbilityCode.includes('const saved: CardConfig | null'),
  '卡片：系统面板预览态也回落到真实设备，不再空白');
ok(cardFormServiceCode.includes('static rememberDefault') && cardFormServiceCode.includes('CardFormService.rememberDefault(context'),
  '卡片：打开系统管理页前先记住默认设备');
ok(homePage.includes('cardDevicePicker()') && homePage.includes('this.cardDeviceDid = device.did;'),
  '卡片面板：可遍历选择任意设备');
ok(homePage.includes("{ key: 'location', label: '所在房间' }")
  && homePage.includes("{ key: 'power', label: '开关状态' }"),
  '卡片面板：内容项含开关状态/所在房间');
ok(cardViewCode.includes("action: 'call'") && cardViewCode.includes('cardToggleDid')
  && cardViewCode.includes('private toggle()'),
  '卡片：自带电源开关按钮（call 拉起 App 执行）');
ok(homePage.includes('pendingCardToggleDid') && homePage.includes('consumePendingCardToggle'),
  '卡片开关：App 侧消费待切换设备');

console.log('\n--- ' + pass + ' 项通过，' + fail + ' 项失败 ---');
process.exit(fail === 0 ? 0 : 1);
