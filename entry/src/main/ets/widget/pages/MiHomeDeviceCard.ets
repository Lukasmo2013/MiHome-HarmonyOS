/*
 * MiHome 桌面卡片（动态 ArkTS 卡片）。
 * 四种规格：1*2 / 2*2 / 2*4 / 4*4，同一套代码按 dimension 自适应。
 */

let cardStorage: LocalStorage = new LocalStorage();

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

  /** 开关按钮：拉起 EntryAbility，由 App 执行真实下发并回写卡片 */
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

  @Builder
  Header() {
    Row({ space: 8 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text('M')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(24)
        .height(24)
        .borderRadius(8)
        .backgroundColor('#3E9AA6')

        Text(this.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172226')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .onClick((): void => { this.openApp(); })

      if (this.dimension !== '1*2') {
        Text(this.status)
          .fontSize(10)
          .fontColor(this.status === '在线' ? '#2AA98C' : '#6E8083')
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .borderRadius(999)
          .backgroundColor('#F2F8F8')
      }

      // 电源开关：直接下发，不必先打开 App
      if (this.deviceDid.length > 0) {
        Text(this.powerOn() ? '关' : '开')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.powerOn() ? '#FFFFFF' : '#3E9AA6')
          .textAlign(TextAlign.Center)
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(this.powerOn() ? '#3E9AA6' : '#EAF6F7')
          .onClick((): void => { this.toggle(); })
      }
    }
    .width('100%')
  }

  @Builder
  ValueBlock(big: boolean) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text(this.value)
          .fontSize(big ? 30 : 22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172226')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.unit.length > 0) {
          Text(this.unit)
            .fontSize(12)
            .fontColor('#6E8083')
        }
      }
      .justifyContent(FlexAlign.Center)
      Text(this.detail)
        .fontSize(10)
        .fontColor('#6E8083')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .onClick((): void => { this.openApp(); })
  }

  build() {
    Column({ space: 10 }) {
      this.Header()

      if (this.deviceDid.length === 0) {
        // 还没绑定设备：给出引导，而不是一张只有占位符的空白卡
        Column({ space: 6 }) {
          Text('＋')
            .fontSize(20)
            .fontColor('#3E9AA6')
          Text('未选择设备')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#172226')
          Text('打开 MiHome，长按设备 → 添加到桌面')
            .fontSize(10)
            .fontColor('#6E8083')
            .maxLines(2)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => { this.openApp(); })
      } else if (this.dimension === '1*2') {
        Row({ space: 8 }) {
          Text(this.value)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172226')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('打开')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor('#3E9AA6')
            .onClick((): void => { this.openApp(); })
        }
        .width('100%')
      } else if (this.dimension === '2*4') {
        this.ValueBlock(false)
        Row({ space: 8 }) {
          Text('打开设备')
            .fontSize(11).fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor('#3E9AA6')
            .onClick((): void => { this.openApp(); })
          Text('刷新')
            .fontSize(11).fontColor('#2F8C96')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor('#F2F8F8')
            .onClick((): void => { this.refresh(); })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      } else if (this.dimension === '4*4') {
        Column({ space: 12 }) {
          this.ValueBlock(true)
          Row({ space: 10 }) {
            Text('打开设备')
              .fontSize(12).fontColor('#FFFFFF')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(999)
              .backgroundColor('#3E9AA6')
              .onClick((): void => { this.openApp(); })
            Text('刷新状态')
              .fontSize(12).fontColor('#2F8C96')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(999)
              .backgroundColor('#F2F8F8')
              .onClick((): void => { this.refresh(); })
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.ValueBlock(true)
        Text('点击进入设备')
          .fontSize(10)
          .fontColor('#2F8C96')
          .onClick((): void => { this.openApp(); })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
}
