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
	DefaultPort    = 4500
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

	serverCmd := findServerCommand()
	if serverCmd.bin == "" {
		return fmt.Errorf("could not find preflight server. Is it installed correctly?")
	}

	// Clear RUBYOPT to avoid inheriting flags from another project's devbox
	// (e.g., --suppress-warnings from a Ruby 3.5+ project)
	os.Unsetenv("RUBYOPT")

	// Inject preflight-specific env vars into the process environment.
	// These are inherited by all child processes (db:prepare and server).
	os.Setenv("PREFLIGHT_DB_PATH", config.DBPath())
	os.Setenv("PIDFILE", config.PIDPath())
	os.Setenv("PORT", fmt.Sprintf("%d", DefaultPort))
	os.Setenv("PREFLIGHT_IDLE_SHUTDOWN", "1")
	os.Setenv("PREFLIGHT_UPLOADS_PATH", filepath.Join(config.HomeDir(), "uploads"))
	if !serverCmd.dev {
		os.Setenv("RAILS_ENV", "production")
	}

	// Run db:prepare to ensure the database exists and is migrated
	if err := runRailsCommand(serverCmd, "db:prepare"); err != nil {
		return err
	}

	logFile, err := os.OpenFile(config.LogPath(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to open log file: %w", err)
	}

	// Start the server with the devbox environment plus preflight vars.
	// Filter out RUBYOPT to prevent cross-project contamination.
	var serverEnv []string
	for _, e := range serverCmd.env {
		if !strings.HasPrefix(e, "RUBYOPT=") {
			serverEnv = append(serverEnv, e)
		}
	}
	serverEnv = append(serverEnv,
		fmt.Sprintf("PREFLIGHT_DB_PATH=%s", config.DBPath()),
		fmt.Sprintf("PIDFILE=%s", config.PIDPath()),
		fmt.Sprintf("PORT=%d", DefaultPort),
		"PREFLIGHT_IDLE_SHUTDOWN=1",
		fmt.Sprintf("PREFLIGHT_UPLOADS_PATH=%s", filepath.Join(config.HomeDir(), "uploads")),
	)
	if !serverCmd.dev {
		serverEnv = append(serverEnv, "RAILS_ENV=production")
	}
	cmd := exec.Command(serverCmd.bin, serverCmd.args...)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.Dir = serverCmd.dir
	cmd.Env = serverEnv

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

type serverCommand struct {
	bin      string
	args     []string
	dir      string
	env      []string
	dev      bool
	rubyPath string // absolute path to ruby binary (dev mode)
	railsPath string // absolute path to bin/rails (dev mode)
}

// railsBin returns the command parts to run a rails command (e.g., ["ruby", "bin/rails"])
func (s serverCommand) railsBin() []string {
	if s.rubyPath != "" {
		return []string{s.rubyPath, s.railsPath}
	}
	return []string{s.bin}
}

func findServerCommand() serverCommand {
	// Dev override: PREFLIGHT_SERVER_DIR points to the Rails app root
	if serverDir := os.Getenv("PREFLIGHT_SERVER_DIR"); serverDir != "" {
		return devServerCommand(serverDir)
	}

	// Production: look relative to the binary
	exe, err := os.Executable()
	if err != nil {
		return serverCommand{}
	}

	// Resolve symlinks so dev symlinks work
	exe, err = filepath.EvalSymlinks(exe)
	if err != nil {
		return serverCommand{}
	}

	// Production layout: prefix/bin/preflight → prefix/libexec/bin/start-server
	dir := filepath.Dir(filepath.Dir(exe))
	candidate := filepath.Join(dir, "libexec", "bin", "start-server")
	if _, err := os.Stat(candidate); err == nil {
		return serverCommand{bin: candidate, env: os.Environ()}
	}

	// Dev layout: project/tmp/preflight → project/bin/rails
	projectDir := dir
	if _, err := os.Stat(filepath.Join(projectDir, "bin", "rails")); err == nil {
		return devServerCommand(projectDir)
	}

	return serverCommand{}
}

func devServerCommand(projectDir string) serverCommand {
	rails := filepath.Join(projectDir, "bin", "rails")
	if _, err := os.Stat(rails); err != nil {
		return serverCommand{}
	}

	env := os.Environ()
	rubyBin := "ruby"

	// If the project uses devbox, capture its shell environment so the
	// spawned process gets the right Ruby/PATH without needing `devbox run`
	devboxJSON := filepath.Join(projectDir, "devbox.json")
	if _, err := os.Stat(devboxJSON); err == nil {
		if devboxEnv, err := captureDevboxEnv(devboxJSON); err == nil {
			env = devboxEnv
			// Find the devbox ruby explicitly so we don't rely on shebang resolution
			for _, e := range env {
				if strings.HasPrefix(e, "PATH=") {
					paths := strings.Split(e[5:], ":")
					for _, p := range paths {
						candidate := filepath.Join(p, "ruby")
						if _, err := os.Stat(candidate); err == nil {
							rubyBin = candidate
							break
						}
					}
					break
				}
			}
		}
	}

	// Run ruby explicitly instead of relying on #!/usr/bin/env shebang
	return serverCommand{
		bin:       rubyBin,
		args:      []string{rails, "server"},
		dir:       projectDir,
		env:       env,
		dev:       true,
		rubyPath:  rubyBin,
		railsPath: rails,
	}
}

func runRailsCommand(serverCmd serverCommand, railsArgs ...string) error {
	// In dev mode with devbox, use `devbox run` which fully manages PATH/Ruby.
	// Don't set cmd.Env — devbox sets up its own env, and preflight vars
	// are already in os env via os.Setenv above.
	devboxJSON := filepath.Join(serverCmd.dir, "devbox.json")
	if serverCmd.dev {
		if devbox, err := exec.LookPath("devbox"); err == nil {
			if _, err := os.Stat(devboxJSON); err == nil {
				args := []string{"run", "--config", devboxJSON, "--", "bin/rails"}
				args = append(args, railsArgs...)
				cmd := exec.Command(devbox, args...)
				cmd.Dir = serverCmd.dir
				if out, err := cmd.CombinedOutput(); err != nil {
					return fmt.Errorf("failed to run rails %s: %s", strings.Join(railsArgs, " "), string(out))
				}
				return nil
			}
		}
	}

	// Fallback: run ruby directly (production)
	args := append([]string{serverCmd.railsPath}, railsArgs...)
	cmd := exec.Command(serverCmd.bin, args...)
	cmd.Dir = serverCmd.dir
	cmd.Env = serverCmd.env
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to run rails %s: %s", strings.Join(railsArgs, " "), string(out))
	}
	return nil
}

func captureDevboxEnv(devboxJSON string) ([]string, error) {
	devbox, err := exec.LookPath("devbox")
	if err != nil {
		return nil, err
	}

	out, err := exec.Command(devbox, "shellenv", "--config", devboxJSON).Output()
	if err != nil {
		return nil, err
	}

	// Start with current env, then apply devbox overrides
	env := os.Environ()
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "export ") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		// Strip trailing semicolon: export KEY="value";
		line = strings.TrimSuffix(line, ";")
		if eqIdx := strings.Index(line, "="); eqIdx > 0 {
			key := line[:eqIdx]
			val := line[eqIdx+1:]
			val = strings.Trim(val, "\"")
			found := false
			for i, existing := range env {
				if strings.HasPrefix(existing, key+"=") {
					env[i] = key + "=" + val
					found = true
					break
				}
			}
			if !found {
				env = append(env, key+"="+val)
			}
		}
	}
	return env, nil
}
