/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 莫洁安
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/*
 * MiHome 桌面卡片（动态 ArkTS 卡片）。
 * 四种规格 1*2 / 2*2 / 2*4 / 4*4 共用一套代码，按 dimension 切换版式。
 *
 * 视觉约定（与 App 内保持一致）：
 * - 白底、深墨字、浅蓝绿点缀，描边极淡；
 * - 主值最大最重，副信息弱化，右侧只留一个电源圆钮；
 * - 离线时状态点变灰，主值仍可读，不做灰化整个卡片。
 */

let cardStorage: LocalStorage = new LocalStorage();

const PRIMARY: string = '#3E9AA6';
const TEXT: string = '#172226';
const SUB: string = '#6E8083';
const FAINT: string = '#9BAFAF';
const LINE: string = '#EDF3F3';
const SOFT: string = '#F1F8F9';
const ONLINE: string = '#2AA98C';

/** 卡片上展示的内容项名称（与 App 配置面板的键值一一对应） */
function contentLabel(key: string): string {
  if (key === 'online') {
    return '在线状态';
  }
  if (key === 'name') {
    return '设备名称';
  }
  if (key === 'location') {
    return '所在房间';
  }
  if (key === 'model') {
    return '设备型号';
  }
  if (key === 'custom') {
    return '自定义';
  }
  return '开关状态';
}

