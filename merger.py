#!/usr/bin/env python3
"""Local, bounded-memory media muxer. JSON-lines protocol for the native app."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time


class Cancelled(Exception):
    pass


class Merger:
    def __init__(self):
        self.cancelled = threading.Event()
        self.child = None
        self.committing = False

    def emit(self, event, **fields):
        print(json.dumps(dict(event=event, **fields), ensure_ascii=False), flush=True)

    def cancel(self, *_):
        if self.committing:
            return  # The final atomic save has begun; report its actual outcome.
        self.cancelled.set()
        child = self.child
        if child is not None and child.poll() is None:
            child.terminate()
            def stop():
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
            threading.Thread(target=stop, daemon=True).start()

    def checkpoint(self):
        if self.cancelled.is_set():
            raise Cancelled()

    def tool(self, name):
        for path in [shutil.which(name), '/opt/homebrew/bin/' + name,
                     '/usr/local/bin/' + name]:
            if path and os.access(path, os.X_OK):
                return path
        raise ValueError('找不到 ' + name + '。请先安装 FFmpeg（brew install ffmpeg）。')

    def probe(self, path):
        self.checkpoint()
        args = [self.tool('ffprobe'), '-v', 'error', '-show_entries',
                'format=duration,size:stream=codec_type,codec_name,width,height,channels,sample_rate,duration',
                '-of', 'json', str(path)]
        self.child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            try:
                out, err = self.child.communicate(timeout=90)
            except subprocess.TimeoutExpired:
                self.child.kill()
                self.child.communicate()
                raise ValueError('读取媒体信息超时。请确认文件已下载到本机，并检查磁盘是否正常。')
            self.checkpoint()
            if self.child.returncode:
                raise ValueError('无法识别文件：' + str(path) + '\n' +
                                 err.decode('utf-8', 'replace')[-2400:] +
                                 '\n如果是特殊 B 站缓存文件头，请先修复副本；本工具不会修改源文件。')
            return json.loads(out)
        finally:
            self.child = None

    def inspect_pair(self, video, audio):
        video, audio = Path(video).expanduser().resolve(), Path(audio).expanduser().resolve()
        for path in [video, audio]:
            if not path.is_file() or not os.access(path, os.R_OK):
                raise ValueError('文件不存在或无法读取：' + str(path))
            if path.stat().st_size == 0:
                raise ValueError('文件为空：' + str(path))
        if os.path.samefile(video, audio):
            raise ValueError('视频和音频选择了同一个文件，请重新选择。')
        vi, ai = self.probe(video), self.probe(audio)
        vs = next((s for s in vi.get('streams', []) if s.get('codec_type') == 'video'), None)
        au = next((s for s in ai.get('streams', []) if s.get('codec_type') == 'audio'), None)
        if vs is None:
            raise ValueError('视频文件中没有视频轨道，请检查是否选反了文件。')
        if au is None:
            raise ValueError('音频文件中没有音频轨道，请检查是否选反了文件。')
        vd = float(vs.get('duration') or vi.get('format', {}).get('duration') or 0)
        ad = float(au.get('duration') or ai.get('format', {}).get('duration') or 0)
        if min(vd, ad) <= 0:
            raise ValueError('无法确定完整时长，请检查文件是否下载完成。')
        if abs(vd - ad) > max(5, min(vd, ad) * 0.01):
            raise ValueError('音视频时长相差过大，可能不是同一段内容：视频 %.1f 秒，音频 %.1f 秒。' % (vd, ad))
        info = dict(video=str(video), audio=str(audio), video_bytes=video.stat().st_size,
                    audio_bytes=audio.stat().st_size, video_codec=vs['codec_name'],
                    audio_codec=au['codec_name'], width=vs.get('width', 0), height=vs.get('height', 0),
                    channels=au.get('channels', 0), duration=max(vd, ad),
                    video_duration=vd, audio_duration=ad)
        self.emit('info', **info)
        return info

    def merge(self, video, audio, output):
        temp_path = None
        started = time.monotonic()
        try:
            self.emit('status', message='正在检查文件与可用空间…')
            info = self.inspect_pair(video, audio)
            output = Path(output).expanduser().absolute()
            if output.suffix.lower() != '.mp4':
                raise ValueError('输出文件的扩展名需要是 .mp4。')
            if output.exists() or output.is_symlink():
                raise ValueError('输出文件已经存在。请改一个文件名，已有文件不会被覆盖。')
            if not output.parent.is_dir():
                raise ValueError('输出文件夹不存在，请重新选择保存位置。')
            required = int((info['video_bytes'] + info['audio_bytes']) * 1.05) + 64 * 1024 * 1024
            if shutil.disk_usage(output.parent).free < required:
                raise ValueError('可用空间不足。本次建议至少保留 %.2f GB 空间。' % (required / 1e9))
            # A private directory on the output volume permits an atomic, no-overwrite final link.
            with tempfile.TemporaryDirectory(prefix='.m4s-merge-', dir=output.parent) as temp_dir:
                # Check the destination before spending time writing a large output.
                source_check = Path(temp_dir) / 'save-check'
                target_check = Path(temp_dir) / 'save-check-link'
                source_check.touch()
                try:
                    os.link(source_check, target_check)
                except OSError as exc:
                    raise ValueError('这个保存位置不支持安全保存，或没有足够的写入权限。'
                                     '请选择 Mac 内置磁盘上的可写文件夹。\n' + str(exc)) from exc
                target_check.unlink()
                source_check.unlink()
                temp_path = Path(temp_dir) / 'result.mp4'
                args = [self.tool('ffmpeg'), '-hide_banner', '-nostdin', '-n', '-v', 'error',
                        '-i', info['video'], '-i', info['audio'],
                        '-map', '0:v:0', '-map', '1:a:0', '-c', 'copy']
                if info['video_codec'] == 'hevc':
                    args += ['-tag:v', 'hvc1']
                args += ['-progress', 'pipe:1', '-stats_period', '0.25', str(temp_path)]
                self.checkpoint()
                self.emit('status', message='正在合并，保留原有画质与音质…')
                with tempfile.TemporaryFile() as errors:
                    self.child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=errors,
                                                  text=True, encoding='utf-8', errors='replace', bufsize=1)
                    self.checkpoint()
                    values = {}
                    for line in self.child.stdout:
                        key, _, value = line.strip().partition('=')
                        values[key] = value
                        if key == 'progress':
                            seconds = max(0, float(values.get('out_time_us', 0)) / 1e6)
                            fraction = min(0.99, seconds / info['duration'])
                            self.emit('progress', fraction=fraction, speed=values.get('speed', ''),
                                      elapsed=time.monotonic() - started,
                                      bytes=int(values.get('total_size', 0) or 0))
                        if self.cancelled.is_set():
                            self.cancel()
                    code = self.child.wait()
                    self.child = None
                    self.checkpoint()
                    if code:
                        errors.seek(0, os.SEEK_END)
                        length = errors.tell()
                        errors.seek(max(0, length - 6000))
                        raise ValueError('合并失败：\n' + errors.read().decode('utf-8', 'replace'))
                self.emit('status', message='正在检查输出的音视频轨道…')
                result = self.probe(temp_path)
                streams = result.get('streams', [])
                rv = next((s for s in streams if s.get('codec_type') == 'video'), None)
                ra = next((s for s in streams if s.get('codec_type') == 'audio'), None)
                if rv is None or ra is None:
                    raise ValueError('输出文件缺少音频或视频轨道，未保存最终文件。')
                for stream, expected, codec in [(rv, info['video_duration'], info['video_codec']),
                                                (ra, info['audio_duration'], info['audio_codec'])]:
                    if stream.get('codec_name') != codec or abs(float(stream.get('duration', 0)) - expected) > 2:
                        raise ValueError('输出轨道信息与输入不一致，未保存最终文件。')
                self.checkpoint()
                self.committing = True
                self.checkpoint()
                self.emit('status', message='正在保存最终文件，请稍候…', cancellable=False)
                # os.link is atomic and refuses an existing destination, including a racing writer.
                while True:
                    try:
                        os.link(temp_path, output)
                        break
                    except InterruptedError:
                        if output.exists() and os.path.samefile(temp_path, output):
                            break
                size = output.stat().st_size
            self.emit('done', output=str(output), bytes=size, elapsed=time.monotonic() - started)
            return 0
        except Cancelled:
            self.emit('cancelled', message='已取消，临时文件已清理。源文件未改动。')
            return 2
        except Exception as exc:
            if self.cancelled.is_set():
                self.emit('cancelled', message='已取消，临时文件已清理。源文件未改动。')
                return 2
            self.emit('error', message=str(exc))
            return 1
        finally:
            if self.child is not None and self.child.poll() is None:
                self.child.kill()
                self.child.wait()
            self.child = None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--video', required=True)
    parser.add_argument('--audio', required=True)
    parser.add_argument('--output')
    parser.add_argument('--inspect', action='store_true')
    args = parser.parse_args()
    merger = Merger()
    signal.signal(signal.SIGTERM, merger.cancel)
    signal.signal(signal.SIGINT, merger.cancel)
    if args.inspect:
        try:
            merger.inspect_pair(args.video, args.audio)
            return 0
        except Cancelled:
            merger.emit('cancelled', message='已取消检查。')
            return 2
        except Exception as exc:
            merger.emit('error', message=str(exc))
            return 1
    if not args.output:
        parser.error('--output is required for merging')
    return merger.merge(args.video, args.audio, args.output)


if __name__ == '__main__':
    sys.exit(main())
