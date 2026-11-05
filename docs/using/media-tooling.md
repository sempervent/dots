# Media tooling (audio / video / retrieval)

Package group **`media`** installs CLI tools for image, audio, and video
processing plus explicit media retrieval. DOTS **installs and validates** these
tools — it does **not** capture devices, play audio, download media, scan user
libraries, or process arbitrary user files during setup or `./dots check media`.

## Install

```bash
./setup.sh --packages media
# profiles that include media: home, all
```

## Tool roles

| Tool | Role |
|------|------|
| `ffmpeg` / `ffprobe` | Decode, transcode, mux, inspect |
| `sox` (`soxi`, optional `play`/`rec`) | Audio processing / synthetic signals |
| `yt-dlp` | Explicit media retrieval frontend |
| ImageMagick / `exiftool` | Image processing / metadata (pre-existing) |
| DaVinci Resolve (optional GUI) | Explicit `--with davinci-resolve` — not part of group `media` |

**yt-dlp** retrieves; **FFmpeg** decodes/transcodes/muxes. yt-dlp may invoke
FFmpeg when **you** run it. DOTS does not combine them during validation.

## Optional: DaVinci Resolve

Professional NLE as an **explicit** Darwin component (omit_from_all). It is
**not** installed by package group `media`, profile `home`/`all`, or
`--with mactools`.

```bash
./setup.sh --with davinci-resolve
./setup.sh --dry-run --with davinci-resolve
```

### Verified install mechanism

| Item | Value |
|------|-------|
| Automated edition | Mac App Store |
| App Store id | `571213070` (verified via iTunes lookup; bundle `com.blackmagic-design.DaVinciResolveLite`) |
| Prerequisite | Homebrew formula `mas` (Brewfile.davinci-resolve) |
| Homebrew cask | **none** (no `davinci-resolve` cask) |

App Store sign-in is required **only** for this explicit component. If unsigned-in,
setup reports `NOT CONFIGURED / AUTH REQUIRED` and continues — other profiles,
CI, and checks do not require an App Store account.

### Manual alternative (Blackmagic direct)

The Blackmagic Design website offers a direct installer that some professional
workflows prefer for OpenFX / VST / control-surface compatibility. DOTS does
**not** automate that download (URLs are not reliably reproducible without
brittle scraping). Install manually from Blackmagic if you need that edition;
DOTS will still report the app as installed when
`/Applications/DaVinci Resolve.app` exists.

### Safety

DOTS never launches Resolve, creates project libraries, scans media folders,
connects Blackmagic Cloud, installs plugins, or requests camera / microphone /
screen-recording permissions.

## Diagnostics

```bash
./dots check media              # CLI presence (+ Darwin mactools inventory)
./dots check media gate         # synthetic lavfi/sox fixtures only
./dots check media examples     # print examples (not executed)
```

### What checks never do

- Open microphone, camera, or screen-capture devices
- Run `play` / `rec` or enumerate audio interfaces
- Download media or contact YouTube / streaming services
- Inspect browser cookies, netrc, or media credentials
- Scan `~/Movies`, `~/Music`, `~/Pictures`, Photos, or Downloads
- Launch GUI apps or request macOS privacy permissions
- Require sudo or a YubiKey

## Examples (user-directed)

```bash
ffmpeg -i in.mov -c:v libx264 -c:a aac out.mp4
ffprobe -hide_banner in.mp4
sox in.wav out.wav rate 44100
sox -n tone.wav synth 1 sine 440
yt-dlp -F 'URL'                 # network + terms apply — never run by DOTS
```

When retrieving media, **you** are responsible for service terms, copyright, and
authorization. DOTS does not provide service-specific bypass behavior.

## Platforms

Homebrew on Darwin (and Homebrew-on-Linux). Linux native maps provide `ffmpeg`,
`sox`, and `yt-dlp` on apt/dnf/pacman/xbps where packaged.
