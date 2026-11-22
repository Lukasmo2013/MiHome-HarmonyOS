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

    let deviceDid: string = stringValue(custom, 'deviceDid', '');
    let deviceName: string = stringValue(custom, 'deviceName', '');
    let content: string = stringValue(custom, 'content', 'power');
    let customText: string = stringValue(custom, 'customText', '');
    let title: string = stringValue(custom, 'title', '');

    // 路径一：系统「服务卡片」面板直接添加时没有 customize，回落到 App 记住的默认配置
    if (deviceDid.length === 0) {
      const preset: CardConfig | null = CardConfigStore.readDefault(this.context);
      if (preset !== null) {
        const p: CardConfig = preset as CardConfig;
        deviceDid = p.deviceDid;
        deviceName = p.deviceName;
        content = p.content;
        customText = p.customText;
        title = p.title;
      }
    }
    // 路径二：连默认配置都没有（如首次安装直接加卡片），取缓存里第一台在线设备
    if (deviceDid.length === 0) {
      const firstState: CardDeviceState | null = CardStateStore.first(this.context);
      if (firstState !== null) {
        const s: CardDeviceState = firstState as CardDeviceState;
        deviceDid = s.did;
        deviceName = s.name;
      }
    }
    if (deviceName.length === 0) {
      deviceName = 'MiHome 设备';
    }
    if (title.length === 0) {
      title = deviceName;
    }

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
      // 定时自刷新：即使 App 未运行，卡片也会按缓存状态重新渲染
      try {
        formProvider.setFormNextRefreshTime(formId, 30).catch(() => {
          // 低版本不支持定时刷新时忽略
        });
      } catch (err) {
        // 同步异常同样忽略
      }
    }
    return this.buildBinding(formId);
  }

  private buildBinding(formId: string): formBindingData.FormBindingData {
    const saved: CardConfig | null = CardConfigStore.read(this.context, formId);

    // 预览态（系统「服务卡片」面板里渲染的那张）formId 为空、也没有 customize，
    // 依次回落到默认配置 → 缓存里的首台设备，避免预览是一片空白。
    let config: CardConfig | null = saved;
    if (config === null) {
      config = CardConfigStore.readDefault(this.context);
    }
    if (config === null) {
      const firstState: CardDeviceState | null = CardStateStore.first(this.context);
      if (firstState !== null) {
        const s: CardDeviceState = firstState as CardDeviceState;
        config = {
          formId: '',
          deviceDid: s.did,
          deviceName: s.name,
          content: 'power',
          customText: '',
          title: s.name,
          dimensionText: '2*2'
        };
      }
    }

    if (config === null) {
      // 没有任何配置：给出可读的引导态，而不是一张只有 "--" 的空白卡
      return formBindingData.createFormBindingData({
        title: 'MiHome',
        value: '未选择设备',
        unit: '',
        status: '待配置',
        detail: '打开 App，长按设备 → 添加到桌面',
        dimension: '2*2',
        content: 'power',
        deviceDid: '',
        room: '',
        model: '',
        updatedAt: 0
      });
    }

    const cfg: CardConfig = config as CardConfig;

    if (cfg.deviceDid.length === 0) {
      // 配置存在但未绑定到设备（系统面板添加且本地无设备缓存）
      return formBindingData.createFormBindingData({
        title: cfg.title.length > 0 ? cfg.title : 'MiHome',
        value: '未选择设备',
        unit: '',
        status: '待配置',
        detail: '打开 App，长按设备 → 添加到桌面',
        dimension: cfg.dimensionText,
        content: cfg.content,
        deviceDid: '',
        room: '',
        model: '',
        updatedAt: 0
      });
    }

    const state: CardDeviceState | null = CardStateStore.read(this.context, cfg.deviceDid);
    let value: string = '--';
    let unit: string = '';
    let status: string = '待同步';
    let detail: string = '打开 App 同步设备状态';
    let room: string = '';
    let model: string = '';

    if (state !== null) {
      const s: CardDeviceState = state as CardDeviceState;
      status = s.online ? '在线' : '离线';
      room = s.location.length > 0 ? s.location : '未分配房间';
      model = s.model.length > 0 ? s.model : '未知型号';
      detail = s.location.length > 0 ? s.location : (s.model.length > 0 ? s.model : '已连接 MiHome');
      if (cfg.content === 'online') {
        value = status;
      } else if (cfg.content === 'name') {
        value = s.name;
      } else if (cfg.content === 'model') {
        value = s.model.length > 0 ? s.model : '未知型号';
      } else if (cfg.content === 'location') {
        value = s.location.length > 0 ? s.location : '未分配房间';
      } else if (cfg.content === 'custom') {
        value = cfg.customText.length > 0 ? cfg.customText : s.name;
      } else {
        value = s.power ? '已开启' : '已关闭';
      }
    } else if (cfg.content === 'name') {
      value = cfg.deviceName;
    }

    return formBindingData.createFormBindingData({
      title: cfg.title.length > 0 ? cfg.title : cfg.deviceName,
      value: value,
      unit: unit,
      status: status,
      detail: detail,
      dimension: cfg.dimensionText,
      content: cfg.content,
      deviceDid: cfg.deviceDid,
      room: room,
      model: model,
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
