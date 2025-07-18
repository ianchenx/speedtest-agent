#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
AGENT_BINARY_URL="https://github.com/ianchenx/speedtest-agent/raw/main/speedtest-agent" 
AGENT_SERVICE_NAME="speedtest-agent"
AGENT_INSTALL_PATH="/usr/local/bin"
CONFIG_DIR="/etc/speedtest-agent"
CONFIG_FILE="$CONFIG_DIR/config.json"

# --- Helper Functions ---

# Function to print messages
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

# Function to print errors and exit
error() {
    echo -e "\033[31m[ERROR] $1\033[0m" >&2
    exit 1
}

# Function to print a warning/final message
warn() {
    echo -e "\033[33m$1\033[0m"
}

# --- Main Script ---

SKIP_CONFIG=0

if [ -f "$AGENT_INSTALL_PATH/$AGENT_SERVICE_NAME" ]; then
    read -p "Detected existing speedtest-agent binary. Overwrite and reinstall? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Installation aborted by user."
        exit 0
    fi
fi

if [ -f "$CONFIG_FILE" ]; then
    # 读取原有端口
    OLD_PORT=$(grep '"port"' "$CONFIG_FILE" | grep -o '[0-9]\+')
    read -p "Detected existing config.json. Overwrite with new token? [y/N]: " confirm_cfg
    if [[ ! "$confirm_cfg" =~ ^[Yy]$ ]]; then
        info "Keeping existing config.json."
        SKIP_CONFIG=1
    else
        read -p "Do you want to reset the port number? [y/N]: " confirm_port
        if [[ "$confirm_port" =~ ^[Yy]$ ]]; then
            read -p "Enter new port [default: 9191]: " NEW_PORT
            if [[ -z "$NEW_PORT" ]]; then
                PORT=9191
            else
                PORT=$NEW_PORT
            fi
        else
            PORT=$OLD_PORT
            if [[ -z "$PORT" ]]; then
                PORT=9191
            fi
        fi
        SKIP_CONFIG=0
    fi
else
    read -p "Enter port for speedtest-agent [default: 9191]: " NEW_PORT
    if [[ -z "$NEW_PORT" ]]; then
        PORT=9191
    else
        PORT=$NEW_PORT
    fi
    SKIP_CONFIG=0
fi

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Please use sudo."
fi

info "Starting Speedtest Agent installation with authentication..."

# 2. Install dependencies (speedtest-cli)
info "Checking for and installing speedtest-cli..."
if command -v apt-get &> /dev/null; then
    if ! command -v speedtest &> /dev/null; then
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash > /dev/null
        apt-get update > /dev/null
        apt-get install -y speedtest > /dev/null
        info "speedtest-cli has been installed."
    else
        info "speedtest-cli is already installed."
    fi
elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
    if ! command -v speedtest &> /dev/null; then
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash > /dev/null
        yum install -y speedtest > /dev/null
        info "speedtest-cli has been installed."
    else
        info "speedtest-cli is already installed."
    fi
else
    error "Unsupported package manager. Please install speedtest-cli manually."
fi

# 3. Download and install the agent binary
if systemctl list-unit-files | grep -q "^$AGENT_SERVICE_NAME\.service"; then
    info "Stopping speedtest-agent service before updating binary..."
    systemctl stop $AGENT_SERVICE_NAME
fi
info "Downloading the speedtest-agent binary..."
curl -L -s -o "$AGENT_INSTALL_PATH/$AGENT_SERVICE_NAME" "$AGENT_BINARY_URL"
if [ $? -ne 0 ]; then
    error "Failed to download agent binary. Check the URL ($AGENT_BINARY_URL) and your network connection."
fi
chmod +x "$AGENT_INSTALL_PATH/$AGENT_SERVICE_NAME"
info "Agent binary installed to $AGENT_INSTALL_PATH/$AGENT_SERVICE_NAME"

# 4. Generate token and create config file
if [ $SKIP_CONFIG -eq 0 ]; then
    info "Generating authentication token and creating config file..."
    AUTH_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+')
    mkdir -p "$CONFIG_DIR"  
    cat << EOF > "$CONFIG_FILE"
{
  "auth_token": "$AUTH_TOKEN",
  "port": $PORT
}
EOF
    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
    info "Configuration file created at $CONFIG_FILE"
else
    info "Skipped config.json creation."
fi

# 5. Create systemd service file
info "Creating systemd service file..."
cat << EOF > /etc/systemd/system/$AGENT_SERVICE_NAME.service
[Unit]
Description=Speedtest Agent
After=network.target

[Service]
Type=simple
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# The agent is now started with the path to its config file
ExecStart=$AGENT_INSTALL_PATH/$AGENT_SERVICE_NAME -config $CONFIG_FILE
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 6. Start the service
info "Reloading systemd, enabling and starting the agent service..."
systemctl daemon-reload
systemctl enable $AGENT_SERVICE_NAME > /dev/null
systemctl start $AGENT_SERVICE_NAME

# 7. Display status and the token
info "Installation complete. Service is running."
if [ $SKIP_CONFIG -eq 0 ]; then
    warn "======================================================================"
    warn "IMPORTANT: Please save this token. It is needed to authenticate."
    warn ""
    warn "  Agent Token: $AUTH_TOKEN"
    warn ""
    warn "======================================================================"
    warn "Example usage:"
    warn "  curl -H \"Authorization: Bearer $AUTH_TOKEN\" http://localhost:9191/speedtest"
fi

info "You can check the service status with: systemctl status $AGENT_SERVICE_NAME --no-pager"
info "You can check its logs with: journalctl -u $AGENT_SERVICE_NAME -f"