import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { AsrResponse, CreateMessageBody, FileObject, RequestContentPart, RequestMessage, StreamEvent, TtsRequest } from '../model/Protocol';
import { SseDecoder, SseFrame } from './SseDecoder';

export class StreamCallbacks {
  onEvent: (event: StreamEvent) => void = () => {
  };
  onDone: () => void = () => {
  };
  onError: (message: string, code: string) => void = () => {
  };
}

export class ApiException extends Error {
  code: string = 'api';
  status: number = 0;

  constructor(message: string, code: string = 'api', status: number = 0) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

export class SpeechAudio {
  data: ArrayBuffer = new ArrayBuffer(0);
  sampleRate: number = 24000;
  channels: number = 1;
}

const BASE_URL: string = 'https://api.deepseek.com';
const ANTHROPIC_VERSION: string = '2023-06-01';
const FILES_BETA: string = 'files-api-2025-04-14';

/**
 * DeepSeek 官方接口封装。
 * - 对话：Anthropic 兼容 /anthropic/v1/messages，SSE 流式
 * - 文件：/anthropic/v1/files
 * - 语音：/v1/tools/asr、/v1/tools/tts
 */
export class DeepSeekClient {
  private apiKey: string = '';
  private session: rcp.Session = rcp.createSession();
  private activeRequest: rcp.Request | undefined = undefined;
  private cancelled: boolean = false;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  setApiKey(key: string): void {
    this.apiKey = key;
  }

  async verify(): Promise<void> {
    let headers: rcp.RequestHeaders = {
      'authorization': `Bearer ${this.apiKey}`,
      'accept': 'application/json'
    };
    let request: rcp.Request = new rcp.Request(`${BASE_URL}/models`, 'GET', headers);
    try {
      let response: rcp.Response = await this.session.fetch(request);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      let message: string = this.parseError(response);
      throw new ApiException(message, 'verify', response.statusCode);
    } catch (err) {
      if (err instanceof ApiException) {
        throw err as ApiException;
      }
      throw new ApiException(this.networkMessage(err), 'network');
    }
  }

  async streamMessages(body: CreateMessageBody, callbacks: StreamCallbacks): Promise<void> {
    this.cancelled = false;
    let decoder: SseDecoder = new SseDecoder();
    let receivedBytes: number = 0;
    let parseFrame = (frame: SseFrame): void => {
      if (frame.data.length === 0) {
        return;
      }
      let event: StreamEvent | null = this.parseEvent(frame);
      if (event !== null) {
        callbacks.onEvent(event);
      }
    };
    let config: rcp.Configuration = {
      transfer: {
        timeout: {
          connectMs: 20000,
          transferMs: 600000,
          inactivityMs: 180000
        }
      },
      tracing: {
        httpEventsHandler: {
          onDataReceive: (data: ArrayBuffer): number => {
            receivedBytes += data.byteLength;
            let frames: SseFrame[] = decoder.feed(data);
            for (let i = 0; i < frames.length; i++) {
              parseFrame(frames[i]);
            }
            return data.byteLength;
          }
        }
      }
    };
    let hasFile: boolean = this.hasFileContent(body);
    let headers: rcp.RequestHeaders = hasFile ? {
      'x-api-key': this.apiKey,
      'anthropic-version': ANTHROPIC_VERSION,
      'anthropic-beta': FILES_BETA,
      'content-type': 'application/json',
      'accept': 'text/event-stream'
    } : {
      'x-api-key': this.apiKey,
      'anthropic-version': ANTHROPIC_VERSION,
      'content-type': 'application/json',
      'accept': 'text/event-stream'
    };
    let request: rcp.Request = new rcp.Request(
      `${BASE_URL}/anthropic/v1/messages`,
      'POST',
      headers,
      JSON.stringify(body),
      undefined,
      undefined,
      config
    );
    this.activeRequest = request;
    try {
      let response: rcp.Response = await this.session.fetch(request);
      if (response.statusCode >= 400) {
        throw new ApiException(this.parseError(response), this.codeForStatus(response.statusCode), response.statusCode);
      }
      if (receivedBytes === 0 && response.body !== undefined && response.body.byteLength > 0) {
        let frames: SseFrame[] = decoder.feed(response.body);
        for (let i = 0; i < frames.length; i++) {
          parseFrame(frames[i]);
        }
      }
      let tail: SseFrame[] = decoder.flush();
      for (let i = 0; i < tail.length; i++) {
        parseFrame(tail[i]);
      }
      callbacks.onDone();
    } catch (err) {
      if (this.cancelled) {
        callbacks.onDone();
      } else if (err instanceof ApiException) {
        let apiErr: ApiException = err as ApiException;
        callbacks.onError(apiErr.message, apiErr.code);
      } else {
        callbacks.onError(this.networkMessage(err), 'network');
      }
    } finally {
      this.activeRequest = undefined;
    }
  }

