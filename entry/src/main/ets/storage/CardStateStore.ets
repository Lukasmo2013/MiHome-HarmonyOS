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
}
