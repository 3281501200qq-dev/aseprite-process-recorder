# Aseprite Process Recorder

[简体中文](README.md) · [日本語](README.ja.md)

Current version: `v0.8.3`. Windows x64 extension for recording visible drawing changes and exporting Aseprite process files or H.264 MP4 video.

## What makes it different

- Three capture modes: Complete records every visible change; Automatic records every change on canvases up to 65,536 pixels and merges rapid events on larger canvases; Performance merges more rapid events for large or long recordings.
- A disk-based 64×64 tile difference journal avoids keeping full frames in memory or generating a PNG sequence.
- The native helper reconstructs frames and streams video directly to a separate FFmpeg process. FFmpeg runs only when exporting MP4.
- Segmented journals, checkpoints, an adjustable memory budget, and split process files support longer recordings.
- Real event timestamps are retained. Playback can be set to 1x, 2x, 5x, or 10x.
- On Windows, the Aseprite process file is generated in the background when recording stops. MP4 export remains synchronous.
- One installer includes both the extension and FFmpeg; no separate download is required.

Automatic and Performance modes capture the final image when recording stops. Performance mode can omit intermediate states that last only briefly. Choose Complete mode if every change matters.

## Install

Download [`aseprite-process-recorder-0.8.3-windows-x64-multilingual-setup.exe`](https://github.com/3281501200qq-dev/aseprite-process-recorder/releases/latest), close Aseprite, run the installer, and restart Aseprite. The `.aseprite-extension` attachment contains only the extension and does not include FFmpeg.

The extension is installed in `%APPDATA%\Aseprite\extensions\aseprite-process-recorder`. FFmpeg is installed separately in `%LOCALAPPDATA%\Programs\Aseprite Process Recorder\FFmpeg`.

## Language and recording

Choose Simplified Chinese, English, or Japanese in **Process Recorder → Language / 语言 / 言語** or in Recorder Settings. The choice persists. Messages change immediately; restart Aseprite to update menu titles. New installations default to Simplified Chinese.

Recording starts automatically when you open or switch to a canvas. The menu's auto-start toggle disables this persistently; manual Start Recording still works. Your artwork, recordings, and videos are preserved when updating or uninstalling.

See the [v0.8.3 release notes](RELEASE_NOTES_v0.8.3.md) and [build instructions](BUILDING.md). The extension code is MIT licensed. The separately installed FFmpeg is GPLv3; exact build and source information are in [third-party notices](installer/licenses/THIRD-PARTY-NOTICES.txt).
