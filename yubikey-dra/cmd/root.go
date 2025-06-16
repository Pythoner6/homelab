package cmd

import (
	"context"
	"github.com/spf13/cobra"
	"os"
	"os/signal"
	"pythoner6.dev/homelab/yubikey-dra/cmd/kubeletplugin"
)

var rootCmd = &cobra.Command{
	Use: "yubikey-dra",
}

func Execute() error {
	ctx, cancel := context.WithCancelCause(context.Background())

	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, os.Kill)
		<-sig
		cancel(nil)
	}()
	kubeletplugin.AddCommands(rootCmd)
	return rootCmd.ExecuteContext(ctx)
}
