"""可选的柔和普通话素材生成工具；只在生成时联网，游戏播放完全离线。"""
import argparse
import asyncio
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--dependency-dir', type=Path, help='可选的 edge-tts/imageio-ffmpeg 安装目录')
parser.add_argument('--sample-only', type=Path, help='只生成一段八筒试听 WAV')
parser.add_argument('--cached-mp3-dir', type=Path, help='复用同一声音参数的生成缓存')
args = parser.parse_args()
if args.dependency_dir:
    sys.path.insert(0, str(args.dependency_dir))
import edge_tts
import aiohttp
import imageio_ffmpeg
from generate_assets import AUDIO, RATE, build_assets, trim_voice

VOICES = ['zh-CN-XiaoxiaoNeural', 'zh-CN-YunxiNeural', 'zh-CN-XiaoyiNeural', 'zh-CN-YunyangNeural']
SOURCE = 'Microsoft Edge; four distinct Mandarin speakers; offline bundled WAV'
NUMBERS = '一二三四五六七八九'
PHRASES = {f'{suit}{rank}': ('幺鸡' if suit == 'tiao' and rank == 1 else NUMBERS[rank - 1] + suffix)
           for suit, suffix in [('wan', '万'), ('tiao', '条'), ('tong', '筒')] for rank in range(1, 10)}
PHRASES.update(pong='碰', kong='杠', ready='报听', hu='胡了', zimo='自摸')


async def synthesize(seat, key, text, directory, semaphore):
    async with semaphore:
        directory = directory / f'seat{seat}'
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / f'{key}.wav'
        mp3 = directory / f'{key}.mp3'
        for rate in ['-10%', '+0%', '+8%']:
            cache_root = (args.cached_mp3_dir if seat == 0 else args.cached_mp3_dir / f'seat{seat}') if args.cached_mp3_dir else None
            cached = cache_root / f'{key}.mp3' if cache_root else None
            if rate == '-10%' and cached and cached.exists():
                shutil.copyfile(cached, mp3)
            else:
                for attempt in range(8):
                    try:
                        async with aiohttp.TCPConnector(family=socket.AF_INET, force_close=True) as connector:
                            speaker = edge_tts.Communicate(text, VOICES[seat], rate=rate, pitch='-2Hz', volume='-8%',
                                                           connector=connector, connect_timeout=12, receive_timeout=20)
                            await speaker.save(str(mp3))
                        break
                    except Exception as error:
                        print(f'seat{seat}/{key}: retry {attempt + 1}: {type(error).__name__}', flush=True)
                        if attempt == 7:
                            raise
                        await asyncio.sleep(2 + attempt * 2)
            subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-v', 'error', '-y', '-i', str(mp3),
                            '-ac', '1', '-ar', str(RATE), '-c:a', 'pcm_s16le', str(target)], check=True)
            duration = trim_voice(target)
            if duration < .99:
                if cache_root:
                    cache_root.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(mp3, cache_root / f'{key}.mp3')
                print(f'seat{seat}/{key}: {duration:.3f}s ({rate})', flush=True)
                return target
        raise RuntimeError(f'{key} 语音超过一秒，保留原素材以便调整')


async def main():
    with tempfile.TemporaryDirectory(prefix='mahjong-soft-voice-') as directory:
        stage = Path(directory)
        semaphore = asyncio.Semaphore(1)
        if args.sample_only:
            target = await synthesize(0, 'tong8', '八筒', stage, semaphore)
            args.sample_only.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(target, args.sample_only)
            return
        paths = []
        for seat in range(4):
            for key, text in PHRASES.items():
                paths.append(await synthesize(seat, key, text, stage, semaphore))
        # 全套都生成成功才覆盖，网络失败时保留游戏现有素材。
        for path in paths:
            seat = int(path.parent.name[-1])
            destination = AUDIO / 'voice' if seat == 0 else AUDIO / 'voice' / f'seat{seat}'
            destination.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination / path.name)
        build_assets(SOURCE, voices_processed=True, speakers=VOICES)


if __name__ == '__main__':
    asyncio.run(main())
