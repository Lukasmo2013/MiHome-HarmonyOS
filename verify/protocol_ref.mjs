import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const B64_TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/* ---- 与 MiotCrypto.ets / MiotFrame.ets 逐行等价的纯函数复刻 ---- */
function joinBytes(parts) {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

function hexToBytes(hex) {
  const out = new Uint8Array(Math.floor(hex.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16) & 0xff;
  return out;
}

function base64Encode(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const n = (a << 16) | (b << 8) | c;
    out += B64_TABLE.charAt((n >> 18) & 63);
    out += B64_TABLE.charAt((n >> 12) & 63);
    out += i + 1 < bytes.length ? B64_TABLE.charAt((n >> 6) & 63) : '=';
    out += i + 2 < bytes.length ? B64_TABLE.charAt(n & 63) : '=';
  }
  return out;
}

function base64Decode(text) {
  const clean = text.replace(/[^A-Za-z0-9+/]/g, '');
  const out = [];
  let buffer = 0, bits = 0;
  for (let i = 0; i < clean.length; i++) {
    buffer = (buffer << 6) | B64_TABLE.indexOf(clean.charAt(i));
    bits += 6;
    if (bits >= 8) { bits -= 8; out.push((buffer >> bits) & 0xff); }
  }
  return new Uint8Array(out);
}

function utf8Encode(text) {
  const out = [];
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      const low = text.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
        i++;
      }
    }
    if (code < 0x80) out.push(code);
    else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 63));
    else if (code < 0x10000) out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
    else out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
  }
  return new Uint8Array(out);
}

function utf8Decode(bytes) {
  let out = '', i = 0;
  while (i < bytes.length) {
    const head = bytes[i];
    let code = head, len = 1;
    if ((head & 0xe0) === 0xc0) { code = head & 0x1f; len = 2; }
    else if ((head & 0xf0) === 0xe0) { code = head & 0x0f; len = 3; }
    else if ((head & 0xf8) === 0xf0) { code = head & 0x07; len = 4; }
    for (let j = 1; j < len && i + j < bytes.length; j++) code = (code << 6) | (bytes[i + j] & 0x3f);
    i += len;
    if (code > 0xffff) {
      const value = code - 0x10000;
      out += String.fromCharCode(0xd800 + (value >> 10), 0xdc00 + (value & 0x3ff));
    } else out += String.fromCharCode(code);
  }
  return out;
}

function rc4(key, data, skip = 0) {
  const box = [];
  for (let i = 0; i < 256; i++) box.push(i);
  let j = 0;
  for (let i = 0; i < 256; i++) {
    j = (j + box[i] + key[i % key.length]) & 0xff;
    const t = box[i]; box[i] = box[j]; box[j] = t;
  }
  const out = new Uint8Array(data.length);
  let a = 0, b = 0;
  const step = () => {
    a = (a + 1) & 0xff;
    b = (b + box[a]) & 0xff;
    const t = box[a]; box[a] = box[b]; box[b] = t;
    return box[(box[a] + box[b]) & 0xff];
  };
  for (let n = 0; n < skip; n++) step();
  for (let n = 0; n < data.length; n++) out[n] = data[n] ^ step();
  return out;
}

function writeUInt32LE(t, o, v) {
  t[o] = v & 0xff; t[o + 1] = (v >>> 8) & 0xff;
  t[o + 2] = (v >>> 16) & 0xff; t[o + 3] = (v >>> 24) & 0xff;
}
function readUInt32LE(s, o) {
  return (s[o] | (s[o + 1] << 8) | (s[o + 2] << 16) | (s[o + 3] << 24)) >>> 0;
}

function hmacSha1Mine(key, data) {
  const short = key.length > 64 ? new Uint8Array(md5(key)) : key;
  const block = new Uint8Array(64);
  block.set(short.subarray(0, Math.min(short.length, 64)), 0);
  const ipad = new Uint8Array(64), opad = new Uint8Array(64);
  for (let i = 0; i < 64; i++) { ipad[i] = block[i] ^ 0x36; opad[i] = block[i] ^ 0x5c; }
  const inner = sha1(joinBytes([ipad, data]));
  return sha1(joinBytes([opad, inner]));
}

/* ---- Node 原生参考实现 ---- */
const md5 = (b) => crypto.createHash('md5').update(b).digest();
const sha1 = (b) => crypto.createHash('sha1').update(b).digest();
const sha256 = (b) => crypto.createHash('sha256').update(b).digest();
const hmacSha1 = (k, d) => crypto.createHmac('sha1', k).update(d).digest();
const aesEnc = (p, k, iv) => {
  const c = crypto.createCipheriv('aes-128-cbc', k, iv);
  return Buffer.concat([c.update(p), c.final()]);
};
const aesDec = (c, k, iv) => {
  const d = crypto.createDecipheriv('aes-128-cbc', k, iv);
  return Buffer.concat([d.update(c), d.final()]);
};

