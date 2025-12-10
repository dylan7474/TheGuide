#!/bin/bash
# deploy_maxi_wiki.sh
# -----------------------------------------------------------------------------
# DEPLOYMENT STREAM 3: Full English Wikipedia (WITH IMAGES/MAXI)
# -----------------------------------------------------------------------------
# VERSION: 4.0 (CLEAN SLATE: Removed all Theming/Proxy complexity)
# -----------------------------------------------------------------------------

set -e  # Exit immediately if a command exits with a non-zero status

# --- CONFIGURATION ---
# Isolated directory for the Maxi version
INSTALL_DIR="$HOME/offline-wiki-maxi"
DATA_DIR="$INSTALL_DIR/data"
BIN_DIR="$INSTALL_DIR/bin"
VENV_DIR="$INSTALL_DIR/venv"

# Network Config (Unique ports for Maxi stream)
PORT_KIWIX=9095
PORT_APP=9094

# Assets
KIWIX_VERSION="3.7.0"
ZIM_BASE_URL="https://download.kiwix.org/zim/wikipedia/"

# --- ZIM FILE SELECTION (MAXI) ---
ZIM_PATTERN="wikipedia_en_all_maxi"
ZIM_FILENAME="wikipedia_maxi.zim"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- ERROR HANDLING ---
trap 'echo -e "${RED}[ERROR] Script failed at line $LINENO during command: $BASH_COMMAND${NC}"' ERR

