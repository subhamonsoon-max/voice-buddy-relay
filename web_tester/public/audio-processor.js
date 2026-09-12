/**
 * AudioWorklet processor for real-time 16kHz PCM capture.
 * Reference: D:\voice_refecrance\app\static\js\audio-processor.js
 * Runs on the dedicated audio rendering thread (off main JS thread).
 */
class Pcm16Processor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.targetSampleRate = 16000;
    this.buffer16k = [];
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];
    if (input && input.length > 0) {
      const inputSamples = input[0]; // 128 samples per WebAudio render block
      const nativeRate = sampleRate; // Hardware rate (48000 or 44100)

      if (Math.abs(nativeRate - this.targetSampleRate) < 100) {
        // Direct 16kHz pass-through (hardware already at 16kHz)
        for (let i = 0; i < inputSamples.length; i++) {
          this.buffer16k.push(inputSamples[i]);
        }
      } else {
        // Accurate downsampling from native hardware rate to 16000Hz
        const ratio = nativeRate / this.targetSampleRate;
        for (let i = 0; i < inputSamples.length; i += ratio) {
          const idx = Math.floor(i);
          if (idx < inputSamples.length) {
            this.buffer16k.push(inputSamples[idx]);
          }
        }
      }

      // Emit exact 512-sample blocks of 16kHz audio (32ms per block)
      while (this.buffer16k.length >= 512) {
        const block = new Float32Array(this.buffer16k.slice(0, 512));
        this.buffer16k = this.buffer16k.slice(512);
        this.port.postMessage(block.buffer, [block.buffer]);
      }
    }
    return true;
  }
}

registerProcessor('pcm16-processor', Pcm16Processor);
