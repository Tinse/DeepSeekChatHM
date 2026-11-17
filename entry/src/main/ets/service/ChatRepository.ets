import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Attachment, ChatMessage, ChatSession, Citation } from '../model/Types';

const DB_NAME: string = 'deepseek_chat.db';

const CREATE_SESSIONS: string = `
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  model TEXT NOT NULL,
  thinking INTEGER NOT NULL,
  search INTEGER NOT NULL
)`;

const CREATE_MESSAGES: string = `
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  thinking TEXT NOT NULL,
  signature TEXT NOT NULL,
  status TEXT NOT NULL,
  error TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  attachments TEXT NOT NULL,
  citations TEXT NOT NULL,
  tool_label TEXT NOT NULL,
  usage_input INTEGER NOT NULL,
  usage_output INTEGER NOT NULL
)`;

const CREATE_INDEX: string = 'CREATE INDEX IF NOT EXISTS idx_messages_session ON messages (session_id, created_at)';

export class ChatRepository {
  private static instance: ChatRepository | undefined = undefined;
  private store: relationalStore.RdbStore | undefined = undefined;

  static get(): ChatRepository {
    if (ChatRepository.instance === undefined) {
      ChatRepository.instance = new ChatRepository();
    }
    return ChatRepository.instance;
  }

  async init(context: common.Context): Promise<void> {
    let config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(CREATE_SESSIONS);
    await this.store.executeSql(CREATE_MESSAGES);
    await this.store.executeSql(CREATE_INDEX);
  }

  async loadSessions(): Promise<ChatSession[]> {
    let sessions: ChatSession[] = [];
    if (this.store === undefined) {
      return sessions;
    }
    let result: relationalStore.ResultSet =
      await this.store.querySql('SELECT * FROM sessions ORDER BY updated_at DESC');
    try {
      while (result.goToNextRow()) {
        let session: ChatSession = new ChatSession();
        session.id = result.getString(result.getColumnIndex('id'));
        session.title = result.getString(result.getColumnIndex('title'));
        session.createdAt = result.getLong(result.getColumnIndex('created_at'));
        session.updatedAt = result.getLong(result.getColumnIndex('updated_at'));
        session.model = result.getString(result.getColumnIndex('model'));
        session.thinking = result.getLong(result.getColumnIndex('thinking')) === 1;
        session.search = result.getLong(result.getColumnIndex('search')) === 1;
        sessions.push(session);
      }
    } finally {
      result.close();
    }
    return sessions;
  }

  async loadMessages(sessionId: string): Promise<ChatMessage[]> {
    let messages: ChatMessage[] = [];
    if (this.store === undefined) {
      return messages;
    }
    let result: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY created_at ASC', [sessionId]);
    try {
      while (result.goToNextRow()) {
        let message: ChatMessage = new ChatMessage();
        message.id = result.getString(result.getColumnIndex('id'));
        let roleText: string = result.getString(result.getColumnIndex('role'));
        message.role = roleText === 'assistant' ? 'assistant' : 'user';
        message.content = result.getString(result.getColumnIndex('content'));
        message.thinking = result.getString(result.getColumnIndex('thinking'));
        message.signature = result.getString(result.getColumnIndex('signature'));
        let statusText: string = result.getString(result.getColumnIndex('status'));
        message.status = statusText === 'streaming' ? 'streaming' :
          (statusText === 'error' ? 'error' : (statusText === 'stopped' ? 'stopped' : 'done'));
        message.error = result.getString(result.getColumnIndex('error'));
        message.createdAt = result.getLong(result.getColumnIndex('created_at'));
        message.toolLabel = result.getString(result.getColumnIndex('tool_label'));
        message.usageInput = result.getLong(result.getColumnIndex('usage_input'));
        message.usageOutput = result.getLong(result.getColumnIndex('usage_output'));
        message.attachments = this.parseAttachments(result.getString(result.getColumnIndex('attachments')));
        message.citations = this.parseCitations(result.getString(result.getColumnIndex('citations')));
        messages.push(message);
      }
    } finally {
      result.close();
    }
    return messages;
  }

  async saveSession(session: ChatSession): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    let bucket: relationalStore.ValuesBucket = {
      'id': session.id,
      'title': session.title,
      'created_at': session.createdAt,
      'updated_at': session.updatedAt,
      'model': session.model,
      'thinking': session.thinking ? 1 : 0,
      'search': session.search ? 1 : 0
    };
    await this.store.insert('sessions', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async saveMessage(sessionId: string, message: ChatMessage): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    let bucket: relationalStore.ValuesBucket = {
      'id': message.id,
      'session_id': sessionId,
      'role': message.role,
      'content': message.content,
      'thinking': message.thinking,
      'signature': message.signature,
      'status': message.status,
      'error': message.error,
      'created_at': message.createdAt,
      'attachments': JSON.stringify(message.attachments),
      'citations': JSON.stringify(message.citations),
      'tool_label': message.toolLabel,
      'usage_input': message.usageInput,
      'usage_output': message.usageOutput
    };
    await this.store.insert('messages', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async deleteSession(sessionId: string): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    let messagePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
    messagePredicates.equalTo('session_id', sessionId);
    await this.store.delete(messagePredicates);
    let sessionPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('sessions');
    sessionPredicates.equalTo('id', sessionId);
    await this.store.delete(sessionPredicates);
  }

  async deleteAll(): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    await this.store.executeSql('DELETE FROM messages');
    await this.store.executeSql('DELETE FROM sessions');
  }

  private parseAttachments(raw: string): Attachment[] {
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as Attachment[];
    } catch (err) {
      return [];
    }
  }

  private parseCitations(raw: string): Citation[] {
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as Citation[];
    } catch (err) {
      return [];
    }
  }
}
