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
 * 桌面卡片（卡片服务）管理中心。
 *
 * 「我的 → 桌面卡片」入口：
 * - 挑一台家电、选一种展示内容、选一个规格，实时预览后添加到桌面；
 * - 管理桌面上已添加的卡片（载入原配置重配、单张刷新）；
 * - 把当前选择设为「系统服务卡片面板」的默认样式。
 */

import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { XiaomiDevice, ALL_HOMES_ID } from '../models/XiaomiHomeModels';
import {
  CARD_CONTENT_OPTIONS,
  CARD_DIMENSIONS,
  CardContentOption,
  cardContentHint,
  cardContentLabel,
  cardDimensionHint,
  cardDimensionRatio
} from '../models/CardConfigModels';
import { CardConfig, CardConfigStore } from '../storage/CardConfigStore';
import { CardDeviceState, CardStateStore } from '../storage/CardStateStore';
import { CardFormService, RunningCardView } from '../services/CardFormService';
import { xiaomiDataService } from '../services/XiaomiDataService';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { FeedbackLogService } from '../services/FeedbackLogService';
import { AppBackground } from '../components/AppBackground';
import { IconCircleButton } from '../components/IconCircleButton';
import {
  HwColor,
  HwRadius,
  HwSpace,
  MijiaCardBorder,
  MijiaCardShadow,
  MijiaOverviewCard,
  MijiaOverviewCardText
} from '../utils/DesignTokens';

