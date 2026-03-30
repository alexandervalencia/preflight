package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/git"
	"github.com/zhubert/preflight-cli/internal/server"
)

var baseBranch string
var prTitle string
var prBody string
var prBodyFile string

var pushCmd = &cobra.Command{
	Use:   "push",
	Short: "Create or open a preflight PR for the current branch",
	RunE: func(cmd *cobra.Command, args []string) error {
		repoPath, err := git.RepoRoot()
		if err != nil {
			return err
		}

		branch, err := git.CurrentBranch()
		if err != nil {
			return err
		}

		base := baseBranch
		if base == "" {
			base, err = git.DefaultBranch()
			if err != nil {
				return fmt.Errorf("could not determine default branch: %w", err)
			}
		}

		if branch == base {
			return fmt.Errorf("you're on %s — switch to a feature branch first", base)
		}

		fmt.Println("Starting preflight server...")
		if err := server.EnsureRunning(); err != nil {
			return fmt.Errorf("failed to start server: %w", err)
		}

		description := prBody
		if prBodyFile != "" {
			content, err := os.ReadFile(prBodyFile)
			if err != nil {
				return fmt.Errorf("failed to read body file: %w", err)
			}
			description = string(content)
		}

		fmt.Printf("Creating PR for %s → %s...\n", branch, base)
		result, err := server.CreatePullRequest(repoPath, branch, base, prTitle, description)
		if err != nil {
			return err
		}

		path, _ := result["url"].(string)
		repoName, _ := result["repository_name"].(string)
		created, _ := result["created"].(bool)
		fullURL := fmt.Sprintf("%s%s", server.ServerURL(), path)

		if created {
			fmt.Printf("Created preflight PR in %s\n", repoName)
		} else {
			fmt.Printf("Opened existing preflight PR in %s\n", repoName)
		}

		fmt.Printf("Opening %s\n", fullURL)
		return openBrowser(fullURL)
	},
}

func init() {
	pushCmd.Flags().StringVar(&baseBranch, "base", "", "Base branch (defaults to main/master)")
	pushCmd.Flags().StringVarP(&prTitle, "title", "t", "", "PR title (defaults to branch name)")
	pushCmd.Flags().StringVarP(&prBody, "body", "b", "", "PR description")
	pushCmd.Flags().StringVar(&prBodyFile, "body-file", "", "Read PR description from file")
	rootCmd.AddCommand(pushCmd)
}

func openBrowser(url string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	default:
		fmt.Fprintf(os.Stderr, "Open this URL in your browser: %s\n", url)
		return nil
	}
	return cmd.Start()
}
