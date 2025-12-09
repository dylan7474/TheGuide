#!/bin/bash
# setup_pi_guide.sh
# -----------------------------------------------------------------------------
# HITCHHIKER'S GUIDE DEPLOYMENT (Universal: Debian 13 Intel & Pi Zero 2 W)
# -----------------------------------------------------------------------------
# VERSION: 7.7 (Fix: Restored Text Cleaning & Wrapping for Reader Mode)
# -----------------------------------------------------------------------------
# Usage:
#   ./setup_pi_guide.sh       -> Setup software only (skips massive download)
#   ./setup_pi_guide.sh -d    -> Setup + Download/Update Wikipedia (Resumable)
#   ./setup_pi_guide.sh -n    -> Configure Static IP/DNS ONLY (Exits after)
# -----------------------------------------------------------------------------

set -e

# --- CONFIGURATION ---
INSTALL_DIR="$HOME/hhgttg"
DATA_DIR="$INSTALL_DIR/data"
BIN_DIR="$INSTALL_DIR/bin"
MODEL_DIR="$INSTALL_DIR/models"
KIWIX_PORT=9095 
AI_PORT=8080

# ASSETS
ZIM_BASE_URL="https://download.kiwix.org/zim/wikipedia/"
ZIM_PATTERN="wikipedia_en_all_nopic"
ZIM_FILENAME="wikipedia_nopic.zim"
ZIM_PATH="$DATA_DIR/$ZIM_FILENAME"
WRONG_ZIM="$DATA_DIR/wikipedia_maxi.zim"

# FLAGS
DOWNLOAD_MODE=false
NETWORK_MODE=false

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${YELLOW}[GUIDE]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# --- PARSE ARGUMENTS ---
while getopts "dn" opt; do
  case ${opt} in
    d) DOWNLOAD_MODE=true ;;
    n) NETWORK_MODE=true ;;
    *) echo "Usage: $0 [-d] (Download/Sync Wiki) [-n] (Configure Network)"; exit 1 ;;
  esac
done

# --- ARCHITECTURE DETECTION ---
ARCH=$(uname -m)
log "Detected Architecture: $ARCH"

if [[ "$ARCH" == "x86_64" ]]; then
    KIWIX_DOWNLOAD_URL="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64-3.7.0.tar.gz"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    KIWIX_DOWNLOAD_URL="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-aarch64-3.7.0.tar.gz"
else
    echo "Error: Unsupported architecture $ARCH"
    exit 1
fi

# ==============================================================================
# 0. NETWORK CONFIGURATION ROUTINE (-n)
# ==============================================================================
configure_network() {
    echo ""
    echo "----------------------------------------------------"
    echo "   MANUAL NETWORK CONFIGURATION (Static IP)"
    echo "----------------------------------------------------"
    
    # Check for NetworkManager
    if ! command -v nmcli >/dev/null; then
        log "NetworkManager (nmcli) not found. Installing..."
        sudo apt-get update && sudo apt-get install -y network-manager
    fi

    # Fix 1: Disable cloud-init network config
    if [ -d /etc/cloud/cloud.cfg.d ]; then
        if [ ! -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg ]; then
            log "Disabling cloud-init network management..."
            echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null
        fi
    fi

    # Detect active connection
    echo "Scanning active connections..."
    echo -e "${YELLOW}Current Configuration:${NC}"
    ip -4 addr | grep inet | grep -v 127.0.0.1
    echo "----------------------------------------------------"

    # Identify interface
    DEVICE=$(nmcli -t -f NAME,DEVICE,TYPE connection show --active | head -n 1 | cut -d: -f2)
    
    if [ -z "$DEVICE" ]; then
        # Fallback detection if NM isn't managing it yet
        DEVICE=$(ip route | grep default | awk '{print $5}' | head -n1)
    fi
    
    if [ -z "$DEVICE" ]; then
        echo "No active interface found. Listing all:"
        nmcli device status
        read -p "Enter Interface Name manually (e.g., eth0, ens18): " DEVICE
        if [ -z "$DEVICE" ]; then error "No device selected."; return; fi
    else
        log "Detected Interface: '$DEVICE'"
    fi

    # Fix 2: Nuclear option for /etc/network/interfaces
    if grep -q "$DEVICE" /etc/network/interfaces; then
        log "Legacy network config detected. Replacing with NetworkManager-only config..."
        
        sudo cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s)
        
        sudo bash -c "cat > /etc/network/interfaces <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# NOTE: Physical interfaces are now managed by NetworkManager
