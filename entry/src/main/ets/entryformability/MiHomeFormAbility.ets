/*
 * MiHome 设备卡片提供方。
 *
 * 支持 1*2 / 2*2 / 2*4 / 4*4 四种规格；卡片配置文件在
 * resources/base/profile/form_config.json。App 长按设备 → 添加到桌面时
 * 把设备 did、内容类型、自定义标题写入 form_customize，这里落盘并生成卡片数据。
 */

import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { CardConfig, CardConfigStore } from '../storage/CardConfigStore';
import { CardStateStore, CardDeviceState } from '../storage/CardStateStore';

function stringValue(obj: Record<string, Object>, key: string, fallback: string): string {
  const value: Object | undefined = obj[key];
  return typeof value === 'string' ? value as string : fallback;
}

function dimensionText(dimension: number): string {
  if (dimension === formInfo.FormDimension.Dimension_1_2) {
    return '1*2';
  }
  if (dimension === formInfo.FormDimension.Dimension_2_4) {
    return '2*4';
  }
  if (dimension === formInfo.FormDimension.Dimension_4_4) {
    return '4*4';
  }
  return '2*2';
}

export default class MiHomeFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params: Record<string, Object> = (want.parameters === undefined)
      ? {} as Record<string, Object>
      : want.parameters as Record<string, Object>;

    const formId: string = stringValue(params, formInfo.FormParam.IDENTITY_KEY, '');
    const dimension: number = typeof params[formInfo.FormParam.DIMENSION_KEY] === 'number'
      ? params[formInfo.FormParam.DIMENSION_KEY] as number
      : formInfo.FormDimension.Dimension_2_2;

    const customRaw: Object | undefined = params[formInfo.FormParam.PARAM_FORM_CUSTOMIZE_KEY];
    let custom: Record<string, Object> = {} as Record<string, Object>;
    if (typeof customRaw === 'string') {
      try {
        custom = JSON.parse(customRaw as string) as Record<string, Object>;
      } catch (err) {
        custom = {} as Record<string, Object>;
      }
    } else if (customRaw !== undefined) {
      custom = customRaw as Record<string, Object>;
    }

    const deviceDid: string = stringValue(custom, 'deviceDid', '');
    const deviceName: string = stringValue(custom, 'deviceName', 'MiHome 设备');
    const content: string = stringValue(custom, 'content', 'power');
    const customText: string = stringValue(custom, 'customText', '');
    const title: string = stringValue(custom, 'title', deviceName);

    if (formId.length > 0) {
      const config: CardConfig = {
        formId: formId,
        deviceDid: deviceDid,
        deviceName: deviceName,
        content: content,
        customText: customText,
        title: title,
        dimensionText: dimensionText(dimension)
      };
      CardConfigStore.save(this.context, config);
    }
    return this.buildBinding(formId);
  }

  private buildBinding(formId: string): formBindingData.FormBindingData {
    const config: CardConfig | null = CardConfigStore.read(this.context, formId);
    const state: CardDeviceState | null = config === null
      ? null
      : CardStateStore.read(this.context, (config as CardConfig).deviceDid);

    let value: string = '--';
    let unit: string = '';
    let status: string = '等待同步';
    let detail: string = '点击卡片打开 MiHome';
    let title: string = 'MiHome';
    let deviceDid: string = '';
    let content: string = 'power';

    if (config !== null) {
      title = config.title.length > 0 ? config.title : config.deviceName;
      deviceDid = config.deviceDid;
      content = config.content;
    }
    if (config !== null && state !== null) {
      const deviceState: CardDeviceState = state as CardDeviceState;
      status = deviceState.online ? '在线' : '离线';
      detail = deviceState.model.length > 0
        ? (deviceState.location.length > 0 ? deviceState.model + ' · ' + deviceState.location : deviceState.model)
        : (deviceState.location.length > 0 ? deviceState.location : '已连接 MiHome');
      if (config.content === 'online') {
        value = status;
      } else if (config.content === 'name') {
        value = deviceState.name;
      } else if (config.content === 'model') {
        value = deviceState.model;
      } else if (config.content === 'custom') {
        value = config.customText.length > 0 ? config.customText : deviceState.name;
      } else {
        value = deviceState.power ? '已开启' : '已关闭';
      }
    }

    return formBindingData.createFormBindingData({
      title: title,
      value: value,
      unit: unit,
      status: status,
      detail: detail,
      dimension: config === null ? '2*2' : config.dimensionText,
      content: content,
      deviceDid: deviceDid,
      updatedAt: state === null ? 0 : (state as CardDeviceState).updatedAt
    });
  }

  onCastToNormalForm(formId: string): void {
    this.refresh(formId);
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onFormEvent(formId: string, message: string): void {
    try {
      const params: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      if (stringValue(params, 'type', '') === 'refresh') {
        this.refresh(formId);
      }
    } catch (err) {
      // 非法消息忽略
    }
  }

  private refresh(formId: string): void {
    try {
      formProvider.updateForm(formId, this.buildBinding(formId)).catch(() => {
        // 卡片可能已移除
      });
    } catch (err) {
      // ignore
    }
  }

  onRemoveForm(formId: string): void {
    CardConfigStore.remove(this.context, formId);
  }
}
