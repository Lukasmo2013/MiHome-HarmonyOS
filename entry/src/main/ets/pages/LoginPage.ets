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
 *
 * miha-fusion 改动：默认使用「网页登录」（ArkWeb 承载小米官方页面，
 * 由页面自己完成密码 + 图形码 + 短信/邮箱二次验证），扫码登录保留为切换项。
 */

import {
  MijiaQrLoginService,
  MijiaQrLoginTicket
} from '../oauth/MijiaQrLoginService';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { Logger } from '../utils/Logger';
import { HwColor, HwRadius, HwSpace, MijiaOverviewCard, MijiaOverviewCardValue } from '../utils/DesignTokens';
import { PressableButton } from '../components/PressableButton';
import { AppBackground } from '../components/AppBackground';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { WebLoginView } from '../components/WebLoginView';
import { webLoginUrl, buildWebAuth } from '../oauth/WebLoginService';
import { MijiaAuthData } from '../cloud/MijiaApiClient';

@Entry
@Component
struct LoginPage {
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';

  private appFontFamily(content: string): string {
    if (this.fontMode !== 'custom') {
      return '';
    }
    const family = this.hasCjk(content) ? this.fontFamilyZh : this.fontFamilyEn;
    return family === 'system' || family.length === 0 ? '' : family;
  }

