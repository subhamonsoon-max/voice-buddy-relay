/**
 * Audio engine for Voice Buddy Web Tester.
 * Approach taken from D:\voice_refecrance\app\static\js\app.js (reference project).
 *
 * Recording: AudioWorklet (off-thread) → ScriptProcessor fallback
 *   - Captures mic at native hardware rate, downsamples to 16kHz PCM Int16
 *   - Emits 512-sample (32ms) blocks
 * Playback: Web Audio API at 24kHz (matching Gemini Live output)
 *   - Queues buffers sequentially with gap-free scheduling
 */

// ─── Playback Engine (24kHz PCM from Gemini Live) ───────────────────────────

class PcmPlayer {
  constructor() {
    this.audioCtx = null;
    this.nextStartTime = 0;
    this.activeSources = [];
    this.analyser = null;
  }

  _ensureCtx() {
    if (!this.audioCtx || this.audioCtx.state === 'closed') {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      this.audioCtx = new Ctx({ sampleRate: 24000 });
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 128;
      this.analyser.connect(this.audioCtx.destination);
    }
    if (this.audioCtx.state === 'suspended') {
      this.audioCtx.resume();
    }
  }

  playChunk(uint8Data) {
    this._ensureCtx();
    if (!uint8Data || uint8Data.byteLength === 0) return;

    // Reinterpret raw bytes as 16-bit signed little-endian PCM samples
    const pcm16 = new Int16Array(
      uint8Data.buffer,
      uint8Data.byteOffset,
      Math.floor(uint8Data.byteLength / 2)
    );

    const float32 = new Float32Array(pcm16.length);
    for (let i = 0; i < pcm16.length; i++) {
      float32[i] = pcm16[i] / 32768.0;
    }

    const buffer = this.audioCtx.createBuffer(1, float32.length, 24000);
    buffer.getChannelData(0).set(float32);

    const source = this.audioCtx.createBufferSource();
    source.buffer = buffer;
    source.connect(this.analyser);

    const now = this.audioCtx.currentTime;
    if (this.nextStartTime < now) this.nextStartTime = now;

    source.start(this.nextStartTime);
    this.nextStartTime += buffer.duration;
    this.activeSources.push(source);

    source.onended = () => {
      const idx = this.activeSources.indexOf(source);
      if (idx !== -1) this.activeSources.splice(idx, 1);
    };
  }

  clearQueue() {
    this.activeSources.forEach((src) => {
      try { src.stop(); } catch (e) { /* ignore */ }
    });
    this.activeSources = [];
    if (this.audioCtx) {
      this.nextStartTime = this.audioCtx.currentTime;
    }
  }

  stop() {
    this.clearQueue();
    if (this.audioCtx) {
      this.audioCtx.close();
      this.audioCtx = null;
    }
  }

  getAmplitude() {
    if (!this.analyser) return 0;
    const data = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteFrequencyData(data);
    let sum = 0;
    for (let i = 0; i < data.length; i++) sum += data[i];
    return sum / (data.length * 255);
  }
}

// ─── Recording Engine (Mic → 16kHz PCM → WebSocket) ─────────────────────────

class PcmRecorder {
  constructor(onChunk) {
    this.onChunk = onChunk; // called with ArrayBuffer (Int16 PCM at 16kHz)
    this.micCtx = null;
    this.mediaStream = null;
    this.workletNode = null;
    this.scriptProcessor = null;
    this.isRecording = false;
  }

  async start() {
    if (this.isRecording) return;

    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });

    this.mediaStream = stream;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    this.micCtx = new Ctx();
    const source = this.micCtx.createMediaStreamSource(stream);

    try {
      // Preferred: AudioWorklet (off main thread — accurate, no jank)
      await this.micCtx.audioWorklet.addModule('/audio-processor.js');
      this.workletNode = new AudioWorkletNode(this.micCtx, 'pcm16-processor');

      this.workletNode.port.onmessage = (e) => {
        if (!this.isRecording) return;
        this._sendFloat32(new Float32Array(e.data));
      };

      source.connect(this.workletNode);
      console.log('[PcmRecorder] AudioWorklet active (off-thread).');
    } catch (err) {
      console.warn('[PcmRecorder] AudioWorklet unavailable, using ScriptProcessor fallback:', err);
      // Fallback: ScriptProcessor (on main thread, deprecated but works everywhere)
      this.scriptProcessor = this.micCtx.createScriptProcessor(512, 1, 1);
      this.scriptProcessor.onaudioprocess = (e) => {
        if (!this.isRecording) return;
        this._sendFloat32(e.inputBuffer.getChannelData(0));
      };
      source.connect(this.scriptProcessor);
      this.scriptProcessor.connect(this.micCtx.destination);
    }

    this.isRecording = true;
  }

  _sendFloat32(float32Array) {
    // Convert Float32 [-1, 1] → Int16 PCM little-endian
    const pcm16 = new Int16Array(float32Array.length);
    for (let i = 0; i < float32Array.length; i++) {
      const s = Math.max(-1, Math.min(1, float32Array[i]));
      pcm16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }
    if (this.onChunk) {
      this.onChunk(pcm16.buffer);
    }
  }

  stop() {
    this.isRecording = false;

    if (this.workletNode) {
      this.workletNode.disconnect();
      this.workletNode = null;
    }
    if (this.scriptProcessor) {
      this.scriptProcessor.disconnect();
      this.scriptProcessor = null;
    }
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((t) => t.stop());
      this.mediaStream = null;
    }
    if (this.micCtx) {
      this.micCtx.close();
      this.micCtx = null;
    }
  }
}

export { PcmPlayer, PcmRecorder };
