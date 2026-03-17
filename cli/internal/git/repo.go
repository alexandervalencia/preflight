package git

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

func RepoRoot() (string, error) {
	out, err := run("rev-parse", "--show-toplevel")
	if err != nil {
		return "", fmt.Errorf("not a git repository")
	}
	return filepath.Clean(out), nil
}

func CurrentBranch() (string, error) {
	out, err := run("branch", "--show-current")
	if err != nil {
		return "", fmt.Errorf("failed to get current branch: %w", err)
	}
	if out == "" {
		return "", fmt.Errorf("HEAD is detached — checkout a branch first")
	}
	return out, nil
}

func DefaultBranch() (string, error) {
	out, err := run("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
	if err == nil && out != "" {
		parts := strings.Split(out, "/")
		return parts[len(parts)-1], nil
	}

	if _, err := run("rev-parse", "--verify", "--quiet", "refs/heads/main"); err == nil {
		return "main", nil
	}

	if _, err := run("rev-parse", "--verify", "--quiet", "refs/heads/master"); err == nil {
		return "master", nil
	}

	return CurrentBranch()
}

func run(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