EOF"
        log "Legacy config removed. Enabling NetworkManager management..."
        
        if grep -q "managed=false" /etc/NetworkManager/NetworkManager.conf; then
            sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
        fi
        sudo systemctl restart NetworkManager
        sleep 2
    fi

    CON_NAME="Static-$DEVICE"
    
    echo -e "${RED}WARNING: Changing IP may disconnect SSH session.${NC}"
    
    # Gather Input
    read -p "Enter Static IP (CIDR, e.g., 192.168.1.50/24): " STATIC_IP
    read -p "Enter Gateway (e.g., 192.168.1.1): " GATEWAY
    read -p "Enter DNS Server (Default: 8.8.8.8): " DNS_SERVER
    if [ -z "$DNS_SERVER" ]; then DNS_SERVER="8.8.8.8"; fi

    if [ -z "$STATIC_IP" ] || [ -z "$GATEWAY" ]; then
        error "IP/Gateway required."
        exit 1
    fi

    echo ""
    echo "Applying Configuration to $CON_NAME..."
    
    sudo nmcli con delete "$CON_NAME" 2>/dev/null || true
    
    sudo nmcli con add type ethernet con-name "$CON_NAME" ifname "$DEVICE" \
        ipv4.addresses "$STATIC_IP" \
        ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS_SERVER" \
        ipv4.method manual \
        connection.autoconnect yes \
        connection.autoconnect-priority 100

    log "Activating connection..."
    ( sudo nmcli con up "$CON_NAME" ) &
    
    echo "Waiting 5 seconds for network to settle..."
    sleep 5
    
    echo "----------------------------------------------------"
    echo "Network Diagnostics:"
    echo "----------------------------------------------------"
    echo "1. IP Address:"
    ip addr show "$DEVICE" | grep inet
    
    echo "2. Route Check:"
    if route -n; then
        success "Route table visible."
    else
        error "Could not read route table (try 'route -n' manually)"
    fi
    
    echo "3. Gateway Ping:"
    if ping -c 1 -W 2 "$GATEWAY" > /dev/null; then
        success "Gateway Reachable."
    else
        error "Gateway Unreachable."
    fi
    
    echo "----------------------------------------------------"
    echo ""
}

if [ "$NETWORK_MODE" = true ]; then
    configure_network
    echo "Network setup complete. Exiting as requested."
    exit 0
fi

# ==============================================================================
# 0.5. ROBUST DOWNLOAD FUNCTION (Restored)
# ==============================================================================
download_robust() {
    local url="$1"
    local output="$2"
    local description="$3"

    log "Downloading $description..."
    local success=false
    
    # Loop 50 times for flaky connections
    for i in {1..50}; do
        if curl -L -k -C - --retry 10 --retry-delay 5 --connect-timeout 60 --speed-time 30 --speed-limit 1000 -o "$output" "$url"; then
            success=true
            break
        else
            log "Download interrupted/stalled. Resuming in 10 seconds... (Attempt $i/50)"
            sleep 10
        fi
    done

    if [ "$success" = false ]; then
        error "Failed to download $description after multiple attempts."
        exit 1
    fi
}

# ==============================================================================
# 1. EXPAND SWAP (CRITICAL FOR LOW RAM)
# ==============================================================================
log "Configuring Swap Space (4GB)..."

