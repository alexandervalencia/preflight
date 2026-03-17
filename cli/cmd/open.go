package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/git"
	"github.com/zhubert/preflight-cli/internal/server"
)

var openCmd = &cobra.Command{
	Use:   "open",
	Short: "Open the preflight PR for the current branch in your browser",
	RunE: func(cmd *cobra.Command, args []string) error {
		repoPath, err := git.RepoRoot()
		if err != nil {
			return err
		}

		branch, err := git.CurrentBranch()
		if err != nil {
			return err
		}

		if err := server.EnsureRunning(); err != nil {
			return fmt.Errorf("failed to start server: %w", err)
		}

		result, err := server.FindPullRequest(repoPath, branch)
		if err != nil {
			return fmt.Errorf("failed to look up PR: %w", err)
		}
		if result == nil {
			return fmt.Errorf("no preflight PR found for branch %s — use 'preflight push' to create one", branch)
		}

		url, _ := result["url"].(string)
		fullURL := fmt.Sprintf("%s%s", server.ServerURL(), url)
		fmt.Printf("Opening %s\n", fullURL)
		return openBrowser(fullURL)
	},
}

func init() {
	rootCmd.AddCommand(openCmd)
}
