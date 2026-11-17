import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

const SAMPLE_RATE: number = 16000;
const CHANNELS: number = 1;
const BITS_PER_SAMPLE: number = 16;

/**
 * 录音：16 kHz / 单声道 / S16LE PCM，手写 WAV 头后交给 /v1/tools/asr。
 * 播放：TTS 返回 24 kHz / 单声道 / S16LE 裸 PCM，直接写 AudioRenderer。
 */
export class SpeechService {
  private capturer: audio.AudioCapturer | undefined = undefined;
  private chunks: Uint8Array[] = [];
  private totalBytes: number = 0;
  private renderer: audio.AudioRenderer | undefined = undefined;

  static async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    let manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let permissions: Permissions[] = ['ohos.permission.MICROPHONE'];
    try {
      let result = await manager.requestPermissionsFromUser(context, permissions);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (err) {
      return false;
    }
  }

  async startRecording(): Promise<void> {
    if (this.capturer !== undefined) {
      return;
    }
    this.chunks = [];
    this.totalBytes = 0;
    let options: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION,
        capturerFlags: 0
      }
    };
    let capturer: audio.AudioCapturer = await audio.createAudioCapturer(options);
    capturer.on('readData', (buffer: ArrayBuffer) => {
      if (this.totalBytes >= 8 * 1024 * 1024) {
        return;
      }
      let copy: Uint8Array = new Uint8Array(buffer.slice(0));
      this.chunks.push(copy);
      this.totalBytes += copy.length;
    });
    try {
      await capturer.start();
      this.capturer = capturer;
    } catch (err) {
      try {
        await capturer.release();
      } catch (releaseErr) {
        // ignore
      }
      throw err as Error;
    }
  }

  getRecordedBytes(): number {
    return this.totalBytes;
  }

  async stopRecording(context: common.UIAbilityContext): Promise<string> {
    if (this.capturer === undefined) {
      throw new Error('录音尚未开始。');
    }
    try {
      await this.capturer.stop();
    } catch (err) {
      // ignore
    }
    try {
      await this.capturer.release();
    } catch (err) {
      // ignore
    }
    this.capturer = undefined;
    if (this.totalBytes === 0) {
      throw new Error('没有录到声音，请重试。');
    }
    let pcm: Uint8Array = new Uint8Array(this.totalBytes);
    let offset: number = 0;
    for (let i = 0; i < this.chunks.length; i++) {
      pcm.set(this.chunks[i], offset);
      offset += this.chunks[i].length;
    }
    this.chunks = [];
    let wav: ArrayBuffer = this.buildWav(pcm);
    let path: string = `${context.filesDir}/voice_${Date.now()}.wav`;
    let file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, wav);
    } finally {
      fs.closeSync(file);
    }
    this.totalBytes = 0;
    return path;
  }

  async cancelRecording(): Promise<void> {
    if (this.capturer !== undefined) {
      try {
        await this.capturer.stop();
      } catch (err) {
        // ignore
      }
      try {
        await this.capturer.release();
      } catch (err) {
        // ignore
      }
      this.capturer = undefined;
    }
    this.chunks = [];
    this.totalBytes = 0;
  }

  async playPcm(data: ArrayBuffer): Promise<void> {
    await this.stopPlayback();
    let options: audio.AudioRendererOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_24000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      rendererInfo: {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      }
    };
    let renderer: audio.AudioRenderer = await audio.createAudioRenderer(options);
    this.renderer = renderer;
    await renderer.start();
    let offset: number = 0;
    while (offset < data.byteLength) {
      let remaining: ArrayBuffer = data.slice(offset);
      let written: number = await renderer.write(remaining);
      if (written <= 0) {
        break;
      }
      offset += written;
    }
    await renderer.drain();
    await renderer.stop();
    await renderer.release();
    this.renderer = undefined;
  }

  async stopPlayback(): Promise<void> {
    if (this.renderer !== undefined) {
      try {
        await this.renderer.stop();
      } catch (err) {
        // ignore
      }
      try {
        await this.renderer.release();
      } catch (err) {
        // ignore
      }
      this.renderer = undefined;
    }
  }

  private buildWav(pcm: Uint8Array): ArrayBuffer {
    let dataLength: number = pcm.length;
    let buffer: ArrayBuffer = new ArrayBuffer(44 + dataLength);
    let view: DataView = new DataView(buffer);
    this.writeAscii(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataLength, true);
    this.writeAscii(view, 8, 'WAVE');
    this.writeAscii(view, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, CHANNELS, true);
    view.setUint32(24, SAMPLE_RATE, true);
    view.setUint32(28, SAMPLE_RATE * CHANNELS * BITS_PER_SAMPLE / 8, true);
    view.setUint16(32, CHANNELS * BITS_PER_SAMPLE / 8, true);
    view.setUint16(34, BITS_PER_SAMPLE, true);
    this.writeAscii(view, 36, 'data');
    view.setUint32(40, dataLength, true);
    let target: Uint8Array = new Uint8Array(buffer, 44);
    target.set(pcm);
    return buffer;
  }

  private writeAscii(view: DataView, offset: number, text: string): void {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  }
}