# Method A: Raspberry Pi OS specific (dphys-swapfile)
if [ -f /etc/dphys-swapfile ] && command -v dphys-swapfile >/dev/null; then
    if ! grep -q "CONF_SWAPSIZE=4096" /etc/dphys-swapfile; then
        sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=4096/' /etc/dphys-swapfile
        sudo dphys-swapfile setup
        sudo dphys-swapfile swapon
        log "RPi Swap expanded via dphys-swapfile."
    else
        log "RPi Swap already configured."
    fi
# Method B: Standard Debian 13 VM (fallocate)
elif [ ! -f /swapfile_guide ]; then
    log "Creating standard Linux swapfile (fallocate)..."
    sudo fallocate -l 4G /swapfile_guide
    sudo chmod 600 /swapfile_guide
    sudo mkswap /swapfile_guide
    sudo swapon /swapfile_guide
    if ! grep -q "/swapfile_guide" /etc/fstab; then
        echo "/swapfile_guide none swap sw 0 0" | sudo tee -a /etc/fstab
    fi
    log "Standard Swap created."
else
    log "Swap already exists."
fi

# ==============================================================================
# 2. DEPENDENCIES (Debian 13 Compatible)
# ==============================================================================
log "Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq git build-essential python3-pip python3-venv libzim-dev curl wget python3-dev libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev libopenjp2-7-dev libtiff-dev zsync cmake libcurl4-openssl-dev network-manager net-tools dnsutils less

# ==============================================================================
# 3. KIWIX (Auto-Architected)
# ==============================================================================
mkdir -p "$BIN_DIR" "$DATA_DIR"
if [ ! -f "$BIN_DIR/kiwix-serve" ]; then
    download_robust "$KIWIX_DOWNLOAD_URL" "kiwix.tar.gz" "Kiwix Tools"
    tar -xzf kiwix.tar.gz -C "$BIN_DIR" --strip-components=1
    rm kiwix.tar.gz
fi

# ==============================================================================
# 4. LLAMA.CPP (The Tiny AI Engine)
# ==============================================================================
if [ ! -f "$BIN_DIR/llama-cli" ]; then
    log "Compiling llama.cpp..."
    if [ ! -d "$INSTALL_DIR/llama.cpp" ]; then
        git clone https://github.com/ggerganov/llama.cpp "$INSTALL_DIR/llama.cpp"
    fi
    
    cd "$INSTALL_DIR/llama.cpp"
    
    if [ ! -d "build" ]; then
        mkdir build
        cd build
        log "Configuring CMake build (Fresh)..."
        cmake ..
    else
        cd build
        log "Configuring CMake build (Incremental)..."
        cmake ..
    fi
    
    log "Building llama-cli..."
    cmake --build . --config Release -j4
    
    if [ -f "bin/llama-cli" ]; then
        cp bin/llama-cli "$BIN_DIR/"
    elif [ -f "llama-cli" ]; then
        cp llama-cli "$BIN_DIR/"
    else
        find . -name llama-cli -type f -exec cp {} "$BIN_DIR/" \; -quit
    fi

    cd "$INSTALL_DIR"
    
    if [ -f "$BIN_DIR/llama-cli" ]; then
        log "AI Engine compiled successfully."
    else
        error "Compilation failed: llama-cli binary not found."
        exit 1
    fi
else
    log "AI Engine already compiled (skipping)."
fi

# ==============================================================================
# 5. MODEL DOWNLOAD (Qwen 2 0.5B)
# ==============================================================================
mkdir -p "$MODEL_DIR"
MODEL_URL="https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_k_m.gguf"
MODEL_PATH="$MODEL_DIR/qwen2-0.5b.gguf"

if [ ! -f "$MODEL_PATH" ]; then
    download_robust "$MODEL_URL" "$MODEL_PATH" "AI Brain (Qwen2-0.5B)"
