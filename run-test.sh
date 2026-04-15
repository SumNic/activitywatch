#!/usr/bin/env bash
#
# Run ActivityWatch in testing mode with a single command
# Auto-installs missing dependencies, builds, and starts all services
#
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }

# ── 0. Detect OS & package manager ────────────────────────────────────
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update || true"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update || true"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_UPDATE="pacman -Sy"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="zypper install -y"
        PKG_UPDATE="zypper refresh"
    elif command -v brew &>/dev/null; then
        PKG_MANAGER="brew"
        PKG_INSTALL="brew install"
        PKG_UPDATE="brew update"
    else
        log_error "No supported package manager found (apt, dnf, yum, pacman, zypper, brew)"
        exit 1
    fi
    log_ok "Detected package manager: $PKG_MANAGER"
}

install_system_packages() {
    local missing=()
    for pkg in "$@"; do
        missing+=("$pkg")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return
    fi

    log_warn "Missing system packages: ${missing[*]}"
    log_info "Installing via $PKG_MANAGER (may require sudo)..."

    sudo $PKG_UPDATE 2>/dev/null || true
    sudo $PKG_INSTALL "${missing[@]}"
    log_ok "System packages installed"
}

# ── 1. Check & install system dependencies ────────────────────────────
check_and_install_deps() {
    log_step "Checking system dependencies"
    detect_package_manager

    local missing_python=false
    local missing_node=false
    local missing_rust=false
    local missing_git=false
    local missing_make=false
    local missing_curl=false
    local missing_npm=false

    # Check Python 3.9+
    if command -v python3 &>/dev/null; then
        local py_version
        py_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        local py_major
        py_major=$(echo "$py_version" | cut -d. -f1)
        local py_minor
        py_minor=$(echo "$py_version" | cut -d. -f2)
        if [ "$py_major" -lt 3 ] || ([ "$py_major" -eq 3 ] && [ "$py_minor" -lt 9 ]); then
            log_warn "Python $py_version found, need 3.9+"
            missing_python=true
        fi
    else
        missing_python=true
    fi

    # Check Node.js 20+
    if command -v node &>/dev/null; then
        local node_version
        node_version=$(node -v | cut -d'v' -f2 | cut -d. -f1)
        if [ "$node_version" -lt 20 ]; then
            log_warn "Node.js $(node -v) found, need 20+"
            missing_node=true
        fi
    else
        missing_node=true
    fi

    # Check npm
    if ! command -v npm &>/dev/null; then
        missing_npm=true
    fi

    # Check Rust
    if ! command -v rustc &>/dev/null || ! command -v cargo &>/dev/null; then
        missing_rust=true
    fi

    # Check git
    if ! command -v git &>/dev/null; then
        missing_git=true
    fi

    # Check make
    if ! command -v make &>/dev/null; then
        missing_make=true
    fi

    # Check curl
    if ! command -v curl &>/dev/null; then
        missing_curl=true
    fi

    # Build install lists
    local apt_pkgs=()
    local brew_pkgs=()

    if [ "$missing_python" = true ]; then
        apt_pkgs+=(python3 python3-venv python3-pip)
        brew_pkgs+=(python)
    fi
    if [ "$missing_git" = true ]; then
        apt_pkgs+=(git)
        brew_pkgs+=(git)
    fi
    if [ "$missing_make" = true ]; then
        apt_pkgs+=(build-essential)
        brew_pkgs+=(make)
    fi
    if [ "$missing_curl" = true ]; then
        apt_pkgs+=(curl)
        brew_pkgs+=(curl)
    fi
    if [ "$missing_node" = true ] || [ "$missing_npm" = true ]; then
        # Node.js 20 via apt requires nodesource setup script
        apt_pkgs+=(nodejs npm)
        brew_pkgs+=(node)
    fi
    if [ "$missing_rust" = true ]; then
        # Rust is installed via rustup, not system packages
        :
    fi

    # Install via package manager
    if [ ${#apt_pkgs[@]} -gt 0 ] && [ "$PKG_MANAGER" = "apt" ]; then
        # For Node.js 20+, use nodesource if apt has old version
        if [ "$missing_node" = true ]; then
            log_info "Setting up Node.js 20.x repository..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
        fi
        install_system_packages "${apt_pkgs[@]}"
    elif [ ${#brew_pkgs[@]} -gt 0 ] && [ "$PKG_MANAGER" = "brew" ]; then
        install_system_packages "${brew_pkgs[@]}"
    fi

    # Install Rust via rustup (cross-platform)
    if [ "$missing_rust" = true ]; then
        log_info "Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        log_ok "Rust installed: $(rustc --version)"
    fi

    # Verify all deps now
    log_info "Verifying dependencies..."
    command -v python3 &>/dev/null || { log_error "Python3 still missing"; exit 1; }
    command -v node &>/dev/null || { log_error "Node.js still missing"; exit 1; }
    command -v rustc &>/dev/null || { log_error "Rust still missing"; exit 1; }
    command -v cargo &>/dev/null || { log_error "Cargo still missing"; exit 1; }
    command -v git &>/dev/null || { log_error "Git still missing"; exit 1; }
    command -v npm &>/dev/null || { log_error "npm still missing"; exit 1; }

    log_ok "All system dependencies satisfied"
}

# ── 2. Install Poetry if missing ──────────────────────────────────────
install_poetry_if_missing() {
    if ! command -v poetry &>/dev/null; then
        log_info "Installing Poetry..."
        curl -sSL https://install.python-poetry.org | python3 -
        export PATH="$HOME/.local/bin:$PATH"
        log_ok "Poetry installed: $(poetry --version)"
    else
        log_ok "Poetry found: $(poetry --version)"
    fi
}

# ── 3. Virtualenv ─────────────────────────────────────────────────────
setup_virtualenv() {
    log_step "Setting up Python virtual environment"

    if [ ! -d "venv" ]; then
        log_info "Creating virtualenv..."
        python3 -m venv venv
        log_ok "Virtualenv created"
    fi

    source venv/bin/activate

    # Upgrade pip
    pip install --quiet --upgrade pip setuptools wheel
}

# ── 4. Install Python dependencies ────────────────────────────────────
install_python_deps() {
    log_step "Installing Python dependencies"

    if python3 -c "import aw_server" &>/dev/null; then
        log_ok "Python dependencies already installed"
        return
    fi

    log_info "Installing Python modules (this may take a while)..."

    # Initialize submodules first (needed for pyproject.toml paths)
    if [ ! -d "aw-core" ] || [ ! -f "aw-core/pyproject.toml" ]; then
        log_info "Initializing git submodules..."
        git submodule update --init --recursive
        log_ok "Submodules initialized"
    fi

    # Install each submodule
    for dir in aw-core aw-client aw-server aw-watcher-afk aw-watcher-window aw-qt; do
        if [ -f "$dir/pyproject.toml" ]; then
            log_info "  Installing $dir..."
            pip install --quiet -e "$dir"
        fi
    done

    log_ok "Python dependencies installed"
}

# ── 5. Build web UI ───────────────────────────────────────────────────
build_webui() {
    log_step "Building web UI"

    # Check if already built AND the static directory has content
    if [ -d "aw-server/aw_server/static" ] && [ -f "aw-server/aw_server/static/index.html" ]; then
        log_ok "Web UI already built"
        return
    fi

    if [ ! -d "aw-server/aw-webui" ]; then
        log_warn "aw-webui directory not found, initializing submodules..."
        git submodule update --init --recursive
    fi

    if [ ! -d "aw-server/aw-webui" ]; then
        log_error "aw-webui still missing after submodule update"
        exit 1
    fi

    # Clean old static files to force fresh build
    rm -rf aw-server/aw_server/static/*

    log_info "Installing npm dependencies..."
    cd aw-server/aw-webui
    npm install --legacy-peer-deps

    log_info "Building web UI (this may take a while)..."
    npm run build
    cd "$PROJECT_DIR"

    # CRITICAL: Copy built web UI to aw_server/static/ where the server serves it from
    log_info "Copying web UI to aw-server/aw_server/static/..."
    mkdir -p aw-server/aw_server/static/
    cp -r aw-server/aw-webui/dist/* aw-server/aw_server/static/
    log_ok "Web UI built and deployed"
}

# ── 6. Kill any previous testing instances ────────────────────────────
cleanup_previous() {
    log_step "Cleaning up previous testing instances"

    local killed=false

    if pkill -f "aw-server.*--testing" 2>/dev/null; then
        log_info "Killed previous aw-server --testing"
        killed=true
    fi

    if pkill -f "aw-watcher-afk.*--testing" 2>/dev/null; then
        log_info "Killed previous aw-watcher-afk --testing"
        killed=true
    fi

    if pkill -f "aw-watcher-window.*--testing" 2>/dev/null; then
        log_info "Killed previous aw-watcher-window --testing"
        killed=true
    fi

    if [ "$killed" = true ]; then
        sleep 1
    fi

    log_ok "Previous instances cleaned up"
}

# ── 7. Start services ─────────────────────────────────────────────────
start_services() {
    log_step "Starting ActivityWatch services"

    log_info "Starting aw-server --testing (port 5666)..."
    aw-server --testing &
    SERVER_PID=$!

    log_info "Starting aw-watcher-afk --testing..."
    aw-watcher-afk --testing &
    AFK_PID=$!

    log_info "Starting aw-watcher-window --testing..."
    aw-watcher-window --testing &
    WINDOW_PID=$!

    # Wait for server to be ready
    log_info "Waiting for server to start..."
    for i in $(seq 1 30); do
        if curl -s http://127.0.0.1:5666/api/0/info &>/dev/null; then
            log_ok "Server is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "Server failed to start within 30 seconds"
            log_info "Check logs above for errors"
            kill $SERVER_PID $AFK_PID $WINDOW_PID 2>/dev/null
            exit 1
        fi
        sleep 1
    done

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ActivityWatch is running in TESTING mode!${NC}"
    echo -e "${GREEN}  Web UI: http://127.0.0.1:5666${NC}"
    echo -e "${GREEN}  Query Explorer: http://127.0.0.1:5666/#/query${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Press Ctrl+C to stop all services${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# ── 8. Handle shutdown ────────────────────────────────────────────────
cleanup() {
    echo ""
    log_info "Shutting down all services..."
    kill $SERVER_PID $AFK_PID $WINDOW_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
    wait $AFK_PID 2>/dev/null || true
    wait $WINDOW_PID 2>/dev/null || true
    log_ok "All services stopped cleanly"
    exit 0
}

trap cleanup SIGINT SIGTERM

# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════
main() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║         ActivityWatch - Single Command Runner         ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_and_install_deps
    install_poetry_if_missing
    setup_virtualenv
    install_python_deps
    build_webui
    cleanup_previous
    start_services

    # Wait for all background processes
    wait
}

main
