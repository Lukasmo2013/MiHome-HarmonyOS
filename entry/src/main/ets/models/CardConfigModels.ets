/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 莫洁安
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * 桌面卡片（卡片服务）的公共配置项：
 * 首页长按菜单、卡片配置面板、桌面卡片管理中心三处共用，避免文案与键值漂移。
 */

export interface CardContentOption {
  key: string;
  label: string;
  /** 面板上的一句话说明，帮助用户理解这项内容在卡片上长什么样 */
  hint: string;
}

/** 卡片规格：宽*高（以 2*2 为基准格） */
export const CARD_DIMENSIONS: string[] = ['1*2', '2*2', '2*4', '4*4'];

export const CARD_CONTENT_OPTIONS: CardContentOption[] = [
  { key: 'power', label: '开关状态', hint: '卡片正中显示「已开启 / 已关闭」，并带一个开关按钮' },
  { key: 'online', label: '在线状态', hint: '显示设备是否在线，适合常看连接情况的设备' },
  { key: 'name', label: '设备名称', hint: '把设备名放到卡片正中，字号最大最醒目' },
  { key: 'location', label: '所在房间', hint: '显示设备所属房间，适合按房间布局桌面' },
  { key: 'model', label: '设备型号', hint: '显示设备型号，适合多台同类型设备区分' },
  { key: 'custom', label: '自定义文字', hint: '卡片显示你自己写的文字，比如「记得关空调」' }
];

export function cardContentLabel(key: string): string {
  for (let i = 0; i < CARD_CONTENT_OPTIONS.length; i++) {
    if (CARD_CONTENT_OPTIONS[i].key === key) {
      return CARD_CONTENT_OPTIONS[i].label;
    }
  }
  return '开关状态';
}

export function cardContentHint(key: string): string {
  for (let i = 0; i < CARD_CONTENT_OPTIONS.length; i++) {
    if (CARD_CONTENT_OPTIONS[i].key === key) {
      return CARD_CONTENT_OPTIONS[i].hint;
    }
  }
  return '';
}

/** 规格说明：用于管理面板上的辅助文案 */
export function cardDimensionHint(label: string): string {
  if (label === '1*2') {
    return '扁长条，适合放在桌面首屏提示';
  }
  if (label === '2*4') {
    return '横向宽卡，信息与操作都能放下';
  }
  if (label === '4*4') {
    return '大方卡，信息最全，适合单独一屏';
  }
  return '标准方形，最百搭';
}

/** 卡片宽高比（高 / 宽），用于配置面板里的实时预览 */
export function cardDimensionRatio(label: string): number {
  if (label === '1*2' || label === '2*4') {
    return 0.5;
  }
  return 1;
}
