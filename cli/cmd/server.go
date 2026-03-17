package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/zhubert/preflight-cli/internal/server"
)

var serverCmd = &cobra.Command{
	Use:   "server",
	Short: "Manage the preflight server",
}

var serverStartCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the preflight server",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Starting preflight server...")
		if err := server.Start(); err != nil {
			return err
		}
		fmt.Printf("Server running at %s\n", server.ServerURL())
		return nil
	},
}

var serverStopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop the preflight server",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Stopping preflight server...")
		if err := server.Stop(); err != nil {
			return err
		}
		fmt.Println("Server stopped.")
		return nil
	},
}

var serverRestartCmd = &cobra.Command{
	Use:   "restart",
	Short: "Restart the preflight server",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Restarting preflight server...")
		if err := server.Restart(); err != nil {
			return err
		}
		fmt.Printf("Server running at %s\n", server.ServerURL())
		return nil
	},
}

func init() {
	serverCmd.AddCommand(serverStartCmd)
	serverCmd.AddCommand(serverStopCmd)
	serverCmd.AddCommand(serverRestartCmd)
	rootCmd.AddCommand(serverCmd)
}
