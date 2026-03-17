package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/db"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all open preflight PRs",
	RunE: func(cmd *cobra.Command, args []string) error {
		prs, err := db.ListOpenPullRequests()
		if err != nil {
			return fmt.Errorf("failed to list PRs: %w", err)
		}

		if len(prs) == 0 {
			fmt.Println("No open preflight PRs.")
			return nil
		}

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(w, "REPO\tBRANCH\tCREATED")
		for _, pr := range prs {
			fmt.Fprintf(w, "%s\t%s\t%s\n", pr.RepoName, pr.SourceBranch, timeAgo(pr.CreatedAt))
		}
		w.Flush()
		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
}

func timeAgo(t time.Time) string {
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		m := int(d.Minutes())
		if m == 1 {
			return "1 minute ago"
		}
		return fmt.Sprintf("%d minutes ago", m)
	case d < 24*time.Hour:
		h := int(d.Hours())
		if h == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", h)
	default:
		days := int(d.Hours() / 24)
		if days == 1 {
			return "yesterday"
		}
		return fmt.Sprintf("%d days ago", days)
	}
}
