import { ApiException, DeepSeekClient, SpeechAudio, StreamCallbacks } from './ApiClient';
import { ChatRepository } from './ChatRepository';
import {
  AppSettings,
  Attachment,
  AttachmentDraft,
  ChatMessage,
  ChatSession,
  Citation
} from '../model/Types';
import {
  ContentBlockDelta,
  ContentBlockStart,
  CreateMessageBody,
  RequestContentPart,
  RequestMessage,
  StreamEvent,
  TextCitation,
  ToolDef
} from '../model/Protocol';

const SYSTEM_PROMPT: string = '该助手为DeepSeek，由深度求索公司创造。';
const TITLE_FALLBACK_LENGTH: number = 22;

export class ChatCallbacks {
  onMessages: (messages: ChatMessage[]) => void = () => {
  };
  onStreaming: (streaming: boolean) => void = () => {
  };
  onTitle: (title: string) => void = () => {
  };
  onError: (message: string) => void = () => {
  };
  onSessionsChanged: () => void = () => {
  };
}

function newId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).substring(2, 8)}`;
}

/**
 * 单会话流式引擎。消息对象本身是 @Observed，UI 通过 @ObjectLink 接收增量；
 * 这里只负责协议拼装、事件归并、节流刷 UI 与持久化。
 */
export class ChatEngine {
  private client: DeepSeekClient | undefined = undefined;
  private repo: ChatRepository = ChatRepository.get();
  private callbacks: ChatCallbacks = new ChatCallbacks();
  private settings: AppSettings = new AppSettings();
  private session: ChatSession | undefined = undefined;
  private messages: ChatMessage[] = [];
  private streaming: boolean = false;
  private stopRequested: boolean = false;
  private activeAssistant: ChatMessage | undefined = undefined;
  private pendingContent: string = '';
  private pendingThinking: string = '';
  private pendingSignature: string = '';
  private pendingToolLabel: string = '';
  private pendingUsageInput: number = 0;
  private pendingUsageOutput: number = 0;
  private flushTimer: number = -1;
  private saveTimer: number = -1;
  private titleRequested: boolean = false;
  private firstUserText: string = '';

  setCallbacks(callbacks: ChatCallbacks): void {
    this.callbacks = callbacks;
  }

  setApiKey(apiKey: string): void {
    if (this.client !== undefined) {
      this.client.close();
      this.client = undefined;
    }
    if (apiKey.length === 0) {
      return;
    }
    this.client = new DeepSeekClient(apiKey);
  }

  async transcribe(wavPath: string): Promise<string> {
    if (this.client === undefined) {
      throw new Error('请先在设置中填写 DeepSeek API Key。');
    }
    return this.client.transcribe(wavPath);
  }

  async synthesize(text: string): Promise<SpeechAudio> {
    if (this.client === undefined) {
      throw new Error('请先在设置中填写 DeepSeek API Key。');
    }
    return this.client.synthesize(text, this.settings.voice);
  }

  dispose(): void {
    this.stop();
    if (this.client !== undefined) {
      this.client.close();
      this.client = undefined;
    }
  }

  setSettings(settings: AppSettings): void {
    this.settings = settings;
    if (this.session !== undefined) {
      this.session.model = settings.model;
      this.session.thinking = settings.thinking;
      this.session.search = settings.search;
    }
  }

  getSettings(): AppSettings {
    return this.settings;
  }

  getSession(): ChatSession | undefined {
    return this.session;
  }

  getMessages(): ChatMessage[] {
    return this.messages;
  }

  isStreaming(): boolean {
    return this.streaming;
  }

  async createSession(): Promise<ChatSession> {
    let session: ChatSession = new ChatSession();
    session.id = newId('s');
    session.title = '新对话';
    session.createdAt = Date.now();
    session.updatedAt = session.createdAt;
    session.model = this.settings.model;
    session.thinking = this.settings.thinking;
    session.search = this.settings.search;
    this.session = session;
    this.messages = [];
    await this.repo.saveSession(session);
    this.callbacks.onTitle(session.title);
    this.callbacks.onMessages([]);
    this.callbacks.onSessionsChanged();
    return session;
  }

  async openSession(session: ChatSession): Promise<void> {
    this.session = session;
    let loaded: ChatMessage[] = await this.repo.loadMessages(session.id);
    for (let i = 0; i < loaded.length; i++) {
      if (loaded[i].status === 'streaming') {
        loaded[i].status = 'stopped';
      }
    }
    this.messages = loaded;
    this.callbacks.onTitle(session.title);
    this.callbacks.onMessages(this.snapshot());
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.repo.deleteSession(sessionId);
    if (this.session !== undefined && this.session.id === sessionId) {
      this.session = undefined;
      this.messages = [];
      this.callbacks.onMessages([]);
      this.callbacks.onTitle('新对话');
    }
    this.callbacks.onSessionsChanged();
  }

  async send(text: string, drafts: AttachmentDraft[]): Promise<boolean> {
    if (this.streaming) {
      return false;
    }
    let trimmed: string = text.trim();
    if (trimmed.length === 0 && drafts.length === 0) {
      return false;
    }
    if (this.client === undefined) {
      this.callbacks.onError('请先在设置中填写 DeepSeek API Key。');
      return false;
    }
    if (this.session === undefined) {
      await this.createSession();
    }
    let session: ChatSession = this.session as ChatSession;
    let isFirstRound: boolean = this.messages.length <= 1;
    this.firstUserText = trimmed;
    this.titleRequested = isFirstRound && session.title === '新对话';

    let attachments: Attachment[] = [];
    if (drafts.length > 0) {
      try {
        attachments = await this.prepareAttachments(drafts);
      } catch (err) {
        let message: string = err instanceof Error ? (err as Error).message : '附件上传失败。';
        this.callbacks.onError(message);
        return false;
      }
    }
    if (this.firstUserText.length === 0 && attachments.length > 0) {
      this.firstUserText = attachments[0].name;
    }

    let user: ChatMessage = new ChatMessage();
    user.id = newId('m');
    user.role = 'user';
    user.content = trimmed;
    user.attachments = attachments;
    user.createdAt = Date.now();
    user.status = 'done';

    let assistant: ChatMessage = new ChatMessage();
    assistant.id = newId('a');
    assistant.role = 'assistant';
    assistant.status = 'streaming';
    assistant.createdAt = Date.now() + 1;

    this.messages.push(user);
    this.messages.push(assistant);
    this.activeAssistant = assistant;
    this.pendingContent = '';
    this.pendingThinking = '';
    this.pendingSignature = '';
    this.pendingToolLabel = '';
    this.pendingUsageInput = 0;
    this.pendingUsageOutput = 0;
    this.notifyMessages();

    await this.repo.saveMessage(session.id, user);
    await this.repo.saveMessage(session.id, assistant);
    session.updatedAt = Date.now();
    await this.repo.saveSession(session);

    this.requestCompletion(assistant);
    return true;
  }

  stop(): void {
    if (!this.streaming) {
      return;
    }
    this.stopRequested = true;
    let assistant: ChatMessage | undefined = this.activeAssistant;
    if (assistant !== undefined) {
      this.finish(assistant);
    }
    if (this.client !== undefined) {
      this.client.cancel();
    }
  }

  async regenerate(): Promise<void> {
    if (this.streaming || this.session === undefined) {
      return;
    }
    let lastUserIndex: number = -1;
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === 'user') {
        lastUserIndex = i;
        break;
      }
    }
    if (lastUserIndex < 0) {
      return;
    }
    let oldAssistantId: string = '';
    let last: ChatMessage | undefined = this.messages[this.messages.length - 1];
    if (last !== undefined && last.role === 'assistant') {
      oldAssistantId = last.id;
    }
    this.messages = this.messages.slice(0, lastUserIndex + 1);
    let assistant: ChatMessage = new ChatMessage();
    assistant.id = oldAssistantId.length > 0 ? oldAssistantId : newId('a');
    assistant.role = 'assistant';
    assistant.status = 'streaming';
    assistant.createdAt = Date.now();
    this.messages.push(assistant);
    this.activeAssistant = assistant;
    this.pendingContent = '';
    this.pendingThinking = '';
    this.pendingSignature = '';
    this.pendingToolLabel = '';
    this.pendingUsageInput = 0;
    this.pendingUsageOutput = 0;
    this.titleRequested = false;
    this.notifyMessages();
    await this.repo.saveMessage(this.session.id, assistant);
    this.requestCompletion(assistant);
  }

  private async prepareAttachments(drafts: AttachmentDraft[]): Promise<Attachment[]> {
    let attachments: Attachment[] = [];
    for (let i = 0; i < drafts.length; i++) {
      let draft: AttachmentDraft = drafts[i];
      let attachment: Attachment = new Attachment();
      attachment.id = newId('f');
      attachment.name = draft.name;
      attachment.mimeType = draft.mimeType;
      attachment.size = draft.size;
      attachment.kind = draft.kind;
      attachment.localPath = draft.localPath;
      attachment.textContent = draft.textContent;
      if (draft.kind === 'image') {
        if (this.client === undefined) {
          throw new Error('客户端未初始化。');
        }
        let uploaded = await this.client.uploadFile(draft.localPath, draft.name, draft.mimeType);
        attachment.fileId = uploaded.id;
      }
      attachments.push(attachment);
    }
    return attachments;
  }

  private requestCompletion(assistant: ChatMessage): void {
    if (this.client === undefined || this.session === undefined) {
      this.finishError(assistant, '客户端未初始化，请重新填写 API Key。');
      return;
    }
    let body: CreateMessageBody = {
      model: this.session.model,
      system: SYSTEM_PROMPT,
      messages: this.buildHistory(),
      thinking: {
        type: this.session.thinking ? 'enabled' : 'disabled'
      },
      tools: this.buildTools(),
      safety_check: {
        level: 'high'
      },
      stream: true
    };
    if (this.titleRequested) {
      body.title = {
        enabled: true
      };
    }

    this.streaming = true;
    this.stopRequested = false;
    this.callbacks.onStreaming(true);

    let streamCallbacks: StreamCallbacks = new StreamCallbacks();
    streamCallbacks.onEvent = (event: StreamEvent): void => {
      this.handleEvent(assistant, event);
    };
    streamCallbacks.onDone = (): void => {
      this.finish(assistant);
    };
    streamCallbacks.onError = (message: string, code: string): void => {
      this.finishError(assistant, message);
    };
    this.client.streamMessages(body, streamCallbacks);
  }

  private handleEvent(assistant: ChatMessage, event: StreamEvent): void {
    switch (event.type) {
      case 'message_start':
        if (event.message !== undefined && event.message.usage !== undefined) {
          assistant.usageInput = event.message.usage.input_tokens !== undefined ?
            event.message.usage.input_tokens : 0;
        }
        break;
      case 'content_block_start':
        if (event.content_block !== undefined) {
          this.handleBlockStart(assistant, event.content_block);
        }
        break;
      case 'content_block_delta':
        if (event.delta !== undefined) {
          this.handleDelta(event.delta.type, event.delta);
        }
        break;
      case 'message_delta':
        if (event.delta !== undefined && event.delta.title !== undefined &&
          event.delta.title !== null && event.delta.title.trim().length > 0 && this.titleRequested &&
          this.session !== undefined && this.session.title === '新对话') {
          this.session.title = event.delta.title.trim();
          this.titleRequested = false;
          this.callbacks.onTitle(this.session.title);
          this.persistSession();
        }
        if (event.usage !== undefined && event.usage.output_tokens !== undefined) {
          assistant.usageOutput = event.usage.output_tokens;
        }
        break;
      case 'error':
        if (event.error !== undefined && event.error.message !== undefined) {
          this.finishError(assistant, event.error.message);
        }
        break;
      default:
        break;
    }
  }

  private handleBlockStart(assistant: ChatMessage, block: ContentBlockStart): void {
    if (block.type === 'text') {
      let initial: string = block.text !== undefined ? block.text : '';
      if (this.pendingContent.length > 0) {
        this.pendingContent += '\n\n';
      }
      this.pendingContent += initial;
      if (block.citations !== undefined) {
        for (let i = 0; i < block.citations.length; i++) {
          this.addCitation(block.citations[i]);
        }
      }
      this.scheduleFlush();
    } else if (block.type === 'thinking') {
      if (block.thinking !== undefined) {
        this.pendingThinking += block.thinking;
      }
      if (block.signature !== undefined) {
        this.pendingSignature += block.signature;
      }
      this.scheduleFlush();
    } else if (block.type === 'server_tool_use') {
      if (block.name === 'deepseek_web_search') {
        assistant.toolLabel = '正在联网搜索…';
      } else if (block.name === 'deepseek_read_url') {
        assistant.toolLabel = '正在读取链接…';
      }
    } else if (block.type === 'web_search_tool_result') {
      assistant.toolLabel = '已完成搜索';
    } else if (block.type === 'web_fetch_tool_result') {
      assistant.toolLabel = '已读取链接';
    }
  }

  private handleDelta(type: string | undefined, delta: ContentBlockDelta): void {
    if (type === 'text_delta') {
      if (delta.text !== undefined) {
        this.pendingContent += delta.text;
        this.scheduleFlush();
      }
    } else if (type === 'thinking_delta') {
      if (delta.thinking !== undefined) {
        this.pendingThinking += delta.thinking;
        this.scheduleFlush();
      }
    } else if (type === 'signature_delta') {
      if (delta.signature !== undefined) {
        this.pendingSignature += delta.signature;
        this.scheduleFlush();
      }
    } else if (type === 'citations_delta') {
      if (delta.citation !== undefined && delta.citation !== null) {
        this.addCitation(delta.citation);
        this.scheduleFlush();
      }
    }
  }

  private addCitation(textCitation: TextCitation): void {
    if (this.activeAssistant === undefined) {
      return;
    }
    if (textCitation.url === undefined || textCitation.url.length === 0) {
      return;
    }
    for (let i = 0; i < this.activeAssistant.citations.length; i++) {
      if (this.activeAssistant.citations[i].url === textCitation.url) {
        return;
      }
    }
    let citation: Citation = new Citation();
    citation.url = textCitation.url;
    citation.title = textCitation.title !== null && textCitation.title !== undefined ?
      textCitation.title : textCitation.url;
    this.activeAssistant.citations.push(citation);
  }

  private scheduleFlush(): void {
    if (this.flushTimer !== -1) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1;
      this.applyPending();
    }, 60);
  }

  private applyPending(): void {
    if (this.activeAssistant === undefined) {
      return;
    }
    this.activeAssistant.content = this.pendingContent;
    this.activeAssistant.thinking = this.pendingThinking;
    this.activeAssistant.signature = this.pendingSignature;
    if (this.pendingUsageInput > 0) {
      this.activeAssistant.usageInput = this.pendingUsageInput;
    }
    if (this.pendingUsageOutput > 0) {
      this.activeAssistant.usageOutput = this.pendingUsageOutput;
    }
    this.scheduleSave();
  }

  private scheduleSave(): void {
    if (this.saveTimer !== -1) {
      return;
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.persistActive();
    }, 700);
  }

  private persistActive(): void {
    if (this.session === undefined || this.activeAssistant === undefined) {
      return;
    }
    let sessionId: string = this.session.id;
    let message: ChatMessage = this.activeAssistant;
    this.repo.saveMessage(sessionId, message).catch((err: Error) => {
      // 流式过程中持久化失败不打断生成
    });
  }

  private finish(assistant: ChatMessage): void {
    if (!this.streaming) {
      return;
    }
    this.flushNow();
    assistant.status = this.stopRequested ? 'stopped' : 'done';
    if (assistant.content.length === 0 && assistant.thinking.length === 0 &&
      assistant.error.length === 0 && assistant.toolLabel.length === 0) {
      assistant.content = '（没有返回内容）';
    }
    this.streaming = false;
    this.stopRequested = false;
    this.activeAssistant = undefined;
    this.finishTitle();
    this.callbacks.onStreaming(false);
    this.notifyMessages();
    this.persistFinal(assistant);
  }

  private finishError(assistant: ChatMessage, message: string): void {
    if (!this.streaming) {
      return;
    }
    this.flushNow();
    assistant.status = 'error';
    assistant.error = message;
    this.streaming = false;
    this.stopRequested = false;
    this.activeAssistant = undefined;
    this.finishTitle();
    this.callbacks.onStreaming(false);
    this.callbacks.onError(message);
    this.notifyMessages();
    this.persistFinal(assistant);
  }

  private flushNow(): void {
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    this.applyPending();
  }

  private finishTitle(): void {
    if (this.session === undefined) {
      return;
    }
    if (this.titleRequested && this.session.title === '新对话') {
      let title: string = this.firstUserText.replace(/\s+/g, ' ').trim();
      if (title.length > TITLE_FALLBACK_LENGTH) {
        title = title.substring(0, TITLE_FALLBACK_LENGTH) + '…';
      }
      if (title.length > 0) {
        this.session.title = title;
        this.callbacks.onTitle(title);
      }
    }
    this.titleRequested = false;
    this.persistSession();
  }

  private persistSession(): void {
    if (this.session === undefined) {
      return;
    }
    let session: ChatSession = this.session;
    session.updatedAt = Date.now();
    this.repo.saveSession(session).catch((err: Error) => {
      // ignore
    });
    this.callbacks.onSessionsChanged();
  }

  private persistFinal(assistant: ChatMessage): void {
    if (this.session === undefined) {
      return;
    }
    let session: ChatSession = this.session;
    session.updatedAt = Date.now();
    this.repo.saveMessage(session.id, assistant).catch((err: Error) => {
      // ignore
    });
    this.repo.saveSession(session).catch((err: Error) => {
      // ignore
    });
    this.callbacks.onSessionsChanged();
  }

  private notifyMessages(): void {
    this.callbacks.onMessages(this.snapshot());
  }

  private snapshot(): ChatMessage[] {
    return this.messages.slice(0);
  }

  private buildTools(): ToolDef[] {
    let tools: ToolDef[] = [{
      type: 'deepseek_read_url',
      name: 'deepseek_read_url'
    }];
    if (this.session !== undefined && this.session.search) {
      tools.push({
        type: 'deepseek_web_search',
        name: 'deepseek_web_search'
      });
    }
    return tools;
  }

  private buildHistory(): RequestMessage[] {
    let result: RequestMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      let message: ChatMessage = this.messages[i];
      if (message.role === 'user') {
        let content: string = this.userText(message);
        let images: RequestContentPart[] = [];
        for (let j = 0; j < message.attachments.length; j++) {
          let attachment: Attachment = message.attachments[j];
          if (attachment.kind === 'image' && attachment.fileId.length > 0) {
            let part: RequestContentPart = {
              type: 'image',
              source: {
                type: 'file',
                file_id: attachment.fileId
              }
            };
            images.push(part);
          }
        }
        if (content.length === 0 && images.length === 0) {
          continue;
        }
        if (images.length === 0) {
          result.push({
            role: 'user',
            content: content
          });
        } else {
          let parts: RequestContentPart[] = images;
          if (content.length > 0) {
            parts.push({
              type: 'text',
              text: content
            });
          }
          result.push({
            role: 'user',
            content: parts
          });
        }
      } else {
        if (message.status !== 'done' && message.status !== 'stopped') {
          continue;
        }
        if (message.content.length === 0) {
          continue;
        }
        result.push({
          role: 'assistant',
          content: message.content
        });
      }
    }
    return result;
  }

  private userText(message: ChatMessage): string {
    let text: string = message.content;
    for (let i = 0; i < message.attachments.length; i++) {
      let attachment: Attachment = message.attachments[i];
      if (attachment.kind === 'text' && attachment.textContent.length > 0) {
        text += `\n\n【附件：${attachment.name}】\n${attachment.textContent}`;
      }
    }
    return text;
  }
}
