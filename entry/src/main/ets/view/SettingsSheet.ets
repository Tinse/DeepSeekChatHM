import { AppSettings } from '../model/Types';
import { borderColor, cardColor, Palette, softColor, subTextColor, textColor } from './common/Theme';

@Component
export struct SettingsSheet {
  @Prop @Watch('syncFromProps') settings: AppSettings = new AppSettings();
  @Prop @Watch('syncFromProps') apiKey: string = '';
  @Prop isDark: boolean = false;
  onSave: (settings: AppSettings, apiKey: string) => Promise<boolean> =
    async (settings: AppSettings, apiKey: string) => false;
  onVerify: (apiKey: string) => Promise<string> = async (apiKey: string) => '';
  onClear: () => Promise<void> = async () => {
  };
  onClose: () => void = () => {
  };

  @State private keyInput: string = '';
  @State private model: string = 'deepseek-flash';
  @State private thinking: boolean = true;
  @State private search: boolean = true;
  @State private voice: string = 'stella';
  @State private haptic: boolean = true;
  @State private textSize: number = 16;
  @State private expandThinking: boolean = false;
  @State private verifying: boolean = false;
  @State private verifyMessage: string = '';
  @State private verifyOk: boolean = false;

  aboutToAppear(): void {
    this.syncFromProps();
  }

