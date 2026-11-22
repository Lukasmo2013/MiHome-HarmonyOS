import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const results = [];

function check(name, fn) {
  try { fn(); results.push(['PASS', name]); }
  catch (e) { results.push(['FAIL', name + ' :: ' + e.message]); }
}
function fail(message) { throw new Error(message); }
function read(rel) { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); }

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (['.git', 'node_modules', 'oh_modules', '.hvigor', 'build', '.workbuddy', '.idea'].includes(entry.name)) continue;
      walk(abs, out);
    } else {
      out.push(path.relative(ROOT, abs).replace(/\\/g, '/'));
    }
  }
  return out;
}

/** 轻量 JSON5 解析：去注释、去尾逗号、给无引号 key 补引号 */
function parseJson5(text) {
  let out = '';
  let inStr = false, quote = '', inLine = false, inBlock = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i], n = text[i + 1];
    if (inLine) { if (c === '\n') { inLine = false; out += c; } continue; }
    if (inBlock) { if (c === '*' && n === '/') { inBlock = false; i++; } continue; }
    if (inStr) {
      out += c;
      if (c === '\\') { i++; out += text[i] ?? ''; continue; }
      if (c === quote) inStr = false;
      continue;
    }
    if (c === '/' && n === '/') { inLine = true; i++; continue; }
    if (c === '/' && n === '*') { inBlock = true; out += ' '; i++; continue; }
    if (c === '"' || c === "'") { inStr = true; quote = c; out += '"'; continue; }
    if (c === ',') {
      if (/^\s*[}\]]/.test(text.slice(i + 1))) continue;
      out += c; continue;
    }
    if (/[A-Za-z_$]/.test(c)) {
      let j = i;
      while (j < text.length && /[A-Za-z0-9_$.-]/.test(text[j])) j++;
      if (/^\s*:/.test(text.slice(j))) {
        out += '"' + text.slice(i, j) + '"';
        i = j - 1;
        continue;
      }
    }
    out += c;
  }
  return JSON.parse(out);
}

function checkBrackets(src, file) {
  const stack = [];
  const pairs = { '}': '{', ')': '(', ']': '[' };
  let i = 0, inStr = false, quote = '', inLine = false, inBlock = false;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (inLine) { if (c === '\n') inLine = false; i++; continue; }
    if (inBlock) { if (c === '*' && n === '/') { inBlock = false; i += 2; continue; } i++; continue; }
    if (inStr) {
      if (c === '\\') { i += 2; continue; }
      if (c === quote) inStr = false;
      i++; continue;
    }
    if (c === '/' && n === '/') { inLine = true; i += 2; continue; }
    if (c === '/' && n === '*') { inBlock = true; i += 2; continue; }
    if (c === '"' || c === "'" || c === '`') { inStr = true; quote = c; i++; continue; }
    if (c === '{' || c === '(' || c === '[') stack.push(c);
    else if (c === '}' || c === ')' || c === ']') {
      if (stack.pop() !== pairs[c]) fail(`${file}: 括号不匹配 @${i}`);
    }
    i++;
  }
  if (stack.length > 0) fail(`${file}: ${stack.length} 个括号未闭合`);
}

const allFiles = walk(ROOT);
const etsFiles = allFiles.filter((f) => f.endsWith('.ets'));

check('必需工程文件齐全', () => {
  const required = [
    'AppScope/app.json5',
    'AppScope/resources/base/element/string.json',
    'AppScope/resources/base/media/app_icon.png',
    'build-profile.json5',
    'hvigorfile.ts',
    'oh-package.json5',
    'hvigor/hvigor-config.json5',
    'entry/build-profile.json5',
    'entry/hvigorfile.ts',
    'entry/oh-package.json5',
    'entry/obfuscation-rules.txt',
    'entry/src/main/module.json5',
    'entry/src/main/resources/base/element/string.json',
    'entry/src/main/resources/base/element/color.json',
    'entry/src/main/resources/base/element/float.json',
    'entry/src/main/resources/base/profile/main_pages.json',
    'entry/src/main/resources/base/media/app_icon.png',
    'entry/src/main/ets/entryability/EntryAbility.ets',
    'entry/src/main/ets/pages/Index.ets',
    'README.md',
    'ARCHITECTURE.md'
  ];
  const missing = required.filter((f) => !fs.existsSync(path.join(ROOT, f)));
  if (missing.length) fail('缺失: ' + missing.join(', '));
});

