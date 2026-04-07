#!/bin/bash

# Configuration
REPO="BrenoAqua/Yomipv"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
YELLOW='\033[1;33m'
NC='\033[0m'

OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
    USER_AGENT="Yomipv-Updater-macOS"
    # BSD sed requires explicit extension argument for in-place edits
    SED_INPLACE_ARG="''"
else
    USER_AGENT="Yomipv-Updater-Linux"
    SED_INPLACE_ARG=""
fi

echo -e "${CYAN}Yomipv Updater${NC}"

# Check dependencies
for cmd in curl unzip grep sed; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is not installed.${NC}"
        exit 1
    fi
done

get_local_version() {
    local main_lua="$SCRIPT_DIR/scripts/yomipv/main.lua"
    if [ -f "$main_lua" ]; then
        local ver=$(sed -n 's/.*yomipv_version = "\(.*\)".*/\1/p' "$main_lua" | head -n 1)
        echo "${ver:-0.0.0}"
    else
        echo "0.0.0"
    fi
}

get_config() {
    local conf_file="$SCRIPT_DIR/script-opts/yomipv.conf"
    if [ -f "$conf_file" ]; then
        grep -v '^\s*#' "$conf_file" | grep '=' | sed 's/ *= */=/'
    fi
}

get_mpv_instances() {
    if command -v pgrep &> /dev/null; then
        pgrep -a mpv | cut -d' ' -f2-
    fi
}

stop_yomipv_processes() {
    echo -e "${CYAN}Checking for running Yomipv processes...${NC}"
    if command -v pkill &> /dev/null; then
        pkill -f "YomipvLookup" &> /dev/null
        pkill -x mpv &> /dev/null
        sleep 1
    fi
}

restart_mpv_instances() {
    local instances="$1"
    if [ -n "$instances" ]; then
        echo -e "${CYAN}Restarting MPV instances...${NC}"
        echo "$instances" | while IFS= read -r cmd; do
            if [ -n "$cmd" ]; then
                ( $cmd > /dev/null 2>&1 & )
            fi
        done
    fi
}

merge_config() {
    local old_conf="$1"
    local conf_file="$SCRIPT_DIR/script-opts/yomipv.conf"
    if [ -n "$old_conf" ] && [ -f "$conf_file" ]; then
        echo -e "${CYAN}Restoring user configuration settings...${NC}"
        echo "$old_conf" | while IFS='=' read -r key value; do
            if [ -n "$key" ]; then
                if grep -q "^\s*#\?\s*$key\s*=" "$conf_file"; then
                    local escaped_val=$(echo "$value" | sed 's/[&/\]/\\&/g')
                    sed -i ${SED_INPLACE_ARG} "0,/^\s*#\?\s*$key\s*=/ s|^\s*#\?\(\s*$key\s*=\s*\).*|\1$escaped_val|" "$conf_file"
                else
                    echo "$key=$value" >> "$conf_file"
                fi
            fi
        done
    fi
}

