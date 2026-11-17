export type ChatRole = 'user' | 'assistant';
export type MessageStatus = 'done' | 'streaming' | 'error' | 'stopped';
export type AttachmentKind = 'image' | 'text';

@Observed
export class Attachment {
  id: string = '';
  name: string = '';
  mimeType: string = '';
  size: number = 0;
  kind: AttachmentKind = 'image';
  fileId: string = '';
  localPath: string = '';
  textContent: string = '';
}

@Observed
export class Citation {
  url: string = '';
  title: string = '';
}

@Observed
export class ChatMessage {
  id: string = '';
  role: ChatRole = 'user';
  content: string = '';
  thinking: string = '';
  signature: string = '';
  status: MessageStatus = 'done';
  error: string = '';
  createdAt: number = 0;
  attachments: Attachment[] = [];
  citations: Citation[] = [];
  toolLabel: string = '';
  usageInput: number = 0;
  usageOutput: number = 0;
  title: string = '';
}

@Observed
export class ChatSession {
  id: string = '';
  title: string = '新对话';
  createdAt: number = 0;
  updatedAt: number = 0;
  model: string = 'deepseek-flash';
  thinking: boolean = true;
  search: boolean = true;
}

export class AppSettings {
  model: string = 'deepseek-flash';
  thinking: boolean = true;
  search: boolean = true;
  voice: string = 'stella';
  haptic: boolean = true;
  textSize: number = 16;
  expandThinking: boolean = false;
}

export class AttachmentDraft {
  name: string = '';
  mimeType: string = '';
  size: number = 0;
  kind: AttachmentKind = 'image';
  localPath: string = '';
  textContent: string = '';
}