check('ArkTS 源码模块数量与分层目录完整', () => {
  if (etsFiles.length < 20) fail('ets 文件仅 ' + etsFiles.length + ' 个，工程不完整');
  for (const dir of ['common', 'model', 'protocol/cloud', 'protocol/lan', 'protocol/crypto',
    'service', 'viewmodel', 'components', 'pages', 'entryability']) {
    if (!allFiles.some((f) => f.includes('/ets/' + dir + '/'))) fail('缺少目录 ' + dir);
  }
});

check('所有 JSON / JSON5 配置可解析', () => {
  const configs = allFiles.filter((f) => f.endsWith('.json') || f.endsWith('.json5'));
  for (const f of configs) {
    try { parseJson5(read(f)); }
    catch (e) { fail(f + ': ' + e.message); }
  }
});

check('图标为合法 PNG', () => {
  for (const f of ['AppScope/resources/base/media/app_icon.png',
    'entry/src/main/resources/base/media/app_icon.png']) {
    const buf = fs.readFileSync(path.join(ROOT, f));
    if (buf.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') fail(f + ' 不是 PNG');
    if (buf.length < 100) fail(f + ' 文件异常小');
  }
});

check('module.json5 的 ability 入口文件存在', () => {
  const mod = parseJson5(read('entry/src/main/module.json5'));
  const abilities = mod.module.abilities;
  if (!Array.isArray(abilities) || abilities.length === 0) fail('未声明 abilities');
  for (const ab of abilities) {
    const target = path.resolve(path.join(ROOT, 'entry/src/main'), ab.srcEntry);
    if (!fs.existsSync(target)) fail('srcEntry 不存在: ' + ab.srcEntry);
  }
  const perms = mod.module.requestPermissions;
  if (!Array.isArray(perms) || perms.length < 3) fail('网络/局域网权限声明不完整');
});

check('main_pages.json 指向的页面文件存在', () => {
  const pages = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json')).src;
  if (!Array.isArray(pages) || pages.length === 0) fail('未声明页面');
  for (const p of pages) {
    const target = path.join(ROOT, 'entry/src/main/ets', p + '.ets');
    if (!fs.existsSync(target)) fail('页面不存在: ' + p);
  }
});

check('$string / $color / $float / $media / $profile 资源引用均可解析', () => {
  const res = { string: new Set(), color: new Set(), float: new Set(), media: new Set(), profile: new Set() };
  for (const base of [path.join(ROOT, 'AppScope/resources'),
    path.join(ROOT, 'entry/src/main/resources')]) {
    for (const rel of walk(base)) {
      const norm = rel;
      const abs = path.join(ROOT, rel);
      if (norm.includes('/element/') && rel.endsWith('.json')) {
        const json = JSON.parse(fs.readFileSync(abs, 'utf8'));
        for (const kind of ['string', 'color', 'float']) {
          if (Array.isArray(json[kind])) for (const item of json[kind]) res[kind].add(item.name);
        }
      }
      if (norm.includes('/media/')) res.media.add(path.basename(rel).replace(/\.[^.]+$/, ''));
      if (norm.includes('/profile/') && rel.endsWith('.json')) res.profile.add(path.basename(rel, '.json'));
    }
  }
  const refRe = /\$(string|color|float|media|profile):([A-Za-z0-9_]+)/g;
  const configs = allFiles.filter((f) => f.endsWith('.json') || f.endsWith('.json5'));
  let count = 0;
  for (const f of configs) {
    let m;
    const src = read(f);
    refRe.lastIndex = 0;
    while ((m = refRe.exec(src)) !== null) {
      count++;
      if (!res[m[1]].has(m[2])) fail(`${f}: 未定义资源 $${m[1]}:${m[2]}`);
    }
  }
  if (count < 8) fail('资源引用数量异常: ' + count.toString());
});

check('所有 .ets 相对 import 路径可解析', () => {
  let count = 0;
  for (const f of etsFiles) {
    const src = read(f);
    const re = /from\s+['"](\.[^'"]+)['"]/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      count++;
      const base = path.resolve(path.dirname(path.join(ROOT, f)), m[1]);
      const candidates = [base + '.ets', base + '.ts', path.join(base, 'index.ets')];
      if (!candidates.some((c) => fs.existsSync(c))) fail(`${f}: 无法解析 import ${m[1]}`);
    }
  }
  if (count < 25) fail('import 数量异常: ' + count.toString());
});

