package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

func CreatePullRequest(repoPath, sourceBranch, baseBranch string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/api/pull_requests", ServerURL())

	payload := map[string]string{
		"repo_path":     repoPath,
		"source_branch": sourceBranch,
		"base_branch":   baseBranch,
	}
	body, _ := json.Marshal(payload)

	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		return nil, fmt.Errorf("failed to contact server: %w", err)
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("invalid response from server: %w", err)
	}

	if resp.StatusCode >= 400 {
		errors, _ := result["errors"]
		return nil, fmt.Errorf("server error: %v", errors)
	}

	return result, nil
}

func FindPullRequest(repoPath, sourceBranch string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/api/pull_requests?repo_path=%s&source_branch=%s",
		ServerURL(), repoPath, sourceBranch)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to contact server: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return nil, nil
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("invalid response from server: %w", err)
	}

	return result, nil
}
