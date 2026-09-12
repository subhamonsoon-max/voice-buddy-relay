// Audio processing utilities for 16kHz PCM recording and 24kHz PCM playback

class PcmPlayer {
  constructor() {
    this.audioCtx = null;
    this.nextStartTime = 0;
    this.isPlaying = false;
    this.analyser = null;
  }

  init() {
    if (!this.audioCtx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      this.audioCtx = new AudioContextClass({ sampleRate: 24000 });
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 128;
      this.analyser.connect(this.audioCtx.destination);
    }
    if (this.audioCtx.state === 'suspended') {
      this.audioCtx.resume();
    }
  }

  playChunk(pcm16Data) {
    this.init();
    if (!pcm16Data || pcm16Data.byteLength === 0) return;

    // Convert Int16 bytes (little-endian) to Float32 (-1.0 to 1.0)
    const int16 = new Int16Array(
      pcm16Data.buffer,
      pcm16Data.byteOffset,
      pcm16Data.byteLength / 2
    );

    const float32 = new Float32Array(int16.length);
    for (let i = 0; i < int16.length; i++) {
      float32[i] = int16[i] / 32768.0;
    }

    const audioBuffer = this.audioCtx.createBuffer(1, float32.length, 24000);
    audioBuffer.copyToChannel(float32, 0);

    const source = this.audioCtx.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(this.analyser);

    const currentTime = this.audioCtx.currentTime;
    if (this.nextStartTime < currentTime) {
      this.nextStartTime = currentTime;
    }

    source.start(this.nextStartTime);
    this.nextStartTime += audioBuffer.duration;
    this.isPlaying = true;

    source.onended = () => {
      if (this.audioCtx && this.audioCtx.currentTime >= this.nextStartTime - 0.05) {
        this.isPlaying = false;
      }
    };
  }

  stop() {
    if (this.audioCtx) {
      this.audioCtx.close();
      this.audioCtx = null;
      this.nextStartTime = 0;
      this.isPlaying = false;
    }
  }

  getAmplitude() {
    if (!this.analyser) return 0;
    const data = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteFrequencyData(data);
    let sum = 0;
    for (let i = 0; i < data.length; i++) {
      sum += data[i];
    }
    return sum / (data.length * 255);
  }
}

class PcmRecorder {
  constructor(onChunk) {
    this.onChunk = onChunk;
    this.audioCtx = null;
    this.mediaStream = null;
    this.processor = null;
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
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    this.audioCtx = new AudioContextClass();

    const source = this.audioCtx.createMediaStreamSource(stream);
    // Buffer size 2048 or 4096
    this.processor = this.audioCtx.createScriptProcessor(4096, 1, 1);

    const inputSampleRate = this.audioCtx.sampleRate;
    const targetSampleRate = 16000;

    this.processor.onaudioprocess = (e) => {
      if (!this.isRecording) return;
      const inputData = e.inputBuffer.getChannelData(0);

      // Resample from inputSampleRate (e.g. 48000 or 44100) down to 16000
      const resampledData = this._resample(inputData, inputSampleRate, targetSampleRate);

      // Convert Float32Array to 16-bit Signed Little-Endian PCM ArrayBuffer
      const pcm16 = new Int16Array(resampledData.length);
      for (let i = 0; i < resampledData.length; i++) {
        const s = Math.max(-1, Math.min(1, resampledData[i]));
        pcm16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
      }

      if (this.onChunk) {
        this.onChunk(pcm16.buffer);
      }
    };

    source.connect(this.processor);
    this.processor.connect(this.audioCtx.destination);
    this.isRecording = true;
  }

  _resample(input, fromRate, toRate) {
    if (fromRate === toRate) return input;
    const ratio = fromRate / toRate;
    const outputLength = Math.round(input.length / ratio);
    const output = new Float32Array(outputLength);

    for (let i = 0; i < outputLength; i++) {
      const srcIndex = i * ratio;
      const indexFloor = Math.floor(srcIndex);
      const indexCeil = Math.min(input.length - 1, indexFloor + 1);
      const weight = srcIndex - indexFloor;
      output[i] = input[indexFloor] * (1 - weight) + input[indexCeil] * weight;
    }
    return output;
  }

  stop() {
    this.isRecording = false;
    if (this.processor) {
      this.processor.disconnect();
      this.processor = null;
    }
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((track) => track.stop());
      this.mediaStream = null;
    }
    if (this.audioCtx) {
      this.audioCtx.close();
      this.audioCtx = null;
    }
  }
}

export { PcmPlayer, PcmRecorder };