check('所有 .ets 文件括号配对正确', () => {
  for (const f of etsFiles) checkBrackets(read(f), f);
});

check('所有 @Component 组件均实现 build()', () => {
  for (const f of etsFiles) {
    const src = read(f);
    if (src.includes('@Component') && !/\bbuild\(\)\s*\{/.test(src)) fail(f + ': 缺少 build()');
  }
});

check('无 ArkTS 禁用写法（any / unknown / 中文引号 / console.log / 占位标记）', () => {
  const banned = [
    [/\bas\s+any\b|:\s*any\b|<any>|\bas\s+unknown\b|:\s*unknown\b/, 'ArkTS 禁止 any / unknown'],
    [/console\.log/, '应使用 Logger 而非 console.log'],
    [/\b(TODO|FIXME)\b/, '存在未完成占位标记'],
    [/[\u201c\u201d\u2018\u2019]/, '代码中出现中文引号']
  ];
  for (const f of etsFiles) {
    const src = read(f);
    for (const [re, why] of banned) {
      if (re.test(src)) fail(`${f}: ${why}`);
    }
  }
});

check('凭据未硬编码、敏感输出走脱敏工具', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  const crypto = read('entry/src/main/ets/common/CredentialStore.ets');
  if (!auth.includes('CredentialStore.save')) fail('登录流程未落盘凭据');
  if (!crypto.includes('device token 不落盘')) fail('缺少 token 安全说明');
  const logger = read('entry/src/main/ets/common/Logger.ets');
  if (!logger.includes('static mask')) fail('Logger 缺少脱敏方法');
});

check('演示 / 模拟数据已彻底移除，默认数据源为真实小米云', () => {
  if (fs.existsSync(path.join(ROOT, 'entry/src/main/ets/protocol/MockMiotProvider.ets'))) {
    fail('MockMiotProvider.ets 未删除');
  }
  const consts = read('entry/src/main/ets/common/Constants.ets');
  if (/'\s*mock\s*'/.test(consts)) fail('Constants.ets 仍定义 mock 模式');
  if (!/MODE:\s*ProviderMode\s*=\s*'cloud'/.test(consts)) fail('默认接入模式不是 cloud');
  for (const f of etsFiles) {
    const src = read(f);
    if (src.includes('MockMiotProvider') || src.includes("source: 'mock'")) {
      fail(f + ': 仍存在模拟数据引用');
    }
  }
  const factory = read('entry/src/main/ets/service/ProviderFactory.ets');
  if (factory.includes('Mock')) fail('ProviderFactory 仍引用模拟 Provider');
  if (!factory.includes('return null')) fail('未登录时未返回空 Provider（会误导为已连接）');
});

