# rss-dl

Downloads MP3s from a podcast RSS feed and writes an M3U playlist. Runs on [Nushell](https://www.nushell.sh/) 0.111+.

## Usage

```nushell
nu rss-dl.nu <rss_url> [flags]
```

### Flags

| Flag | Short | Default | Description |
| --- | --- | --- | --- |
| `--list` | `-l` | — | Print episodes without downloading |
| `--output-dir` | `-o` | `.` | Where to save MP3s and the playlist |
| `--playlist-name` | `-p` | `playlist.m3u` | Playlist filename |
| `--retries` | `-r` | `3` | HTTP attempts per request |
| `--retry-delay` | `-d` | `1sec` | Initial retry delay (doubles each attempt) |

### Examples

```nushell
# Check what's in a feed before downloading
nu rss-dl.nu https://example.com/feed.rss -l

# Download to the current directory
nu rss-dl.nu https://example.com/feed.rss

# Custom output folder and playlist name
nu rss-dl.nu https://example.com/feed.rss -o ./my-podcast -p my-podcast.m3u

# More retries for a flaky connection
nu rss-dl.nu https://example.com/feed.rss -o ./pod -r 5 -d 2sec
```

### Output

`-l` (list mode):

```nushell
📡 Fetching RSS feed: https://example.com/feed.rss

🎵 Found 12 audio enclosures

  🎙  Episode 12: The Latest One
      https://cdn.example.com/ep12.mp3
  🎙  Episode 11: The Previous One
      https://cdn.example.com/ep11.mp3
  ...
```

Download mode:

```nushell
📡 Fetching RSS feed: https://example.com/feed.rss

🎵 Found 12 audio enclosures

  ⬇  Downloading: ep12.mp3
  ✓  Downloaded: ep12.mp3
  ⏭  Skipping (already exists): ep11.mp3
  ...

✅ Playlist saved: ./playlist.m3u (12 tracks)
```

## How it works

The feed is fetched as raw bytes and parsed with `from xml` — not `query xml`, which uses CSS selectors and can't reach XML attributes like `url=` and `type=`. Each `<item>` is checked for an `<enclosure>` with an `audio/*` MIME type; anything else is skipped.

Downloads go through `http-get-with-retry`, which backs off exponentially between attempts (1s → 2s → 4s…). Files already on disk are skipped, so re-running is safe. Query strings are stripped from URLs before they become filenames (`ep1.mp3?token=abc` → `ep1.mp3`).

The playlist is standard `#EXTM3U` with relative paths, so it works wherever you put the folder.

## Installation

Copy the script into your Nushell scripts directory:

```nushell
cp rss-dl.nu ($nu.default-config-dir | path join scripts)
```

Run it from anywhere with an explicit `nu` call:

```nushell
nu ($nu.default-config-dir | path join scripts rss-dl.nu) -l https://example.com/feed.rss
```

To run it as a bare command (`rss-dl ...`), add the scripts directory to `$env.PATH` in your `env.nu`:

```nushell
$env.PATH = ($env.PATH | prepend ($nu.default-config-dir | path join scripts))
```

To uninstall:

```nushell
rm ($nu.default-config-dir | path join scripts rss-dl.nu)
```
