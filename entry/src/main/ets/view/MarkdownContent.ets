import { Markdown, MarkdownController } from '@luvi/lv-markdown-in';
import { applyMarkdownTheme } from './common/Theme';
import { copyText } from '../utils/TextUtils';

@Component
export struct MarkdownContent {
  @Prop text: string = '';
  @Prop @Watch('onThemeChanged') isDark: boolean = false;
  @Prop @Watch('onThemeChanged') textSize: number = 16;
  onLink: (url: string) => void = () => {
  };

  private controller: MarkdownController = new MarkdownController();

  aboutToAppear(): void {
    this.controller.setCodeCopyListener((code: string) => {
      copyText(code, '代码已复制', this.getUIContext());
    });
    this.controller.setTextSelectionCopyListener((selected: string) => {
      copyText(selected, '已复制选中文本', this.getUIContext());
    });
    this.controller.setHyperlinkClickListener((title: string, src: string) => {
      this.onLink(src);
      return true;
    });
    this.controller.setTextSelectionEnable(true);
    this.applyStyle();
  }

  onThemeChanged(): void {
    this.applyStyle();
  }

  private applyStyle(): void {
    applyMarkdownTheme(this.controller, this.isDark, this.textSize);
  }

  build() {
    Markdown({
      controller: this.controller,
      text: this.text,
      mode: 'text',
      rawfilePath: '',
      sandboxPath: '',
      plugins: [],
      callback: {},
      context: this.getUIContext().getHostContext()
    })
      .width('100%')
  }
}