check('账号密码登录界面与会话管理完整', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['serviceLogin', 'serviceLoginAuth2', 'captCode', 'notificationUrl',
    'extractCookie', 'CredentialStore.save']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 ' + k);
  }
  const sheet = read('entry/src/main/ets/components/LoginSheet.ets');
  if (!sheet.includes('InputType.Password')) fail('登录界面缺少密码输入框');
  if (!sheet.includes('onSubmit')) fail('登录界面缺少提交回调');
  const index = read('entry/src/main/ets/pages/Index.ets');
  if (!index.includes('LoginSheet')) fail('首页未集成登录弹窗');
  if (!index.includes('handleLogout')) fail('首页缺少退出登录');
  const vm = read('entry/src/main/ets/viewmodel/HomeViewModel.ets');
  if (!vm.includes('XiaomiAuth.login')) fail('ViewModel 未接入真实登录');
});

check('云 API 采用 RC4 加密签名且具备多方案 / 多路径自动适配', () => {
  const signer = read('entry/src/main/ets/protocol/cloud/CloudSigner.ets');
  for (const k of ['rc4_hash__', 'VARIANT_COUNT', 'sha256', 'encSignature']) {
    if (!signer.includes(k)) fail('CloudSigner 缺少 ' + k);
  }
  const provider = read('entry/src/main/ets/protocol/cloud/XiaomiCloudProvider.ets');
  for (const k of ["'MIOT-ENCRYPT-ALGORITHM'", "'x-xiaomi-protocal-flag-cli'",
    'fillProperties', 'VARIANT_COUNT', 'MIOT_GET_ALT']) {
    if (!provider.includes(k)) fail('XiaomiCloudProvider 缺少 ' + k);
  }
  const constants = read('entry/src/main/ets/common/Constants.ets');
  if (!constants.includes('/miotspec/prop/get')) fail('未使用真实 MIoT Spec 路径');
});

check('设备清单走家庭维度主链路且签名参数支持 URL query', () => {
  const constants = read('entry/src/main/ets/common/Constants.ets');
  for (const k of ['/v2/homeroom/gethome', '/v2/home/home_device_list']) {
    if (!constants.includes(k)) fail('Constants 缺少现役设备端点 ' + k);
  }
  const provider = read('entry/src/main/ets/protocol/cloud/XiaomiCloudProvider.ets');
  for (const k of ['HOME_LIST', 'HOME_DEVICE_LIST', 'useQuery', 'queryMode',
    'device_info', 'parseDeviceItems', 'collectDevices', 'parseHomeIds']) {
    if (!provider.includes(k)) fail('XiaomiCloudProvider 缺少 ' + k);
  }
  if (!provider.includes("url + '?' + signed.query")) {
    fail('未把签名字段拼到 URL query（现役米家云必需，放 body 会导致已登录却列表为空）');
  }
  const signer = read('entry/src/main/ets/protocol/cloud/CloudSigner.ets');
  if (!signer.includes('query: string')) fail('CloudSigner 缺少 query 表单串');
});

check('二维码扫码登录链路与 UI 完整（现役 longPolling/loginUrl 端点）', () => {
  const constants = read('entry/src/main/ets/common/Constants.ets');
  if (!constants.includes('longPolling/loginUrl') || !constants.includes('QR_POLL_MS')) {
    fail('缺少现役扫码登录端点 / 轮询配置');
  }
  if (constants.includes('pass/qrcode/get')) {
    fail('仍引用已失效的 pass/qrcode/get 端点（实测 HTTP 404）');
  }
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['qrStart', 'qrPoll', 'qrFinish', 'completeLogin', 'QrSession',
    'loginUrl', 'qrTips', 'qrImage', 'longPolling']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 ' + k);
  }
  const sheet = read('entry/src/main/ets/components/LoginSheet.ets');
  if (!sheet.includes('QRCode(')) fail('登录弹窗未渲染本地二维码兜底');
  if (!sheet.includes('Image(this.qrImage)')) fail('登录弹窗未渲染官方二维码图片');
  if (!sheet.includes('onModeChange')) fail('登录弹窗缺少登录方式切换');
  const vm = read('entry/src/main/ets/viewmodel/HomeViewModel.ets');
  if (!vm.includes('startQrLogin') || !vm.includes('pollQrLogin')) fail('ViewModel 缺少扫码状态机');
  if (!vm.includes('qrImage')) fail('ViewModel 未传递官方二维码图片');
  const index = read('entry/src/main/ets/pages/Index.ets');
  if (!index.includes('setInterval') || !index.includes('stopQrPolling')) fail('首页缺少扫码轮询驱动');
});

