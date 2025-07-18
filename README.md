# speedtest-agent

`speedtest-agent` is a network speed test server with authentication, suitable for automated speed testing and health check scenarios.

## Features

- Provides an HTTP endpoint `/speedtest` that returns bandwidth, latency, and other speed test data
- Requires token authentication for security
- Uses [ookla/speedtest-cli](https://www.speedtest.net/apps/cli) for speed testing
- Supports systemd service deployment

## Installation

### One-click Installation (Recommended)

You can install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/ianchenx/speedtest-agent/main/install.sh -o install.sh && sudo bash install.sh
```

> The installation script will automatically install `speedtest-cli`, download the agent binary, generate configuration, and set up the systemd service.
>
> **Note:** The agent now always listens on port **9191** (fixed), not random. Please make sure this port is available and open in your firewall.

### Manual Installation

1.  **Download and run the installation script**

    ```bash
    sudo bash install.sh
    ```

2.  **Save the Token**

    After installation, the script will output the `Agent Token`. Please keep it safe. This token is required for API requests.

3.  **Check service status**

    ```bash
    systemctl status speedtest-agent --no-pager
    journalctl -u speedtest-agent -f
    ```

## Usage

- HTTP request example:

  ```bash
  curl -H "Authorization: Bearer <YourToken>" http://localhost:9191/speedtest
  ```

- Response example:

  ```json
  {
    "download_speed_MB_s": 12.34,
    "upload_speed_MB_s": 5.67,
    "latency_ms": 20.1,
    "server_country": "China",
    "server_host": "speedtest.example.com"
  }
  ```

## Configuration File

- Path: `/etc/speedtest-agent/config.json`
- Example content:

  ```json
  {
    "auth_token": "your_token_here"
  }
  ```

## Notes

- Installation and running require root privileges
- Depends on `speedtest-cli` (the installation script will handle this automatically)
- The port is now always **9191** and does not need to be set in config.json. Only the token is required in the config file.
