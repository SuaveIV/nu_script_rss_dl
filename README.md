# rss-dl

A [Nushell](https://www.nushell.sh/) script that downloads MP3s from a podcast RSS feed and generates an M3U playlist.

## Requirements

- [Nushell](https://www.nushell.sh/) 0.111 or later
- Internet access (uses Nushell's built-in `http get`)

## Usage

```nushell
nu rss-dl.nu <rss_url> [flags]
```

### Flags

| Flag | Short | Default | Description |
| --- | --- | --- | --- |
| `--list` | `-l` | — | Print episodes without downloading anything |
| `--output-dir` | `-o` | `.` | Directory to save MP3s and the playlist |
| `--playlist-name` | `-p` | `playlist.m3u` | Filename for the generated M3U playlist |
| `--retries` | `-r` | `3` | Number of HTTP attempts per request |
| `--retry-delay` | `-d` | `1sec` | Initial delay between retries (doubles each attempt) |

### Examples

```nushell
# Preview what's in a feed before downloading anything
nu rss-dl.nu https://example.com/feed.rss -l

# Download everything into the current directory
nu rss-dl.nu https://example.com/feed.rss

# Download into a specific folder with a custom playlist name
nu rss-dl.nu https://example.com/feed.rss -o ./my-podcast -p my-podcast.m3u

# Be more aggressive about retrying flaky connections
nu rss-dl.nu https://example.com/feed.rss -o ./pod -r 5 -d 2sec
```

### List mode output

```nushell
📡 Fetching RSS feed: https://example.com/feed.rss

🎵 Found 12 audio enclosures

  🎙  Episode 12: The Latest One
      https://cdn.example.com/ep12.mp3
  🎙  Episode 11: The Previous One
      https://cdn.example.com/ep11.mp3
  ...
```

### Download mode output

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

1. **Fetch** — `http-get-with-retry` fetches the RSS XML as raw bytes with exponential-backoff retries (1s → 2s → 4s → …).
2. **Parse** — `from xml` walks the RSS tree extracting `<title>` and `<enclosure url type>` from each `<item>`. Items without an `audio/*` MIME type are skipped.
3. **Download** — each MP3 URL is fetched via `http-get-with-retry` and written to disk with `save`. Files that already exist are skipped.
4. **Playlist** — an `#EXTM3U` playlist is written with relative paths (`./episode.mp3`) and `#EXTINF` title lines.

## Notes

- **`query xml` is not used** for attribute access. Nushell's `query xml` uses CSS selectors, which cannot extract XML attribute values (`url=`, `type=`). The script uses `from xml` throughout for full tree access.
- **Query strings are stripped** from enclosure URLs before using them as filenames (e.g. `ep1.mp3?token=abc` → `ep1.mp3`).
- **Re-runs are safe** — already-downloaded files are detected by path and skipped without re-fetching.
