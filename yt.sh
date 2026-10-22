#!/usr/bin/env bash
# yt.sh - download YouTube audio as mp3 and append an entry to audio.json
# Usage: ./yt.sh            (interactive loop)
#        ./yt.sh "URL" ID CATEGORY "TITLE"   (processes one entry first, then keeps looping)

JSON_FILE="audio.json"
DURATION_UNIT="seconds"   # "seconds" (matches your existing data, e.g. 360) or "minutes"
# Extra yt-dlp options if YouTube blocks you, e.g.:
#   YTDLP_EXTRA=(--cookies-from-browser chrome)
YTDLP_EXTRA=()

# ---- dependency checks ----
command -v yt-dlp >/dev/null 2>&1 || { echo "Error: yt-dlp not found in PATH."; exit 1; }
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1; then
  JSON_TOOL="python3"
else
  echo "Error: need either jq or python3 to edit $JSON_FILE."
  exit 1
fi

# Create audio.json if missing
[ -f "$JSON_FILE" ] || echo '{"tracks": []}' > "$JSON_FILE"

strip_quotes() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  s="${s#\'}"; s="${s%\'}"
  printf '%s' "$s"
}

show_help() {
  cat <<'EOF'

----------------------------------------------------------------
 INPUT FORMAT:
   "YOUTUBE_URL" ID CATEGORY "TITLE"

 - YOUTUBE_URL : the video link (quotes optional)
 - ID          : unique name, no spaces (file saved as ID.mp3)
 - CATEGORY    : one word, e.g. Krishna  (no quotes needed)
 - TITLE       : full title, put inside quotes (spaces allowed)

 EXAMPLE:
   "https://www.youtube.com/watch?v=XXXXXXXXXXX" brindaban_ma_gau Krishna "वृन्दावनमा गौ भन्देउ न कृष्णजी तिमी कहाँ छौ"

 Type  exit  or  quit  (or press Ctrl+C) to stop.
----------------------------------------------------------------
EOF
}

append_entry() {
  local id="$1" title="$2" url="$3" duration="$4" category="$5"
  if [ "$JSON_TOOL" = "jq" ]; then
    jq --arg id "$id" --arg title "$title" --arg url "$url" \
       --argjson duration "$duration" --arg category "$category" \
       '.tracks += [{id:$id, title:$title, url:$url, duration:$duration, category:$category}]' \
       "$JSON_FILE" > "$JSON_FILE.tmp" && mv "$JSON_FILE.tmp" "$JSON_FILE"
  else
    python3 - "$JSON_FILE" "$id" "$title" "$url" "$duration" "$category" <<'PY'
import json, sys
f, id_, title, url, duration, category = sys.argv[1:7]
with open(f, encoding="utf-8") as fh:
    data = json.load(fh)
data.setdefault("tracks", []).append({
    "id": id_, "title": title, "url": url,
    "duration": json.loads(duration), "category": category,
})
with open(f, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
  fi
}

process() {
  local yt_url="$1" id="$2" category="$3" title="$4"

  if [ -z "$yt_url" ] || [ -z "$id" ] || [ -z "$category" ] || [ -z "$title" ]; then
    echo "Error: all four values are required."
    return 1
  fi

  # Download as mp3 named ID.mp3; duration is written to a temp file in the same run
  echo "Downloading audio to ${id}.mp3 ..."
  local durfile=".${id}.duration.tmp"
  rm -f "$durfile"
  if ! yt-dlp --no-playlist -x --audio-format mp3 --audio-quality 0 \
        "${YTDLP_EXTRA[@]}" \
        --print-to-file "%(duration)s" "$durfile" \
        -o "${id}.%(ext)s" "$yt_url"; then
    echo "Error: yt-dlp failed (see message above). Nothing added to $JSON_FILE."
    echo "Tip: update yt-dlp first (run: yt-dlp -U) and try again."
    rm -f "$durfile"
    return 1
  fi

  local secs
  secs=$(head -n1 "$durfile" 2>/dev/null | tr -d '\r[:space:]')
  rm -f "$durfile"
  secs="${secs%%.*}"
  if ! [[ "$secs" =~ ^[0-9]+$ ]]; then
    echo "Error: could not read duration (got: '$secs'). Nothing added to $JSON_FILE."
    return 1
  fi

  local duration
  if [ "$DURATION_UNIT" = "minutes" ]; then
    duration=$(awk -v s="$secs" 'BEGIN{printf "%.2f", s/60}')
  else
    duration="$secs"
  fi

  if [ ! -f "${id}.mp3" ]; then
    echo "Error: ${id}.mp3 not found after download. Nothing added to $JSON_FILE."
    return 1
  fi

  append_entry "$id" "$title" "${id}.mp3" "$duration" "$category" \
    && echo "Done: added '$id' ($duration $DURATION_UNIT) to $JSON_FILE"
}

# ---- optional first run from command-line args ----
if [ "$#" -ge 4 ]; then
  process "$(strip_quotes "$1")" "$2" "$3" "$(strip_quotes "$4")"
fi

# ---- infinite loop ----
while true; do
  show_help
  read -r -p "> " line || break
  line="${line#"${line%%[![:space:]]*}"}"   # trim leading spaces
  [ -z "$line" ] && continue
  case "$line" in exit|quit) echo "Bye."; break ;; esac

  # url, id, category are single words; everything after is the title
  read -r url id category title <<< "$line"
  url="$(strip_quotes "$url")"
  title="$(strip_quotes "$title")"

  process "$url" "$id" "$category" "$title"
  echo
done