check('二次验证（手机短信 / 邮箱验证码）协议层与 UI 完整', () => {
  const constants = read('entry/src/main/ets/common/Constants.ets');
  for (const k of ['/identity/list', '/identity/auth/verifyPhone',
    '/identity/auth/verifyEmail', '/identity/auth/sendPhoneTicket',
    '/identity/auth/sendEmailTicket', 'VERIFY_EXPIRE_MS']) {
    if (!constants.includes(k)) fail('Constants 缺少二次验证端点 / 配置 ' + k);
  }
  if (/\/identity\/auth\/sendTicket['"?]/.test(constants)) {
    fail('误用已确认返回 404 的 /identity/auth/sendTicket 端点');
  }
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['TwoFactorSession', 'sendVerifyCode', 'submitVerifyCode',
    'finishVerified', 'identity_session', 'identityListUrl', 'channelOrder']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 ' + k);
  }
  const vm = read('entry/src/main/ets/viewmodel/HomeViewModel.ets');
  for (const k of ['needVerify', 'sendVerifyCode', 'submitVerifyCode', 'clearVerify']) {
    if (!vm.includes(k)) fail('HomeViewModel 缺少 ' + k);
  }
  const sheet = read('entry/src/main/ets/components/LoginSheet.ets');
  for (const k of ['needVerify', 'onSendVerifyCode', 'onSubmitVerifyCode', 'verifyCode']) {
    if (!sheet.includes(k)) fail('LoginSheet 缺少 ' + k);
  }
  const index = read('entry/src/main/ets/pages/Index.ets');
  if (!index.includes('handleSendVerifyCode') || !index.includes('handleSubmitVerifyCode')) {
    fail('首页未接通二次验证回调');
  }
});

check('二次验证收尾补齐 ssecurity（跑完重定向链且不重放密码）', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['harvest', 'emptyIdentityTokens', 'step1Code', 'skipUrl',
    'hops < 8', "extractCookie(session.cookieJar, 'ssecurity')",
    "typeof resp.result === 'string'"]) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 2FA 收尾契约 ' + k);
  }
  if (!auth.includes('code === 0')) {
    fail('未校验 serviceLogin 的 code=0，会把未登录态网页 location 当成 sts 回调');
  }
  const tail = auth.slice(auth.indexOf('private static async finishVerified'));
  if (tail.includes('LOGIN_STEP2')) {
    fail('2FA 收尾误重放 serviceLoginAuth2（会重新触发验证并要求再次输入密码）');
  }
});

check('2FA code=70016 修复：完整 Cookie jar + 多组合登录态探测 + 种子兜底', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['collectAllCookies', 'loginCookieVariants', 'loginCookieFlags',
    'seedSecurity', 'seedPassToken', 'isStsCallback', 'reply.jar',
    "codes.join('/')", 'overrideJar.length === 0']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 70016 修复契约 ' + k);
  }
  if (auth.includes('serviceToken.length === 0 && location.length > 0')) {
    fail('自动重定向兜底仍被限制为「缺 serviceToken」才执行，会漏建 account 域登录态');
  }
  if (!auth.includes('psecurity') || !auth.includes('passToken')) {
    fail('Cookie 名单未补齐 account.xiaomi.com 判断登录态所需的字段');
  }
  if (!auth.includes('withoutCookies')) {
    fail('缺少剔除 identity_session / ick 验证残留的 Cookie 变体');
  }
});

