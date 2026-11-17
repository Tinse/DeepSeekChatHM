import { asset } from '@kit.AssetStoreKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const ALIAS: string = 'deepseek_api_key';
const PREF_STORE: string = 'deepseek_secret';
const PREF_KEY: string = 'api_key_fallback';

/**
 * API Key 优先写入 AssetStoreKit（系统级凭据加密，设备首次解锁后可读）；
 * 部分模拟器/老设备不支持 Asset 时回退 preferences，行为对上层透明。
 */
export class SecretStore {
  private static instance: SecretStore | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private cached: string = '';
  private assetReady: boolean = false;

  static get(): SecretStore {
    if (SecretStore.instance === undefined) {
      SecretStore.instance = new SecretStore();
    }
    return SecretStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.pref = await preferences.getPreferences(context, PREF_STORE);
    try {
      this.assetReady = true;
    } catch (err) {
      this.assetReady = false;
    }
    this.cached = await this.load();
  }

  get(): string {
    return this.cached;
  }

  hasKey(): boolean {
    return this.cached.length > 0;
  }

  async save(key: string): Promise<void> {
    this.cached = key;
    if (this.assetReady) {
      try {
        await this.removeAsset();
        let encoder: util.TextEncoder = new util.TextEncoder();
        let secret: Uint8Array = encoder.encodeInto(key);
        let attributes: asset.AssetMap = new Map();
        attributes.set(asset.Tag.ALIAS, this.encode(ALIAS));
        attributes.set(asset.Tag.SECRET, secret);
        attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        attributes.set(asset.Tag.DATA_LABEL_NORMAL_1, this.encode('deepseek-chat'));
        await asset.add(attributes);
      } catch (err) {
        // 忽略，仍写 preferences 兜底
      }
    }
    if (this.pref !== undefined) {
      await this.pref.put(PREF_KEY, key);
      await this.pref.flush();
    }
  }

  async clear(): Promise<void> {
    this.cached = '';
    if (this.assetReady) {
      try {
        await this.removeAsset();
      } catch (err) {
        // ignore
      }
    }
    if (this.pref !== undefined) {
      await this.pref.put(PREF_KEY, '');
      await this.pref.flush();
    }
  }

  private async load(): Promise<string> {
    if (this.assetReady) {
      try {
        let query: asset.AssetMap = new Map();
        query.set(asset.Tag.ALIAS, this.encode(ALIAS));
        query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
        let results: Array<asset.AssetMap> = await asset.query(query);
        if (results.length > 0) {
          let secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
          if (secret !== undefined) {
            let bytes: Uint8Array = secret as Uint8Array;
            let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
            return decoder.decodeToString(bytes);
          }
        }
      } catch (err) {
        // 无记录或不支持
      }
    }
    if (this.pref !== undefined) {
      let raw: preferences.ValueType = await this.pref.get(PREF_KEY, '');
      return raw as string;
    }
    return '';
  }

  private async removeAsset(): Promise<void> {
    let query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(ALIAS));
    await asset.remove(query);
  }

  private encode(text: string): Uint8Array {
    let encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(text);
  }
}
