/*
 * miha-fusion 新增：统一的属性布尔值判定与写入值归一化。
 *
 * 米家 MIoT-Spec 里开关属性可能是 bool，也可能是 int（1/0）或字符串（"1"/"true"）。
 * 首页快捷开关与详情页电源大卡原先各处自己判定，导致读到 1 时显示"关闭"、
 * 点击后反向误下发。此处统一判定，避免各页面行为不一致。
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/** 把米家属性值（bool / 1 / "1" / "true" / "on"）统一判为开关状态 */
export function asBool(value: Object | undefined): boolean {
  if (value === undefined || value === null) {
    return false;
  }
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  if (typeof value === 'number') {
    return (value as number) !== 0;
  }
  if (typeof value === 'string') {
    const text: string = (value as string).trim().toLowerCase();
    return text === 'true' || text === '1' || text === 'on' || text === 'yes';
  }
  return false;
}

/**
 * 按属性 format 把目标开关状态转换成正确的下发值：
 * bool 属性下发 true/false；int/number 属性下发 1/0；其余下发 1/0 兜底。
 */
export function boolWriteValue(format: string, on: boolean): Object {
  if (format === 'bool') {
    return on;
  }
  return on ? 1 : 0;
}
