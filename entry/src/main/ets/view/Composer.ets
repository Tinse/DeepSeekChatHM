import { common } from '@kit.AbilityKit';
import { AttachmentDraft } from '../model/Types';
import { AttachmentService } from '../service/AttachmentService';
import { SpeechService } from '../service/SpeechService';
import { borderColor, cardColor, Palette, softColor, subTextColor, textColor } from './common/Theme';
import { imageUri, toast } from '../utils/TextUtils';

@Component
export struct Composer {
  @Prop isDark: boolean = false;
  @Prop textSize: number = 16;
  @Prop streaming: boolean = false;
  onSend: (text: string, drafts: AttachmentDraft[]) => Promise<boolean> =
    async (text: string, drafts: AttachmentDraft[]) => false;
  onStop: () => void = () => {
  };
  onTranscribe: (wavPath: string) => Promise<string> = async (wavPath: string) => '';

  @State input: string = '';
  @State drafts: AttachmentDraft[] = [];
  @State recording: boolean = false;
  @State recordSeconds: number = 0;
  @State transcribing: boolean = false;
  @State sending: boolean = false;

  private speech: SpeechService = new SpeechService();
  private timer: number = -1;

  build() {
    Column({ space: 8 }) {
      if (this.drafts.length > 0) {
        this.DraftStrip()
      }
      if (this.recording) {
        Row({ space: 8 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(Palette.danger)
          Text(`正在录音 ${this.clockText()}，再次点击麦克风结束`)
            .fontSize(12)
            .fontColor(subTextColor(this.isDark))
        }
        .width('100%')
        .padding({ left: 8 })
      }
      Row({ space: 6 }) {
        this.AttachButton()
        TextArea({ text: this.input, placeholder: '给 DeepSeek 发送消息' })
          .layoutWeight(1)
          .fontSize(this.textSize)
          .fontColor(textColor(this.isDark))
          .placeholderColor(subTextColor(this.isDark))
          .backgroundColor(Color.Transparent)
          .borderWidth(0)
          .padding({ left: 4, right: 4, top: 10, bottom: 10 })
          .maxLength(8000)
          .constraintSize({ minHeight: 44, maxHeight: 132 })
          .onChange((value: string) => {
            this.input = value;
          })
        this.MicButton()
        this.SendButton()
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
    }
    .padding({ left: 10, right: 8, top: 8, bottom: 8 })
    .backgroundColor(cardColor(this.isDark))
    .borderRadius(20)
    .border({ width: 1, color: borderColor(this.isDark) })
    .width('100%')
  }

  @Builder
  DraftStrip() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.drafts, (draft: AttachmentDraft, index: number) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            if (draft.kind === 'image') {
              Image(imageUri(draft.localPath))
                .width(58)
                .height(58)
                .borderRadius(10)
                .objectFit(ImageFit.Cover)
            } else {
              Row({ space: 4 }) {
                Text('TXT')
                  .fontSize(9)
                  .fontColor(Palette.brand)
                Text(draft.name)
                  .fontSize(11)
                  .fontColor(subTextColor(this.isDark))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width(92)
              .height(58)
              .padding(6)
              .backgroundColor(softColor(this.isDark))
              .borderRadius(10)
            }
            Text('×')
              .width(18)
              .height(18)
              .textAlign(TextAlign.Center)
              .fontSize(11)
              .fontColor('#FFFFFF')
              .backgroundColor('#99000000')
              .borderRadius(9)
              .margin({ top: 2, right: 2 })
              .onClick(() => {
                this.removeDraft(index);
              })
          }
        }, (draft: AttachmentDraft, index: number) => `${index}_${draft.localPath}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  AttachButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Image($r('app.media.ic_add'))
        .width(17)
        .height(17)
        .fillColor(subTextColor(this.isDark))
    }
    .width(34)
    .height(34)
    .backgroundColor(Color.Transparent)
    .bindMenu([
      {
        value: '从相册选择图片',
        action: () => {
          this.addImages();
        }
      },
      {
        value: '选择文本文件',
        action: () => {
          this.addDocuments();
        }
      }
    ])
  }

  @Builder
  MicButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      if (this.transcribing) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(Palette.brand)
      } else {
        Image($r('app.media.ic_mic'))
          .width(17)
          .height(17)
          .fillColor(this.recording ? '#FFFFFF' : subTextColor(this.isDark))
      }
    }
    .width(34)
    .height(34)
    .backgroundColor(this.recording ? Palette.danger : Color.Transparent)
    .onClick(() => {
      this.toggleRecord();
    })
  }

  @Builder
  SendButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      if (this.sending && !this.streaming) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color('#FFFFFF')
      } else {
        Image(this.streaming ? $r('app.media.ic_stop') : $r('app.media.ic_send'))
          .width(16)
          .height(16)
          .fillColor('#FFFFFF')
      }
    }
    .width(36)
    .height(36)
    .backgroundColor(this.streaming ? Palette.danger : Palette.brand)
    .enabled(this.streaming || (!this.sending && !this.recording && !this.transcribing &&
      (this.input.trim().length > 0 || this.drafts.length > 0)))
    .opacity(this.streaming || this.sending || this.input.trim().length > 0 || this.drafts.length > 0 ? 1 : 0.45)
    .onClick(() => {
      if (this.streaming) {
        this.onStop();
      } else {
        this.submit();
      }
    })
  }

  private async submit(): Promise<void> {
    if (this.sending || this.streaming) {
      return;
    }
    if (this.input.trim().length === 0 && this.drafts.length === 0) {
      return;
    }
    this.sending = true;
    try {
      let accepted: boolean = await this.onSend(this.input, this.drafts);
      if (accepted) {
        this.input = '';
        this.drafts = [];
      }
    } catch (err) {
      toast((err as Error).message, this.getUIContext());
    } finally {
      this.sending = false;
    }
  }

  private async addImages(): Promise<void> {
    let imageCount: number = 0;
    for (let i = 0; i < this.drafts.length; i++) {
      if (this.drafts[i].kind === 'image') {
        imageCount += 1;
      }
    }
    if (imageCount >= 4) {
      toast('最多添加 4 张图片', this.getUIContext());
      return;
    }
    try {
      let context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      let picked: AttachmentDraft[] = await AttachmentService.pickImages(context);
      let room: number = 4 - imageCount;
      if (picked.length > room) {
        picked = picked.slice(0, room);
        toast(`最多添加 4 张图片，已保留前 ${room} 张`, this.getUIContext());
      }
      this.drafts = this.drafts.concat(picked);
    } catch (err) {
      toast((err as Error).message, this.getUIContext());
    }
  }

  private async addDocuments(): Promise<void> {
    let textCount: number = 0;
    for (let i = 0; i < this.drafts.length; i++) {
      if (this.drafts[i].kind === 'text') {
        textCount += 1;
      }
    }
    if (textCount >= 2) {
      toast('最多添加 2 个文本文件', this.getUIContext());
      return;
    }
    try {
      let context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      let picked: AttachmentDraft[] = await AttachmentService.pickDocuments(context);
      let room: number = 2 - textCount;
      if (picked.length > room) {
        picked = picked.slice(0, room);
        toast(`最多添加 2 个文本文件，已保留前 ${room} 个`, this.getUIContext());
      }
      this.drafts = this.drafts.concat(picked);
    } catch (err) {
      toast((err as Error).message, this.getUIContext());
    }
  }

  private removeDraft(index: number): void {
    let copy: AttachmentDraft[] = this.drafts.slice();
    copy.splice(index, 1);
    this.drafts = copy;
  }

  private async toggleRecord(): Promise<void> {
    if (this.transcribing) {
      return;
    }
    if (this.recording) {
      await this.finishRecord();
      return;
    }
    try {
      let context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      let granted: boolean = await SpeechService.ensurePermission(context);
      if (!granted) {
        toast('需要麦克风权限才能语音输入', this.getUIContext());
        return;
      }
      await this.speech.startRecording();
      this.recording = true;
      this.recordSeconds = 0;
      this.timer = setInterval(() => {
        this.recordSeconds += 1;
        if (this.recordSeconds >= 120) {
          this.finishRecord();
        }
      }, 1000);
    } catch (err) {
      this.recording = false;
      toast(`无法开始录音：${(err as Error).message}`, this.getUIContext());
    }
  }

  private async finishRecord(): Promise<void> {
    if (!this.recording) {
      return;
    }
    this.recording = false;
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    try {
      let context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      let wavPath: string = await this.speech.stopRecording(context);
      this.transcribing = true;
      let text: string = await this.onTranscribe(wavPath);
      if (text.length > 0) {
        this.input = this.input.trim().length > 0 ? `${this.input} ${text}` : text;
      }
    } catch (err) {
      toast((err as Error).message, this.getUIContext());
    } finally {
      this.transcribing = false;
    }
  }

  private clockText(): string {
    let minutes: number = Math.floor(this.recordSeconds / 60);
    let seconds: number = this.recordSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }
}
