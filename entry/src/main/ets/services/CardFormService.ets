/*
 * 桌面卡片桥接：App 状态写入 + 打开系统卡片管理页。
 */

import { Context, Want } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { XiaomiDevice } from '../models/XiaomiHomeModels';
import { CardConfig, CardConfigStore } from '../storage/CardConfigStore';
import { CardDeviceState, CardStateStore } from '../storage/CardStateStore';

const BUNDLE_NAME: string = 'com.mihome.client';
const FORM_ABILITY: string = 'MiHomeFormAbility';
const FORM_NAME: string = 'MiHomeDeviceCard';
const MODULE_NAME: string = 'entry';

export class CardFormService {
  static dimensionValue(label: string): number {
    if (label === '1*2') {
      return formInfo.FormDimension.Dimension_1_2;
    }
    if (label === '2*4') {
      return formInfo.FormDimension.Dimension_2_4;
    }
    if (label === '4*4') {
      return formInfo.FormDimension.Dimension_4_4;
    }
    return formInfo.FormDimension.Dimension_2_2;
  }

  /**
   * 长按菜单 / 配置面板入口：
   * 1) 先把当前选择写入「默认卡片配置」，系统服务卡片面板直接添加时由 FormAbility 回落使用；
   * 2) 再打开系统卡片管理页，由用户选择放置位置。
   */
  static openCardManager(context: Context, device: XiaomiDevice, dimensionLabel: string,
    content: string, customText: string, title: string): void {
    CardFormService.rememberDefault(context, device, dimensionLabel, content, customText, title);

    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: FORM_ABILITY,
      parameters: {
        'ohos.extra.param.key.module_name': MODULE_NAME,
        'ohos.extra.param.key.form_name': FORM_NAME,
        'ohos.extra.param.key.form_dimension': CardFormService.dimensionValue(dimensionLabel),
        'ohos.extra.param.key.form_customize': JSON.stringify({
          deviceDid: device.did,
          deviceName: device.name,
          content: content,
          customText: customText,
          title: title
        })
      }
    };
    formProvider.openFormManager(want);
  }

  /** 记住「下次添加卡片用哪台设备 / 哪种内容」，供系统面板添加时回落 */
  static rememberDefault(context: Context, device: XiaomiDevice, dimensionLabel: string,
    content: string, customText: string, title: string): void {
    CardConfigStore.saveDefault(context, {
      formId: 'default',
      deviceDid: device.did,
      deviceName: device.name.length > 0 ? device.name : 'MiHome 设备',
      content: content,
      customText: customText,
      title: title,
      dimensionText: dimensionLabel
    });
  }

  static buildStates(devices: XiaomiDevice[],
    powerStates: Record<string, boolean>): CardDeviceState[] {
    const out: CardDeviceState[] = [];
    const now: number = Date.now();
    for (let i = 0; i < devices.length; i++) {
      const device: XiaomiDevice = devices[i];
      out.push({
        did: device.did,
        name: device.name,
        model: device.model,
        location: device.roomName,
        online: device.online,
        power: powerStates[device.did] === true,
        updatedAt: now
      });
    }
    return out;
  }

  /** 设备列表/开关状态变化后刷新所有已添加卡片 */
  static async syncFromDevices(context: Context, devices: XiaomiDevice[],
    powerStates: Record<string, boolean>): Promise<void> {
    CardStateStore.saveAll(context, CardFormService.buildStates(devices, powerStates));
    await CardFormService.updateRunningForms(context);
  }

  private static async updateRunningForms(context: Context): Promise<void> {
    try {
      const infos: Array<formInfo.RunningFormInfo> =
        await formProvider.getPublishedRunningFormInfos();
      for (let i = 0; i < infos.length; i++) {
        const info: formInfo.RunningFormInfo = infos[i];
        if (info.formName !== FORM_NAME || info.formId.length === 0) {
          continue;
        }
        const config: CardConfig | null = CardConfigStore.read(context, info.formId);
        if (config === null) {
          continue;
        }
        const state: CardDeviceState | null = CardStateStore.read(context, config.deviceDid);
        let value: string = '--';
        let status: string = '待同步';
        let detail: string = '打开 App 同步设备状态';
        if (state !== null) {
          const s: CardDeviceState = state as CardDeviceState;
          status = s.online ? '在线' : '离线';
          detail = s.location.length > 0 ? s.location : (s.model.length > 0 ? s.model : '已连接 MiHome');
          if (config.content === 'online') {
            value = status;
          } else if (config.content === 'name') {
            value = s.name;
          } else if (config.content === 'model') {
            value = s.model.length > 0 ? s.model : '未知型号';
          } else if (config.content === 'location') {
            value = s.location.length > 0 ? s.location : '未分配房间';
          } else if (config.content === 'custom') {
            value = config.customText.length > 0 ? config.customText : s.name;
          } else {
            value = s.power ? '已开启' : '已关闭';
          }
        } else if (config.content === 'name') {
          value = config.deviceName;
        }
        const data: formBindingData.FormBindingData = formBindingData.createFormBindingData({
          title: config.title.length > 0 ? config.title : config.deviceName,
          value: value,
          unit: '',
          status: status,
          detail: detail,
          dimension: config.dimensionText,
          content: config.content,
          deviceDid: config.deviceDid,
          updatedAt: state === null ? 0 : (state as CardDeviceState).updatedAt
        });
        await formProvider.updateForm(info.formId, data);
      }
    } catch (err) {
      // 系统卡片服务不可用时静默降级，不影响主 App
    }
  }
}
