/*
 * 卡片展示用的设备状态快照（App 写入 / FormExtensionAbility 读取）。
 */

import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'mihome_card_state';
const KEY_PREFIX: string = 'device_';

export interface CardDeviceState {
  did: string;
  name: string;
  model: string;
  location: string;
  online: boolean;
  power: boolean;
  updatedAt: number;
}

export class CardStateStore {
  private static store(context: Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  static save(context: Context, state: CardDeviceState): void {
    try {
      const store: preferences.Preferences = CardStateStore.store(context);
      store.putSync(KEY_PREFIX + state.did, JSON.stringify(state));
      store.flushSync();
    } catch (err) {
      // ignore
    }
  }

  static saveAll(context: Context, states: CardDeviceState[]): void {
    let store: preferences.Preferences | null = null;
    try {
      store = CardStateStore.store(context);
      for (let i = 0; i < states.length; i++) {
        store.putSync(KEY_PREFIX + states[i].did, JSON.stringify(states[i]));
      }
      store.flushSync();
    } catch (err) {
      // ignore
    }
  }

  static read(context: Context, did: string): CardDeviceState | null {
    try {
      const raw: string = CardStateStore.store(context).getSync(KEY_PREFIX + did, '') as string;
      if (raw.length === 0) {
        return null;
      }
      return JSON.parse(raw) as CardDeviceState;
    } catch (err) {
      return null;
    }
  }

  /**
   * 枚举全部已缓存设备：在线优先，其次按更新时间倒序。
   * 卡片提供方在「系统服务卡片面板直接添加、没有 customize」时用它回落默认设备，
   * 避免生成一张只有占位符的空白卡片。
   */
  static list(context: Context): CardDeviceState[] {
    const out: CardDeviceState[] = [];
    try {
      const all: Record<string, Object> = CardStateStore.store(context).getAllSync() as Record<string, Object>;
      const keys: string[] = Object.keys(all);
      for (let i = 0; i < keys.length; i++) {
        if (keys[i].indexOf(KEY_PREFIX) !== 0) {
          continue;
        }
        const raw: Object | undefined = all[keys[i]];
        if (typeof raw !== 'string') {
          continue;
        }
        try {
          out.push(JSON.parse(raw as string) as CardDeviceState);
        } catch (err) {
          // 单条损坏跳过，不影响其余设备
        }
      }
    } catch (err) {
      // 存储不可用时返回空列表
    }
    out.sort((a: CardDeviceState, b: CardDeviceState): number => {
      if (a.online !== b.online) {
        return a.online ? -1 : 1;
      }
      return b.updatedAt - a.updatedAt;
    });
    return out;
  }

  static first(context: Context): CardDeviceState | null {
    const list: CardDeviceState[] = CardStateStore.list(context);
    return list.length > 0 ? list[0] : null;
  }
}
