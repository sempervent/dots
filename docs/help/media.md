# Media tooling

Package group `media`: FFmpeg/ffprobe, SoX, yt-dlp, ImageMagick, exiftool.

```bash
./setup.sh --packages media
./dots check media
./dots check media gate
./dots check media examples
```

DOTS never captures devices, plays audio, downloads media, reads browser
cookies, or launches GUIs during setup/check. On Darwin, `./dots check media`
also inventories optional mactools apps without launching them.

See `docs/using/media-tooling.md` and `docs/macos/mactools.md`.