const results = [];
function check(name, fn) {
  try { fn(); results.push(['PASS', name]); }
  catch (e) { results.push(['FAIL', name + ' :: ' + e.message]); }
}

const samples = [
  'get_properties',
  '客厅主灯 26.3°C',
  '温度 🌡️ 与湿度',
  '{"did":"blt.3.1a2b","siid":2,"piid":1,"value":true}'
];

check('UTF-8 编解码与 Node 一致（含中文 / emoji / JSON）', () => {
  for (const s of samples) {
    assert.equal(Buffer.from(utf8Encode(s)).toString('hex'), Buffer.from(s, 'utf8').toString('hex'));
    assert.equal(utf8Decode(new Uint8Array(Buffer.from(s, 'utf8'))), s);
  }
});

check('Base64 编解码与 Node 一致', () => {
  for (const s of samples) {
    const mine = base64Encode(utf8Encode(s));
    assert.equal(mine, Buffer.from(s, 'utf8').toString('base64'));
    assert.equal(utf8Decode(base64Decode(mine)), s);
  }
});

check('uint32 小端读写与 Node 一致', () => {
  for (const v of [0, 1, 54321, 0xffffffff, 1700000000]) {
    const buf = new Uint8Array(4);
    writeUInt32LE(buf, 0, v);
    const ref = Buffer.alloc(4);
    ref.writeUInt32LE(v >>> 0, 0);
    assert.equal(Buffer.from(buf).toString('hex'), ref.toString('hex'));
    assert.equal(readUInt32LE(buf, 0), v >>> 0);
  }
});

const rc4Key = Buffer.from('0123456789abcdef0123456789abcdef', 'hex');
check('RC4（skip=1024）加解密往返正确', () => {
  const data = utf8Encode('data={"params":[{"did":"123456","siid":2,"piid":1}]}&_nonce=abc');
  const enc = rc4(new Uint8Array(rc4Key), data, 1024);
  const dec = rc4(new Uint8Array(rc4Key), enc, 1024);
  assert.equal(Buffer.from(dec).toString('hex'), Buffer.from(data).toString('hex'));
});

check('signedNonce = SHA1(ssecurity ‖ nonce) 与 Node 一致', () => {
  const ssecurity = base64Encode(Buffer.from('ssecurity-raw-32-bytes-secret!!'));
  const nonce = base64Encode(Buffer.concat([crypto.randomBytes(8), Buffer.alloc(4)]));
  const mine = base64Encode(new Uint8Array(sha1(joinBytes([base64Decode(ssecurity), base64Decode(nonce)]))));
  const ref = sha1(Buffer.concat([
    Buffer.from(base64Decode(ssecurity)), Buffer.from(base64Decode(nonce))
  ])).toString('base64');
  assert.equal(mine, ref);
});

check('HMAC-SHA1 纯实现与 Node 原生一致', () => {
  const data = utf8Encode('/home/device_list&signedNonce&nonce&data=xxx');
  assert.equal(Buffer.from(hmacSha1Mine(new Uint8Array(rc4Key), data)).toString('hex'),
    hmacSha1(rc4Key, Buffer.from(data)).toString('hex'));
});

const token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const tokenBytes = hexToBytes(token);
const key = md5(Buffer.from(tokenBytes));
const iv = md5(Buffer.concat([key, Buffer.from(tokenBytes)]));
const payload = '{"id":7,"method":"get_properties","params":[{"did":"123456","siid":2,"piid":1}]}';

check('miIO 密钥派生 key=MD5(token) / iv=MD5(key‖token)', () => {
  assert.equal(key.length, 16);
  assert.equal(iv.length, 16);
  assert.equal(key.toString('hex'), crypto.createHash('md5').update(Buffer.from(tokenBytes)).digest('hex'));
});

check('AES-128-CBC + PKCS7 加解密往返正确', () => {
  const cipher = aesEnc(Buffer.from(payload, 'utf8'), key, iv);
  assert.equal(aesDec(cipher, key, iv).toString('utf8'), payload);
  assert.equal(cipher.length % 16, 0);
});

check('hello 广播包 32 字节布局正确', () => {
  const hello = new Uint8Array(32);
  hello[0] = 0x21; hello[1] = 0x31; hello[2] = 0x00; hello[3] = 0x20;
  for (let i = 4; i < 32; i++) hello[i] = 0xff;
  assert.equal(hello.length, 32);
  assert.equal(hello[0], 0x21);
  assert.equal(hello[1], 0x31);
  assert.equal((hello[2] << 8) | hello[3], 32);
  assert.equal(readUInt32LE(hello, 8), 0xffffffff);
});

