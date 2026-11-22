/*
 * 融合新增：网页登录 Cookie → 米居 MijiaAuthData 转换器。
 *
 * 职责：把 WebLoginView 从 ArkWeb 读回的三样东西
 *   (1) 全域 Cookie 文本  (2) 页内 extension-pragma  (3) 最终跳转地址
 * 解析、归一化、交叉补齐，组装成米居数据服务可直接 setMijiaAuth 的
 * MijiaAuthData（9 字段）。这是本 App 网页登录协议层与米居云客户端的桥。
 *
 * 取值优先级（与 miha-fusion 网页登录一致）：
 *   ssecurity / userId / serviceToken：最终跳转地址 query > extension-pragma > Cookie
 * deviceId / passO / userAgent / locale：本地随机生成（与 MijiaQrLoginService 同格式）
 * 采用 GPL-3.0-or-later，与基座工程一致。
 */

import { MijiaAuthData } from '../cloud/MijiaApiClient';
import { Logger } from '../utils/Logger';

const LOGIN_STEP1: string = 'https://account.xiaomi.com/pass/serviceLogin';
const LOGIN_SID: string = 'xiaomiio';
const LOGIN_CALLBACK: string = 'https://sts.api.io.mi.com/sts';
const USER_AGENT_PREFIX: string =
  'Android-15-11.0.701-Xiaomi-23046RP50C-OS2.0.212.0.VMYCNXM-';

/** 官方文档 HTML 登录页（不带 _json，否则返回 JSON 而非页面） */
export function webLoginUrl(): string {
  return LOGIN_STEP1
    + '?sid=' + LOGIN_SID
    + '&callback=' + encodeURIComponent(LOGIN_CALLBACK)
    + '&_locale=zh_CN';
}

/** 解析结果，供 UI 展示失败原因（不含任何明文密钥值） */
export interface WebLoginResult {
  auth: MijiaAuthData | null;
  message: string;
}

function sanitizeValue(value: string): string {
  let v: string = value === undefined || value === null ? '' : value.trim();
  if (v.length >= 2 && v.charAt(0) === '"' && v.charAt(v.length - 1) === '"') {
    v = v.substring(1, v.length - 1).trim();
  }
  if (v.indexOf('%') >= 0) {
    try {
      v = decodeURIComponent(v);
    } catch (err) {
      // 保留原值
    }
  }
  return v.trim();
}

function isNumericId(value: string): boolean {
  if (value.length === 0) {
    return false;
  }
  for (let i = 0; i < value.length; i++) {
    const c: string = value.charAt(i);
    if (c < '0' || c > '9') {
      return false;
    }
  }
  return true;
}

function putPair(pairs: Array<string>, name: string, value: string): void {
  const marker: string = name + '=';
  for (let i = 0; i < pairs.length; i++) {
    if (pairs[i].indexOf(marker) === 0) {
      pairs[i] = marker + value;
      return;
    }
  }
  pairs.push(marker + value);
}

function isCookieNameChar(c: string): boolean {
  const code: number = c.charCodeAt(0);
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 90)
    || (code >= 97 && code <= 122) || c === '_' || c === '-' || c === '.';
}

/** 汇总全域 Cookie 文本，跳过 Set-Cookie 属性段，去重按名覆盖 */
function collectAllCookies(cookiesText: string, pairs: Array<string>): void {
  const skip: Array<string> = ['path', 'domain', 'expires', 'max-age', 'httponly',
    'secure', 'samesite', 'priority', 'partitioned', 'version', 'comment'];
  const segments: Array<string> = cookiesText.split(';');
  for (let i = 0; i < segments.length; i++) {
    const seg: string = segments[i].trim();
    const eq: number = seg.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const name: string = seg.substring(0, eq).trim();
    if (name.length === 0 || skip.indexOf(name.toLowerCase()) >= 0) {
      continue;
    }
    let valid: boolean = true;
    for (let k = 0; k < name.length; k++) {
      if (!isCookieNameChar(name.charAt(k))) {
        valid = false;
        break;
      }
    }
    if (!valid) {
      continue;
    }
    let value: string = seg.substring(eq + 1).trim();
    if (value.length > 0 && value.charAt(0) === '"') {
      value = value.substring(1);
    }
    const quote: number = value.indexOf('"');
    if (quote >= 0) {
      value = value.substring(0, quote);
    }
    if (value.length === 0 || value === 'undefined' || value === 'null') {
      continue;
    }
    putPair(pairs, name, value);
  }
}

function extractCookie(pairs: Array<string>, name: string): string {
  const marker: string = name + '=';
  for (let i = 0; i < pairs.length; i++) {
    if (pairs[i].indexOf(marker) === 0) {
      return sanitizeValue(pairs[i].substring(marker.length));
    }
  }
  return '';
}

function queryParam(url: string, key: string): string {
  const marker: string = key + '=';
  const at: number = url.indexOf(marker);
  if (at < 0) {
    return '';
  }
  const from: number = at + marker.length;
  let end: number = url.indexOf('&', from);
  if (end < 0) {
    end = url.length;
  }
  const raw: string = url.substring(from, end);
  return sanitizeValue(raw);
}

/** 从 extension-pragma（可能是转义 JSON 串）里取 ssecurity */
function pragmaSecurity(pragmaJson: string): string {
  if (pragmaJson.length === 0) {
    return '';
  }
  return pickString(pragmaJson.split('\\"').join('"'), 'ssecurity');
}