fi

# ==============================================================================
# 6. DATABASE DOWNLOAD (50GB Nopic) - CONDITIONAL
# ==============================================================================

# Check for the wrong file (Maxi)
if [ -f "$WRONG_ZIM" ]; then
    echo -e "${RED}FOUND MAXI ZIM (100GB).${NC} We need the NoPic ZIM (50GB) for this version."
    read -p "Delete Maxi ZIM to free space? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$WRONG_ZIM"
        log "Maxi ZIM deleted."
    fi
fi

if [ "$DOWNLOAD_MODE" = true ]; then
    log "Running Wikipedia Download/Sync (-d flag set)..."
    
    # Resolve URL
    log "Resolving latest ZIM version for: $ZIM_PATTERN"
    LATEST_ZIM_FILE=$(curl -s -k "$ZIM_BASE_URL" | grep -o "${ZIM_PATTERN}_[0-9]\{4\}-[0-9]\{2\}\.zim" | sort | tail -n 1)
    
    if [ -z "$LATEST_ZIM_FILE" ]; then
        log "Could not resolve latest filename via scrape. Using generic fallback if file exists..."
        if [ ! -f "$ZIM_PATH" ]; then error "Cannot resolve ZIM URL."; exit 1; fi
    else
        REAL_ZIM_URL="${ZIM_BASE_URL}${LATEST_ZIM_FILE}"
        log "Target: $REAL_ZIM_URL"
    fi

    if [ ! -z "$REAL_ZIM_URL" ]; then
        DOWNLOAD_SUCCESS=false

        # Strategy 1: ZSYNC (Syncs differences / Resumes / Repairs)
        if command -v zsync >/dev/null; then
            ZSYNC_URL="${REAL_ZIM_URL}.zsync"
            log "Attempting ZSYNC (Repair/Update)..."
            if zsync -o "$ZIM_PATH" "$ZSYNC_URL"; then
                DOWNLOAD_SUCCESS=true
                success "Zsync complete."
            else
                log "Zsync failed (Metadata missing?). Falling back to Curl..."
            fi
        fi

        # Strategy 2: CURL (Resume only) - Uses Robust Function
        if [ "$DOWNLOAD_SUCCESS" = false ]; then
            download_robust "$REAL_ZIM_URL" "$ZIM_PATH" "Wikipedia ZIM (Fallback)"
            DOWNLOAD_SUCCESS=true
        fi

        if [ "$DOWNLOAD_SUCCESS" = false ]; then
            error "Failed to download ZIM file."
            exit 1
        fi
        success "Database updated/verified."
    fi
else
    log "Skipping Wikipedia Download (Run with -d to update/fix)."
    if [ ! -f "$ZIM_PATH" ]; then
        echo -e "${RED}WARNING: ZIM file missing! The guide will fail to start.${NC}"
        echo "Run: ./setup_pi_guide.sh -d"
    fi
fi

# ==============================================================================
# 7. PYTHON ENVIRONMENT (OLED & Input)
# ==============================================================================
log "Setting up Python Environment..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
    python3 -m venv "$INSTALL_DIR/venv"
fi
source "$INSTALL_DIR/venv/bin/activate"
pip install requests beautifulsoup4 luma.oled pillow

# ==============================================================================
# 8. THE "GUIDE" APPLICATION (API CLIENT)
# ==============================================================================
log "Updating Guide Application Logic..."
rm -f "$INSTALL_DIR/guide.py" # Ensure old version is gone

cat <<EOF > "$INSTALL_DIR/guide.py"
import requests
import time
import sys
import json
import pydoc
import textwrap
import shutil
from bs4 import BeautifulSoup

# CONFIG
KIWIX_URL = "http://localhost:$KIWIX_PORT"
AI_API_URL = "http://localhost:$AI_PORT/completion"

def display_text(text):
    print("-" * 40)
    print(f">> GUIDE DISPLAY: {text}")
    print("-" * 40)

