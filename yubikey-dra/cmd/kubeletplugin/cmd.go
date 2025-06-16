package kubeletplugin

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"pythoner6.dev/homelab/yubikey-dra/pkg/config"
	"pythoner6.dev/homelab/yubikey-dra/pkg/discovery"
)

var kubeletpluginCmd = &cobra.Command{
	Use: "kubeletplugin",
	RunE: func(cmd *cobra.Command, args []string) error {
		var wg sync.WaitGroup
		err, monitor := discovery.Init(cmd.Context(), &wg)
		if err != nil {
			return err
		}
		config.BindEnvs()
		var config config.Config
		viper.SetEnvPrefix("YUBIKEYDRA")
		viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
		viper.AutomaticEnv()
		viper.Unmarshal(&config)
		fmt.Printf("Config: %v\n", config)
		driver, err := NewDriver(cmd.Context(), config.Kubeletplugin)
		if err != nil {
			return err
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			monitor.Run(func(devices map[string]discovery.Device) {
				devarr := zerolog.Arr()
				for _, dev := range devices {
					devarr.Str(dev.Syspath)
				}
				log.Info().Array("devices", devarr).Msg("enumerated devices")
				if err := driver.UpdateDevices(cmd.Context(), devices); err != nil {
					log.Err(err).Msg("error publishing devices")
				}
			})
			log.Info().Msg("monitoring shutdown")
		}()
		<-cmd.Context().Done()
		log.Info().Msg("shutting down")
		driver.Shutdown(context.Background())

		wg.Wait()
		return nil
	},
}

func AddCommands(parent *cobra.Command) {
	parent.AddCommand(kubeletpluginCmd)
}