  private syncFromProps(): void {
    this.keyInput = this.apiKey;
    this.model = this.settings.model;
    this.thinking = this.settings.thinking;
    this.search = this.settings.search;
    this.voice = this.settings.voice;
    this.haptic = this.settings.haptic;
    this.textSize = this.settings.textSize;
    this.expandThinking = this.settings.expandThinking;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(textColor(this.isDark))
        Blank()
        Text('关闭')
          .fontSize(14)
          .fontColor(subTextColor(this.isDark))
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 12 })

      Scroll() {
        Column({ space: 22 }) {
          this.SectionTitle('接口')
          Column({ space: 8 }) {
            TextInput({ text: this.keyInput, placeholder: 'sk-...' })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .fontSize(14)
              .fontColor(textColor(this.isDark))
              .placeholderColor(subTextColor(this.isDark))
              .backgroundColor(softColor(this.isDark))
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .height(46)
              .onChange((value: string) => {
                this.keyInput = value;
                this.verifyMessage = '';
              })
            Row({ space: 10 }) {
              Text('验证')
                .fontSize(12)
                .fontColor(Palette.brand)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(softColor(this.isDark))
                .borderRadius(10)
                .onClick(() => {
                  this.verify();
                })
              if (this.verifying) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(Palette.brand)
              }
              if (this.verifyMessage.length > 0) {
                Text(this.verifyMessage)
                  .fontSize(12)
                  .fontColor(this.verifyOk ? '#2E9E5B' : Palette.danger)
                  .layoutWeight(1)
              }
            }
            .width('100%')
            Text('密钥使用 Asset Store 加密保存在本机，仅用于直连 DeepSeek。')
              .fontSize(11)
              .fontColor(subTextColor(this.isDark))
          }
          .alignItems(HorizontalAlign.Start)

          this.SectionTitle('模型')
          Row({ space: 10 }) {
            this.ModelCard('deepseek-flash', 'DeepSeek Flash', '日常对话，响应更快')
            this.ModelCard('deepseek-v4-pro', 'DeepSeek V4 Pro', '深度思考，能力更强')
          }
          .width('100%')

          this.SectionTitle('对话')
          Column({ space: 2 }) {
            this.ToggleRow('深度思考', '先推理再作答，支持折叠查看', this.thinking, (value: boolean) => {
              this.thinking = value;
            })
            this.ToggleRow('联网搜索', '需要时检索网页并附带引用', this.search, (value: boolean) => {
              this.search = value;
            })
            this.ToggleRow('默认展开思考', '新消息的思考过程自动展开', this.expandThinking, (value: boolean) => {
              this.expandThinking = value;
            })
          }
          .backgroundColor(softColor(this.isDark))
          .borderRadius(14)
          .padding({ left: 12, right: 12, top: 2, bottom: 2 })

          this.SectionTitle('外观')
          Column({ space: 10 }) {
            Row() {
              Text('正文字号')
                .fontSize(14)
                .fontColor(textColor(this.isDark))
              Blank()
              Text(`${this.textSize}`)
                .fontSize(13)
                .fontColor(subTextColor(this.isDark))
            }
            Slider({ value: this.textSize, min: 14, max: 20, step: 1, style: SliderStyle.InSet })
              .selectedColor(Palette.brand)
              .onChange((value: number) => {
                this.textSize = Math.round(value);
              })
          }
          .padding(12)
          .backgroundColor(softColor(this.isDark))
          .borderRadius(14)

          this.SectionTitle('语音')
          Row({ space: 10 }) {
            this.VoiceCard('stella', 'Stella', '女声')
            this.VoiceCard('tide', 'Tide', '男声')
          }
          .width('100%')

          this.SectionTitle('触感')
          Column() {
            this.ToggleRow('轻触反馈', '发送、切换会话时轻微震动', this.haptic, (value: boolean) => {
              this.haptic = value;
            })
          }
          .backgroundColor(softColor(this.isDark))
          .borderRadius(14)
          .padding({ left: 12, right: 12, top: 2, bottom: 2 })

          this.SectionTitle('数据')
          Column({ space: 10 }) {
            Row() {
              Column({ space: 2 }) {
                Text('清空本地数据')
                  .fontSize(14)
                  .fontColor(textColor(this.isDark))
                Text('删除全部会话、消息与密钥')
                  .fontSize(11)
                  .fontColor(subTextColor(this.isDark))
              }
              .alignItems(HorizontalAlign.Start)
              Blank()
              Text('清空')
                .fontSize(13)
                .fontColor(Palette.danger)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(softColor(this.isDark))
                .borderRadius(10)
                .onClick(() => {
                  this.confirmClear();
                })
            }
            .width('100%')
          }
          .padding(12)
          .backgroundColor(softColor(this.isDark))
          .borderRadius(14)

          Text('DeepSeek for HarmonyOS · API 26 · ArkTS 原生')
            .fontSize(11)
            .fontColor(subTextColor(this.isDark))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .padding({ left: 20, right: 20, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(softColor(this.isDark))
          .fontColor(textColor(this.isDark))
          .fontSize(15)
          .onClick(() => {
            this.onClose();
          })
        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Palette.brand)
          .fontColor('#FFFFFF')
          .fontSize(15)
          .onClick(() => {
            this.save();
          })
      }
      .padding({ left: 20, right: 20, top: 10, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(cardColor(this.isDark))
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(subTextColor(this.isDark))
      .width('100%')
  }

  @Builder
  ToggleRow(title: string, desc: string, value: boolean, onChange: (value: boolean) => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor(textColor(this.isDark))
        Text(desc)
          .fontSize(11)
          .fontColor(subTextColor(this.isDark))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(Palette.brand)
        .onChange((isOn: boolean) => {
          onChange(isOn);
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  ModelCard(id: string, title: string, desc: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(this.model === id ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.model === id ? Palette.brand : textColor(this.isDark))
      Text(desc)
        .fontSize(11)
        .fontColor(subTextColor(this.isDark))
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .layoutWeight(1)
    .backgroundColor(this.model === id ? (this.isDark ? '#1D2333' : '#EEF1FF') : softColor(this.isDark))
    .borderRadius(14)
    .border({ width: 1, color: this.model === id ? Palette.brand : borderColor(this.isDark) })
    .onClick(() => {
      this.model = id;
    })
  }

  @Builder
  VoiceCard(id: string, title: string, desc: string) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(14)
        .fontColor(this.voice === id ? Palette.brand : textColor(this.isDark))
      Text(desc)
        .fontSize(11)
        .fontColor(subTextColor(this.isDark))
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(this.voice === id ? (this.isDark ? '#1D2333' : '#EEF1FF') : softColor(this.isDark))
    .borderRadius(14)
    .border({ width: 1, color: this.voice === id ? Palette.brand : borderColor(this.isDark) })
    .onClick(() => {
      this.voice = id;
    })
  }

  private async verify(): Promise<void> {
    if (this.keyInput.trim().length === 0) {
      this.verifyOk = false;
      this.verifyMessage = '请先填写 API Key';
      return;
    }
    this.verifying = true;
    this.verifyMessage = '';
    try {
      let error: string = await this.onVerify(this.keyInput.trim());
      if (error.length === 0) {
        this.verifyOk = true;
        this.verifyMessage = 'Key 有效，模型列表已通过';
      } else {
        this.verifyOk = false;
        this.verifyMessage = error;
      }
    } catch (err) {
      this.verifyOk = false;
      this.verifyMessage = (err as Error).message;
    } finally {
      this.verifying = false;
    }
  }

  private async save(): Promise<void> {
    let next: AppSettings = new AppSettings();
    next.model = this.model;
    next.thinking = this.thinking;
    next.search = this.search;
    next.voice = this.voice;
    next.haptic = this.haptic;
    next.textSize = this.textSize;
    next.expandThinking = this.expandThinking;
    let ok: boolean = await this.onSave(next, this.keyInput.trim());
    if (ok) {
      this.onClose();
    }
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清空本地数据',
      message: '将删除全部会话、消息和本机保存的 API Key，且无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: Palette.danger,
        action: () => {
          this.clearAll();
        }
      }
    });
  }

  private async clearAll(): Promise<void> {
    try {
      await this.onClear();
      this.keyInput = '';
      this.verifyMessage = '';
      this.onClose();
    } catch (err) {
      this.verifyMessage = (err as Error).message;
      this.verifyOk = false;
    }
  }
}