function pickString(text: string, key: string): string {
  const marker: string = '"' + key + '":';
  const at: number = text.indexOf(marker);
  if (at < 0) {
    return '';
  }
  let i: number = at + marker.length;
  while (i < text.length && (text.charAt(i) === ' ' || text.charAt(i) === '\n')) {
    i++;
  }
  if (text.charAt(i) !== '"') {
    return '';
  }
  i++;
  const out: Array<string> = [];
  while (i < text.length) {
    const c: string = text.charAt(i);
    if (c === '"') {
      break;
    }
    if (c === '\\' && i + 1 < text.length) {
      const next: string = text.charAt(i + 1);
      out.push(next === 'n' ? '\n' : (next === 't' ? '\t' : next));
      i += 2;
      continue;
    }
    out.push(c);
    i++;
  }
  return sanitizeValue(out.join(''));
}

function randomHex(length: number): string {
  const bytes: Uint8Array = new Uint8Array(Math.ceil(length / 2));
  // 使用轻量伪随机（时间戳 + 计数器混合），仅用于 deviceId/passO/UA 伪装字段
  let seed: number = Date.now() % 2147483647;
  for (let i = 0; i < bytes.length; i++) {
    seed = (seed * 48271) % 2147483647;
    bytes[i] = seed & 0xFF;
  }
  let result: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const hex: string = bytes[i].toString(16);
    result += hex.length === 1 ? '0' + hex : hex;
  }
  return result.substring(0, length);
}

function buildUserAgent(passO: string): string {
  return USER_AGENT_PREFIX
    + randomHex(40) + '-CN-' + randomHex(32) + '-' + randomHex(32)
    + '-SmartHome-MI_APP_STORE-' + randomHex(40) + '|' + randomHex(40)
    + '|' + passO + '-64';
}

/**
 * 把 ArkWeb 回传的三样东西转换为米居 MijiaAuthData。
 * 缺任一关键字段（ssecurity / serviceToken / 有效 userId）都返回失败，并给出
 * 不含密钥值的诊断信息，避免拿着错密钥去签名导致云接口全量失败。
 */
export function buildWebAuth(cookiesText: string, pragmaJson: string,
                             finalUrl: string): WebLoginResult {
  const out: WebLoginResult = { auth: null, message: '' };
  const pairs: Array<string> = [];
  collectAllCookies(cookiesText, pairs);
  if (pairs.length === 0) {
    out.message = '未取到小米登录 Cookie，请先在页面内完成登录';
    return out;
  }

  let serviceToken: string = extractCookie(pairs, 'serviceToken');
  let ssecurity: string = extractCookie(pairs, 'ssecurity');
  let userId: string = extractCookie(pairs, 'userId');
  let cUserId: string = extractCookie(pairs, 'cUserId');
  let passToken: string = extractCookie(pairs, 'passToken');

  // 首选：最终跳转地址（sts 页）query
  if (finalUrl.length > 0) {
    const uSec: string = queryParam(finalUrl, 'ssecurity');
    const uUser: string = queryParam(finalUrl, 'userId');
    const uTok: string = queryParam(finalUrl, 'serviceToken');
    const uCUser: string = queryParam(finalUrl, 'cUserId');
    const uPass: string = queryParam(finalUrl, 'passToken');
    if (uSec.length > 4) {
      ssecurity = uSec;
    }
    if (isNumericId(uUser)) {
      userId = uUser;
    }
    if (uTok.length > 0) {
      serviceToken = uTok;
    }
    if (uCUser.length > 0) {
      cUserId = uCUser;
    }
    if (uPass.length > 0) {
      passToken = uPass;
    }
  }

  // 次选：extension-pragma 响应头
  if (ssecurity.length <= 4 && pragmaJson.length > 0) {
    ssecurity = pragmaSecurity(pragmaJson);
    if (ssecurity.length <= 4) {
      ssecurity = pickString(pragmaJson, 'ssecurity');
    }
  }

  if (ssecurity.length <= 4) {
    out.message = '登录已完成，但小米没有下发签名密钥 ssecurity。'
      + '请等页面完全跳转到 sts 后再点「提取令牌」，或改用扫码登录';
    return out;
  }
  if (serviceToken.length === 0) {
    out.message = '未取到 serviceToken，请等页面跳转到 sts 完成后再提取';
    return out;
  }
  if (!isNumericId(userId)) {
    out.message = '未取到有效 userId（' + (userId.length > 0 ? '非数字' : '空')
      + '），请重新登录后再提取';
    return out;
  }

  if (cUserId.length === 0) {
    cUserId = userId;
  }
  const deviceId: string = randomHex(16);
  const passO: string = randomHex(16);
  const auth: MijiaAuthData = {
    userId: userId,
    cUserId: cUserId,
    passToken: passToken,
    ssecurity: ssecurity,
    serviceToken: serviceToken,
    deviceId: deviceId,
    passO: passO,
    userAgent: buildUserAgent(passO),
    locale: 'zh_CN'
  };
  Logger.info('web login auth built: userId=%{public}s, tokenLen=%{public}d',
    userId, serviceToken.length);
  out.auth = auth;
  out.message = '登录信息已提取，正在加载设备…';
  return out;
}
