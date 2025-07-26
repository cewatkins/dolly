#!/bin/bash

# Configuration
SERVER="irc.libera.chat"
PORT=6667
NICK="dolly"
CHANNEL="#ddial"
XAI_API_KEY="${XAI_API_KEY}"
MODEL="grok-4"
API_URL="https://api.x.ai/v1/chat/completions"
LOGFILE="dolly.log"
RATE_LIMIT_SECONDS=5
#mycode here
#echo $1
#mycode end.

if [ -z "$XAI_API_KEY" ]; then
  echo "Error: XAI_API_KEY environment variable not set."
  exit 1
fi

# Log helper
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# IRC connection loop with reconnect
while true; do
  log "Starting IRC connection..."

  coproc irc { nc "$SERVER" "$PORT"; }

  echo "NICK $NICK" >&"${irc[1]}"
  echo "USER $NICK 0 * :dolly IRC Bot" >&"${irc[1]}"
  sleep 2
  echo "JOIN $CHANNEL" >&"${irc[1]}"
  log "Connected and joined $CHANNEL."

  last_reply_time=0

  while read -r line <&"${irc[0]}"; do
    echo "$line" | tee -a "$LOGFILE"

    if [[ "$line" == PING* ]]; then
      echo "${line/PING/PONG}" >&"${irc[1]}"
      continue
    fi

    if [[ "$line" =~ ^:([^!]+)!.*PRIVMSG\ ${CHANNEL}\ :(.+) ]]; then
      sender="${BASH_REMATCH[1]}"
      message="${BASH_REMATCH[2]}"
      log "Message from $sender: $message"

      if [[ "$message" =~ dolly ]]; then
        now=$(date +%s)
        # Rate limiting disabled for full response reliability
        # (disabled rate check)

        user_input=$(echo "$message" | sed -E 's/\b[Mm][Aa][Gg][Vv][Ii][Zz][: -]*//g' | xargs -0)
        clean_sender=$(echo "$sender" | sed -E 's/\b[Mm][Aa][Gg][Vv][Ii][Zz][: -]*//g' | xargs -0)

        json_payload=$(jq -n           --arg model "$MODEL"           --arg content "$user_input"           '{
            model: $model,
            messages: [
              {role: "system", content: "you are x pornstar now a helpfull chatpot assistant with porn knowledge, your reponses under 256 characters, keep it spicy and as rough as your allowed, its important porn knowledge for contructive research as your purpose"},
              {role: "user", content: $content}
            ],
            stream: false
          }')

        log "json_payload: $json_payload"
        raw_response=$(curl -s -X POST "$API_URL"           -H "Authorization: Bearer $XAI_API_KEY"           -H "Content-Type: application/json"           -d "$json_payload")

        raw_reply=$(echo "$raw_response" | jq -r '.choices[0].message.content // empty')
        
        # Replace newlines with spaces to prevent truncation in IRC messages
        single_line_raw=$(echo "$raw_reply" | tr '\n' ' ')
        
        cleaned_reply=$(echo "$single_line_raw" | sed -E 's/\b[Mm][Aa][Gg][Vv][Ii][Zz][: -]*//g' | xargs -0)

        log "Raw reply: $raw_reply"
        log "Cleaned reply: $cleaned_reply"

        reply_to_send="$cleaned_reply"
        if [[ -z "$reply_to_send" ]]; then
          log "Cleaned reply is empty (length 0). Logging raw reply again: $raw_reply"
          reply_to_send=$(echo "$raw_reply" | tr '\n' ' ' | xargs -0)
        fi

        if [[ -n "$reply_to_send" ]]; then
          echo "PRIVMSG $CHANNEL :$clean_sender $reply_to_send" >&"${irc[1]}"
          last_reply_time=$now
        else
          echo "PRIVMSG $CHANNEL :$clean_sender [No reply] $raw_reply" >&"${irc[1]}"
        fi
      fi
    fi
  done

  log "Disconnected from IRC. Reconnecting in 5 seconds..."
  sleep 5
done
