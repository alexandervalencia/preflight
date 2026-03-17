package config

import (
	"os"
	"path/filepath"
)

func HomeDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".preflight")
}

func DBPath() string {
	return filepath.Join(HomeDir(), "db.sqlite3")
}

func PIDPath() string {
	return filepath.Join(HomeDir(), "preflight.pid")
}

func LogPath() string {
	return filepath.Join(HomeDir(), "preflight.log")
}

func EnsureHomeDir() error {
	return os.MkdirAll(HomeDir(), 0755)
}
