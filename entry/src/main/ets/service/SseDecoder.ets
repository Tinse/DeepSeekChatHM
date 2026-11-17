import { util } from '@kit.ArkTS';

export class SseFrame {
  event: string = '';
  data: string = '';
}

/**
 * 增量 UTF-8 解码 + SSE 帧解析。
 * 参考华为开发者问答《ArkTS 使用 RCP 接收 SSE 流式数据时，如何处理消息拆包问题》。
 */
export class SseDecoder {
  private buffer: string = '';
  private eventName: string = '';
  private dataLines: string[] = [];
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  feed(chunk: ArrayBuffer): SseFrame[] {
    let text: string = this.decoder.decodeWithStream(new Uint8Array(chunk), { stream: true });
    this.buffer += text;
    return this.drain();
  }

  flush(): SseFrame[] {
    let text: string = this.decoder.decodeWithStream(new Uint8Array(0), { stream: false });
    this.buffer += text;
    let frames: SseFrame[] = [];
    while (this.buffer.length > 0) {
      let idx: number = this.buffer.indexOf('\n');
      let line: string = '';
      if (idx < 0) {
        line = this.buffer;
        this.buffer = '';
      } else {
        line = this.buffer.substring(0, idx);
        this.buffer = this.buffer.substring(idx + 1);
      }
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      this.consumeLine(line, frames);
    }
    this.dispatch(frames);
    return frames;
  }

  private drain(): SseFrame[] {
    let frames: SseFrame[] = [];
    while (true) {
      let idx: number = this.buffer.indexOf('\n');
      if (idx < 0) {
        break;
      }
      let line: string = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      this.consumeLine(line, frames);
    }
    return frames;
  }

  private consumeLine(line: string, frames: SseFrame[]): void {
    if (line.length === 0) {
      this.dispatch(frames);
      return;
    }
    if (line.startsWith(':')) {
      return;
    }
    let colon: number = line.indexOf(':');
    let field: string = colon < 0 ? line : line.substring(0, colon);
    let value: string = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field === 'event') {
      this.eventName = value;
    } else if (field === 'data') {
      this.dataLines.push(value);
    }
  }

  private dispatch(frames: SseFrame[]): void {
    if (this.dataLines.length === 0 && this.eventName.length === 0) {
      return;
    }
    let frame: SseFrame = new SseFrame();
    frame.event = this.eventName;
    frame.data = this.dataLines.join('\n');
    frames.push(frame);
    this.eventName = '';
    this.dataLines = [];
  }
}
