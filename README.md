# video_automation
video_automation DIY ideas on how to make my life easier for content creation
# 1st lets download the https://www.gyan.dev/ffmpeg/builds/
# better to use choco install 
choco install ffmpeg-full

ffmpeg -i GX020250.MP4 -vf "transpose=2,transpose=2" -c:a copy rotated.mp4
ffmpeg -i rotated.mp4 -c copy -map 0 -f segment -segment_time 60 output_%03d.mp4
# above wont work if yourre doing it for mp4 becuase of the time code and meta data 
### -vf will rotate the video into 180*
ffmpeg -i GX020250.MP4 -vf "transpose=2,transpose=2" -map 0:v:0 -map 0:a:0 -f segment -segment_time 60 -c:v libx264 -c:a copy output_%03d.mp4
### if you dont want it to be rotated 

ffmpeg -i GX020250.MP4 -map 0:v:0 -map 0:a:0 -f segment -segment_time 60 -c:v libx264 -c:a copy output_%03d.mp4


- AI GENERATED - 
# 🎬 FFmpeg Video Auto Split & Rotate Guide

This guide explains how to **rotate a video 180°** and **split it into 60-second chunks** using [FFmpeg](https://ffmpeg.org/). This is perfect for creators who use helmet cams or upside-down mounts and want to automate splitting without losing quality.

---

## ✅ Prerequisites

### 🧱 Install FFmpeg

#### Windows:
1. Download FFmpeg static build: https://www.gyan.dev/ffmpeg/builds/
2. Extract the ZIP.
3. Add the `bin/` folder (inside FFmpeg) to your system `PATH`, or run `ffmpeg.exe` directly using its full path.

#### macOS:
```bash
brew install ffmpeg
choco install ffmpeg-full
```

#### Linux (Ubuntu/Debian):
```bash
sudo apt update
sudo apt install ffmpeg
```

---

## 🔁 Step 1: Rotate the Video 180 Degrees

If your video is upside down:

```bash
ffmpeg -i GX020250.MP4 -vf "transpose=2,transpose=2" -c:a copy rotated.mp4
```

- `transpose=2` = Rotate 90° counterclockwise.
- Two transposes = 180° rotation.
- `-c:a copy` keeps the original audio.

---

## ✂️ Step 2: Split the Rotated Video into 60-Second Segments

```bash
ffmpeg -i rotated.mp4 -c copy -map 0 -f segment -segment_time 60 output_%03d.mp4
```

This creates files:
```
output_000.mp4
output_001.mp4
output_002.mp4
...
```

> ⚡ Super fast because there's **no re-encoding**.

---

## 🧪 Optional: Combine Rotate + Split in One Command

```bash
ffmpeg -i GX020250.MP4 -vf "transpose=2,transpose=2" -map 0 -f segment -segment_time 60 -c:a copy -c:v libx264 output_%03d.mp4
```

- This re-encodes video using `libx264` (slower but necessary if applying filters).
- You can control quality using:
```bash
-crf 23 -preset fast
```

---

## 📂 Want a Drag-and-Drop `.bat` for Windows?

Let me know and I’ll create a ready-made batch script you can drag & drop videos onto.

---

## 🧠 Tips

- Adjust `-segment_time 60` for different durations.
- Always test the output quality if you re-encode.
- FFmpeg works with all formats: `.mp4`, `.mov`, `.avi`, etc.

Happy Editing! 🎥