log() { echo -e "${BLUE}[DEPLOY-MAXI]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; }

# --- ROBUST IP DETECTION ---
HOST_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
if [ -z "$HOST_IP" ]; then HOST_IP=$(hostname -I | awk '{print $1}'); fi
if [ -z "$HOST_IP" ]; then HOST_IP="localhost"; fi

# ==============================================================================
# 1. SYSTEM PREPARATION
# ==============================================================================
log "Preparing directories in $INSTALL_DIR..."
mkdir -p "$DATA_DIR" "$BIN_DIR" "$INSTALL_DIR"

log "Checking system dependencies..."
if command -v apt-get >/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl wget tar python3 python3-pip python3-venv libzim-dev ca-certificates zsync
else
    log "Warning: 'apt-get' not found. Assuming dependencies are managed manually."
fi

# ==============================================================================
# 2. INSTALL KIWIX TOOLS
# ==============================================================================
if [ ! -f "$BIN_DIR/kiwix-serve" ]; then
    log "Downloading Kiwix Tools v$KIWIX_VERSION..."
    curl -L -k -o kiwix-tools.tar.gz "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64-$KIWIX_VERSION.tar.gz"
    
    log "Extracting Kiwix Tools..."
    tar -xzf kiwix-tools.tar.gz -C "$BIN_DIR" --strip-components=1
    rm kiwix-tools.tar.gz
    
    chmod +x "$BIN_DIR/kiwix-serve" "$BIN_DIR/kiwix-manage"
    success "Kiwix Tools installed."
else
    log "Kiwix tools already installed."
fi

# ==============================================================================
# 3. DOWNLOAD WIKIPEDIA ZIM (MAXI)
# ==============================================================================
ZIM_PATH="$DATA_DIR/$ZIM_FILENAME"

validate_final_file() {
    if [ ! -f "$ZIM_PATH" ]; then return 1; fi
    FILE_SIZE=$(wc -c < "$ZIM_PATH")
    if [ "$FILE_SIZE" -lt 50000000000 ]; then 
        log "Validation Failed: File is smaller than 50GB."
        return 1
    fi
    if [ -x "$BIN_DIR/kiwix-manage" ]; then
        if ! "$BIN_DIR/kiwix-manage" "$INSTALL_DIR/integrity_check.xml" add "$ZIM_PATH" >/dev/null 2>&1; then
            rm -f "$INSTALL_DIR/integrity_check.xml"
            log "Validation Failed: Kiwix tool could not read the file structure."
            return 1
        fi
        rm -f "$INSTALL_DIR/integrity_check.xml"
    fi
    return 0
}

remove_garbage_files() {
    if [ -f "$ZIM_PATH" ]; then
        FILE_SIZE=$(wc -c < "$ZIM_PATH")
        if [ "$FILE_SIZE" -lt 10000000 ]; then 
            log "Detected tiny/garbage file (<10MB). Deleting to restart download..."
            rm "$ZIM_PATH"
        else
            log "Found existing partial download (>10MB). System will attempt to repair/resume..."
        fi
    fi
}

remove_garbage_files

if [ ! -f "$ZIM_PATH" ] || ! validate_final_file; then
    log "Resolving latest ZIM version for: $ZIM_PATTERN"
    LATEST_ZIM_FILE=$(curl -s -k "$ZIM_BASE_URL" | grep -o "${ZIM_PATTERN}_[0-9]\{4\}-[0-9]\{2\}\.zim" | sort | tail -n 1)
    
    if [ -z "$LATEST_ZIM_FILE" ]; then
        error "Could not find a valid ZIM file on the server."
        exit 1
    fi
    
    REAL_ZIM_URL="${ZIM_BASE_URL}${LATEST_ZIM_FILE}"
    log "Found latest version: $LATEST_ZIM_FILE"
    log "WARNING: This is a ~100GB+ download."
    
    DOWNLOAD_SUCCESS=false

    if command -v zsync >/dev/null; then
        log "Attempting smart download/repair with zsync..."
        ZSYNC_URL="${REAL_ZIM_URL}.zsync"
        if zsync -o "$ZIM_PATH" "$ZSYNC_URL"; then
            DOWNLOAD_SUCCESS=true
            success "Zsync download complete."
        else
            log "Zsync failed. Falling back to standard download..."
        fi
    else
        log "Zsync tool not found. Falling back to standard download..."
    fi

    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        log "Starting Curl download from: $REAL_ZIM_URL"
        for i in {1..50}; do 
            log "Download attempt $i/50..."
            if curl -4 -L -k -C - --retry 5 --connect-timeout 60 -o "$ZIM_PATH" "$REAL_ZIM_URL"; then
                DOWNLOAD_SUCCESS=true
                break
            else
                log "Download interrupted. Retrying in 15 seconds..."
                sleep 15
            fi
        done
    fi

    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        error "Failed to download ZIM file."
        exit 1
    fi
    
    if ! validate_final_file; then
        error "Download finished but validation failed."
        exit 1
    fi
    success "Download complete and verified."
else
    log "ZIM file verified at $ZIM_PATH"
fi

# ==============================================================================
# 4. GENERATE PYTHON MIDDLEWARE (app.py)
# ==============================================================================
log "Stopping app service..."
systemctl --user stop wiki-maxi-ui.service || true

log "Generating application code (app.py)..."

cat <<EOF > "$INSTALL_DIR/app.py"
import requests
from flask import Flask, render_template_string, request, redirect, url_for, jsonify
from bs4 import BeautifulSoup
import time
import datetime
import sys
import re

app = Flask(__name__)

# --- CONFIGURATION (MAXI WIKI) ---
KIWIX_HOST = "http://localhost"
KIWIX_PORT = $PORT_KIWIX
KIWIX_URL = f"{KIWIX_HOST}:{KIWIX_PORT}"
APP_VERSION = "v4.0-CLEAN-SLATE"

# --- HTML TEMPLATE ---
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wiki Maxi {{ version }}</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 0; background: #f4f4f9; color: #333; height: 100vh; display: flex; flex-direction: column; overflow: hidden; }
        
        /* Header */
        .header { height: 60px; background: #fff; border-bottom: 1px solid #ccc; display: flex; align-items: center; justify-content: space-between; padding: 0 20px; flex-shrink: 0; z-index: 2000; }
        .brand { font-weight: bold; color: #2c3e50; font-size: 1.2em; display: flex; align-items: center; gap: 10px; }
        .badge { background: #2980b9; color: white; padding: 2px 6px; border-radius: 4px; font-size: 0.6em; }
        
        .search-container { position: relative; width: 60%; max-width: 600px; }
        .search-bar { display: flex; gap: 10px; width: 100%; }
        input { flex: 1; padding: 8px 12px; border: 1px solid #ccc; border-radius: 4px; font-size: 16px; }
        button { padding: 8px 16px; border: none; border-radius: 4px; background: #2980b9; color: white; font-weight: bold; cursor: pointer; }
        button.ai-btn { background: #27ae60; }
        button:hover { opacity: 0.9; }

        #suggestions { position: absolute; top: 100%; left: 0; right: 0; background: white; border: 1px solid #ccc; border-top: none; border-radius: 0 0 4px 4px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); display: none; z-index: 100; }
        .suggestion-item { padding: 10px; cursor: pointer; border-bottom: 1px solid #eee; }
        .suggestion-item:hover { background: #f1f1f1; }

        /* Workspace */
        .workspace { display: flex; flex: 1; overflow: hidden; }
        .sidebar { width: 350px; background: #fff; border-right: 1px solid #ccc; overflow-y: auto; display: flex; flex-direction: column; }
        .result-item { padding: 12px 15px; border-bottom: 1px solid #eee; cursor: pointer; text-decoration: none; color: #333; display: block; }
        .result-item:hover { background: #f8f9fa; }
        .result-item.active { background: #e3f2fd; border-left: 4px solid #2980b9; }
        .result-title { font-weight: bold; font-size: 0.95em; }
        .result-url { font-size: 0.75em; color: #777; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .no-results { padding: 20px; color: #777; text-align: center; }

        .content-area { flex: 1; background: white; position: relative; }
        iframe { width: 100%; height: 100%; border: none; }
        
        .ai-overlay { position: absolute; top: 0; left: 0; right: 0; bottom: 0; background: #f4f4f9; padding: 40px; overflow-y: auto; }
        .ai-card { max-width: 800px; margin: 0 auto; background: #fff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); border: 1px solid #ddd; }
        .ai-header { color: #27ae60; border-bottom: 2px solid #eee; padding-bottom: 10px; margin-bottom: 20px; }

        @media (max-width: 768px) {
            .workspace { flex-direction: column; }
            .sidebar { width: 100%; height: 30vh; border-right: none; border-bottom: 1px solid #ccc; }
            .content-area { height: 70vh; }
            .brand span { display: none; }
        }
    </style>
</head>
<body>
    <header class="header">
        <div class="brand">Wiki <span class="badge">{{ version }}</span></div>
        <div class="search-container">
            <form action="/search" method="get" class="search-bar" autocomplete="off">
                <input type="text" id="searchInput" name="q" placeholder="Search..." value="{{ query }}" required>
                <input type="hidden" name="mode" value="{{ mode }}">
                <button type="submit" onclick="this.form.mode.value='direct'">Go</button>
                <button type="submit" class="ai-btn" onclick="this.form.mode.value='ai'">AI</button>
            </form>
            <div id="suggestions"></div>
        </div>
    </header>

    <div class="workspace">
        <div class="sidebar">
            {% if results %}
                <div style="padding:10px; font-size:0.8em; color:#666; background:#eee;">Found {{ results|length }} results</div>
                {% for res in results %}
                    <a href="{{ url_for('search', q=query, mode=mode, url=res.url) }}" 
                       class="result-item {% if current_url == res.public_url %}active{% endif %}">
                        <div class="result-title">{{ res.title }}</div>
                        <div class="result-url">{{ res.url }}</div>
                    </a>
                {% endfor %}
            {% else %}
                <div class="no-results">
                    {% if query %}No results found.{% else %}Type to search.{% endif %}
                </div>
            {% endif %}
        </div>

        <div class="content-area">
            {% if mode == 'ai' and ai_content %}
                <div class="ai-overlay"><div class="ai-card">{{ ai_content | safe }}</div></div>
            {% elif current_url %}
                <iframe src="{{ current_url }}"></iframe>
            {% else %}
                <div style="display:flex; align-items:center; justify-content:center; height:100%; color:#ccc;">Select an article</div>
            {% endif %}
        </div>
    </div>

    <script>
        // Search Suggestions Logic
        const input = document.getElementById('searchInput');
        const list = document.getElementById('suggestions');
        let debounceTimer;

        input.addEventListener('input', function() {
            clearTimeout(debounceTimer);
            const term = this.value;
            if (term.length < 2) { list.style.display = 'none'; return; }

            debounceTimer = setTimeout(() => {
                fetch('/api/suggest?term=' + encodeURIComponent(term))
                    .then(r => r.json())
                    .then(data => {
                        list.innerHTML = '';
                        if (data.length > 0) {
                            list.style.display = 'block';
                            data.forEach(item => {
                                const div = document.createElement('div');
                                div.className = 'suggestion-item';
                                div.textContent = item;
                                div.onclick = () => {
                                    input.value = item;
                                    list.style.display = 'none';
                                    input.form.submit();
                                };
                                list.appendChild(div);
                            });
                        } else {
                            list.style.display = 'none';
                        }
                    });
            }, 300);
        });

        document.addEventListener('click', e => {
            if (e.target !== input && e.target !== list) list.style.display = 'none';
        });
    </script>
</body>
</html>
"""

def mock_ai_process(title, content):
    # Basic text cleanup
    clean_text = re.sub(r'\[\d+\]', '', content)
    clean_text = re.sub(r'\[edit\]', '', clean_text)
    clean_text = re.sub(r'\s+', ' ', clean_text).strip()
    
    summary = clean_text[:1200] + "..."
    words = len(clean_text.split())
    read_time = max(1, round(words / 200))
    
    return f"""
    <div class="ai-header">
        <h2 style="margin:0;">Analysis: {title}</h2>
        <span style="font-size:0.8em; color:#666;">Reading Time: ~{read_time} min</span>
    </div>
    <p><strong>Processed {words} words from the offline archive.</strong></p>
    <hr>
    <div style="line-height:1.6;">{summary}</div>
    """

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, query="", mode="direct", version=APP_VERSION)

@app.route('/api/suggest')
def api_suggest():
    term = request.args.get('term', '')
    if not term: return jsonify([])
    try:
        api_url = f"{KIWIX_URL}/suggest?term={term}&count=10"
        resp = requests.get(api_url, timeout=2)
        if resp.status_code == 200:
            return jsonify(resp.json())
        return jsonify([])
    except:
        return jsonify([])

@app.route('/search')
def search():
    query = request.args.get('q', '')
    mode = request.args.get('mode', 'direct')
    selected_url = request.args.get('url')
    
    results_list = []
    current_url = None
    ai_content = None
    
    try:
        search_api = f"{KIWIX_URL}/search?pattern={query}"
        resp = requests.get(search_api, timeout=5)
        soup = BeautifulSoup(resp.content, 'html.parser')
        
        all_links = soup.find_all('a', href=True)
        
        for a in all_links:
            href = a['href']
            text = a.get_text().strip()
            # Strict Content Filter
            if href.startswith('/content/') or href.startswith('/wikipedia') or href.startswith('/A/'):
                if text:
                    # DIRECT URL (No Proxy)
                    user_host = request.host.split(':')[0]
                    pub_url = f"http://{user_host}:{KIWIX_PORT}{href}"
                    int_url = f"{KIWIX_URL}{href}"
                    results_list.append({'title': text, 'url': href, 'public_url': pub_url, 'internal_url': int_url})
                    if len(results_list) >= 50: break

        active_res = None
        if selected_url:
            for res in results_list:
                if res['url'] == selected_url:
                    active_res = res
                    break
        elif results_list:
            active_res = results_list[0]

        if active_res:
            current_url = active_res['public_url']
            
            if mode == 'ai':
                art_resp = requests.get(active_res['internal_url'])
                art_soup = BeautifulSoup(art_resp.content, 'html.parser')
                for s in art_soup(['script', 'style']): s.extract()
                text_content = art_soup.get_text(separator=' ', strip=True)
                ai_content = mock_ai_process(active_res['title'], text_content)

        return render_template_string(HTML_TEMPLATE, 
                                      query=query, 
                                      mode=mode, 
                                      results=results_list, 
                                      current_url=current_url,
                                      ai_content=ai_content,
                                      version=APP_VERSION,
                                      error_msg=None)

    except Exception as e:
        return render_template_string(HTML_TEMPLATE, query=query, mode=mode, error_msg=str(e), version=APP_VERSION)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=$PORT_APP)
EOF

# ==============================================================================
# 5. PYTHON ENVIRONMENT SETUP
# ==============================================================================
log "Setting up Python environment..."
if [ ! -d "$VENV_DIR" ]; then python3 -m venv "$VENV_DIR"; fi
source "$VENV_DIR/bin/activate"
pip install -q flask requests beautifulsoup4
success "Python environment ready."

# ==============================================================================
# 6. SETUP SYSTEMD SERVICE (Kiwix Maxi)
# ==============================================================================
log "Configuring Kiwix systemd service..."
if command -v loginctl >/dev/null; then
    sudo loginctl enable-linger $(whoami) || true
fi

mkdir -p "$HOME/.config/systemd/user"
KIWIX_SERVICE_FILE="$HOME/.config/systemd/user/kiwix-maxi.service"

rm -f "$DATA_DIR/library.xml"
"$BIN_DIR/kiwix-manage" "$DATA_DIR/library.xml" add "$DATA_DIR/$ZIM_FILENAME"

cat <<EOF > "$KIWIX_SERVICE_FILE"
[Unit]
Description=Kiwix Maxi Offline Wikipedia Server
After=network.target

[Service]
ExecStart=$BIN_DIR/kiwix-serve --port=$PORT_KIWIX --library "$DATA_DIR/library.xml"
Restart=always

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable kiwix-maxi.service >/dev/null 2>&1
systemctl --user restart kiwix-maxi.service

# ==============================================================================
# 7. SETUP SYSTEMD SERVICE (Python Middleware)
# ==============================================================================
log "Configuring App systemd service..."
APP_SERVICE_FILE="$HOME/.config/systemd/user/wiki-maxi-ui.service"

cat <<EOF > "$APP_SERVICE_FILE"
[Unit]
Description=Offline Wiki AI Middleware (Maxi Version)
After=network.target kiwix-maxi.service

[Service]
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/app.py
WorkingDirectory=$INSTALL_DIR
Restart=always

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable wiki-maxi-ui.service >/dev/null 2>&1
systemctl --user restart wiki-maxi-ui.service

sleep 2

# ==============================================================================
# 8. STATUS
# ==============================================================================
echo ""
echo "------------------------------------------------------------------"
echo "   MAXI DEPLOYMENT COMPLETE (v4.0)"
echo "------------------------------------------------------------------"
echo "   1. AI Dashboard:  http://$HOST_IP:$PORT_APP  <-- USE THIS LINK"
echo "   2. Raw Archive:   http://$HOST_IP:$PORT_KIWIX"
echo "------------------------------------------------------------------"