@Entry(cardStorage)
@Component
struct MiHomeDeviceCard {
  @LocalStorageProp('title') title: string = 'MiHome';
  @LocalStorageProp('value') value: string = '--';
  @LocalStorageProp('unit') unit: string = '';
  @LocalStorageProp('status') status: string = '等待同步';
  @LocalStorageProp('detail') detail: string = '点击卡片打开 MiHome';
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('content') content: string = 'power';
  @LocalStorageProp('deviceDid') deviceDid: string = '';
  @LocalStorageProp('room') room: string = '';
  @LocalStorageProp('model') model: string = '';

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: JSON.stringify({ deviceDid: this.deviceDid })
    });
  }

  private refresh(): void {
    postCardAction(this, {
      action: 'message',
      params: JSON.stringify({ type: 'refresh' })
    });
  }

  /** 开关按钮：拉起 App 由 EntryAbility 执行真实下发，再回写卡片 */
  private toggle(): void {
    postCardAction(this, {
      action: 'call',
      abilityName: 'EntryAbility',
      params: JSON.stringify({ cardToggleDid: this.deviceDid })
    });
  }

  private powerOn(): boolean {
    return this.value === '已开启';
  }

  private online(): boolean {
    return this.status === '在线';
  }

  /** 副标题：优先房间，其次型号，都没有时给一句中性描述 */
  private subLine(): string {
    if (this.room.length > 0) {
      return this.room;
    }
    if (this.model.length > 0) {
      return this.model;
    }
    return this.detail;
  }

  private valueColor(): string {
    if (this.content === 'power') {
      return this.powerOn() ? PRIMARY : TEXT;
    }
    return TEXT;
  }

  private valueSize(): number {
    if (this.content === 'name' || this.content === 'custom') {
      return this.dimension === '4*4' ? 26 : 20;
    }
    return this.dimension === '4*4' ? 36 : 30;
  }

  /** 顶部：品牌点 + 标题 + 状态 / 电源 */
  @Builder
  Header() {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('M')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width(24)
      .height(24)
      .borderRadius(8)
      .backgroundColor(PRIMARY)

      Column({ space: 1 }) {
        Text(this.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.dimension !== '1*2') {
          Text(this.subLine())
            .fontSize(9)
            .fontColor(FAINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.content === 'power' && this.deviceDid.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.powerOn() ? '关' : '开')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.powerOn() ? '#FFFFFF' : PRIMARY)
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(this.powerOn() ? PRIMARY : SOFT)
        .onClick((): void => {
          this.toggle();
        })
      } else {
        Row({ space: 4 }) {
          Column()
            .width(5)
            .height(5)
            .borderRadius(3)
            .backgroundColor(this.online() ? ONLINE : '#B9CBCD')
          if (this.dimension !== '1*2') {
            Text(this.status)
              .fontSize(9)
              .fontColor(this.online() ? ONLINE : FAINT)
          }
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openApp();
    })
  }

  /** 1*2：一条扁卡，主值一行带走 */
  @Builder
  SlimBody() {
    Row({ space: 8 }) {
      Text(this.value)
        .fontSize(this.valueSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(this.valueColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.content !== 'power') {
        Text(contentLabel(this.content))
          .fontSize(9)
          .fontColor(FAINT)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .borderRadius(999)
          .backgroundColor(SOFT)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 2*2：方形，主值居中 */
  @Builder
  SquareBody() {
    Column({ space: 6 }) {
      Text(this.value)
        .fontSize(this.valueSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(this.valueColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.detail)
        .fontSize(10)
        .fontColor(SUB)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.openApp();
    })
  }

  /** 2*4：横向宽卡，左主值右信息 */
  @Builder
  WideBody() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(this.value)
          .fontSize(this.valueSize())
          .fontWeight(FontWeight.Bold)
          .fontColor(this.valueColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail)
          .fontSize(10)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 6 }) {
        Row() {
          Text('房间')
            .fontSize(9)
            .fontColor(FAINT)
          Blank()
          Text(this.room.length > 0 ? this.room : '--')
            .fontSize(9)
            .fontColor(SUB)
            .maxLines(1)
        }
        .width(96)

        Row() {
          Text('内容')
            .fontSize(9)
            .fontColor(FAINT)
          Blank()
          Text(contentLabel(this.content))
            .fontSize(9)
            .fontColor(SUB)
            .maxLines(1)
        }
        .width(96)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openApp();
    })
  }

  /** 4*4：大方卡，信息最全 */
  @Builder
  LargeBody() {
    Column({ space: 0 }) {
      Column({ space: 4 }) {
        Text(this.value)
          .fontSize(this.valueSize())
          .fontWeight(FontWeight.Bold)
          .fontColor(this.valueColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail)
          .fontSize(10)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.openApp();
      })

      Divider()
        .color(LINE)
        .margin({ bottom: 8 })

      Row() {
        Text('房间')
          .fontSize(9)
          .fontColor(FAINT)
        Blank()
        Text(this.room.length > 0 ? this.room : '--')
          .fontSize(9)
          .fontColor(SUB)
          .maxLines(1)
      }
      .width('100%')
      .margin({ bottom: 4 })

      Row() {
        Text('型号')
          .fontSize(9)
          .fontColor(FAINT)
        Blank()
        Text(this.model.length > 0 ? this.model : '--')
          .fontSize(9)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 底部操作条：宽卡与大卡才有 */
  @Builder
  ActionBar() {
    Row({ space: 8 }) {
      Text('打开设备')
        .fontSize(10)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 6, bottom: 6 })
        .borderRadius(999)
        .backgroundColor(PRIMARY)
        .onClick((): void => {
          this.openApp();
        })
      Text('刷新')
        .fontSize(10)
        .fontColor(SUB)
        .textAlign(TextAlign.Center)
        .width(56)
        .padding({ top: 6, bottom: 6 })
        .borderRadius(999)
        .backgroundColor(SOFT)
        .onClick((): void => {
          this.refresh();
        })
    }
    .width('100%')
    .margin({ top: 8 })
  }

  /** 空卡：给出下一步动作，而不是一张只有占位符的卡 */
  @Builder
  EmptyBody() {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('＋')
          .fontSize(16)
          .fontColor(PRIMARY)
      }
      .width(30)
      .height(30)
      .borderRadius(15)
      .backgroundColor(SOFT)

      Text('未选择设备')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT)
      if (this.dimension !== '1*2') {
        Text('打开 MiHome → 我的 → 桌面卡片')
          .fontSize(9)
          .fontColor(FAINT)
          .maxLines(2)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.openApp();
    })
  }

  build() {
    Column({ space: this.dimension === '1*2' ? 6 : 8 }) {
      this.Header()

      if (this.deviceDid.length === 0) {
        this.EmptyBody()
      } else if (this.dimension === '1*2') {
        this.SlimBody()
      } else if (this.dimension === '2*4') {
        this.WideBody()
        this.ActionBar()
      } else if (this.dimension === '4*4') {
        this.LargeBody()
        this.ActionBar()
      } else {
        this.SquareBody()
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.dimension === '1*2' ? 10 : 12)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }
}
