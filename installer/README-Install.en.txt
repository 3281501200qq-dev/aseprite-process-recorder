Aseprite Process Recorder v0.8.3
================================

This Windows installer includes two separate components:

1. Aseprite Process Recorder extension
   Installed to: %APPDATA%\Aseprite\extensions\aseprite-process-recorder

2. FFmpeg 2026-08-06 essentials build with libx264
   Installed to: %LOCALAPPDATA%\Programs\Aseprite Process Recorder\FFmpeg

Close Aseprite completely before installing. Restart Aseprite after installation.
The extension starts recording when you open or switch to a canvas by default.
You can turn this off permanently in the Process Recorder menu; manual recording
remains available. FFmpeg is installed automatically and runs only for MP4 export.

The extension offers Complete, Automatic, and Performance capture modes.
Complete records every visible change. Automatic records every change on small
canvases up to 65,536 pixels and merges closely spaced events on larger canvases.
Performance merges more events to reduce load during large or long recordings.
Automatic and Performance always capture the final image when recording stops.

Use Language / 语言 / 言語 in the Process Recorder menu, or choose a language
in Recorder Settings, to select Simplified Chinese, English, or Japanese.
Messages change immediately; restart Aseprite to update menu titles.

Process files are generated in the background when a recording stops on Windows.
The journal and manifest are retained until export finishes. MP4 export remains
synchronous. Large canvases may still pause during image capture and disk writes.

Upgrades preserve Aseprite extension preferences and all recordings and videos
in Documents\Aseprite Process Recordings. Uninstalling removes this extension
and the bundled FFmpeg, but keeps your artwork, videos, and recordings.

FFmpeg is a separate GPLv3 third-party program. Its license, build information,
and exact source revision are installed with this package.
