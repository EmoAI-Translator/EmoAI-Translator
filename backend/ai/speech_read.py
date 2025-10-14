import asyncio
import edge_tts
import os

async def speak_text_edge(text, voice="ko-KR-SunHiNeural"):
    output_path = "tts_edge.mp3"
    communicate = edge_tts.Communicate(text, voice=voice)
    await communicate.save(output_path)
    os.system(f"open {output_path}")  # macOS에서 자동 실행

# Example
asyncio.run(speak_text_edge("이 문장을 한국어로 읽어드릴게요."))