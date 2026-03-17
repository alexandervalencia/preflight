package db

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/zhubert/preflight-cli/internal/config"
	_ "modernc.org/sqlite"
)

type PullRequestRow struct {
	RepoName     string
	SourceBranch string
	CreatedAt    time.Time
}

func ListOpenPullRequests() ([]PullRequestRow, error) {
	dbPath := config.DBPath()
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database at %s: %w", dbPath, err)
	}
	defer db.Close()

	rows, err := db.Query(`
		SELECT lr.name, pr.source_branch, pr.created_at
		FROM pull_requests pr
		JOIN local_repositories lr ON lr.id = pr.local_repository_id
		WHERE pr.status = 'open'
		ORDER BY pr.created_at DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}
	defer rows.Close()

	var results []PullRequestRow
	for rows.Next() {
		var r PullRequestRow
		var createdStr string
		if err := rows.Scan(&r.RepoName, &r.SourceBranch, &createdStr); err != nil {
			return nil, fmt.Errorf("scan failed: %w", err)
		}
		for _, layout := range []string{
			"2006-01-02 15:04:05.999999",
			"2006-01-02T15:04:05.999999",
			"2006-01-02 15:04:05",
			time.RFC3339,
		} {
			if t, err := time.Parse(layout, createdStr); err == nil {
				r.CreatedAt = t
				break
			}
		}
		results = append(results, r)
	}
	return results, nil
}
