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

import { deviceInfo } from '@kit.BasicServicesKit';
import { MijiaCardBorder, MijiaCardShadow } from './DesignTokens';

/**
 * 当前运行系统 API 是否 >= 26。
 */
export function isApi26OrAbove(): boolean {
  try {
    return deviceInfo.sdkApiVersion >= 26;
  } catch (err) {
    return false;
  }
}

/**
 * HarmonyOS 7 雾玻璃：卡片使用半透明白 + 背景模糊，
 * 不依赖旧版 API 24+ 的 uiMaterial，跨版本安全。
 */
export class ImmersiveMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundColor('rgba(255,255,255,0.86)');
    instance.backdropBlur(18);
    instance.border({ width: 1, color: MijiaCardBorder });
    instance.shadow({ radius: 20, color: MijiaCardShadow, offsetY: 4 });
  }
}

export const immersiveMaterialModifier: ImmersiveMaterialModifier = new ImmersiveMaterialModifier();

/**
 * 旧毛玻璃修饰器，保持半透明白底并补充描边/柔和阴影。
 */
export class LegacyMaterialModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundColor('rgba(255,255,255,0.86)');
    instance.backdropBlur(12);
    instance.border({ width: 1, color: MijiaCardBorder });
    instance.shadow({ radius: 16, color: MijiaCardShadow, offsetY: 3 });
  }
}

export const legacyMaterialModifier: LegacyMaterialModifier = new LegacyMaterialModifier();

/**
 * 底部弹窗使用纯色背景，不叠加系统材质。
 * 返回 undefined 并保留导出，兼容既有调用；调用方不再把结果传给 SheetOptions。
 */
export function sheetSystemMaterial(): Object | undefined {
  return undefined;
}

export function sheetBlurStyle(): BlurStyle | undefined {
  return undefined;
}