def get_wiki_results(query):
    # Returns a list of results so user can choose
    try:
        resp = requests.get(f"{KIWIX_URL}/search?pattern={query}", timeout=5)
        soup = BeautifulSoup(resp.content, 'html.parser')
        
        results = []
        for a in soup.find_all('a', href=True):
            if '/A/' in a['href'] or '/content/' in a['href']:
                title = a.get_text().strip()
                link = a['href']
                if title:
                    results.append({'title': title, 'href': link})
                if len(results) >= 5: break # Top 5 results
        return results
    except Exception as e:
        print(f"Archive Error: {e}")
        return []

def get_content(href):
    try:
        article_url = f"{KIWIX_URL}{href}"
        art_resp = requests.get(article_url, timeout=5)
        art_soup = BeautifulSoup(art_resp.content, 'html.parser')
        
        # 1. Clean useless elements
        # 'sup' removes [1][2] citation marks
        # '.hatnote' removes "Not to be confused with..."
        # '.infobox' removes table data that reads poorly in text
        for s in art_soup.select('script, style, table, nav, footer, sup, .mw-editsection, .hatnote, .infobox, .reference, .noprint, .IPA'): 
            s.extract()
        
        # Determine terminal width (default 80, max 100 for readability)
        term_width = shutil.get_terminal_size((80, 20)).columns
        wrap_width = min(term_width, 100)
        wrapper = textwrap.TextWrapper(width=wrap_width, replace_whitespace=False)
        
        # 2. Extract structured text (Headers + Paragraphs)
        content_lines = []
        
        # Add Title if H1 exists
        title_tag = art_soup.find('h1')
        if title_tag:
            title = title_tag.get_text().strip()
            content_lines.append("=" * wrap_width)
            content_lines.append(title.center(wrap_width))
            content_lines.append("=" * wrap_width + "\\n")
        
        # We target specific readable tags
        for tag in art_soup.find_all(['p', 'h2', 'h3']):
            text = tag.get_text(" ", strip=True)
            if not text: continue
            
            if tag.name in ['h2', 'h3']:
                # Make headers stand out
                header = text.upper()
                content_lines.append(f"\\n\\n{header}")
                content_lines.append("-" * len(header))
            else:
                # Wrap paragraph
                content_lines.append(wrapper.fill(text))
        
        return "\\n".join(content_lines)
    except:
        return ""

def ask_ai(context, question):
    print("...Thinking (AI)...")
    
    # Internal Truncate: Only feed ~2000 chars to AI to save RAM
    # This prevents the Pi Zero from crashing on large articles
    ai_context = context[:2000]
    
    prompt = f"<|im_start|>user\\nBased ONLY on the Context below, answer the Question.\\nContext: {ai_context}\\n\\nQuestion: {question}\\n\\nSummarize the answer in one short sentence for a traveler.<|im_end|>\\n<|im_start|>assistant\\n"
    
    data = {
        "prompt": prompt,
        "n_predict": 64,
        "temperature": 0.7,
        "stream": True 
    }
    
    full_answer = ""
    print("-" * 40)
    print(">> GUIDE:", end=" ", flush=True)
    
    try:
        # TIMEOUT INCREASED to 120s for Slow Pi
        with requests.post(AI_API_URL, json=data, stream=True, timeout=120) as r:
            r.raise_for_status()
            for line in r.iter_lines():
                if line:
                    decoded = line.decode('utf-8')
                    if decoded.startswith("data: "):
                        json_str = decoded[6:]
                        try:
                            chunk = json.loads(json_str)
                            content = chunk.get("content", "")
                            print(content, end="", flush=True)
                            full_answer += content
                            if chunk.get("stop", False):
                                break
                        except:
                            pass
    except requests.exceptions.ConnectionError:
        print("\\n[ERROR] AI Brain not ready.")
        return None
    except Exception as e:
        print(f"\\n[ERROR] {e}")
        return None
        
    print("\\n" + "-" * 40)
    return full_answer

