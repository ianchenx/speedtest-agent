package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// --- Structs ---

// AgentConfig holds the configuration loaded from a JSON file.
type AgentConfig struct {
	AuthToken string `json:"auth_token"`
	Port      int    `json:"port"`
}

// SpeedtestCliOutput matches the structure of `speedtest-cli --format=json`
type SpeedtestCliOutput struct {
	Type      string    `json:"type"`
	Timestamp time.Time `json:"timestamp"`
	Ping      struct {
		Jitter  float64 `json:"jitter"`
		Latency float64 `json:"latency"`
	} `json:"ping"`
	Download struct {
		Bandwidth int `json:"bandwidth"`
	} `json:"download"`
	Upload struct {
		Bandwidth int `json:"bandwidth"`
	} `json:"upload"`
	Server struct {
		Host    string `json:"host"`
		Country string `json:"country"`
	} `json:"server"`
}

// AgentResponse is the simplified structure we return to the main app.
type AgentResponse struct {
	DownloadSpeedMBS float64 `json:"download_speed_MB_s"`
	UploadSpeedMBS   float64 `json:"upload_speed_MB_s"`
	LatencyMs        float64 `json:"latency_ms"`
	ServerCountry    string  `json:"server_country"`
	ServerHost       string  `json:"server_host"`
	Error            string  `json:"error,omitempty"`
}

// App holds application-wide state, like the auth token.
type App struct {
	authToken string
}

// --- Main Logic ---

// loadConfig reads the configuration file and returns the AgentConfig.
func loadConfig(path string) (*AgentConfig, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var config AgentConfig
	if err := json.NewDecoder(file).Decode(&config); err != nil {
		return nil, err
	}

	if config.AuthToken == "" {
		return nil, log.Output(1, "auth_token is missing from config file")
	}

	return &config, nil
}

// speedTestHandler is the HTTP handler that requires authentication.
func (app *App) speedTestHandler(w http.ResponseWriter, r *http.Request) {
	// 1. Authenticate the request
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		http.Error(w, "Authorization header is required", http.StatusUnauthorized)
		return
	}

	splitToken := strings.Split(authHeader, "Bearer ")
	if len(splitToken) != 2 {
		http.Error(w, "Invalid Authorization header format", http.StatusUnauthorized)
		return
	}

	if splitToken[1] != app.authToken {
		http.Error(w, "Invalid token", http.StatusUnauthorized)
		return
	}

	// 2. Run the speed test (if authenticated)
	log.Println("Request authenticated. Executing speed test...")
	cmd := exec.Command("speedtest", "--format=json", "--accept-license", "--accept-gdpr")
	output, err := cmd.CombinedOutput()
	w.Header().Set("Content-Type", "application/json")

	if err != nil {
		log.Printf("Speedtest command failed: %s\nOutput: %s", err, string(output))
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(AgentResponse{Error: "Failed to execute speedtest-cli: " + err.Error()})
		return
	}

	var cliResult SpeedtestCliOutput
	if err := json.Unmarshal(output, &cliResult); err != nil {
		log.Printf("Failed to parse speedtest JSON: %s", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(AgentResponse{Error: "Failed to parse speedtest-cli output: " + err.Error()})
		return
	}

	// 3. Format and return the response
	// Convert bandwidth from bytes/sec to MB/s
	downloadMBS := float64(cliResult.Download.Bandwidth) / 8 / 1e6
	uploadMBS := float64(cliResult.Upload.Bandwidth) / 8 / 1e6
	response := AgentResponse{
		DownloadSpeedMBS: downloadMBS,
		UploadSpeedMBS:   uploadMBS,
		LatencyMs:        cliResult.Ping.Latency,
		ServerCountry:    cliResult.Server.Country,
		ServerHost:       cliResult.Server.Host,
	}

	log.Printf("Speed test successful. Download: %.2f MB/s, Upload: %.2f MB/s", downloadMBS, uploadMBS)
	json.NewEncoder(w).Encode(response)
}

func main() {
	// Define and parse command-line flags
	configPath := flag.String("config", "/etc/speedtest-agent/config.json", "Path to JSON config file")
	flag.Parse()

	// Load configuration
	config, err := loadConfig(*configPath)
	if err != nil {
		log.Fatalf("Failed to load config file at %s: %v", *configPath, err)
	}

	// Create the app instance with the token
	app := &App{authToken: config.AuthToken}

	// Set up the HTTP server
	http.HandleFunc("/speedtest", app.speedTestHandler)
	addr := ":" + strconv.Itoa(config.Port)
	log.Printf("Starting speedtest-agent on port %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
