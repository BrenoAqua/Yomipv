#!/bin/bash

CONF_PATH="$1"
URL="https://anilist.co/api/v2/oauth/authorize?client_id=36986&response_type=token"

echo -e "\033[36mOpening your web browser...\033[0m"
echo "Please authorize Yomipv on AniList."

if command -v xdg-open &> /dev/null; then
    xdg-open "$URL"
elif command -v open &> /dev/null; then
    open "$URL"
else
    echo "Could not open browser automatically. Please open this link:"
    echo "$URL"
fi

echo ""
read -p "After clicking Approve, paste the ENTIRE URL from your browser address bar here: " pasted

if [[ "$pasted" =~ \#access_token=([^&]+) ]]; then
    token="${BASH_REMATCH[1]}"
    
    if [ -f "$CONF_PATH" ]; then
        if grep -q "^anilist_token=" "$CONF_PATH"; then
            sed -i.bak "s/^anilist_token=.*/anilist_token=$token/" "$CONF_PATH"
        else
            echo "anilist_token=$token" >> "$CONF_PATH"
        fi
        
        if grep -q "^anilist_enabled=" "$CONF_PATH"; then
            sed -i.bak "s/^anilist_enabled=.*/anilist_enabled=yes/" "$CONF_PATH"
        else
            echo "anilist_enabled=yes" >> "$CONF_PATH"
        fi
        
        rm -f "${CONF_PATH}.bak"
        
        echo ""
        echo -e "\033[32mAuthentication Successful!\033[0m"
        echo "Your yomipv.conf has been updated."
        echo -e "\033[33mIMPORTANT: Please restart MPV to apply the changes.\033[0m"
    else
        echo -e "\033[31mError: Could not find yomipv.conf at path: $CONF_PATH\033[0m"
    fi
else
    echo ""
    echo -e "\033[31mError: Invalid URL pasted. Could not extract access token.\033[0m"
fi

echo ""
echo "Closing in 5 seconds..."
sleep 5
