#!/usr/bin/env nu

# Download MP3s from a podcast RSS feed and generate an M3U playlist.
#
# Note: nu_plugin_query's `query xml` uses CSS selectors on structured XML
# (output of `from xml`), and cannot extract attribute values. Since
# <enclosure url="..." type="..."> attributes are essential, this script
# uses `from xml` throughout for full RSS tree access.
#
# Usage:
#   nu rss-dl.nu <rss_url>
#   nu rss-dl.nu <rss_url> -l
#   nu rss-dl.nu <rss_url> -o ./my-podcast
#   nu rss-dl.nu <rss_url> -o ./pod -p feed.m3u
#   nu rss-dl.nu <rss_url> -o ./pod -r 5 -d 2sec

# GET a URL with exponential-backoff retries on failure.
# Always fetches raw bytes (binary); use `from xml`, `from json`, or `save` on the result.
# Retries are silent; the final failure raises an error.
def http-get-with-retry [
    url: string                         # URL to fetch
    --retries (-r): int = 3             # Maximum number of attempts
    --retry-delay (-d): duration = 1sec # Initial delay between attempts (doubles each retry)
]: nothing -> binary {
    # Null-guard typed flags (linter requires explicit default even when flag has one)
    let max_attempts = ($retries     | default 3)
    let base_delay   = ($retry_delay | default 1sec)

    mut attempt  = 0
    mut delay    = $base_delay
    mut last_err = ""
    mut result   = 0x[]
    mut success  = false
    while $attempt < $max_attempts and not $success {
        $attempt += 1
        let outcome = try {
            {ok: true, data: (http get --raw $url), msg: ""}
        } catch {|err|
            {ok: false, data: 0x[], msg: $err.msg}
        }

        if $outcome.ok {
            $result  = $outcome.data
            $success = true
        } else {
            $last_err = $outcome.msg
            if $attempt < $max_attempts {
                sleep $delay
                $delay = ($delay * 2)
            }
        }
    }

    if not $success {
        error make {
            msg: $"Failed after ($max_attempts) attempts: ($url)"
            label: {text: url span: (metadata $url).span}
            help: $"Last error: ($last_err)"
        }
    }

    $result
}

# Fetch raw RSS XML as a string from a URL
def fetch-feed [
    url: string
    --retries (-r): int = 3
    --retry-delay (-d): duration = 1sec
]: nothing -> string {
    try {
        http-get-with-retry $url --retries $retries --retry-delay $retry_delay
    } catch {|err|
        error make {
            msg: "Failed to fetch RSS feed"
            label: {text: url span: (metadata $url).span}
            help: $"Check the URL and your connection. Detail: ($err.msg)"
        }
    }
}

# Parse audio episodes from RSS XML (via pipeline); returns [{title, url}]
def parse-episodes []: string -> list {
    let raw = $in
    let xml = try {
        $raw | from xml
    } catch {|err|
        error make {
            msg: "Failed to parse RSS XML"
            label: {text: "feed input" span: (metadata $raw).span}
            help: $err.msg
        }
    }

    mut episodes = []
    for item in ($xml.content.0?.content? | default [] | where tag == item) {
        let title_nodes = ($item.content | where tag == title)
        let title       = ($title_nodes.0?.content?.0?.content? | default Untitled)
        let enc_nodes   = ($item.content | where tag == enclosure)
        let enc         = ($enc_nodes.0?.attributes? | default {url: "", type: ""})
        let url         = ($enc.url?  | default "")
        let mime        = ($enc.type? | default "")
        if ($url | is-not-empty) and ($mime =~ audio) {
            $episodes ++= [
                {title: $title, url: $url}
            ]
        }
    }
    $episodes
}

# Download one episode with retries; returns {title, filename, status}
def download-episode [
    ep: record
    output_dir: string
    --retries (-r): int = 3
    --retry-delay (-d): duration = 1sec
]: nothing -> record {
    let parts    = ($ep.url | parse "{base}?{_}")
    let url_base = ($parts.0?.base? | default $ep.url)
    let filename = ($url_base | path basename | url decode)
    let dest     = ([$output_dir $filename] | path join)
    let status   = if ($dest | path exists) {
        skipped
    } else {
        try {
            http-get-with-retry $ep.url --retries $retries --retry-delay $retry_delay
            | save --force $dest
            ok
        } catch {
            failed
        }
    }
    {title: $ep.title, filename: $filename, status: $status}
}

# Write an M3U playlist from [{title, filename}] records to a file
def write-playlist [tracks: list, playlist_path: path]: nothing -> nothing {
    let content = (
        $tracks
        | each {|ep| [$"#EXTINF:-1,($ep.title)" $"./($ep.filename)"] }
        | flatten
        | prepend "#EXTM3U"
        | str join "\n"
    )
    try {
        $content | save --force $playlist_path
    } catch {|err|
        error make {
            msg: "Failed to write playlist"
            label: {text: path span: (metadata $playlist_path).span}
            help: $"Check write permissions. Detail: ($err.msg)"
        }
    }
}

def main [
    rss_url: string                               # URL of the RSS/podcast feed
    --list (-l)                                   # Print episodes without downloading
    --output-dir (-o): string = "."               # Directory to save MP3s and playlist
    --playlist-name (-p): string = "playlist.m3u" # M3U output filename
    --retries (-r): int = 3                       # HTTP retry attempts per request
    --retry-delay (-d): duration = 1sec           # Initial delay between retries (doubles each time)
]: nothing -> nothing {
    print $"📡 Fetching RSS feed: ($rss_url)\n"

    let episodes = (
        fetch-feed $rss_url --retries $retries --retry-delay $retry_delay
        | parse-episodes
    )
    print $"🎵 Found ($episodes | length) audio enclosures\n"

    if $list {
        for ep in $episodes {
            print $"  🎙  ($ep.title)\n      ($ep.url)"
        }
        return
    }

    try { mkdir $output_dir }

    mut downloaded = []
    for ep in $episodes {
        let result = (
            download-episode $ep $output_dir --retries $retries --retry-delay $retry_delay
        )
        match $result.status {
            ok      => { print $"  ✓  Downloaded: ($result.filename)" }
            skipped => { print $"  ⏭  Skipping (already exists): ($result.filename)" }
            _       => { print $"  ✗  Failed: ($result.filename)" }
        }
        if $result.status != failed {
            $downloaded ++= [$result]
        }
    }

    let playlist_path = ([$output_dir $playlist_name] | path join)
    write-playlist $downloaded $playlist_path
    print $"\n✅ Playlist saved: ($playlist_path) ($downloaded | length) tracks"
}
