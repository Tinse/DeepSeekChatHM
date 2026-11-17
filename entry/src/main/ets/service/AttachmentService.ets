import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AttachmentDraft } from '../model/Types';

const MAX_TEXT_BYTES: number = 256 * 1024;

export class AttachmentService {
  static async pickImages(context: common.UIAbilityContext): Promise<AttachmentDraft[]> {
    let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 4;
    let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    let result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
    let drafts: AttachmentDraft[] = [];
    for (let i = 0; i < result.photoUris.length; i++) {
      let uri: string = result.photoUris[i];
      let ext: string = AttachmentService.extension(uri);
      let originalName: string = AttachmentService.fileName(uri);
      let storedName: string = `image_${Date.now()}_${i}${ext}`;
      let dest: string = `${context.filesDir}/${storedName}`;
      let src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        await fs.copyFile(src.fd, dest);
      } finally {
        fs.closeSync(src);
      }
      let draft: AttachmentDraft = new AttachmentDraft();
      draft.name = originalName.length > 0 ? originalName : storedName;
      draft.mimeType = AttachmentService.imageMime(ext);
      draft.size = fs.statSync(dest).size;
      draft.kind = 'image';
      draft.localPath = dest;
      drafts.push(draft);
    }
    return drafts;
  }

  static async pickDocuments(context: common.UIAbilityContext): Promise<AttachmentDraft[]> {
    let options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 2;
    options.fileSuffixFilters = ['.txt', '.md', '.markdown', '.json', '.csv', '.log', '.xml', '.yaml', '.yml'];
    let documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    let uris: string[] = await documentPicker.select(options);
    let drafts: AttachmentDraft[] = [];
    for (let i = 0; i < uris.length; i++) {
      let uri: string = uris[i];
      let ext: string = AttachmentService.extension(uri);
      let originalName: string = AttachmentService.fileName(uri);
      let storedName: string = `file_${Date.now()}_${i}${ext}`;
      let dest: string = `${context.filesDir}/${storedName}`;
      let src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        await fs.copyFile(src.fd, dest);
      } finally {
        fs.closeSync(src);
      }
      let size: number = fs.statSync(dest).size;
      if (size > MAX_TEXT_BYTES) {
        throw new Error(`「${originalName}」超过 256 KB，暂不支持。`);
      }
      let content: string = '';
      try {
        content = fs.readTextSync(dest);
      } catch (err) {
        throw new Error(`「${originalName}」不是 UTF-8 文本，无法读取。`);
      }
      let draft: AttachmentDraft = new AttachmentDraft();
      draft.name = originalName.length > 0 ? originalName : storedName;
      draft.mimeType = AttachmentService.textMime(ext);
      draft.size = size;
      draft.kind = 'text';
      draft.localPath = dest;
      draft.textContent = content;
      drafts.push(draft);
    }
    return drafts;
  }

  private static fileName(uri: string): string {
    let clean: string = uri;
    let query: number = clean.indexOf('?');
    if (query >= 0) {
      clean = clean.substring(0, query);
    }
    let slash: number = clean.lastIndexOf('/');
    return slash >= 0 ? clean.substring(slash + 1) : clean;
  }

  private static extension(uri: string): string {
    let clean: string = uri;
    let query: number = clean.indexOf('?');
    if (query >= 0) {
      clean = clean.substring(0, query);
    }
    let slash: number = clean.lastIndexOf('/');
    let name: string = slash >= 0 ? clean.substring(slash + 1) : clean;
    let dot: number = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) {
      return '';
    }
    return name.substring(dot).toLowerCase();
  }

  private static imageMime(ext: string): string {
    if (ext === '.png') {
      return 'image/png';
    }
    if (ext === '.webp') {
      return 'image/webp';
    }
    if (ext === '.gif') {
      return 'image/gif';
    }
    if (ext === '.heic' || ext === '.heif') {
      return 'image/heic';
    }
    if (ext === '.bmp') {
      return 'image/bmp';
    }
    return 'image/jpeg';
  }

  private static textMime(ext: string): string {
    if (ext === '.md' || ext === '.markdown') {
      return 'text/markdown';
    }
    if (ext === '.json') {
      return 'application/json';
    }
    if (ext === '.csv') {
      return 'text/csv';
    }
    if (ext === '.xml') {
      return 'application/xml';
    }
    if (ext === '.yaml' || ext === '.yml') {
      return 'text/yaml';
    }
    return 'text/plain';
  }
}
