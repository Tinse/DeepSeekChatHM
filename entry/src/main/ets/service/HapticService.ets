import { vibrator } from '@kit.SensorServiceKit';

export class HapticService {
  private static enabled: boolean = true;

  static setEnabled(value: boolean): void {
    HapticService.enabled = value;
  }

  static tap(): void {
    if (!HapticService.enabled) {
      return;
    }
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 8
      }, {
        id: 0,
        usage: 'touch'
      }).catch(() => {
        // 设备不支持时静默
      });
    } catch (err) {
      // 设备不支持时静默
    }
  }
}