  cancel(): void {
    this.cancelled = true;
    if (this.activeRequest !== undefined) {
      try {
        this.session.cancel(this.activeRequest);
      } catch (err) {
        // 已结束的请求取消时可能抛错，忽略即可。
      }
    }
  }

  close(): void {
    try {
      this.session.close();
    } catch (err) {
      // ignore
    }
  }

  async uploadFile(path: string, fileName: string, mimeType: string): Promise<FileObject> {
    let fileField: rcp.FormFieldFileValue = {
      contentType: mimeType,
      remoteFileName: fileName,
      contentOrPath: path
    };
    let fields: rcp.MultipartFormFields = {
      'file': fileField
    };
    let form: rcp.MultipartForm = new rcp.MultipartForm(fields);
    let headers: rcp.RequestHeaders = {
      'x-api-key': this.apiKey,
      'anthropic-version': ANTHROPIC_VERSION,
      'anthropic-beta': FILES_BETA,
      'accept': 'application/json'
    };
    let request: rcp.Request = new rcp.Request(`${BASE_URL}/anthropic/v1/files`, 'POST', headers, form);
    try {
      let response: rcp.Response = await this.session.fetch(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw new ApiException(this.parseError(response), 'upload', response.statusCode);
      }
      let text: string = this.decodeBody(response.body);
      return JSON.parse(text) as FileObject;
    } catch (err) {
      if (err instanceof ApiException) {
        throw err as ApiException;
      }
      throw new ApiException(this.networkMessage(err), 'network');
    }
  }

  async deleteFile(fileId: string): Promise<void> {
    let headers: rcp.RequestHeaders = {
      'x-api-key': this.apiKey,
      'anthropic-version': ANTHROPIC_VERSION,
      'anthropic-beta': FILES_BETA
    };
    let request: rcp.Request =
      new rcp.Request(`${BASE_URL}/anthropic/v1/files/${fileId}`, 'DELETE', headers);
    try {
      await this.session.fetch(request);
    } catch (err) {
      // 删除失败不影响主流程
    }
  }

  async transcribe(wavPath: string): Promise<string> {
    let fileField: rcp.FormFieldFileValue = {
      contentType: 'audio/wav',
      remoteFileName: 'speech.wav',
      contentOrPath: wavPath
    };
    let fields: rcp.MultipartFormFields = {
      'file': fileField
    };
    let form: rcp.MultipartForm = new rcp.MultipartForm(fields);
    let headers: rcp.RequestHeaders = {
      'authorization': `Bearer ${this.apiKey}`,
      'accept': 'application/json'
    };
    let request: rcp.Request = new rcp.Request(`${BASE_URL}/v1/tools/asr`, 'POST', headers, form);
    try {
      let response: rcp.Response = await this.session.fetch(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw new ApiException(this.parseError(response), 'asr', response.statusCode);
      }
      let parsed: AsrResponse = JSON.parse(this.decodeBody(response.body)) as AsrResponse;
      return parsed.text;
    } catch (err) {
      if (err instanceof ApiException) {
        throw err as ApiException;
      }
      throw new ApiException(this.networkMessage(err), 'network');
    }
  }

