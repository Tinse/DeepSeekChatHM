import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DeepSeekChat';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    let mainWindow: window.Window = windowStage.getMainWindowSync();
    let dark: boolean = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    mainWindow.setWindowSystemBarEnable(['status']).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarEnable failed: %{public}s', err.message);
    });
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      statusBarContentColor: dark ? '#FFFFFF' : '#000000'
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', err.message);
    });
    mainWindow.setWindowLayoutFullScreen(true).then(() => {
      this.loadChatPage(windowStage);
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', err.message);
      this.loadChatPage(windowStage);
    });
  }

  private loadChatPage(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }
}