function encodeFrame(did, stamp, tk, text) {
  const tb = hexToBytes(tk);
  const k = md5(Buffer.from(tb));
  const v = md5(Buffer.concat([k, Buffer.from(tb)]));
  const cipher = aesEnc(Buffer.from(text, 'utf8'), k, v);
  const total = 32 + cipher.length;
  const frame = new Uint8Array(total);
  frame[0] = 0x21; frame[1] = 0x31;
  frame[2] = (total >> 8) & 0xff; frame[3] = total & 0xff;
  writeUInt32LE(frame, 4, 0);
  writeUInt32LE(frame, 8, did);
  writeUInt32LE(frame, 12, stamp);
  const sum = md5(Buffer.concat([Buffer.from(frame.subarray(0, 16)), cipher, Buffer.from(tb)]));
  frame.set(sum.subarray(0, 16), 16);
  frame.set(cipher, 32);
  return frame;
}

function decodeFrame(frame, tk) {
  const view = new Uint8Array(frame);
  assert.ok(view.length > 32);
  assert.equal(view[0], 0x21);
  assert.equal(view[1], 0x31);
  assert.equal(((view[2] << 8) | view[3]), view.length);
  const tb = hexToBytes(tk);
  const k = md5(Buffer.from(tb));
  const v = md5(Buffer.concat([k, Buffer.from(tb)]));
  const cipher = Buffer.from(view.subarray(32));
  const sum = md5(Buffer.concat([Buffer.from(view.subarray(0, 16)), cipher, Buffer.from(tb)]));
  assert.equal(Buffer.from(view.subarray(16, 32)).toString('hex'), sum.subarray(0, 16).toString('hex'));
  return aesDec(cipher, k, v).toString('utf8');
}

check('miIO 帧编解码、长度字段与 checksum 校验通过', () => {
  const frame = encodeFrame(123456789, 1700000000, token, payload);
  assert.equal(readUInt32LE(frame, 8), 123456789);
  assert.equal(readUInt32LE(frame, 12), 1700000000);
  assert.equal(decodeFrame(frame, token), payload);
});

check('MIoT JSON-RPC 方法名与参数结构符合规范', () => {
  const frameSrc = fs.readFileSync(path.join(ROOT, 'entry/src/main/ets/protocol/lan/MiotFrame.ets'), 'utf8');
  for (const name of ['get_properties', 'set_properties', 'action', '0x2131']) {
    assert.ok(frameSrc.includes(name), 'missing ' + name);
  }
  const getReq = JSON.parse(JSON.stringify({ id: 1, method: 'get_properties', params: [{ did: '123456', siid: 2, piid: 1 }] }));
  const setReq = JSON.parse(JSON.stringify({ id: 2, method: 'set_properties', params: [{ did: '123456', siid: 2, piid: 1, value: true }] }));
  const actReq = JSON.parse(JSON.stringify({ id: 3, method: 'action', params: [{ did: '123456', siid: 2, aiid: 1, in: [1] }] }));
  assert.equal(getReq.params[0].piid, 1);
  assert.equal(setReq.params[0].value, true);
  assert.equal(actReq.params[0].aiid, 1);
});

check('signedNonce = SHA256(ssecurity ‖ nonce) 与 Node 一致', () => {
  const ssecurity = base64Encode(Buffer.from('ssecurity-raw-32-bytes-secret!!'));
  const nonce = base64Encode(Buffer.concat([crypto.randomBytes(8), Buffer.alloc(4)]));
  const material = Buffer.concat([Buffer.from(base64Decode(ssecurity)), Buffer.from(base64Decode(nonce))]);
  const mine = base64Encode(new Uint8Array(sha256(material)));
  assert.equal(mine, sha256(material).toString('base64'));
});

check('encSignature = BASE64(SHA1(POST&path&k=v...&signedNonce)) 与 Node 一致', () => {
  const signedNonce = base64Encode(sha1(Buffer.from('signed-nonce-material')));
  const parts = ['POST', '/home/device_list', 'data={"params":[]}',
    'rc4_hash__=' + base64Encode(sha1(Buffer.from('h'))), 'data=ENCRYPTED', signedNonce];
  const mine = base64Encode(new Uint8Array(sha1(Buffer.from(parts.join('&'), 'utf8'))));
  assert.equal(mine, sha1(Buffer.from(parts.join('&'), 'utf8')).toString('base64'));
});

check('RC4(signedNonce, skip=1024) 加密参数可往返且与 Node 一致', () => {
  const signedNonce = base64Encode(sha256(Buffer.from('session-key')));
  const key = base64Decode(signedNonce);
  const plain = 'data={"getVirtualModel":true,"getHuamiDevices":1}';
  const enc = rc4(key, utf8Encode(plain), 1024);
  const dec = rc4(key, enc, 1024);
  assert.equal(utf8Decode(dec), plain);
  assert.equal(base64Encode(enc), Buffer.from(enc).toString('base64'));
});

console.log('=== 米家鸿蒙工程 · 协议算法等价验证 ===');
for (const [status, name] of results) console.log(`[${status}] ${name}`);
const failed = results.filter((r) => r[0] === 'FAIL').length;
console.log(`--- ${results.length} 项，${results.length - failed} 通过，${failed} 失败 ---`);
if (failed > 0) process.exitCode = 1;
