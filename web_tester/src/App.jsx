import React, { useState, useEffect, useRef } from 'react';
import { PcmPlayer, PcmRecorder } from './services/audioProcessor';
import { 
  Mic, 
  MicOff, 
  Activity, 
  Database, 
  Wifi, 
  WifiOff, 
  Sparkles, 
  RefreshCw, 
  Server, 
  Volume2, 
  Trash2,
  CheckCircle2,
  AlertCircle
} from 'lucide-react';

const ENDPOINTS = [
  {
    name: 'Render Cloud (Live)',
    wsUrl: 'wss://voice-buddy-relay.onrender.com/ws/audio',
    httpUrl: 'https://voice-buddy-relay.onrender.com',
  },
  {
    name: 'Localhost (Port 8000)',
    wsUrl: 'ws://localhost:8000/ws/audio',
    httpUrl: 'http://localhost:8000',
  },
];

export default function App() {
  const [selectedEndpoint, setSelectedEndpoint] = useState(ENDPOINTS[0]);
  const [connectionStatus, setConnectionStatus] = useState('disconnected'); // disconnected, connecting, connected, error
  const [avatarState, setAvatarState] = useState('idle'); // idle, listening, talking
  const [liveSubtitle, setLiveSubtitle] = useState('');
  const [logs, setLogs] = useState([]);
  const [stats, setStats] = useState({
    chunksSent: 0,
    chunksReceived: 0,
    healthLatency: null,
    backendStatus: null,
  });

  const wsRef = useRef(null);
  const pcmPlayerRef = useRef(null);
  const pcmRecorderRef = useRef(null);
  const canvasRef = useRef(null);
  const animFrameRef = useRef(null);
  const reconnectTimeoutRef = useRef(null);

  // Helper to append diagnostic logs
  const addLog = (tag, msg) => {
    const time = new Date().toLocaleTimeString();
    setLogs((prev) => [{ id: Math.random(), time, tag, msg }, ...prev.slice(0, 99)]);
  };

  // Initialize Audio Player
  useEffect(() => {
    pcmPlayerRef.current = new PcmPlayer();
    addLog('audio', 'Audio playback engine initialized (24kHz PCM).');

    // Visualizer animation loop
    const renderVisualizer = () => {
      const canvas = canvasRef.current;
      if (canvas) {
        const ctx = canvas.getContext('2d');
        const amp = pcmPlayerRef.current ? pcmPlayerRef.current.getAmplitude() : 0;
        
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = avatarState === 'talking' ? '#6366f1' : avatarState === 'listening' ? '#22c55e' : '#334155';
        
        const numBars = 32;
        const barWidth = canvas.width / numBars;
        for (let i = 0; i < numBars; i++) {
          const height = Math.max(4, Math.sin((i / numBars) * Math.PI) * (amp * canvas.height * 2.5) + (avatarState === 'listening' ? 8 : 2));
          ctx.fillRect(i * barWidth + 2, (canvas.height - height) / 2, barWidth - 4, height);
        }
      }
      animFrameRef.current = requestAnimationFrame(renderVisualizer);
    };
    renderVisualizer();

    return () => {
      if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
      if (pcmPlayerRef.current) pcmPlayerRef.current.stop();
      if (pcmRecorderRef.current) pcmRecorderRef.current.stop();
    };
  }, [avatarState]);

  // Connect WebSocket
  const connectWs = (endpoint = selectedEndpoint) => {
    // Clear any pending reconnect timer first
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    // Kill old socket WITHOUT triggering its onclose reconnect
    if (wsRef.current) {
      wsRef.current.onclose = null; // ← prevents old socket from scheduling another reconnect
      wsRef.current.onerror = null;
      wsRef.current.close();
      wsRef.current = null;
    }

    setConnectionStatus('connecting');
    addLog('ws', `Connecting to ${endpoint.wsUrl}...`);

    try {
      const ws = new WebSocket(endpoint.wsUrl);
      ws.binaryType = 'arraybuffer';
      wsRef.current = ws;

      ws.onopen = () => {
        addLog('ws', 'WebSocket connection established. Waiting for Gemini Live handshake...');
      };

      ws.onmessage = (event) => {
        if (event.data instanceof ArrayBuffer) {
          // Binary 24kHz PCM audio chunk from Gemini Live
          const uint8 = new Uint8Array(event.data);
          setStats((s) => ({ ...s, chunksReceived: s.chunksReceived + 1 }));
          setAvatarState('talking');
          if (pcmPlayerRef.current) {
            pcmPlayerRef.current.playChunk(uint8);
          }
        } else if (typeof event.data === 'string') {
          try {
            const data = JSON.parse(event.data);
            if (data.type === 'ping') {
              // Server keepalive - ignore silently
            } else if (data.type === 'status' && data.status === 'ready') {
              setConnectionStatus('connected');
              setAvatarState('idle');
              addLog('gemini', 'Gemini Live Ready! Anvi will greet you now...');
            } else if (data.type === 'clear_audio') {
              // Reference pattern: barge-in detected — flush audio queue immediately
              if (pcmPlayerRef.current) pcmPlayerRef.current.clearQueue();
              setAvatarState('idle');
              addLog('gemini', 'Barge-in — audio queue cleared.');
            } else if (data.type === 'turn_complete') {
              addLog('gemini', 'Anvi finished speaking.');
              setAvatarState('idle');
            } else if (data.type === 'transcript') {
              setLiveSubtitle(data.text);
              addLog('gemini', `Transcript: "${data.text}"`);
            }
          } catch (e) {
            addLog('ws', `Message: ${event.data}`);
          }
        }
      };

      ws.onerror = () => {
        addLog('err', 'WebSocket connection error occurred.');
      };

      ws.onclose = () => {
        // Only reconnect if this is still the current socket (not already replaced)
        if (wsRef.current !== ws) return;
        setConnectionStatus('disconnected');
        setAvatarState('idle');
        addLog('ws', 'WebSocket disconnected. Will retry in 4s...');
        reconnectTimeoutRef.current = setTimeout(() => {
          connectWs(endpoint);
        }, 4000);
      };
    } catch (e) {
      setConnectionStatus('error');
      addLog('err', `Failed to open WebSocket: ${e.message}`);
    }
  };

  // Disconnect WebSocket
  const disconnectWs = () => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (pcmRecorderRef.current) {
      pcmRecorderRef.current.stop();
      pcmRecorderRef.current = null;
    }
    if (pcmPlayerRef.current) {
      pcmPlayerRef.current.stop();
    }
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    setConnectionStatus('disconnected');
    setAvatarState('idle');
  };

  // Toggle Live Microphone Talk
  const toggleListening = async () => {
    if (connectionStatus !== 'connected') {
      connectWs(selectedEndpoint);
      return;
    }

    if (avatarState === 'listening') {
      // Stop recording
      if (pcmRecorderRef.current) {
        pcmRecorderRef.current.stop();
        pcmRecorderRef.current = null;
      }
      if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({ type: 'end_of_turn' }));
      }
      setAvatarState('idle');
      addLog('audio', 'Microphone paused. Sent end_of_turn signal.');
    } else {
      // Start recording
      if (pcmPlayerRef.current) {
        pcmPlayerRef.current.stop();
      }
      try {
        pcmRecorderRef.current = new PcmRecorder((pcm16Buffer) => {
          if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
            wsRef.current.send(pcm16Buffer);
            setStats((s) => ({ ...s, chunksSent: s.chunksSent + 1 }));
          }
        });
        await pcmRecorderRef.current.start();
        setAvatarState('listening');
        addLog('audio', 'Microphone active! Streaming 16kHz PCM chunks live...');
      } catch (err) {
        addLog('err', `Microphone permission error: ${err.message}`);
        alert(`Microphone error: ${err.message}`);
      }
    }
  };

  // Test REST Backend Health
  const checkHealth = async () => {
    const start = performance.now();
    addLog('db', `Checking ${selectedEndpoint.httpUrl}/health...`);
    try {
      const res = await fetch(`${selectedEndpoint.httpUrl}/health`);
      const latency = Math.round(performance.now() - start);
      const data = await res.json();
      setStats((s) => ({ ...s, healthLatency: latency, backendStatus: data.status }));
      addLog('db', `Backend Health 200 OK (${latency}ms): ${JSON.stringify(data)}`);
    } catch (e) {
      setStats((s) => ({ ...s, healthLatency: null, backendStatus: 'failed' }));
      addLog('err', `Health check failed: ${e.message}`);
    }
  };

  // Auto-connect on mount
  useEffect(() => {
    connectWs(selectedEndpoint);
    return () => disconnectWs();
  }, [selectedEndpoint]);

  return (
    <div className="app-container">
      {/* Top Header */}
      <header className="app-header glass-panel">
        <div className="brand">
          <div className="brand-icon">
            <Sparkles size={22} color="#ffffff" />
          </div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span className="brand-title">Anvi Voice Buddy</span>
              <span className="brand-tag">Web Test Studio</span>
            </div>
          </div>
        </div>

        <div className="header-actions">
          {/* Target Backend Select */}
          <select
            className="target-select"
            value={selectedEndpoint.wsUrl}
            onChange={(e) => {
              const ep = ENDPOINTS.find((item) => item.wsUrl === e.target.value);
              if (ep) {
                setSelectedEndpoint(ep);
              }
            }}
          >
            {ENDPOINTS.map((ep) => (
              <option key={ep.wsUrl} value={ep.wsUrl}>
                {ep.name}
              </option>
            ))}
          </select>

          {/* Connection Status Badge */}
          <div className={`status-badge ${connectionStatus}`}>
            <span className="status-dot" />
            <span>
              {connectionStatus === 'connected'
                ? 'Relay Connected'
                : connectionStatus === 'connecting'
                ? 'Connecting...'
                : 'Offline'}
            </span>
          </div>

          {connectionStatus === 'connected' ? (
            <button className="btn-sm" onClick={disconnectWs}>
              <WifiOff size={14} /> Disconnect
            </button>
          ) : (
            <button className="btn-sm btn-primary" onClick={() => connectWs(selectedEndpoint)}>
              <RefreshCw size={14} /> Reconnect
            </button>
          )}
        </div>
      </header>

      {/* Main Grid */}
      <main className="main-grid">
        {/* Left Column: Live Avatar & Voice Stage */}
        <section className="glass-panel voice-stage">
          {/* Avatar Face */}
          <div className="avatar-container">
            <div className={`avatar-body ${avatarState}`}>
              <div className="avatar-eyes">
                <div className="avatar-eye" />
                <div className="avatar-eye" />
              </div>
              <div className="avatar-cheeks">
                <div className="avatar-cheek" />
                <div className="avatar-cheek" />
              </div>
              <div className="avatar-mouth" />
            </div>
          </div>

          {/* Status text */}
          <h2 className="conversation-status-text">
            {avatarState === 'listening'
              ? '🎙️ Listening to you... (Tap to Pause)'
              : avatarState === 'talking'
              ? '🔊 Anvi is speaking...'
              : connectionStatus === 'connected'
              ? '✨ Anvi is ready! Tap below to speak'
              : '⚡ Connecting to Gemini Live relay...'}
          </h2>

          {/* Live Subtitle Box */}
          <div className="live-transcript-box">
            {liveSubtitle || 'Subtitles and conversation transcripts will stream here in real time...'}
          </div>

          {/* Single-Tap Call Toggle Button */}
          <button
            className={`mic-btn ${avatarState === 'listening' ? 'active' : ''}`}
            onClick={toggleListening}
            title={avatarState === 'listening' ? 'Tap to Pause' : 'Tap to Speak'}
          >
            {avatarState === 'listening' ? <Mic size={38} /> : <MicOff size={34} />}
          </button>
          <span className="mic-hint">Single-tap to start or pause live voice</span>

          {/* Real-time Oscilloscope */}
          <div style={{ width: '100%', maxWidth: '420px', marginTop: '24px' }}>
            <canvas ref={canvasRef} className="visualizer-canvas" width={420} height={48} />
          </div>
        </section>

        {/* Right Column: Diagnostic & API Testing Tools */}
        <section className="tools-panel">
          {/* Diagnostic Metrics Card */}
          <div className="glass-panel diag-card">
            <div className="panel-title">
              <Activity size={18} color="#6366f1" /> API & Relay Diagnostics
            </div>

            <div className="diag-row">
              <span className="diag-label">Active Backend</span>
              <span className="diag-value mono" style={{ fontSize: 11 }}>
                {selectedEndpoint.wsUrl}
              </span>
            </div>

            <div className="diag-row">
              <span className="diag-label">Live Gemini Model</span>
              <span className="diag-value" style={{ color: '#818cf8' }}>
                gemini-2.5-flash-native-audio-latest
              </span>
            </div>

            <div className="diag-row">
              <span className="diag-label">REST Health Status</span>
              <span className="diag-value">
                {stats.healthLatency !== null ? (
                  <span style={{ color: '#4ade80', display: 'flex', alignItems: 'center', gap: 4 }}>
                    <CheckCircle2 size={14} /> {stats.healthLatency}ms latency
                  </span>
                ) : (
                  <span style={{ color: '#94a3b8' }}>Untested</span>
                )}
              </span>
            </div>

            <div className="diag-row">
              <span className="diag-label">Audio Frames Streamed</span>
              <span className="diag-value mono">
                ↑ {stats.chunksSent} sent / ↓ {stats.chunksReceived} received
              </span>
            </div>

            <div style={{ display: 'flex', gap: 10, marginTop: 6 }}>
              <button className="btn-sm" onClick={checkHealth}>
                <Server size={14} /> Ping /health
              </button>
              <button
                className="btn-sm"
                onClick={() => {
                  window.open(`${selectedEndpoint.httpUrl}/admin/dashboard`, '_blank');
                }}
              >
                <Database size={14} /> Open DB Dashboard
              </button>
            </div>
          </div>

          {/* Live Event Stream Logs Card */}
          <div className="glass-panel" style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
            <div className="panel-header">
              <div className="panel-title">
                <Volume2 size={16} color="#ec4899" /> Real-time Event Stream
              </div>
              <button className="btn-sm" onClick={() => setLogs([])}>
                <Trash2 size={12} /> Clear
              </button>
            </div>

            <div className="logs-container" style={{ margin: '14px', flex: 1, minHeight: '220px' }}>
              {logs.length === 0 ? (
                <div style={{ color: '#64748b', textAlign: 'center', padding: '20px' }}>
                  No events yet. Connect or tap mic to start streaming.
                </div>
              ) : (
                logs.map((log) => (
                  <div key={log.id} className="log-entry">
                    <span className="log-time mono">{log.time}</span>
                    <span className={`log-tag ${log.tag}`}>{log.tag}</span>
                    <span className="log-msg mono">{log.msg}</span>
                  </div>
                ))
              )}
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
