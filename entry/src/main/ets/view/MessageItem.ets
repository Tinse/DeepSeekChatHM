import { Attachment, ChatMessage, Citation } from '../model/Types';
import { cardColor, Palette, softColor, subTextColor, textColor } from './common/Theme';
import { MarkdownContent } from './MarkdownContent';
import { copyText, imageUri } from '../utils/TextUtils';

@Component
export struct MessageItem {
  @ObjectLink message: ChatMessage;
  @Prop isDark: boolean = false;
  @Prop textSize: number = 16;
  @Prop expandThinking: boolean = false;
  onRetry: () => void = () => {
  };
  onRead: (text: string) => void = () => {
  };
  onLink: (url: string) => void = () => {
  };

  @State thinkingOpen: boolean = false;

  aboutToAppear(): void {
    this.thinkingOpen = this.expandThinking && this.message.thinking.length > 0;
  }

  build() {
    Column({ space: 10 }) {
      if (this.message.role === 'user') {
        this.UserContent()
      } else {
        this.AssistantContent()
      }
    }
    .width('100%')
    .alignItems(this.message.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  UserContent() {
    Column({ space: 8 }) {
      if (this.message.attachments.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.message.attachments, (att: Attachment, index: number) => {
              if (att.kind === 'image') {
                Image(imageUri(att.localPath))
                  .width(72)
                  .height(72)
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
              } else {
                Row({ space: 6 }) {
                  Text('TXT')
                    .fontSize(10)
                    .fontColor(Palette.brand)
                    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                    .backgroundColor(softColor(this.isDark))
                    .borderRadius(4)
                  Text(att.name)
                    .fontSize(12)
                    .fontColor(subTextColor(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 160 })
                }
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .backgroundColor(cardColor(this.isDark))
                .borderRadius(12)
                .border({ width: 1, color: softColor(this.isDark) })
              }
            }, (att: Attachment, index: number) => `${index}_${att.localPath}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      if (this.message.content.length > 0) {
        Text(this.message.content)
          .fontSize(this.textSize)
          .lineHeight(this.textSize + 7)
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 11, bottom: 11 })
          .backgroundColor(Palette.brand)
          .borderRadius(18)
          .constraintSize({ maxWidth: '82%' })
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  AssistantContent() {
    Column({ space: 10 }) {
      if (this.message.thinking.length > 0) {
        this.ThinkingPanel()
      }
      if (this.message.toolLabel.length > 0 && this.message.content.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(Palette.brand)
          Text(this.message.toolLabel)
            .fontSize(12)
            .fontColor(subTextColor(this.isDark))
        }
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .backgroundColor(softColor(this.isDark))
        .borderRadius(12)
      }
      if (this.message.content.length > 0) {
        MarkdownContent({
          text: this.message.content,
          isDark: this.isDark,
          textSize: this.textSize,
          onLink: (url: string) => {
            this.onLink(url);
          }
        })
      }
      if (this.message.citations.length > 0) {
        this.CitationList()
      }
      if (this.message.status === 'error') {
        Column({ space: 8 }) {
          Text('生成失败')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.danger)
          Text(this.message.error.length > 0 ? this.message.error : '网络异常，请稍后重试。')
            .fontSize(12)
            .fontColor(subTextColor(this.isDark))
          Text('重试')
            .fontSize(12)
            .fontColor(Palette.brand)
            .onClick(() => {
              this.onRetry();
            })
        }
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .width('100%')
        .backgroundColor(softColor(this.isDark))
        .borderRadius(12)
      }
      if (this.message.status === 'done' || this.message.status === 'stopped') {
        Row({ space: 18 }) {
          Text('复制')
            .fontSize(12)
            .fontColor(subTextColor(this.isDark))
            .onClick(() => {
              copyText(this.message.content, '已复制', this.getUIContext());
            })
          Text('重新生成')
            .fontSize(12)
            .fontColor(subTextColor(this.isDark))
            .onClick(() => {
              this.onRetry();
            })
          if (this.message.content.length > 0) {
            Text('朗读')
              .fontSize(12)
              .fontColor(subTextColor(this.isDark))
              .onClick(() => {
                this.onRead(this.message.content);
              })
          }
          if (this.message.status === 'stopped') {
            Text('已停止')
              .fontSize(12)
              .fontColor(subTextColor(this.isDark))
          }
        }
        .padding({ top: 2, bottom: 2 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  ThinkingPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('深度思考')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(subTextColor(this.isDark))
        if (this.message.status === 'streaming' && this.message.content.length === 0) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(Palette.brand)
        }
        Blank()
        Text(this.thinkingOpen ? '收起' : '展开')
          .fontSize(12)
          .fontColor(Palette.brand)
      }
      .width('100%')
      .onClick(() => {
        this.thinkingOpen = !this.thinkingOpen;
      })

      if (this.thinkingOpen) {
        Scroll() {
          Text(this.message.thinking)
            .fontSize(13)
            .lineHeight(20)
            .fontColor(subTextColor(this.isDark))
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: 240 })
        .width('100%')
      }
    }
    .padding(12)
    .width('100%')
    .backgroundColor(softColor(this.isDark))
    .borderRadius(14)
  }

  @Builder
  CitationList() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.message.citations, (item: Citation, index: number) => {
          Row({ space: 5 }) {
            Text('↗')
              .fontSize(11)
              .fontColor(Palette.brand)
            Text(item.title.length > 0 ? item.title : item.url)
              .fontSize(11)
              .fontColor(subTextColor(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 180 })
          }
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(softColor(this.isDark))
          .borderRadius(10)
          .onClick(() => {
            this.onLink(item.url);
          })
        }, (item: Citation, index: number) => `${index}_${item.url}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}