@Entry
@Component
struct CardServicePage {
  @StorageLink('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageLink('cardsFromTop') cardsFromTop: boolean = true;
  @StorageLink('fontMode') fontMode: string = 'system';
  @StorageLink('fontFamilyEn') fontFamilyEn: string = 'system';
  @StorageLink('fontFamilyZh') fontFamilyZh: string = 'system';
  @StorageLink('fontWeightMode') fontWeightMode: string = 'system';
  @StorageLink('fontWeightValue') fontWeightValue: number = 400;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('currentWidthBreakpoint') @Watch('onBreakpointChange')
  widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;

  @State isWideScreen: boolean = false;
  @State devices: CardDeviceState[] = [];
  @State runningCards: RunningCardView[] = [];
  @State loading: boolean = true;
  @State busy: boolean = false;
  @State selectedDid: string = '';
  @State cardContent: string = 'power';
  @State cardDimension: string = '2*2';
  @State cardCustomText: string = '';
  @State cardTitle: string = '';
  @State keyword: string = '';
  @State tipsText: string = '';

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

  private appFontWeight(): number {
    return this.fontWeightMode === 'custom' ? this.fontWeightValue : 400;
  }

  private topOffset(): number {
    return 56 + this.statusBarHeight;
  }

  onBreakpointChange(): void {
    this.isWideScreen = this.widthBp === WidthBreakpoint.WIDTH_LG ||
      this.widthBp === WidthBreakpoint.WIDTH_MD;
  }

  aboutToAppear(): void {
    FeedbackLogService.setCurrentPage('桌面卡片');
    this.onBreakpointChange();
    this.loadRunning();
    this.loadDevices();
  }

  onPageShow(): void {
    this.loadRunning();
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  /** 读取设备：先用本地快照点亮列表，再尝试用云端快照补齐房间/型号 */
  private async loadDevices(): Promise<void> {
    const cached: CardDeviceState[] = CardStateStore.list(this.context());
    if (cached.length > 0) {
      this.devices = cached;
      this.ensureSelection();
    }
    try {
      const snapshot = await xiaomiDataService.getHomeSnapshot(this.context(), false);
      const map = JSON.parse(snapshot.devicesJson) as Record<string, XiaomiDevice>;
      const homeId: string = AppSettingsStore.getString('selectedHomeId', '');
      const dids: string[] = Object.keys(map);
      const list: CardDeviceState[] = [];
      for (let i = 0; i < dids.length; i++) {
        const device: XiaomiDevice = map[dids[i]];
        if (homeId.length > 0 && homeId !== ALL_HOMES_ID && device.homeId !== homeId) {
          continue;
        }
        const cachedState: CardDeviceState | null = CardStateStore.read(this.context(), device.did);
        list.push({
          did: device.did,
          name: device.name,
          model: device.model,
          location: device.roomName,
          online: device.online,
          power: cachedState === null ? false : (cachedState as CardDeviceState).power,
          updatedAt: Date.now()
        });
      }
      list.sort((a: CardDeviceState, b: CardDeviceState): number => {
        if (a.online !== b.online) {
          return a.online ? -1 : 1;
        }
        return a.name.localeCompare(b.name);
      });
      if (list.length > 0) {
        this.devices = list;
        CardStateStore.saveAll(this.context(), list);
      }
      this.ensureSelection();
    } catch (err) {
      if (this.devices.length === 0) {
        this.tipsText = '设备列表暂时读取不到，先回首页下拉刷新，再回来配置卡片';
      }
    } finally {
      this.loading = false;
    }
  }

  private async loadRunning(): Promise<void> {
    try {
      this.runningCards = await CardFormService.runningCards(this.context());
    } catch (err) {
      this.runningCards = [];
    }
    this.ensureSelection();
  }

  /** 默认选中：桌面已有卡片 → 该卡片设备；否则第一台设备 */
  private ensureSelection(): void {
    if (this.selectedDid.length > 0) {
      return;
    }
    for (let i = 0; i < this.runningCards.length; i++) {
      if (this.runningCards[i].deviceDid.length > 0) {
        this.selectedDid = this.runningCards[i].deviceDid;
        this.cardContent = this.runningCards[i].content;
        this.cardDimension = this.runningCards[i].dimensionText;
        this.cardTitle = this.runningCards[i].title;
        return;
      }
    }
    if (this.devices.length > 0) {
      this.selectedDid = this.devices[0].did;
      this.cardTitle = this.devices[0].name;
    }
  }

  private selectedDevice(): CardDeviceState | null {
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].did === this.selectedDid) {
        return this.devices[i];
      }
    }
    return null;
  }

  private selectDevice(device: CardDeviceState): void {
    const previousName: string = this.selectedName();
    this.selectedDid = device.did;
    if (this.cardTitle.length === 0 || this.cardTitle === previousName) {
      this.cardTitle = device.name;
    }
  }

  private selectedName(): string {
    const device: CardDeviceState | null = this.selectedDevice();
    return device === null ? '' : (device as CardDeviceState).name;
  }

  private visibleDevices(): CardDeviceState[] {
    const key: string = this.keyword.trim();
    if (key.length === 0) {
      return this.devices;
    }
    const out: CardDeviceState[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      const d: CardDeviceState = this.devices[i];
      if (d.name.indexOf(key) >= 0 || d.location.indexOf(key) >= 0 || d.model.indexOf(key) >= 0) {
        out.push(d);
      }
    }
    return out;
  }

  /** 预览用主值：与 FormAbility 的取值规则保持一致 */
  private previewValue(): string {
    const device: CardDeviceState | null = this.selectedDevice();
    if (device === null) {
      return '未选择设备';
    }
    const d: CardDeviceState = device as CardDeviceState;
    if (this.cardContent === 'online') {
      return d.online ? '在线' : '离线';
    }
    if (this.cardContent === 'name') {
      return d.name;
    }
    if (this.cardContent === 'location') {
      return d.location.length > 0 ? d.location : '未分配房间';
    }
    if (this.cardContent === 'model') {
      return d.model.length > 0 ? d.model : '未知型号';
    }
    if (this.cardContent === 'custom') {
      return this.cardCustomText.length > 0 ? this.cardCustomText : d.name;
    }
    return d.power ? '已开启' : '已关闭';
  }

  private previewDetail(): string {
    const device: CardDeviceState | null = this.selectedDevice();
    if (device === null) {
      return '长按首页设备也能添加到桌面';
    }
    const d: CardDeviceState = device as CardDeviceState;
    const parts: string[] = [];
    if (d.location.length > 0) {
      parts.push(d.location);
    }
    if (d.model.length > 0) {
      parts.push(d.model);
    }
    if (parts.length === 0) {
      parts.push(d.online ? '已连接 MiHome' : '设备离线');
    }
    return parts.join(' · ');
  }

  private previewOnline(): boolean {
    const device: CardDeviceState | null = this.selectedDevice();
    return device === null ? false : (device as CardDeviceState).online;
  }

  private previewLocation(): string {
    const device: CardDeviceState | null = this.selectedDevice();
    if (device === null) {
      return '--';
    }
    const location: string = (device as CardDeviceState).location;
    return location.length > 0 ? location : '未分配房间';
  }

  private previewPowerOn(): boolean {
    return this.previewValue() === '已开启';
  }

  private previewWidth(): number {
    return cardDimensionRatio(this.cardDimension) === 0.5 ? 248 : 172;
  }

  /** 规格示意图：宽高按 4 列 4 行的格子数等比缩放，2*2 与 4*4 一眼可分 */
  private dimensionSketchWidth(label: string): number {
    if (label === '1*2') {
      return 32;
    }
    if (label === '2*4') {
      return 40;
    }
    return label === '4*4' ? 32 : 24;
  }

  private dimensionSketchHeight(label: string): number {
    if (label === '1*2') {
      return 16;
    }
    if (label === '2*4') {
      return 20;
    }
    return label === '4*4' ? 32 : 24;
  }

  private addToHome(): void {
    const device: CardDeviceState | null = this.selectedDevice();
    if (device === null) {
      this.toast('请先选择一台设备');
      return;
    }
    const d: CardDeviceState = device as CardDeviceState;
    const title: string = this.cardTitle.trim().length > 0 ? this.cardTitle.trim() : d.name;
    try {
      CardFormService.openCardManager(this.context(), d.did, d.name, this.cardDimension,
        this.cardContent, this.cardCustomText, title);
      this.tipsText = '已打开系统卡片面板，选好位置后松手即可添加';
      FeedbackLogService.recordOperation('UI',
        `桌面卡片：${d.name} / ${cardContentLabel(this.cardContent)} / ${this.cardDimension}`);
      setTimeout((): void => {
        this.loadRunning();
      }, 1200);
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '打开卡片面板失败';
      this.toast(message);
    }
  }

  private saveAsDefault(): void {
    const device: CardDeviceState | null = this.selectedDevice();
    if (device === null) {
      this.toast('请先选择一台设备');
      return;
    }
    const d: CardDeviceState = device as CardDeviceState;
    const title: string = this.cardTitle.trim().length > 0 ? this.cardTitle.trim() : d.name;
    CardFormService.rememberDefault(this.context(), d.did, d.name, this.cardDimension,
      this.cardContent, this.cardCustomText, title);
    this.toast('已设为系统卡片面板默认样式');
  }

  private refreshAll(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    CardFormService.refreshAllCards(this.context()).then((count: number) => {
      this.busy = false;
      this.toast(count > 0 ? `已刷新 ${count} 张卡片` : '桌面上还没有卡片');
    }).catch(() => {
      this.busy = false;
      this.toast('刷新失败，稍后再试');
    });
  }

  private refreshOne(card: RunningCardView): void {
    CardFormService.refreshCard(this.context(), card.formId).then((ok: boolean) => {
      this.toast(ok ? '卡片已刷新' : '这张卡片还没绑定设备');
    }).catch(() => {
      this.toast('刷新失败，稍后再试');
    });
  }

  /** 把桌面上已有卡片的配置载回上方表单，改完再添加一张 */
  private loadCardConfig(card: RunningCardView): void {
    if (card.deviceDid.length > 0) {
      this.selectedDid = card.deviceDid;
    }
    this.cardContent = card.content;
    this.cardDimension = card.dimensionText;
    this.cardTitle = card.title;
    let custom: string = '';
    const config: CardConfig | null = CardConfigStore.read(this.context(), card.formId);
    if (config !== null) {
      custom = (config as CardConfig).customText;
    }
    this.cardCustomText = custom;
    this.tipsText = `已载入「${card.title}」的配置，确认后点下方按钮重新添加`;
    this.toast('已载入到上方配置');
  }

  // ---------- 视觉 ----------

  @Builder
  SectionHeader(title: string, subtitle: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontFamily(this.appFontFamily(title))
        .fontWeight(this.appFontWeight())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(MijiaOverviewCardText)
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontFamily(this.appFontFamily(subtitle))
          .fontWeight(this.appFontWeight())
          .fontSize(11)
          .fontColor('#6E8083')
          .maxLines(2)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  PreviewCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text('M')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(26)
        .height(26)
        .borderRadius(9)
        .backgroundColor(HwColor.primary)

        Text(this.cardTitle.trim().length > 0 ? this.cardTitle : this.selectedName())
          .fontFamily(this.appFontFamily(this.cardTitle))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(MijiaOverviewCardText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Row({ space: 4 }) {
          Circle()
            .width(6)
            .height(6)
            .fill(this.previewOnline() ? HwColor.online : '#A9BABA')
          Text(this.previewOnline() ? '在线' : '离线')
            .fontFamily(this.appFontFamily('在线'))
            .fontWeight(this.appFontWeight())
            .fontSize(10)
            .fontColor('#6E8083')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (cardDimensionRatio(this.cardDimension) === 0.5) {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(this.previewValue())
              .fontFamily(this.appFontFamily(this.previewValue()))
              .fontWeight(this.appFontWeight())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.previewPowerOn() && this.cardContent === 'power'
                ? HwColor.primary : MijiaOverviewCardText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.previewDetail())
              .fontFamily(this.appFontFamily(this.previewDetail()))
              .fontWeight(this.appFontWeight())
              .fontSize(10)
              .fontColor('#6E8083')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.cardContent === 'power') {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.power'))
                .fontSize(16)
                .fontColor([this.previewPowerOn() ? '#FFFFFF' : HwColor.primary])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.previewPowerOn() ? HwColor.primary : '#EAF6F7')
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 8 }) {
          Column({ space: 4 }) {
            Text(this.previewValue())
              .fontFamily(this.appFontFamily(this.previewValue()))
              .fontWeight(this.appFontWeight())
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.previewPowerOn() && this.cardContent === 'power'
                ? HwColor.primary : MijiaOverviewCardText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.previewDetail())
              .fontFamily(this.appFontFamily(this.previewDetail()))
              .fontWeight(this.appFontWeight())
              .fontSize(10)
              .fontColor('#6E8083')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          if (this.cardDimension === '4*4') {
            Column({ space: 5 }) {
              Divider()
                .color('#EDF3F3')
              Row() {
                Text('房间')
                  .fontFamily(this.appFontFamily('房间'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(10)
                  .fontColor('#9BAFAF')
                Blank()
                Text(this.previewLocation())
                  .fontFamily(this.appFontFamily(this.previewLocation()))
                  .fontWeight(this.appFontWeight())
                  .fontSize(10)
                  .fontColor('#5A6D70')
                  .maxLines(1)
              }
              .width('100%')

              Row() {
                Text('连接')
                  .fontFamily(this.appFontFamily('连接'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(10)
                  .fontColor('#9BAFAF')
                Blank()
                Text(this.previewOnline() ? '在线' : '离线')
                  .fontFamily(this.appFontFamily('连接'))
                  .fontWeight(this.appFontWeight())
                  .fontSize(10)
                  .fontColor(this.previewOnline() ? HwColor.online : '#9BAFAF')
              }
              .width('100%')
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width(this.previewWidth())
    .aspectRatio(cardDimensionRatio(this.cardDimension))
    .padding(14)
    .borderRadius(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: MijiaCardBorder })
    .shadow({ radius: 18, color: MijiaCardShadow, offsetX: 0, offsetY: 6 })
  }

  @Builder
  PreviewSection() {
    Column({ space: 10 }) {
      this.SectionHeader('卡片预览', `当前规格 ${this.cardDimension} · ${cardDimensionHint(this.cardDimension)}`)
      Row() {
        this.PreviewCard()
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 6, bottom: 6 })
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  DeviceTile(device: CardDeviceState) {
    Row({ space: 9 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text(device.name.length > 0 ? device.name.substring(0, 1) : 'M')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedDid === device.did ? '#FFFFFF' : HwColor.primary)
      }
      .width(32)
      .height(32)
      .borderRadius(10)
      .backgroundColor(this.selectedDid === device.did ? HwColor.primary : '#EDF7F8')

      Column({ space: 2 }) {
        Text(device.name)
          .fontFamily(this.appFontFamily(device.name))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(MijiaOverviewCardText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 4 }) {
          Circle()
            .width(5)
            .height(5)
            .fill(device.online ? HwColor.online : '#A9BABA')
          Text(device.location.length > 0 ? device.location : '未分配房间')
            .fontFamily(this.appFontFamily(device.location))
            .fontWeight(this.appFontWeight())
            .fontSize(10)
            .fontColor('#6E8083')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(58)
    .padding({ left: 9, right: 9 })
    .borderRadius(HwRadius.control)
    .backgroundColor(this.selectedDid === device.did ? '#F4FBFC' : '#FFFFFF')
    .border({
      width: this.selectedDid === device.did ? 1.5 : 1,
      color: this.selectedDid === device.did ? HwColor.primary : MijiaCardBorder
    })
    .onClick(() => {
      this.selectDevice(device);
    })
  }

  @Builder
  DeviceSection() {
    Column({ space: 10 }) {
      this.SectionHeader('选择家电',
        this.devices.length === 0 ? '设备列表为空' : `共 ${this.devices.length} 台，点一下选中要放上桌面的设备`)

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(15)
          .fontColor(['#6E8083'])
        TextInput({ text: this.keyword, placeholder: '搜索设备名称 / 房间' })
          .fontFamily(this.appFontFamily(this.keyword))
          .fontWeight(this.appFontWeight())
          .fontSize(13)
          .fontColor(MijiaOverviewCardText)
          .placeholderColor('#9BAFAF')
          .backgroundColor(Color.Transparent)
          .padding(0)
          .layoutWeight(1)
          .height(38)
          .onChange((value: string) => {
            this.keyword = value;
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10 })
      .borderRadius(HwRadius.control)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: MijiaCardBorder })

      if (this.devices.length === 0) {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.square_on_square_fill'))
            .fontSize(26)
            .fontColor(['#B9CBCD'])
          Text(this.loading ? '正在读取设备…' : '还没有可选的家电')
            .fontFamily(this.appFontFamily('还没有可选的家电'))
            .fontWeight(this.appFontWeight())
            .fontSize(13)
            .fontColor(MijiaOverviewCardText)
          Text('回到首页下拉刷新设备列表，或确认已登录米家账号')
            .fontFamily(this.appFontFamily('回到首页下拉刷新设备列表'))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor('#6E8083')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 22, bottom: 22 })
        .borderRadius(HwRadius.control)
        .backgroundColor('#FAFDFD')
        .border({ width: 1, color: MijiaCardBorder })
      } else if (this.visibleDevices().length === 0) {
        Text(`没有匹配「${this.keyword}」的设备`)
          .fontFamily(this.appFontFamily('没有匹配的设备'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor('#6E8083')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 18, bottom: 18 })
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.visibleDevices(), (device: CardDeviceState) => {
            Column() {
              this.DeviceTile(device)
            }
            .width('48.5%')
            .margin({ bottom: 8 })
          }, (device: CardDeviceState) => device.did)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  ContentSection() {
    Column({ space: 10 }) {
      this.SectionHeader('展示内容', cardContentHint(this.cardContent))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(CARD_CONTENT_OPTIONS, (item: CardContentOption) => {
          Text(item.label)
            .fontFamily(this.appFontFamily(item.label))
            .fontWeight(this.appFontWeight())
            .fontSize(12)
            .fontColor(this.cardContent === item.key ? '#FFFFFF' : MijiaOverviewCardText)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(HwRadius.pill)
            .backgroundColor(this.cardContent === item.key ? HwColor.primary : '#FFFFFF')
            .border({
              width: 1,
              color: this.cardContent === item.key ? HwColor.primary : MijiaCardBorder
            })
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.cardContent = item.key;
            })
        }, (item: CardContentOption) => item.key)
      }
      .width('100%')

      if (this.cardContent === 'custom') {
        TextInput({ text: this.cardCustomText, placeholder: '卡片上显示的文字，比如「记得关空调」' })
          .fontFamily(this.appFontFamily(this.cardCustomText))
          .fontWeight(this.appFontWeight())
          .width('100%')
          .height(42)
          .fontSize(13)
          .fontColor(MijiaOverviewCardText)
          .placeholderColor('#9BAFAF')
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: MijiaCardBorder })
          .borderRadius(HwRadius.control)
          .onChange((value: string) => {
            this.cardCustomText = value;
          })
      }
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  DimensionSection() {
    Column({ space: 10 }) {
      this.SectionHeader('卡片规格', cardDimensionHint(this.cardDimension))
      Row({ space: 8 }) {
        ForEach(CARD_DIMENSIONS, (label: string) => {
          Column({ space: 6 }) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(this.dimensionSketchWidth(label))
                .height(this.dimensionSketchHeight(label))
                .borderRadius(4)
                .backgroundColor(this.cardDimension === label ? HwColor.primary : '#DCEAEB')
            }
            .width('100%')
            .height(44)
            .borderRadius(8)
            .backgroundColor(this.cardDimension === label ? '#F4FBFC' : '#FAFDFD')
            .border({
              width: 1,
              color: this.cardDimension === label ? HwColor.primary : MijiaCardBorder
            })
            Text(label)
              .fontFamily(this.appFontFamily(label))
              .fontWeight(this.appFontWeight())
              .fontSize(12)
              .fontColor(this.cardDimension === label ? HwColor.primary : MijiaOverviewCardText)
          }
          .layoutWeight(1)
          .padding({ top: 8, bottom: 8 })
          .borderRadius(HwRadius.control)
          .backgroundColor('#FFFFFF')
          .onClick(() => {
            this.cardDimension = label;
          })
        }, (label: string) => label)
      }
      .width('100%')
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  TitleSection() {
    Column({ space: 8 }) {
      this.SectionHeader('卡片标题', '留空时使用设备名，也可以写成「客厅空调」这类更好认的名字')
      TextInput({ text: this.cardTitle, placeholder: this.selectedName() })
        .fontFamily(this.appFontFamily(this.cardTitle))
        .fontWeight(this.appFontWeight())
        .width('100%')
        .height(42)
        .fontSize(13)
        .fontColor(MijiaOverviewCardText)
        .placeholderColor('#9BAFAF')
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: MijiaCardBorder })
        .borderRadius(HwRadius.control)
        .onChange((value: string) => {
          this.cardTitle = value;
        })
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  ActionSection() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Button(this.devices.length === 0 ? '暂无可选设备' : '添加到桌面')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(this.devices.length === 0 ? '#B9CBCD' : HwColor.primary)
          .borderRadius(HwRadius.control)
          .enabled(this.devices.length > 0)
          .onClick(() => {
            this.addToHome();
          })
        Button('设为默认')
          .width(104)
          .height(46)
          .fontSize(14)
          .fontColor(HwColor.primary)
          .backgroundColor('#F4FBFC')
          .border({ width: 1, color: HwColor.primary })
          .borderRadius(HwRadius.control)
          .onClick(() => {
            this.saveAsDefault();
          })
      }
      .width('100%')

      if (this.tipsText.length > 0) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(13)
            .fontColor([HwColor.primary])
          Text(this.tipsText)
            .fontFamily(this.appFontFamily(this.tipsText))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor('#5A6D70')
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RunningCardRow(card: RunningCardView) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text('M')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(30)
        .height(30)
        .borderRadius(10)
        .backgroundColor(card.hasConfig ? HwColor.primary : '#B9CBCD')

        Column({ space: 2 }) {
          Text(card.title)
            .fontFamily(this.appFontFamily(card.title))
            .fontWeight(this.appFontWeight())
            .fontSize(14)
            .fontColor(MijiaOverviewCardText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(card.hasConfig
            ? `${card.contentLabel} · ${card.dimensionText} · ${card.online ? '在线' : '离线'}`
            : '还没绑定设备，重新配置一次即可')
            .fontFamily(this.appFontFamily(card.contentLabel))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor('#6E8083')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('载入')
          .fontFamily(this.appFontFamily('载入'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor(HwColor.primary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(HwRadius.pill)
          .backgroundColor('#F4FBFC')
          .onClick(() => {
            this.loadCardConfig(card);
          })

        Text('刷新')
          .fontFamily(this.appFontFamily('刷新'))
          .fontWeight(this.appFontWeight())
          .fontSize(12)
          .fontColor('#5A6D70')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(HwRadius.pill)
          .backgroundColor('#F4F7F7')
          .onClick(() => {
            this.refreshOne(card);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .borderRadius(HwRadius.control)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  RunningSection() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 2 }) {
          Text('桌面上已添加')
            .fontFamily(this.appFontFamily('桌面上已添加'))
            .fontWeight(this.appFontWeight())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(MijiaOverviewCardText)
          Text(this.runningCards.length === 0
            ? '还没有卡片，选好家电后点「添加到桌面」'
            : `共 ${this.runningCards.length} 张，可载入原配置再改`)
            .fontFamily(this.appFontFamily('桌面上已添加'))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor('#6E8083')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.runningCards.length > 0) {
          Button(this.busy ? '刷新中…' : '全部刷新')
            .height(32)
            .fontSize(12)
            .fontColor(HwColor.primary)
            .backgroundColor('#F4FBFC')
            .borderRadius(HwRadius.pill)
            .enabled(!this.busy)
            .onClick(() => {
              this.refreshAll();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.runningCards.length === 0) {
        Column({ space: 6 }) {
          Text('桌面空白？')
            .fontFamily(this.appFontFamily('桌面空白？'))
            .fontWeight(this.appFontWeight())
            .fontSize(13)
            .fontColor(MijiaOverviewCardText)
          Text('在桌面长按空白处 → 添加卡片 → 找到 MiHome，也能直接添加；' +
            '添加时会用这里的「设为默认」样式。')
            .fontFamily(this.appFontFamily('在桌面长按空白处'))
            .fontWeight(this.appFontWeight())
            .fontSize(11)
            .fontColor('#6E8083')
            .lineHeight(17)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .borderRadius(HwRadius.control)
        .backgroundColor('#FAFDFD')
        .border({ width: 1, color: MijiaCardBorder })
      } else {
        ForEach(this.runningCards, (card: RunningCardView) => {
          this.RunningCardRow(card)
        }, (card: RunningCardView) => card.formId)
      }
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor(MijiaOverviewCard)
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  TipsSection() {
    Column({ space: 8 }) {
      Text('用卡片的小提示')
        .fontFamily(this.appFontFamily('用卡片的小提示'))
        .fontWeight(this.appFontWeight())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(MijiaOverviewCardText)
      Text('· 卡片上的电源按钮会拉起 App 执行真实开关，再回写卡片状态')
        .fontFamily(this.appFontFamily('卡片上的电源按钮'))
        .fontWeight(this.appFontWeight())
        .fontSize(11)
        .fontColor('#6E8083')
        .lineHeight(17)
      Text('· 想换设备或内容：在下方列表点「载入」，改好后重新添加一张，再把旧的从桌面移除')
        .fontFamily(this.appFontFamily('想换设备或内容'))
        .fontWeight(this.appFontWeight())
        .fontSize(11)
        .fontColor('#6E8083')
        .lineHeight(17)
      Text('· App 打开时会把最新设备状态同步到所有卡片，也会定时自刷新')
        .fontFamily(this.appFontFamily('App 打开时会把最新设备状态同步到所有卡片'))
        .fontWeight(this.appFontWeight())
        .fontSize(11)
        .fontColor('#6E8083')
        .lineHeight(17)
    }
    .width('100%')
    .padding(HwSpace.lg)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(HwRadius.card)
    .backgroundColor('#FAFDFD')
    .border({ width: 1, color: MijiaCardBorder })
  }

  @Builder
  NavBar() {
    Row({ space: 4 }) {
      IconCircleButton({
        symbol: $r('sys.symbol.chevron_left'),
        tint: MijiaOverviewCardText,
        buttonSize: 40,
        iconSize: 20,
        buttonBackground: '#F2F8F8',
        onAction: (): void => {
          router.back();
        }
      })
      Text('桌面卡片')
        .fontFamily(this.appFontFamily('桌面卡片'))
        .fontWeight(this.appFontWeight())
        .margin({ left: HwSpace.md })
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MijiaOverviewCardText)
        .layoutWeight(1)
      IconCircleButton({
        symbol: $r('sys.symbol.arrow_counterclockwise'),
        tint: MijiaOverviewCardText,
        buttonSize: 40,
        iconSize: 19,
        buttonBackground: '#F2F8F8',
        buttonEnabled: !this.busy,
        spinning: this.busy,
        onAction: (): void => {
          this.refreshAll();
        }
      })
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ left: 12, right: 12, top: this.statusBarHeight })
    .backgroundColor('#F2FFFFFF')
    .backgroundEffect({ radius: 24, saturation: 1.3, color: '#B3FFFFFF' })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      AppBackground()
      Scroll() {
        Column({ space: 0 }) {
          Blank().height(this.topOffset())
          Column({ space: 12 }) {
            this.PreviewSection()
            this.DeviceSection()
            this.ContentSection()
            this.DimensionSection()
            this.TitleSection()
            this.ActionSection()
            this.RunningSection()
            this.TipsSection()
            Blank().height(28)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.isWideScreen ? 720 : '100%' })
          .padding({ left: HwSpace.lg, right: HwSpace.lg })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(this.cardsFromTop ? Alignment.Top : Alignment.Center)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      this.NavBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HwColor.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      router.back();
    })
  }
}
