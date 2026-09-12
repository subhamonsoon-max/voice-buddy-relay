import asyncio
import json
import logging
from typing import Optional, List, Tuple
from fastapi import WebSocket, WebSocketDisconnect
from google import genai
from google.genai import types

from app.config import settings
from app.prompt_builder import build_system_prompt

logger = logging.getLogger("voice_buddy.live")

class GeminiLiveRelay:
    """Relays bidirectional PCM audio between the mobile client and Google AI Studio Gemini Live."""

    def __init__(
        self,
        client_ws: WebSocket,
        facts: List[str],
        summaries: List[str],
    ):
        self.client_ws = client_ws
        self.facts = facts
        self.summaries = summaries
        self.transcript_entries: List[str] = []
        self._stop_event = asyncio.Event()

    async def run(self) -> str:
        """Starts bidirectional relay and returns the aggregated transcript upon completion."""
        system_prompt = build_system_prompt(
            facts=self.facts,
            summaries=self.summaries,
        )

        client = genai.Client(api_key=settings.GEMINI_API_KEY, vertexai=False)
        model_name = (
            settings.LIVE_MODEL
            if settings.LIVE_MODEL.startswith("models/")
            else f"models/{settings.LIVE_MODEL}"
        )

        config = types.LiveConnectConfig(
            response_modalities=[types.Modality.AUDIO],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=settings.VOICE_NAME
                    )
                )
            ),
            system_instruction=types.Content(
                parts=[types.Part.from_text(text=system_prompt)]
            ),
        )

        logger.info(f"Connecting to Gemini Live API with model={model_name}, voice={settings.VOICE_NAME}")

        try:
            async with client.aio.live.connect(
                model=model_name,
                config=config,
            ) as session:
                logger.info("Connected to Gemini Live session. Starting audio pipes...")
                # Inform client that connection is ready
                await self.client_ws.send_text(
                    json.dumps({"type": "status", "status": "ready"})
                )

                task_in = asyncio.create_task(self._client_to_gemini(session))
                task_out = asyncio.create_task(self._gemini_to_client(session))
                task_ping = asyncio.create_task(self._ping_client())

                # Wait until one task terminates or stop event is set
                done, pending = await asyncio.wait(
                    [task_in, task_out, task_ping],
                    return_when=asyncio.FIRST_COMPLETED,
                )

                for task in pending:
                    task.cancel()

        except Exception as e:
            logger.error(f"Error in Gemini Live relay session: {e}", exc_info=True)
            try:
                await self.client_ws.send_text(
                    json.dumps({"type": "error", "message": str(e)})
                )
            except Exception:
                pass

        return "\n".join(self.transcript_entries)

    async def _ping_client(self) -> None:
        """Sends a lightweight ping to the client every 20s to prevent Render proxy from
        dropping idle WebSocket connections (Render drops idle WS after ~30s)."""
        try:
            while not self._stop_event.is_set():
                await asyncio.sleep(20)
                if self._stop_event.is_set():
                    break
                await self.client_ws.send_text(
                    json.dumps({"type": "ping"})
                )
                logger.debug("Sent keepalive ping to client.")
        except asyncio.CancelledError:
            pass
        except Exception:
            self._stop_event.set()

    async def _client_to_gemini(self, session) -> None:
        """Pipes incoming audio/messages from mobile client WebSocket to Gemini Live."""
        try:
            while not self._stop_event.is_set():
                message = await self.client_ws.receive()

                if "bytes" in message and message["bytes"]:
                    # Raw PCM audio frame from client microphone
                    pcm_chunk = message["bytes"]
                    await session.send_realtime_input(
                        media=types.Blob(
                            data=pcm_chunk,
                            mime_type="audio/pcm;rate=16000",
                        )
                    )
                elif "text" in message and message["text"]:
                    try:
                        data = json.loads(message["text"])
                        msg_type = data.get("type")

                        if msg_type == "end_of_turn" or msg_type == "hold_stop":
                            # Child finished speaking/released talk button
                            await session.send_client_content(turn_complete=True)
                            logger.debug("Sent turn_complete signal to Gemini")
                        elif msg_type == "interrupt":
                            # User interrupted
                            pass
                        elif msg_type == "text_turn":
                            # Child typed or sent text transcript directly
                            user_text = data.get("text", "")
                            if user_text:
                                self.transcript_entries.append(f"Child: {user_text}")
                                await session.send_client_content(
                                    turns=[
                                        types.Content(
                                            parts=[types.Part.from_text(text=user_text)],
                                            role="user",
                                        )
                                    ],
                                    turn_complete=True,
                                )
                    except json.JSONDecodeError:
                        logger.warning(f"Unrecognized text payload from client: {message['text']}")

        except WebSocketDisconnect:
            logger.info("Mobile client disconnected.")
            self._stop_event.set()
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Error in client_to_gemini pump: {e}")
            self._stop_event.set()

    async def _gemini_to_client(self, session) -> None:
        """Pipes Gemini Live response audio frames and transcript back to mobile client."""
        try:
            async for response in session.receive():
                if self._stop_event.is_set():
                    break

                server_content = response.server_content
                if not server_content:
                    continue

                if server_content.interrupted:
                    await self.client_ws.send_text(
                        json.dumps({"type": "interrupted"})
                    )
                    continue

                if server_content.model_turn:
                    for part in server_content.model_turn.parts:
                        # Audio chunk from Gemini
                        if part.inline_data and part.inline_data.data:
                            raw_audio = part.inline_data.data
                            # Send raw PCM audio binary frame to client
                            await self.client_ws.send_bytes(raw_audio)

                        # Text or thought from Gemini if present
                        if part.text:
                            self.transcript_entries.append(f"Anvi: {part.text}")
                            await self.client_ws.send_text(
                                json.dumps({"type": "transcript", "role": "model", "text": part.text})
                            )

                if server_content.turn_complete:
                    await self.client_ws.send_text(
                        json.dumps({"type": "turn_complete"})
                    )

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Error in gemini_to_client pump: {e}")
            self._stop_event.set()