  async synthesize(text: string, voiceId: string): Promise<SpeechAudio> {
    let body: TtsRequest = {
      text: text,
      voice_id: voiceId,
      format: 'pcm',
      filter_markdown: true
    };
    let chunks: Uint8Array[] = [];
    let total: number = 0;
    let config: rcp.Configuration = {
      transfer: {
        timeout: {
          connectMs: 20000,
          transferMs: 300000
        }
      },
      tracing: {
        httpEventsHandler: {
          onDataReceive: (data: ArrayBuffer): number => {
            let chunk: Uint8Array = new Uint8Array(data.slice(0));
            chunks.push(chunk);
            total += chunk.length;
            return data.byteLength;
          }
        }
      }
    };
    let headers: rcp.RequestHeaders = {
      'authorization': `Bearer ${this.apiKey}`,
      'content-type': 'application/json',
      'accept': 'application/octet-stream'
    };
    let request: rcp.Request = new rcp.Request(
      `${BASE_URL}/v1/tools/tts`,
      'POST',
      headers,
      JSON.stringify(body),
      undefined,
      undefined,
      config
    );
    try {
      let response: rcp.Response = await this.session.fetch(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw new ApiException(this.parseError(response), 'tts', response.statusCode);
      }
      let output: SpeechAudio = new SpeechAudio();
      if (total > 0) {
        let merged: Uint8Array = new Uint8Array(total);
        let offset: number = 0;
        for (let i = 0; i < chunks.length; i++) {
          merged.set(chunks[i], offset);
          offset += chunks[i].length;
        }
        output.data = merged.buffer as ArrayBuffer;
      } else if (response.body !== undefined) {
        output.data = response.body;
      }
      output.sampleRate = 24000;
      output.channels = 1;
      return output;
    } catch (err) {
      if (err instanceof ApiException) {
        throw err as ApiException;
      }
      throw new ApiException(this.networkMessage(err), 'network');
    }
  }

  private hasFileContent(body: CreateMessageBody): boolean {
    for (let i = 0; i < body.messages.length; i++) {
      let message: RequestMessage = body.messages[i];
      if (typeof message.content === 'string') {
        continue;
      }
      let parts: RequestContentPart[] = message.content as RequestContentPart[];
      for (let j = 0; j < parts.length; j++) {
        if (parts[j].type === 'image' || parts[j].type === 'document') {
          return true;
        }
      }
    }
    return false;
  }

  private parseEvent(frame: SseFrame): StreamEvent | null {
    let raw: string = frame.data.trim();
    if (!raw.startsWith('{')) {
      return null;
    }
    try {
      let event: StreamEvent = JSON.parse(raw) as StreamEvent;
      if (event.type === undefined || event.type.length === 0) {
        event.type = frame.event;
      }
      return event;
    } catch (err) {
      return null;
    }
  }

  private decodeBody(body: ArrayBuffer | undefined): string {
    if (body === undefined) {
      return '';
    }
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(body));
  }

  private parseError(response: rcp.Response): string {
    let text: string = this.decodeBody(response.body);
    if (text.length > 0) {
      try {
        let parsed: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
        let error: Object | undefined = parsed['error'];
        if (error !== undefined) {
          let info: Record<string, Object> = error as Record<string, Object>;
          let message: Object | undefined = info['message'];
          if (message !== undefined) {
            return `${message}`;
          }
        }
      } catch (err) {
        // 非 JSON 错误体
      }
    }
    return this.codeForStatus(response.statusCode);
  }

  private codeForStatus(status: number): string {
    if (status === 401 || status === 403) {
      return 'API Key 无效或没有权限，请到设置中重新填写。';
    }
    if (status === 402) {
      return '账户余额不足，请前往 DeepSeek 开放平台充值。';
    }
    if (status === 429) {
      return '请求过于频繁，请稍后再试。';
    }
    if (status === 413) {
      return '附件体积超出接口限制。';
    }
    if (status >= 500) {
      return 'DeepSeek 服务暂时不可用，请稍后再试。';
    }
    return `请求失败（HTTP ${status}）。`;
  }

  private networkMessage(err: Object): string {
    let be: BusinessError = err as BusinessError;
    if (be !== undefined && be.message !== undefined && be.message.length > 0) {
      return `网络请求失败：${be.message}`;
    }
    return '网络请求失败，请检查网络连接后重试。';
  }
}
