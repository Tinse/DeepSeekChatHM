import { pasteboard } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

export function toast(message: string, ui: UIContext): void {
  try {
    ui.getPromptAction().showToast({
      message: message,
      duration: 2000
    });
  } catch (err) {
    // ignore
  }
}

export function copyText(text: string, hint: string, ui: UIContext): void {
  if (text.length === 0) {
    return;
  }
  try {
    let data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      toast(hint, ui);
    }).catch((err: Error) => {
      toast('复制失败', ui);
    });
  } catch (err) {
    toast('复制失败', ui);
  }
}

export function openUrl(context: common.UIAbilityContext, url: string, ui: UIContext): void {
  if (url.length === 0) {
    return;
  }
  try {
    context.openLink(url).catch((err: Error) => {
      toast('无法打开链接', ui);
    });
  } catch (err) {
    toast('无法打开链接', ui);
  }
}

export function imageUri(path: string): string {
  if (path.length === 0 || path.startsWith('file://') || path.startsWith('data:') ||
    path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  return `file://${path}`;
}

export function formatClock(timestamp: number): string {
  let date: Date = new Date(timestamp);
  let now: Date = new Date();
  let sameDay: boolean = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
  if (sameDay) {
    return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }
  if (date.getFullYear() === now.getFullYear()) {
    return `${date.getMonth() + 1}/${date.getDate()}`;
  }
  return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