def main_loop():
    display_text("DON'T PANIC v7.7. Ready.")
    
    while True:
        try:
            query = input("Query > ")
            if not query: continue
            
            results = get_wiki_results(query)
            
            if not results:
                display_text("Entry not found in Archive.")
                continue
            
            # Selection Logic: If multiple results, ask user
            target = results[0]
            if len(results) > 1:
                print("\\nFound multiple entries:")
                for i, res in enumerate(results):
                    print(f"{i+1}. {res['title']}")
                
                sel = input(f"Select 1-{len(results)} (default 1): ")
                if sel.isdigit() and 1 <= int(sel) <= len(results):
                    target = results[int(sel)-1]

            display_text(f"Accessing: {target['title']}...")
            
            # Fetch Full Content (Unlimited size for display)
            full_text = get_content(target['href'])
            
            # Check for AI Service
            ai_online = False
            try:
                requests.get(f"http://localhost:$AI_PORT/health", timeout=2)
                ai_online = True
            except:
                pass

            if ai_online:
                ask_ai(full_text, query)
            else:
                print("\\n[AI OFFLINE] Displaying Database Entry (Press Q to quit view):\\n")
                # Use pager for full text reading experience
                pydoc.pager(full_text)
                print("\\n[End of Article]\\n")
            
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    main_loop()
EOF

# ==============================================================================
# 9. STARTUP SCRIPT (DAEMON MODE)
# ==============================================================================
cat <<EOF > "$INSTALL_DIR/start_guide.sh"
#!/bin/bash

# FLAGS
USE_AI=false

while [[ "\$#" -gt 0 ]]; do
    case \$1 in
        -ai) USE_AI=true ;;
        *) echo "Unknown parameter passed: \$1"; exit 1 ;;
    esac
    shift
done

# 1. Start Kiwix
if [ ! -f "$ZIM_PATH" ]; then
    echo "ERROR: ZIM file missing."
    exit 1
fi

echo "Starting Kiwix Archive..."
$BIN_DIR/kiwix-serve --port=$KIWIX_PORT "$ZIM_PATH" > /dev/null 2>&1 &
KIWIX_PID=\$!

# 2. Start AI Brain (Optional)
AI_PID=""
if [ "\$USE_AI" = true ]; then
    echo "Waking up the Brain (This takes ~15s)..."
    # -c 512: Tiny context to fit in RAM
    # --port 8080: Standard API port
    $BIN_DIR/llama-server -m "$MODEL_PATH" -c 512 --port $AI_PORT --host 127.0.0.1 > /dev/null 2>&1 &
    AI_PID=\$!

    # Wait loop for AI readiness
    echo "Waiting for Brain to load..."
    for i in {1..30}; do
        if curl -s http://localhost:$AI_PORT/health > /dev/null; then
            echo "Brain is Online!"
            break
        fi
        sleep 2
    done
else
    echo "AI Module Disabled (Fast Mode)."
fi

# 3. Start Interface
echo "Launching Guide..."
source $INSTALL_DIR/venv/bin/activate
python $INSTALL_DIR/guide.py

# 4. Cleanup
echo "Shutting down..."
kill \$KIWIX_PID
if [ -n "\$AI_PID" ]; then
    kill \$AI_PID
fi
EOF

chmod +x "$INSTALL_DIR/start_guide.sh"

echo ""
echo "------------------------------------------------------------------"
echo "   HITCHHIKER'S GUIDE SETUP COMPLETE"
echo "------------------------------------------------------------------"
echo "1. Data location: $DATA_DIR"
echo "2. Run (Fast Mode): $INSTALL_DIR/start_guide.sh"
echo "3. Run (AI Mode):   $INSTALL_DIR/start_guide.sh -ai"
echo "------------------------------------------------------------------"
