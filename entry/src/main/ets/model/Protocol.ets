/** Anthropic 兼容 Messages API 的请求/响应类型，只保留本应用使用的部分。 */

export interface TextCitation {
  type: string;
  url: string;
  title: string | null;
  cited_text: string;
  encrypted_index: string;
}

export interface ServerToolInput {
  action?: string;
  query?: string;
  queries?: string[];
  url?: string;
  pattern?: string;
}

export interface ContentBlockStart {
  type: string;
  text?: string;
  thinking?: string;
  signature?: string;
  citations?: TextCitation[];
  id?: string;
  name?: string;
  input?: ServerToolInput;
  kind?: string;
  tool_use_id?: string;
  content?: Object;
}

export interface ContentBlockDelta {
  type: string;
  text?: string;
  thinking?: string;
  signature?: string;
  citation?: TextCitation;
  partial_json?: string;
  title?: string;
}

export interface MessageUsage {
  input_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
  output_tokens?: number;
}

export interface StreamMessage {
  id: string;
  model: string;
  usage?: MessageUsage;
}

export interface StreamDelta {
  type?: string;
  stop_reason?: string;
  stop_sequence?: string | null;
  title?: string;
}

export interface ApiErrorInfo {
  message: string;
  type?: string;
  param?: string | null;
  code?: string | null;
}

export interface ApiErrorBody {
  error: ApiErrorInfo;
}

export interface StreamEvent {
  type: string;
  index?: number;
  message?: StreamMessage;
  content_block?: ContentBlockStart;
  delta?: ContentBlockDelta;
  usage?: MessageUsage;
  error?: ApiErrorInfo;
}

export interface FileSource {
  type: string;
  file_id: string;
}

export interface RequestContentPart {
  type: string;
  text?: string;
  source?: FileSource;
}

export interface RequestMessage {
  role: string;
  content: string | RequestContentPart[];
}

export interface ToolDef {
  type: string;
  name: string;
}

export interface ThinkingOption {
  type: string;
}

export interface SafetyCheck {
  level: string;
}

export interface TitleOption {
  enabled: boolean;
}

export interface CreateMessageBody {
  model: string;
  system: string;
  messages: RequestMessage[];
  thinking: ThinkingOption;
  tools: ToolDef[];
  safety_check: SafetyCheck;
  title?: TitleOption;
  stream: boolean;
}

export interface FileObject {
  id: string;
  type: string;
  size_bytes: number;
  created_at: string;
  filename: string;
  mime_type: string;
}

export interface AsrResponse {
  text: string;
}

export interface TtsRequest {
  text: string;
  voice_id: string;
  format: string;
  filter_markdown: boolean;
}
