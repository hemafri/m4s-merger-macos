# M4S 合并器 · macOS

![应用图标](assets/icon.png)

把分离的视频和音频文件合并成一个 MP4 的本机工具。使用 Swift / AppKit 原生界面，调用本机 FFmpeg 复制音视频轨道，不重新编码，也不上传文件。

## 功能

- 选择文件或粘贴路径，检查编码、时长、分辨率与文件大小。
- 直接复制视频和音频轨道，保留原有画质与音质，适合大文件。
- 显示进度，支持取消、临时文件清理和处理记录。
- 保留源文件，拒绝覆盖已有输出，开始前检查空间和保存位置。
- 完成后检查输出轨道、编码和时长，可直接播放或在 Finder 中显示。
- 每次启动时三个路径字段都为空，不保存上次使用的文件路径。

## 安装和使用

发布包适用于 **Apple 芯片 Mac**，最低部署目标为 macOS 13。其他系统版本与 Intel Mac 尚未进行实际运行验证。

1. 安装 **Python 3** 和 **FFmpeg / ffprobe**。已安装 Homebrew 的用户可以运行：

   ```sh
   brew install python ffmpeg
   ```

2. 从 [Releases](https://github.com/hemafri/m4s-merger-macos/releases) 下载应用 ZIP 并解压，打开 `M4S合并器.app`。
3. 选择视频和音频文件，再选择输出 MP4 的保存位置，点击「开始合并」。

应用不会捆绑 Python 或 FFmpeg。它会检查 Homebrew 常见安装位置，以及 Python 官方安装包的 Current 路径。发布包使用本机临时签名，**未经过 Apple 公证**；macOS 可能阻止直接打开。如果需要经过公证的安装包，当前发布版本尚不提供。

## 兼容性与限制

- 适用于包含完整媒体信息、可被 FFmpeg 直接读取的文件；扩展名为 `.m4s` 并不保证内容完整。
- **不会修复特殊 B 站缓存文件头，也不会解密文件。** 带自定义前缀、缺少初始化数据或下载不完整的缓存可能无法读取。
- 音视频应来自同一内容。工具会拒绝明显的时长不匹配，但不会自动校正素材原本存在的音画偏移。
- 输出为 MP4，所选编码须能写入 MP4。HEVC 视频使用 `hvc1` 标记，以改善 Apple 播放器兼容性。
- 另需接近输入文件大小之和的磁盘空间，并留有余量。处理会写入临时文件，成功后才保存最终文件。
- 保存位置需要支持硬链接；不支持的目标磁盘会在开始处理前提示更换位置。
- 最终保存阶段会短暂禁用取消。此前取消会清理临时文件。
- 为避免再次遍历大文件，当前不启用 `faststart` 优化，主要用于本地文件播放。
- 输出检查包括音视频轨道、编码和时长，**不等于逐帧完整解码验证**。

## 从源码构建

需要 Xcode Command Line Tools：

```sh
xcode-select --install
git clone https://github.com/hemafri/m4s-merger-macos.git
cd m4s-merger-macos
zsh build.sh
```

应用生成在 `dist/M4S合并器.app`。构建脚本使用当前电脑的 CPU 架构，不会自动生成 Universal 二进制。运行应用仍需要 Python 3 和 FFmpeg。

## 源码

| 文件 | 用途 |
| --- | --- |
| `Main.swift` | 原生窗口、文件选择、状态和进度 |
| `merger.py` | 媒体检查、合并、取消和输出验证 |
| `Info.plist` | 应用元信息 |
| `AppIcon.icns` | 多尺寸应用图标 |
| `GenerateIcon.swift` | 图标的矢量绘制源 |
| `build.sh` | 编译、打包和本机签名 |

后端也可以单独运行：

```sh
python3 merger.py --video '/path/to/video.m4s' \
  --audio '/path/to/audio.m4s' --output '/path/to/merged.mp4'
```

重新生成图标：

```sh
mkdir -p work
swift GenerateIcon.swift work/AppIcon.iconset
iconutil -c icns work/AppIcon.iconset -o AppIcon.icns
```

## 已验证范围

在 Apple 芯片 Mac 上测试过约 8.5 GB 的 4K HEVC 视频与 AAC 音频合并，并核对了输出轨道和时长。取消清理、已有输出保护、相同文件和错误轨道输入也经过检查。仓库和发行包不包含测试媒体、用户路径或本机操作记录。
