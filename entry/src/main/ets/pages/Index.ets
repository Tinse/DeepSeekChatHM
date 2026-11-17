import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { uiMaterial, window } from '@kit.ArkUI';
import { ChatEngine, ChatCallbacks } from '../service/ChatEngine';
import { ChatRepository } from '../service/ChatRepository';
import { DeepSeekClient } from '../service/ApiClient';
import { SecretStore } from '../service/SecretStore';
import { SettingsStore } from '../service/SettingsStore';
import { SpeechService } from '../service/SpeechService';
import { HapticService } from '../service/HapticService';
import { AppSettings, AttachmentDraft, ChatMessage, ChatSession } from '../model/Types';
import { MessageItem } from '../view/MessageItem';
import { Composer } from '../view/Composer';
import { WelcomePanel } from '../view/WelcomePanel';
import { SessionPanel } from '../view/SessionPanel';
import { SettingsSheet } from '../view/SettingsSheet';
import { bgColor, cardColor, Palette, softColor, subTextColor, textColor } from '../view/common/Theme';
import { openUrl, toast } from '../utils/TextUtils';

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State sessions: ChatSession[] = [];
  @State title: string = '新对话';
  @State streaming: boolean = false;
  @State dark: boolean = false;
  @State settings: AppSettings = new AppSettings();
  @State apiKey: string = '';
  @State showSheet: boolean = false;
  @State sheetMode: number = 0;
  @State isWide: boolean = false;
  @State stickToBottom: boolean = true;
  @State immersive: boolean = false;
  @State reading: boolean = false;
  @State topInset: number = 0;
  @State bottomInset: number = 0;

  private engine: ChatEngine = new ChatEngine();
  private speech: SpeechService = new SpeechService();
  private scroller: Scroller = new Scroller();
  private material: uiMaterial.Material = uiMaterial.Material.empty;

  aboutToAppear(): void {
    let context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.dark = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.initMaterial();
    this.applySafeArea(context);
    this.bootstrap(context);
  }

  private async applySafeArea(context: common.UIAbilityContext): Promise<void> {
    try {
      let mainWindow: window.Window = await window.getLastWindow(context);
      if (!mainWindow.getWindowProperties().isLayoutFullScreen) {
        this.topInset = 0;
        this.bottomInset = 0;
        return;
      }
      let area: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = this.getUIContext().px2vp(area.topRect.height);
      let bottomPx: number = area.bottomRect.height;
      try {
        let indicator: window.AvoidArea =
          mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        if (indicator.bottomRect.height > bottomPx) {
          bottomPx = indicator.bottomRect.height;
        }
      } catch (indicatorErr) {
        // 部分设备不支持导航条避让区域
      }
      this.bottomInset = this.getUIContext().px2vp(bottomPx);
    } catch (err) {
      this.topInset = 0;
      this.bottomInset = 0;
    }
  }

  aboutToDisappear(): void {
    this.engine.dispose();
    this.speech.stopPlayback();
  }

  private initMaterial(): void {
    try {
      this.immersive = uiMaterial.isImmersiveMaterialSupported();
      if (this.immersive) {
        this.material = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true,
          colorInvert: this.dark,
          lightEffect: {
            color: Palette.brand
          }
        });
      }
    } catch (err) {
      this.immersive = false;
    }
  }

  private async bootstrap(context: common.UIAbilityContext): Promise<void> {
    let callbacks: ChatCallbacks = new ChatCallbacks();
    callbacks.onMessages = (messages: ChatMessage[]): void => {
      this.messages = messages;
      if (this.stickToBottom) {
        this.scrollToBottom();
      }
    };
    callbacks.onStreaming = (streaming: boolean): void => {
      this.streaming = streaming;
    };
    callbacks.onTitle = (title: string): void => {
      this.title = title;
    };
    callbacks.onError = (message: string): void => {
      toast(message, this.getUIContext());
    };
    callbacks.onSessionsChanged = (): void => {
      this.reloadSessions();
    };
    this.engine.setCallbacks(callbacks);

    try {
      await ChatRepository.get().init(context);
      await SettingsStore.get().init(context);
      await SecretStore.get().init(context);
      this.settings = SettingsStore.get().get();
      this.apiKey = SecretStore.get().get();
      this.dark = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      this.initMaterial();
      this.engine.setSettings(this.settings);
      this.engine.setApiKey(this.apiKey);
      HapticService.setEnabled(this.settings.haptic);
      this.sessions = await ChatRepository.get().loadSessions();
      if (this.sessions.length > 0) {
        await this.engine.openSession(this.sessions[0]);
      } else {
        await this.engine.createSession();
      }
      this.scrollToBottom();
    } catch (err) {
      toast(`初始化失败：${(err as Error).message}`, this.getUIContext());
    }
  }

  private async reloadSessions(): Promise<void> {
    try {
      this.sessions = await ChatRepository.get().loadSessions();
    } catch (err) {
      // ignore
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (err) {
        // list 尚未布局
      }
    }, 30);
  }

  private async send(text: string, drafts: AttachmentDraft[]): Promise<boolean> {
    if (this.apiKey.length === 0) {
      this.openSheet(1);
      toast('请先在设置中填写 DeepSeek API Key', this.getUIContext());
      return false;
    }
    HapticService.tap();
    let accepted: boolean = false;
    try {
      accepted = await this.engine.send(text, drafts);
    } catch (err) {
      toast(`发送失败：${(err as Error).message}`, this.getUIContext());
      accepted = false;
    }
    if (accepted) {
      this.stickToBottom = true;
      this.scrollToBottom();
    }
    return accepted;
  }

  private async selectSession(id: string): Promise<void> {
    if (this.streaming) {
      toast('请先停止当前生成再切换会话', this.getUIContext());
      return;
    }
    let target: ChatSession | undefined = undefined;
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === id) {
        target = this.sessions[i];
        break;
      }
    }
    if (target === undefined) {
      return;
    }
    try {
      await this.engine.openSession(target);
    } catch (err) {
      toast(`打开会话失败：${(err as Error).message}`, this.getUIContext());
      return;
    }
    this.showSheet = false;
    this.stickToBottom = true;
    this.scrollToBottom();
    HapticService.tap();
  }

  private openSheet(mode: number): void {
    this.sheetMode = mode;
    this.showSheet = true;
  }

  private async newChat(): Promise<void> {
    if (this.streaming) {
      toast('请先停止当前生成再新建会话', this.getUIContext());
      return;
    }
    try {
      await this.engine.createSession();
    } catch (err) {
      toast(`新建会话失败：${(err as Error).message}`, this.getUIContext());
      return;
    }
    this.showSheet = false;
    this.stickToBottom = true;
    HapticService.tap();
  }

  private confirmDelete(id: string): void {
    if (this.streaming) {
      toast('请先停止当前生成再删除会话', this.getUIContext());
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除会话',
      message: '该会话的全部消息将从本机删除。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Palette.danger,
        action: () => {
          this.deleteSession(id);
        }
      }
    });
  }

  private async deleteSession(id: string): Promise<void> {
    try {
      await this.engine.deleteSession(id);
    } catch (err) {
      toast(`删除失败：${(err as Error).message}`, this.getUIContext());
      return;
    }
    await this.reloadSessions();
    if (this.engine.getSession() === undefined) {
      await this.engine.createSession();
    }
  }

  private async saveSettings(next: AppSettings, key: string): Promise<boolean> {
    try {
      if (key.length > 0) {
        await SecretStore.get().save(key);
        this.apiKey = key;
      } else {
        await SecretStore.get().clear();
        this.apiKey = '';
      }
      await SettingsStore.get().save(next);
      this.settings = next;
      this.engine.setSettings(next);
      this.engine.setApiKey(this.apiKey);
      HapticService.setEnabled(next.haptic);
      return true;
    } catch (err) {
      toast(`保存失败：${(err as Error).message}`, this.getUIContext());
      return false;
    }
  }

  private async verifyKey(key: string): Promise<string> {
    if (key.length === 0) {
      return '请先填写 API Key';
    }
    let client: DeepSeekClient = new DeepSeekClient(key);
    try {
      await client.verify();
      return '';
    } catch (err) {
      return (err as Error).message;
    } finally {
      try {
        client.close();
      } catch (err) {
        // ignore
      }
    }
  }

  private async clearAll(): Promise<void> {
    if (this.streaming) {
      throw new Error('请先停止当前生成再清空数据');
    }
    await ChatRepository.get().deleteAll();
    await SecretStore.get().clear();
    let defaults: AppSettings = new AppSettings();
    await SettingsStore.get().save(defaults);
    this.settings = defaults;
    this.apiKey = '';
    this.engine.setApiKey('');
    this.engine.setSettings(defaults);
    await this.engine.createSession();
    await this.reloadSessions();
  }

  private async readAloud(text: string): Promise<void> {
    if (this.reading) {
      await this.speech.stopPlayback();
      this.reading = false;
      return;
    }
    if (this.apiKey.length === 0) {
      toast('请先配置 API Key', this.getUIContext());
      return;
    }
    this.reading = true;
    try {
      let audio = await this.engine.synthesize(text);
      await this.speech.playPcm(audio.data);
    } catch (err) {
      toast(`朗读失败：${(err as Error).message}`, this.getUIContext());
    } finally {
      this.reading = false;
    }
  }

  private openLink(url: string): void {
    openUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, url, this.getUIContext());
  }

  build() {
    Row() {
      if (this.isWide) {
        SessionPanel({
          sessions: this.sessions,
          activeId: this.engine.getSession() !== undefined ? (this.engine.getSession() as ChatSession).id : '',
          isDark: this.dark,
          onSelect: (id: string) => {
            this.selectSession(id);
          },
          onNew: () => {
            this.newChat();
          },
          onDelete: (id: string) => {
            this.confirmDelete(id);
          }
        })
          .width(272)
          .height('100%')
      }

      Navigation() {
        Column() {
          if (this.messages.length === 0) {
            if (this.apiKey.length === 0) {
              this.KeyBanner()
            }
            WelcomePanel({
              isDark: this.dark,
              onPick: (text: string) => {
                this.send(text, []);
              }
            })
              .layoutWeight(1)
          } else {
            List({ space: 0, scroller: this.scroller }) {
              ForEach(this.messages, (message: ChatMessage) => {
                ListItem() {
                  MessageItem({
                    message: message,
                    isDark: this.dark,
                    textSize: this.settings.textSize,
                    expandThinking: this.settings.expandThinking,
                    onRetry: () => {
                      this.engine.regenerate();
                    },
                    onRead: (text: string) => {
                      this.readAloud(text);
                    },
                    onLink: (url: string) => {
                      this.openLink(url);
                    }
                  })
                }
                .width('100%')
              }, (message: ChatMessage) => message.id)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onScrollIndex((first: number, last: number) => {
              this.stickToBottom = last >= this.messages.length - 1;
            })
          }

          Column() {
            Composer({
              isDark: this.dark,
              textSize: this.settings.textSize,
              streaming: this.streaming,
              onSend: (text: string, drafts: AttachmentDraft[]) => this.send(text, drafts),
              onStop: () => {
                HapticService.tap();
                this.engine.stop();
              },
              onTranscribe: (wavPath: string) => this.engine.transcribe(wavPath)
            })
          }
          .padding({ left: 12, right: 12, bottom: 8 })
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(bgColor(this.dark))
      }
      .layoutWeight(1)
      .height('100%')
      .title(this.TitleBar)
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .backgroundColor(bgColor(this.dark))
      .bindSheet($$this.showSheet, this.SheetBuilder, {
        height: this.sheetMode === 1 ? SheetSize.LARGE : SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: cardColor(this.dark),
        onDisappear: () => {
          this.showSheet = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset, bottom: this.bottomInset })
    .backgroundColor(bgColor(this.dark))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      let width: number = Number(newArea.width.toString());
      this.isWide = width >= 840;
    })
  }

  @Builder
  TitleBar() {
    Row({ space: 2 }) {
      if (!this.isWide) {
        this.NavButton($r('app.media.ic_menu'), () => {
          this.openSheet(0);
        })
      }
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(textColor(this.dark))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 4 })
      if (this.streaming) {
        LoadingProgress()
          .width(15)
          .height(15)
          .color(Palette.brand)
          .margin({ right: 2 })
      }
      this.NavButton($r('app.media.ic_add'), () => {
        this.newChat();
      })
      this.NavButton($r('app.media.ic_settings'), () => {
        this.openSheet(1);
      })
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  NavButton(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Image(icon)
        .width(17)
        .height(17)
        .fillColor(textColor(this.dark))
    }
    .width(34)
    .height(34)
    .backgroundColor(this.immersive ? Color.Transparent : softColor(this.dark))
    .systemMaterial(this.immersive ? this.material : undefined)
    .onClick(action)
  }

  @Builder
  KeyBanner() {
    Row({ space: 10 }) {
      Text('未配置 DeepSeek API Key，暂时无法发送消息。')
        .fontSize(12)
        .fontColor(subTextColor(this.dark))
        .layoutWeight(1)
      Text('去设置')
        .fontSize(12)
        .fontColor(Palette.brand)
        .onClick(() => {
          this.openSheet(1);
        })
    }
    .width('100%')
    .padding(12)
    .margin({ top: 8 })
    .backgroundColor(softColor(this.dark))
    .borderRadius(12)
  }

  @Builder
  SheetBuilder() {
    if (this.sheetMode === 1) {
      this.SettingsSheetBuilder()
    } else {
      this.SessionSheetBuilder()
    }
  }

  @Builder
  SessionSheetBuilder() {
    SessionPanel({
      sessions: this.sessions,
      activeId: this.engine.getSession() !== undefined ? (this.engine.getSession() as ChatSession).id : '',
      isDark: this.dark,
      onSelect: (id: string) => {
        this.selectSession(id);
      },
      onNew: () => {
        this.newChat();
      },
      onDelete: (id: string) => {
        this.confirmDelete(id);
      }
    })
      .height('100%')
  }

  @Builder
  SettingsSheetBuilder() {
    SettingsSheet({
      settings: this.settings,
      apiKey: this.apiKey,
      isDark: this.dark,
      onSave: (settings: AppSettings, key: string) => this.saveSettings(settings, key),
      onVerify: (key: string) => this.verifyKey(key),
      onClear: () => this.clearAll(),
      onClose: () => {
        this.showSheet = false;
      }
    })
      .height('100%')
  }
}