check('2FA 会话级 Cookie（API 26 enableAutoCookie）与 Cookie 文本归一化', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['enableAutoCookie(true)', 'twoFactorHttp', 'ensureTwoFactorHttp',
    'releaseTwoFactorHttp', 'cookieText(', 'isNumericId',
    'collectAllCookies(rawCookies', 'uidShape']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少会话级 Cookie 修复契约 ' + k);
  }
  const start = auth.indexOf('private static async identityCall');
  const stop = auth.indexOf('private static channelEndpoint');
  const body = start >= 0 && stop > start ? auth.slice(start, stop) : '';
  if (body.length === 0) fail('无法定位 identityCall 实现');
  if (body.includes('http.createHttp()') || body.includes('.destroy()')) {
    fail('identityCall 仍逐请求新建/销毁 HttpRequest，会丢掉 SDK 自动维护的 passport Cookie');
  }
  if (auth.includes('JSON.stringify(step1.cookies)')
    || auth.includes('JSON.stringify(step2.cookies)')) {
    fail('仍对 HttpResponse.cookies 做 JSON.stringify，首个 Cookie 会因前导引号被整条丢弃');
  }
});

check('2FA 收尾走现役 serviceLoginAuth2/end（extension-pragma 是 ssecurity 唯一来源）', () => {
  const constants = read('entry/src/main/ets/common/Constants.ets');
  for (const k of ['/pass/serviceLoginAuth2/end', '/identity/result/check']) {
    if (!constants.includes(k)) fail('Constants 缺少 2FA 收尾端点 ' + k);
  }
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['AUTH2_END', 'IDENTITY_RESULT_CHECK', 'extension-pragma',
    'pragmaSecurity', 'finishViaAuth2End', 'findAbsoluteUrl', 'endStatus',
    'sts.api.io.mi.com/sts', 'viaEnd.ok', 'sign: string']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 2FA 收尾契约 ' + k);
  }
  const endStart = auth.indexOf('private static async finishViaAuth2End');
  const fvStart = auth.indexOf('private static async finishVerified');
  const endBody = endStart >= 0 && fvStart > endStart ? auth.slice(endStart, fvStart) : '';
  if (endBody.length === 0) fail('无法定位 finishViaAuth2End 实现');
  if (!endBody.includes('pragmaSecurity(end.raw)')) fail('end 跳未解析 extension-pragma');
  if (!endBody.includes('findAbsoluteUrl')) fail('缺少从 Tips 页 body 搜 sts 地址的兜底');
  if (endBody.includes('LOGIN_STEP2')) fail('2FA 收尾误重放 serviceLoginAuth2');
  const callStart = auth.indexOf('private static async identityCall');
  const callStop = auth.indexOf('private static channelEndpoint');
  const callBody = callStart >= 0 && callStop > callStart ? auth.slice(callStart, callStop) : '';
  if (!callBody.includes('maxRedirects: redirects')
    || !callBody.includes('followRedirect ? 5 : 0')) {
    fail('identityCall 未按调用方控制重定向，end 跳的 extension-pragma 会丢失');
  }
  const tail = auth.slice(fvStart);
  if (!tail.includes('finishViaAuth2End') || !tail.includes('session.endStatus')) {
    fail('finishVerified 未优先走 end 主路径或未透出 end 链路诊断');
  }
});

check('2FA end 链路校准：服务端给地址、响应体可读、诊断可定位', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['expectDataType: http.HttpDataType.STRING', 'followRedirect',
    'standardCheck', 'endBodyShape', 'bodyShape', 'headerFlags', 'check-retry',
    'JSON.stringify(resp.result)', 'session.verifyUrl']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少 end 链路校准契约 ' + k);
  }
  const callStart = auth.indexOf('private static async identityCall');
  const callStop = auth.indexOf('private static channelEndpoint');
  const callBody = callStart >= 0 && callStop > callStart ? auth.slice(callStart, callStop) : '';
  if (!callBody.includes('expectDataType')) fail('未声明 STRING 响应体，Tips 页 / location 会读不到');
  if (callBody.includes("reply.text = '';")) fail('非 string 响应体仍被直接丢弃');
  const endStart = auth.indexOf('private static async finishViaAuth2End');
  const fvStart = auth.indexOf('private static async finishVerified');
  const endBody = endStart >= 0 && fvStart > endStart ? auth.slice(endStart, fvStart) : '';
  if (!endBody.includes('standardCheck')) fail('end 地址未优先走 result/check');
  if (!endBody.includes("src = 'sign'")) fail('_sign 兜底未标记来源');
  if (!endBody.includes('attempt < 3')) fail('Tips 页重试不足');
  for (const k of ['/ src ', '/ body ', '/ hdr ']) {
    if (!endBody.includes(k)) fail('诊断串缺少 ' + k + ' 字段，真机无法定位');
  }
});