  private hasCjk(content: string): boolean {
    for (let i = 0; i < content.length; i++) {
      const code = content.charCodeAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) {
        return true;
      }
    }
    return false;
  }
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('登录页');
  }

  aboutToDisappear(): void {
    this.loginCancelled = true;
    this.cancelWebAuthTimer();
  }

  onBackPress(): boolean | void {
    if (this.showWeb) {
      this.closeWebLogin();
      return true;
    }
    return false;
  }

  /** 网页登录统一退出：无论提取中进行到哪一步都必须能回到登录方式页 */
  private closeWebLogin(): void {
    this.cancelWebAuthTimer();
    this.webBusy = false;
    this.showWeb = false;
    this.webHint = '';
  }

  @State qrUrl: string = '';
  @State loading: boolean = false;
  @State statusMessage: string = '';
  @State errorMessage: string = '';
  @State webMode: boolean = true;          // 默认网页登录
  @State showWeb: boolean = false;         // 是否已打开官方页
  @State webHint: string = '';
  @State webBusy: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('isWearable') isWearable: boolean = false;

  private loginService: MijiaQrLoginService | null = null;
  private ticket: MijiaQrLoginTicket | null = null;
  private loginCancelled: boolean = false;
  private webAuthTimer: number = -1;

  private cancelWebAuthTimer(): void {
    if (this.webAuthTimer >= 0) {
      clearTimeout(this.webAuthTimer);
      this.webAuthTimer = -1;
    }
  }

  /** 登录后统一收尾：清空家庭选择、跳转首页 */
  private finishLogin(): void {
    AppStorage.setOrCreate('selectedHomeId', '');
    AppStorage.setOrCreate('selectedHomeName', '');
    AppStorage.setOrCreate('homeSelectionVersion', 0);
    AppSettingsStore.setString('selectedHomeId', '');
    AppSettingsStore.setString('selectedHomeName', '');
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' });
  }

  /** 网页登录：把 ArkWeb 回传的 Cookie + pragma + 最终地址注入米居数据服务 */
  private handleWebHarvest(cookies: string, pragma: string, finalUrl: string): void {
    if (this.webBusy) {
      return;
    }
    this.webBusy = true;
    const result = buildWebAuth(cookies, pragma, finalUrl);
    if (result.auth === null) {
      this.webHint = result.message;
      this.webBusy = false;
      return;
    }
    // 防止 setMijiaAuth 长时间无响应导致“令牌提取中”永久卡死
    this.cancelWebAuthTimer();
    this.webAuthTimer = setTimeout((): void => {
      this.webAuthTimer = -1;
      if (this.webBusy) {
        this.webBusy = false;
        this.webHint = '登录信息注入超时，请返回登录方式后重试或改用扫码登录';
      }
    }, 8000);
    const auth: MijiaAuthData = result.auth as MijiaAuthData;
    xiaomiDataService.setMijiaAuth(auth)
      .then(() => {
        this.cancelWebAuthTimer();
        this.webHint = '';
        this.finishLogin();
      })
      .catch((err: Error) => {
        this.cancelWebAuthTimer();
        this.webHint = '登录信息注入失败：' + err.message;
        this.webBusy = false;
      });
  }

  async startMijiaLogin(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.statusMessage = '';
    this.loginCancelled = false;
    const maxAttempts = 6;
    try {
      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        if (this.loginCancelled) {
          return;
        }
        try {
          this.loginService = new MijiaQrLoginService();
          this.ticket = await this.loginService.buildLoginTicket();
          this.qrUrl = this.ticket.qr;
          this.statusMessage = attempt === 1 ? '请使用小米/米家 App 扫码登录' : '二维码已自动刷新，请重新扫码';
          const auth = await this.loginService.pollTicket(this.ticket);
          await xiaomiDataService.setMijiaAuth(auth);
          this.finishLogin();
          return;
        } catch (err) {
          if (this.loginCancelled) {
            return;
          }
          const message = err instanceof Error ? err.message : '登录失败';
          Logger.error('mijia qr login attempt failed, %{public}s', message);
          if (attempt >= maxAttempts) {
            throw err instanceof Error ? err : new Error(message);
          }
          this.statusMessage = '二维码已过期，正在自动刷新…';
        }
      }
    } catch (err) {
      this.errorMessage = err instanceof Error ? err.message : '登录失败';
      Logger.error('mijia qr login failed, %{public}s', this.errorMessage);
    } finally {
      this.loading = false;
    }
  }

  @Builder
  QrPanel() {
    Column({ space: 18 }) {
      Column() {
        if (this.qrUrl.length > 0) {
          Image(this.qrUrl)
            .width(this.isWearable ? 160 : 240)
            .height(this.isWearable ? 160 : 240)
            .objectFit(ImageFit.Contain)
        } else {
          Text('二维码将显示在这里')
            .fontFamily(this.appFontFamily('二维码将显示在这里'))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(HwColor.textSecondary)
        }
      }
      .width(this.isWearable ? 160 : 240)
      .height(this.isWearable ? 160 : 240)
      .justifyContent(FlexAlign.Center)
      .borderRadius(HwRadius.card)
      .backgroundColor(MijiaOverviewCard)
      .border({ width: 1, color: '#E2EDED' })
      .clip(true)

      PressableButton({
        label: this.loading ? '等待扫码...' : '生成二维码登录',
        emphasized: true,
        loading: this.loading,
        fullWidth: true,
        buttonHeight: 48,
        role: ButtonRole.NORMAL,
        onAction: () => {
          this.startMijiaLogin();
        }
      })
    }
    .width('100%')
    .padding(this.isWearable ? HwSpace.md : HwSpace.xl)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: '#E2EDED' })
    .clip(true)
  }

  @Builder
  WebPanel() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text('推荐：网页登录')
          .fontFamily(this.appFontFamily('推荐：网页登录'))
          .fontWeight(this.appFontWeight())
          .fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor(HwColor.textPrimary)
        Text('在小米官方页面完成账号密码与短信/邮箱验证，本应用只读取登录结果，不接触你的账号密码。')
          .fontFamily(this.appFontFamily('在小米官方页面完成账号密码与短信/邮箱验证'))
          .fontWeight(this.appFontWeight())
          .fontSize(13).fontColor(HwColor.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      PressableButton({
        label: '打开官方登录页',
        emphasized: true,
        fullWidth: true,
        buttonHeight: 48,
        role: ButtonRole.NORMAL,
        onAction: () => {
          this.cancelWebAuthTimer();
          this.webBusy = false;
          this.webHint = '';
          this.showWeb = true;
        }
      })
    }
    .width('100%')
    .padding(this.isWearable ? HwSpace.md : HwSpace.xl)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: '#E2EDED' })
    .clip(true)
  }

  build() {
    Stack() {
      AppBackground()
      if (this.showWeb) {
        WebLoginView({
          initialUrl: webLoginUrl(),
          hint: this.webHint,
          onHarvest: (cookies: string, pragma: string, finalUrl: string): void => {
            this.handleWebHarvest(cookies, pragma, finalUrl);
          },
          onClose: (): void => {
            this.closeWebLogin();
          }
        })
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Column({ space: HwSpace.sm }) {
            Text('米家控制')
              .fontFamily(this.appFontFamily('米家控制'))
              .fontWeight(this.appFontWeight())
              .fontSize(this.isWearable ? 24 : 32)
              .fontWeight(FontWeight.Bold)
              .fontColor(HwColor.textPrimary)

            Text('登录后管理你的米家设备')
              .fontFamily(this.appFontFamily('登录后管理你的米家设备'))
              .fontWeight(this.appFontWeight())
              .fontSize(this.isWearable ? 13 : 16)
              .fontColor(HwColor.textSecondary)
          }
          .margin({ top: this.isWearable ? 24 : 48, bottom: this.isWearable ? 16 : 24 })

          Row({ space: 8 }) {
            Text('网页登录')
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(this.webMode ? '#FFFFFF' : HwColor.textSecondary)
              .padding({ left: 18, right: 18, top: 9, bottom: 9 })
              .borderRadius(HwRadius.card)
              .backgroundColor(this.webMode ? HwColor.primary : '#E8F1F1')
              .onClick((): void => { this.webMode = true; })
            Text('扫码登录')
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(!this.webMode ? '#FFFFFF' : HwColor.textSecondary)
              .padding({ left: 18, right: 18, top: 9, bottom: 9 })
              .borderRadius(HwRadius.card)
              .backgroundColor(!this.webMode ? HwColor.primary : '#E8F1F1')
              .onClick((): void => { this.webMode = false; })
          }
          .margin({ bottom: 18 })

          Scroll() {
            Column({ space: 18 }) {
              if (this.webMode) {
                this.WebPanel()
              } else {
                this.QrPanel()
              }

              if (this.statusMessage.length > 0 && !this.webMode) {
                Text(this.statusMessage)
                  .fontFamily(this.appFontFamily(this.statusMessage))
                  .fontWeight(this.appFontWeight())
                  .fontSize(14)
                  .fontColor(MijiaOverviewCardValue)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }

              if (this.errorMessage.length > 0) {
                Text(this.errorMessage)
                  .fontFamily(this.appFontFamily(this.errorMessage))
                  .fontWeight(this.appFontWeight())
                  .fontSize(14)
                  .fontColor(HwColor.danger)
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')
        .padding({
          left: HwSpace.xl,
          right: HwSpace.xl,
          top: HwSpace.xl + this.statusBarHeight,
          bottom: HwSpace.xl + this.navigationBarHeight
        })
        .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? HwColor.backgroundDark : HwColor.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
