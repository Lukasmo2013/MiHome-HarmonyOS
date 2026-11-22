/*
 * HarmonyOS 卡片配置持久化（跨进程：App 与 FormExtensionAbility 共享）。
 */

import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'mihome_card_config';
const KEY_PREFIX: string = 'form_';
/** App 侧记住的「下次添加卡片用哪台设备/哪种内容」；key 不带 form_ 前缀，不会被 all() 当成卡片实例 */
const DEFAULT_KEY: string = 'default_card';

export interface CardConfig {
  formId: string;
  deviceDid: string;
  deviceName: string;
  content: string;
  customText: string;
  title: string;
  dimensionText: string;
}

export class CardConfigStore {
  private static store(context: Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  static save(context: Context, config: CardConfig): void {
    try {
      const store: preferences.Preferences = CardConfigStore.store(context);
      store.putSync(KEY_PREFIX + config.formId, JSON.stringify(config));
      store.flushSync();
    } catch (err) {
      // 卡片配置写入失败不影响主流程
    }
  }

  static read(context: Context, formId: string): CardConfig | null {
    try {
      const raw: string = CardConfigStore.store(context).getSync(KEY_PREFIX + formId, '') as string;
      if (raw.length === 0) {
        return null;
      }
      return JSON.parse(raw) as CardConfig;
    } catch (err) {
      return null;
    }
  }

  static remove(context: Context, formId: string): void {
    try {
      const store: preferences.Preferences = CardConfigStore.store(context);
      store.deleteSync(KEY_PREFIX + formId);
      store.flushSync();
    } catch (err) {
      // ignore
    }
  }

  /** 记录默认卡片配置：系统「服务卡片」面板直接添加时拿不到 customize，用它回落 */
  static saveDefault(context: Context, config: CardConfig): void {
    try {
      const store: preferences.Preferences = CardConfigStore.store(context);
      store.putSync(DEFAULT_KEY, JSON.stringify(config));
      store.flushSync();
    } catch (err) {
      // ignore
    }
  }

  static readDefault(context: Context): CardConfig | null {
    try {
      const raw: string = CardConfigStore.store(context).getSync(DEFAULT_KEY, '') as string;
      if (raw.length === 0) {
        return null;
      }
      return JSON.parse(raw) as CardConfig;
    } catch (err) {
      return null;
    }
  }

  static all(context: Context): CardConfig[] {
    const out: CardConfig[] = [];
    try {
      const all: Record<string, Object> = CardConfigStore.store(context).getAllSync() as Record<string, Object>;
      const keys: Array<string> = Object.keys(all);
      for (let i = 0; i < keys.length; i++) {
        if (keys[i].indexOf(KEY_PREFIX) !== 0) {
          continue;
        }
        const raw: Object | undefined = all[keys[i]];
        if (typeof raw !== 'string') {
          continue;
        }
        out.push(JSON.parse(raw as string) as CardConfig);
      }
    } catch (err) {
      // ignore
    }
    return out;
  }
}
