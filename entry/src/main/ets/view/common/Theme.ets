import { MarkdownController } from '@luvi/lv-markdown-in';

export class Palette {
  static readonly brand: string = '#4D6BFE';
  static readonly brandPressed: string = '#3E56D6';
  static readonly bgLight: string = '#F7F8FA';
  static readonly bgDark: string = '#0F1115';
  static readonly cardLight: string = '#FFFFFF';
  static readonly cardDark: string = '#171A21';
  static readonly textLight: string = '#1A1D24';
  static readonly textDark: string = '#ECEFF4';
  static readonly subLight: string = '#6B7280';
  static readonly subDark: string = '#9AA3B2';
  static readonly borderLight: string = '#E6E8EF';
  static readonly borderDark: string = '#262B36';
  static readonly softLight: string = '#EFF1F7';
  static readonly softDark: string = '#1B1F28';
  static readonly danger: string = '#E5484D';
}

export function bgColor(dark: boolean): string {
  return dark ? Palette.bgDark : Palette.bgLight;
}

export function cardColor(dark: boolean): string {
  return dark ? Palette.cardDark : Palette.cardLight;
}

export function textColor(dark: boolean): string {
  return dark ? Palette.textDark : Palette.textLight;
}

export function subTextColor(dark: boolean): string {
  return dark ? Palette.subDark : Palette.subLight;
}

export function borderColor(dark: boolean): string {
  return dark ? Palette.borderDark : Palette.borderLight;
}

export function softColor(dark: boolean): string {
  return dark ? Palette.softDark : Palette.softLight;
}

/** 统一 Markdown 排版，保证流式追加时样式稳定。 */
export function applyMarkdownTheme(controller: MarkdownController, dark: boolean, textSize: number): void {
  let titleSizes: [number, number, number, number, number, number] =
    [textSize + 10, textSize + 6, textSize + 3, textSize + 1, textSize, textSize];
  let titleHeights: [number, number, number, number, number, number] =
    [textSize + 18, textSize + 14, textSize + 11, textSize + 9, textSize + 8, textSize + 8];
  controller
    .setTitleColor(textColor(dark))
    .setTitleSize(titleSizes)
    .setTitleLineHeight(titleHeights)
    .setTitleFontWeight(FontWeight.Bold)
    .setTextColor(textColor(dark))
    .setTextSize(textSize)
    .setTextLineHeight(textSize + 8)
    .setInlineCodeColor(dark ? '#9ECBFF' : '#0550AE')
    .setInlineCodeBackgroundColor(softColor(dark))
    .setInlineCodeBackgroundRadius(5)
    .setQuoteTextColor(subTextColor(dark))
    .setQuoteBorderColor(Palette.brand)
    .setQuoteBackgroundColor(softColor(dark))
    .setQuoteBorderRadius(8)
    .setQuoteBorderWidth(3)
    .setCodeBlockTheme(dark ? 'dark' : 'light')
    .setCodeBlockBorderRadius(12)
    .setCodeBlockAutoCollapseEnable(true)
    .setCodeBlockAutoCollapseThreshold(18)
    .setHyperlinkTextColor(Palette.brand)
    .setHyperlinkUnderlineState(false)
    .setTableBackgroundColor(cardColor(dark))
    .setTableTitleBackgroundColor(softColor(dark))
    .setTableTitleTextColor(textColor(dark));
  controller.setTableNormalTextColor(textColor(dark));
  controller.setTableInterleaveTextColor(textColor(dark));
  // Mermaid / HTML 预览依赖 ArkWeb 内联 Web 组件；API 26 x86_64 模拟器上初始化会阻塞主线程并触发 appfreeze，
  // 默认关闭，Mermaid 源码以代码块展示。LaTeX 走原生 formula 库，不受影响。
  controller
    .setTableInterleaveBackgroundColor(dark ? '#141821' : '#F9FAFD')
    .setTableBorderRadius(12)
    .setTableOuterBorderColor(borderColor(dark))
    .setTableInnerBorderColor(borderColor(dark))
    .setLineColor(borderColor(dark))
    .setMermaidEnable(false)
    .setHtmlPreviewEnable(false)
    .setMermaidTheme(dark ? 'dark' : 'light')
    .setLatexMathTextColor(dark ? 0xFFECEFF4 : 0xFF1A1D24)
    .setBlockSpacing(12);
  controller.setCopyOption(CopyOptions.LocalDevice);
}
