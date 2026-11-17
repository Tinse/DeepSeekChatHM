import { Palette, subTextColor, textColor } from './common/Theme';

class SuggestionItem {
  title: string;
  prompt: string;

  constructor(title: string, prompt: string) {
    this.title = title;
    this.prompt = prompt;
  }
}

@Component
export struct WelcomePanel {
  @Prop isDark: boolean = false;
  onPick: (text: string) => void = () => {
  };

  private suggestions: SuggestionItem[] = [
    new SuggestionItem('解释概念', '用通俗的语言解释什么是鸿蒙的分布式软总线'),
    new SuggestionItem('写代码', '用 ArkTS 写一个带防抖的搜索输入框，并说明原理'),
    new SuggestionItem('读长文', '帮我总结这篇文章的核心观点，并列出三个关键论据'),
    new SuggestionItem('做对比', '对比鸿蒙 RCP 与系统 HTTP 请求的差异和适用场景')
  ];

  build() {
    Column({ space: 26 }) {
      Column({ space: 12 }) {
        Text('D')
          .width(58)
          .height(58)
          .textAlign(TextAlign.Center)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(Palette.brand)
          .borderRadius(18)
        Text('DeepSeek')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(textColor(this.isDark))
        Text('深度求索 · 原生鸿蒙版')
          .fontSize(13)
          .fontColor(subTextColor(this.isDark))
      }
      .margin({ top: 48 })

      Column({ space: 10 }) {
        ForEach(this.suggestions, (item: SuggestionItem) => {
          Row({ space: 10 }) {
            Text(item.title)
              .fontSize(12)
              .fontColor(Palette.brand)
              .width(56)
            Text(item.prompt)
              .fontSize(14)
              .fontColor(textColor(this.isDark))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('↗')
              .fontSize(13)
              .fontColor(subTextColor(this.isDark))
          }
          .alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 14, top: 13, bottom: 13 })
          .width('100%')
          .backgroundColor(this.isDark ? '#171A21' : '#FFFFFF')
          .borderRadius(14)
          .onClick(() => {
            this.onPick(item.prompt);
          })
        }, (item: SuggestionItem) => item.prompt)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .alignItems(HorizontalAlign.Start)
  }
}
