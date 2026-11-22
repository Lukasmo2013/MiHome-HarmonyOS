/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 莫洁安
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/**
 * HarmonyOS 7 雾玻璃 · 浅蓝绿设计语言
 * - 页面背景：纯白，素雅干净
 * - 卡片/输入框：白底 + 浅灰蓝描边 + 轻阴影，与底色清晰区分；文字深墨色
 * - 强调色：浅蓝绿（#3E9AA6），只用于按钮、开关、选中态
 */

export interface HwColorPalette {
  primary: string;
  background: string;
  backgroundDark: string;
  surface: string;
  textPrimary: string;
  textSecondary: string;
  danger: string;
  online: string;
}

export const HwColor: HwColorPalette = {
  primary: '#3E9AA6',         // 浅蓝绿主色
  background: '#FFFFFF',      // 全局纯白底
  backgroundDark: '#FFFFFF',  // 仍保持白底体系
  surface: '#FFFFFF',         // 白卡
  textPrimary: '#172226',     // 主文深墨
  textSecondary: '#6E8083',   // 副文灰绿
  danger: '#D94838',
  online: '#2AA98C'
};

/** 顶栏：中等明度蓝绿，白字可读，整体仍为浅色系 */
export const MijiaHeaderGradient: string[] = ['#F02F8C96', '#F0409AA4', '#F04EA5AE'];

/** 白卡 / 雾玻璃卡：统一白底深字 */
export const MijiaOverviewCard: string = '#FFFFFF';
export const MijiaOverviewCardPressed: string = '#F3FAFA';
export const MijiaOverviewCardText: string = '#172226';
export const MijiaOverviewCardValue: string = '#2F8C96';

/** 辅助文字与弹层面：白底体系 */
export const MijiaDarkSubText: string = '#5A6D70';
export let MijiaSheetBackground: string = '#FFFFFF';
/** 卡片与输入框统一描边色：与「我的」页列表框线一致，白底上仍能看出框体层次 */
export const MijiaCardBorder: string = '#E2EDED';
/** 柔和阴影：浅蓝绿半透明，避免灰黑脏感 */
export const MijiaCardShadow: string = '#143E9AA6';

/**
 * 应用主题：固定为 HarmonyOS 7 浅色雾玻璃。
 * 保留入参兼容旧调用，暗色开关只把背景调深一档，卡片与文字仍保持白底黑字。
 */
export function applyAppTheme(isDark: boolean): void {
  HwColor.background = '#FFFFFF';
  HwColor.backgroundDark = '#FFFFFF';
  HwColor.surface = '#FFFFFF';
  HwColor.textPrimary = '#172226';
  HwColor.textSecondary = '#6E8083';
  MijiaSheetBackground = '#FFFFFF';
  HwGlassCardColor.surface = '#FFFFFF';
}

/** 兼容旧引用 */
export const MijiaSkyGradient: string[] = MijiaHeaderGradient;
export const MijiaDarkCard: string = MijiaOverviewCard;
export const MijiaDarkCardPressed: string = MijiaOverviewCardPressed;
export const MijiaDarkCardText: string = MijiaOverviewCardText;
export const MijiaDarkCardSub: string = MijiaDarkSubText;
export const MijiaDarkCardIcon: string = MijiaOverviewCardValue;
export const MijiaWhiteCard: string = '#FFFFFF';
export const MijiaWhiteCardText: string = '#172226';
export const MijiaWhiteCardSub: string = '#6E8083';
export const MijiaOnButton: string = HwColor.online;
export const MijiaOffButton: string = '#D7E4E5';
export const MijiaTabBar: string = '#FFFFFF';
export const MijiaTabBarActive: string = '#2F8C96';
export const MijiaTabBarInactive: string = '#6E8083';
export const MijiaRoomPill: string = '#FFFFFF';
export const MijiaRoomPillActive: string = '#FFFFFF';
export const MijiaRoomPillText: string = '#172226';
export const MijiaRoomPillTextActive: string = '#2F8C96';

export interface HwRadiusScale {
  card: number;
  control: number;
  pill: number;
  small: number;
  large: number;
}

export const HwRadius: HwRadiusScale = {
  card: 14,
  control: 12,
  pill: 999,
  small: 8,
  large: 18
};

export interface HwSpaceScale {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

export const HwSpace: HwSpaceScale = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24
};

export interface HwGlassCardPalette {
  surface: string;
  border: string;
}

export const HwGlassCardColor: HwGlassCardPalette = {
  surface: '#FFFFFF',
  border: '#E3ECEE'
};
