package server

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/zhubert/preflight-cli/internal/config"
)

const (
	DefaultPort    = 3000
	HealthEndpoint = "/api/status"
	StartTimeout   = 15 * time.Second
)

func ServerURL() string {
	return fmt.Sprintf("http://localhost:%d", DefaultPort)
}

func IsRunning() bool {
	pid, err := readPID()
	if err != nil {
		return false
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	return process.Signal(syscall.Signal(0)) == nil
}

func EnsureRunning() error {
	if IsRunning() {
		return nil
	}
	return Start()
}

func Start() error {
	if IsRunning() {
		return fmt.Errorf("server is already running")
	}

	if err := config.EnsureHomeDir(); err != nil {
		return fmt.Errorf("failed to create ~/.preflight: %w", err)
	}

	serverBin, serverArgs := findServerCommand()
	if serverBin == "" {
		return fmt.Errorf("could not find preflight server. Is it installed correctly?")
	}

	logFile, err := os.OpenFile(config.LogPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to open log file: %w", err)
	}

	cmd := exec.Command(serverBin, serverArgs...)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("PREFLIGHT_DB_PATH=%s", config.DBPath()),
		fmt.Sprintf("PIDFILE=%s", config.PIDPath()),
		fmt.Sprintf("PORT=%d", DefaultPort),
		"PREFLIGHT_IDLE_SHUTDOWN=1",
		fmt.Sprintf("PREFLIGHT_UPLOADS_PATH=%s", filepath.Join(config.HomeDir(), "uploads")),
		"RAILS_ENV=production",
	)

	if err := cmd.Start(); err != nil {
		logFile.Close()
		return fmt.Errorf("failed to start server: %w", err)
	}

	cmd.Process.Release()
	logFile.Close()

	return waitForHealthy(StartTimeout)
}

func Stop() error {
	pid, err := readPID()
	if err != nil {
		return fmt.Errorf("server is not running (no PID file)")
	}

	process, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("could not find process %d: %w", pid, err)
	}

	if err := process.Signal(syscall.SIGTERM); err != nil {
		return fmt.Errorf("could not stop server: %w", err)
	}

	for i := 0; i < 30; i++ {
		if process.Signal(syscall.Signal(0)) != nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	os.Remove(config.PIDPath())
	return nil
}

func Restart() error {
	if IsRunning() {
		if err := Stop(); err != nil {
			return err
		}
	}
	return Start()
}

func waitForHealthy(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	url := fmt.Sprintf("%s%s", ServerURL(), HealthEndpoint)

	for time.Now().Before(deadline) {
		resp, err := http.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}

	return fmt.Errorf("server did not become healthy within %s", timeout)
}

func readPID() (int, error) {
	data, err := os.ReadFile(config.PIDPath())
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(data)))
}

func findServerCommand() (string, []string) {
	exe, err := os.Executable()
	if err != nil {
		return "", nil
	}
	dir := filepath.Dir(filepath.Dir(exe))
	candidate := filepath.Join(dir, "libexec", "bin", "start-server")
	if _, err := os.Stat(candidate); err == nil {
		return candidate, nil
	}

	devCandidate := filepath.Join(filepath.Dir(filepath.Dir(exe)), "bin", "rails")
	if _, err := os.Stat(devCandidate); err == nil {
		return devCandidate, []string{"server"}
	}

	return "", nil
}