update_from_source() {
    echo -e "${CYAN}Updating from source (main branch)...${NC}"
    local zip_url="https://github.com/$REPO/archive/refs/heads/main.zip"
    local temp_zip="/tmp/yomipv-source.zip"
    
    curl -L -A "$USER_AGENT" -o "$temp_zip" "$zip_url"
    
    local old_conf=$(get_config)
    local extract_dir="/tmp/yomipv-extract"
    rm -rf "$extract_dir" && mkdir -p "$extract_dir"
    
    unzip -q "$temp_zip" -d "$extract_dir"
    local source_folder=$(ls -d "$extract_dir"/*/ | head -n 1)
    
    if [ -n "$source_folder" ]; then
        echo -e "${GREEN}Applying source changes...${NC}"
        local mpv_instances=$(get_mpv_instances)
        stop_yomipv_processes
        
        # Copy everything except .git
        cp -r "$source_folder"* "$SCRIPT_DIR/"
        merge_config "$old_conf"
        restart_mpv_instances "$mpv_instances"
    fi
    
    rm -f "$temp_zip"
    rm -rf "$extract_dir"
    return 0
}

# Check for updates
if [ -d "$SCRIPT_DIR/.git" ]; then
    echo -e "${CYAN}Git repository detected. Updating via git...${NC}"
    git fetch origin main
    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git rev-parse origin/main)
    
    if [ "$local_hash" == "$remote_hash" ]; then
        echo -e "${GREEN}You are already using the latest version.${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}New updates available. Pulling...${NC}"
    local old_conf=$(get_config)
    local mpv_instances=$(get_mpv_instances)
    stop_yomipv_processes
    
    git pull origin main
    merge_config "$old_conf"
    restart_mpv_instances "$mpv_instances"
    
    echo -e "${CYAN}Update installed!${NC}"
    exit 0
fi

# Ask for source preference if not set
USER_PREF=""
CONFIG_PREF=$(get_config | grep "^updater_use_source=" | cut -d'=' -f2)

if [ -z "$CONFIG_PREF" ]; then
    echo -e "${GREEN}Choose update source: [1] Official Releases (default) or [2] Latest Source?${NC}"
    read -t 10 -n 1 -p "[1/2]: " choice
    echo ""
    if [ "$choice" == "2" ]; then
        USER_PREF="source"
    else
        USER_PREF="release"
    fi
else
    if [ "$CONFIG_PREF" == "yes" ]; then
        USER_PREF="source"
    else
        USER_PREF="release"
    fi
fi

if [ "$USER_PREF" == "source" ]; then
    update_from_source
    echo -e "${CYAN}Update installed! Please restart MPV to apply changes.${NC}"
    echo -e "${MAGENTA}Operation completed${NC}"
    exit 0
fi

echo -e "${CYAN}Checking for latest release...${NC}"
RELEASE_JSON=$(curl -s -A "$USER_AGENT" "$API_URL")
LATEST_TAG=$(echo "$RELEASE_JSON" | grep -m 1 '"tag_name":' | sed 's/.*"tag_name": "\(.*\)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
    echo -e "${RED}Error: Could not fetch latest release info. You might be rate-limited.${NC}"
    exit 1
fi

LATEST_VER="${LATEST_TAG#v}"
LOCAL_VER=$(get_local_version)

echo "Local version: $LOCAL_VER"
echo "Latest version: $LATEST_VER"

if [[ "$LATEST_VER" == "$LOCAL_VER" ]]; then
    echo -e "${GREEN}You are already using the latest version -- v$LATEST_VER${NC}"
    exit 0
fi

echo -e "${GREEN}Newer Yomipv build available -- v$LATEST_VER${NC}"

if [ "$OS_TYPE" = "Darwin" ]; then
    ZIP_URL=$(echo "$RELEASE_JSON" | grep -o 'https://github.com/[^"]*mac-yomipv-[^"]*\.zip' | head -n 1)
else
    ZIP_URL=$(echo "$RELEASE_JSON" | grep -o 'https://github.com/[^"]*linux-yomipv-[^"]*\.zip' | head -n 1)
fi

if [ -z "$ZIP_URL" ]; then
    ZIP_URL=$(echo "$RELEASE_JSON" | grep -o 'https://github.com/[^"]*\.zip' | grep -v "win-" | head -n 1)
fi

if [ -z "$ZIP_URL" ]; then
    ZIP_URL=$(echo "$RELEASE_JSON" | grep '"zipball_url":' | sed 's/.*"zipball_url": "\(.*\)".*/\1/')
fi

if [ -z "$ZIP_URL" ]; then
    echo -e "${RED}Error: Could not find a valid download URL.${NC}"
    exit 1
fi

echo -e "${GREEN}Downloading archive...${NC}"
TEMP_ZIP="/tmp/yomipv-update.zip"
curl -L -A "$USER_AGENT" -o "$TEMP_ZIP" "$ZIP_URL"

old_conf=$(get_config)
mpv_instances=$(get_mpv_instances)
stop_yomipv_processes

echo -e "${GREEN}Extracting update...${NC}"
unzip -o -q "$TEMP_ZIP" -d "$SCRIPT_DIR"
merge_config "$old_conf"
restart_mpv_instances "$mpv_instances"

rm -f "$TEMP_ZIP"
echo -e "${CYAN}Update installed!${NC}"
echo -e "${MAGENTA}Operation completed${NC}"
