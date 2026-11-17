import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings } from '../model/Types';

const STORE_NAME: string = 'deepseek_settings';
const SETTINGS_KEY: string = 'app_settings';

export class SettingsStore {
  private static instance: SettingsStore | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private cache: AppSettings = new AppSettings();

  static get(): SettingsStore {
    if (SettingsStore.instance === undefined) {
      SettingsStore.instance = new SettingsStore();
    }
    return SettingsStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.pref = await preferences.getPreferences(context, STORE_NAME);
    let raw: preferences.ValueType = await this.pref.get(SETTINGS_KEY, '');
    let text: string = raw as string;
    if (text.length === 0) {
      return;
    }
    try {
      let parsed: AppSettings = JSON.parse(text) as AppSettings;
      let merged: AppSettings = new AppSettings();
      if (parsed.model !== undefined) {
        merged.model = parsed.model;
      }
      if (parsed.thinking !== undefined) {
        merged.thinking = parsed.thinking;
      }
      if (parsed.search !== undefined) {
        merged.search = parsed.search;
      }
      if (parsed.voice !== undefined) {
        merged.voice = parsed.voice;
      }
      if (parsed.haptic !== undefined) {
        merged.haptic = parsed.haptic;
      }
      if (parsed.textSize !== undefined) {
        merged.textSize = parsed.textSize;
      }
      if (parsed.expandThinking !== undefined) {
        merged.expandThinking = parsed.expandThinking;
      }
      this.cache = merged;
    } catch (err) {
      this.cache = new AppSettings();
    }
  }

  get(): AppSettings {
    return this.cache;
  }

  async save(settings: AppSettings): Promise<void> {
    this.cache = settings;
    if (this.pref === undefined) {
      return;
    }
    await this.pref.put(SETTINGS_KEY, JSON.stringify(settings));
    await this.pref.flush();
  }
}