check('网页登录通道（ArkWeb 承载官方页面，只读结果 Cookie）', () => {
  const auth = read('entry/src/main/ets/protocol/cloud/XiaomiAuth.ets');
  for (const k of ['webLoginUrl', 'completeWebLogin', 'WebLoginCookies',
    'extractWebCookies', 'private static async rawGet']) {
    if (!auth.includes(k)) fail('XiaomiAuth 缺少网页登录契约 ' + k);
  }
  if (!auth.includes('LOGIN_STEP1')) fail('网页登录未复用 serviceLogin 官方页面地址');
  const web = read('entry/src/main/ets/components/WebLogin.ets');
  for (const k of ['WebCookieManager.fetchCookieSync', 'sts.api.io.mi.com',
    'serviceLoginAuth2/end', 'Web({', 'onHarvest', 'javaScriptOnDocumentStart',
    '__miPragma', 'extension-pragma']) {
    if (!web.includes(k)) fail('WebLogin 组件缺少 ' + k);
  }
  const sheet = read('entry/src/main/ets/components/LoginSheet.ets');
  if (!sheet.includes('网页登录') || !sheet.includes('onOpenWeb')) {
    fail('登录面板未提供网页登录入口');
  }
  const index = read('entry/src/main/ets/pages/Index.ets');
  if (!index.includes('showWebLogin') || !index.includes('WebLogin')
    || !index.includes('XiaomiAuth.webLoginUrl()')) {
    fail('首页未挂载网页登录全屏覆盖层');
  }
  const vm = read('entry/src/main/ets/viewmodel/HomeViewModel.ets');
  if (!vm.includes('completeWebLogin')) fail('ViewModel 未接网页登录结果');
  if (auth.includes('_sign=') && !auth.includes('不可依赖')) {
    fail('自造 end 地址需在注释中标明不可依赖（真机实测 code=10017）');
  }
  if (!web.includes('finalUrl') || !web.includes('controller.getUrl')) {
    fail('WebLogin 未回传最终跳转地址（sts 页 query 携带 ssecurity / userId）');
  }
  if (!auth.includes('sanitizeValue') || !auth.includes("queryParam(finalUrl")) {
    fail('网页登录未从最终跳转地址提取 ssecurity / userId');
  }
  if (!sheet.includes('webTab: boolean = true')) {
    fail('登录面板未默认到网页登录');
  }
});

check('云接口健壮性（字符串响应 / 凭据归一化 / 协议诊断）', () => {
  const p = read('entry/src/main/ets/protocol/cloud/XiaomiCloudProvider.ets');
  for (const k of ['expectDataType', 'HttpDataType.STRING', 'apiStatus',
    'private static clean', 'is_online', 'nonjson']) {
    if (!p.includes(k)) fail('云通道缺少 ' + k);
  }
  if (!p.includes('this.apiStatus')) fail('云通道未记录协议诊断');
});

check('账号凭据未硬编码（真实账号只能由用户在输入框提供）', () => {
  for (const f of etsFiles) {
    if (/['"][A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}['"]/.test(read(f))) {
      fail(f + ': 疑似硬编码邮箱账号');
    }
  }
});

console.log('=== 米家鸿蒙工程 · 结构自检 ===');
for (const [status, name] of results) console.log(`[${status}] ${name}`);
const failed = results.filter((r) => r[0] === 'FAIL').length;
console.log(`--- ${results.length} 项，${results.length - failed} 通过，${failed} 失败 ---`);
if (failed > 0) process.exitCode = 1;
