package main

import (
	"github.com/rs/zerolog"
	"pythoner6.dev/homelab/yubikey-dra/cmd"
)

func main() {
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
	err := cmd.Execute()
	if err != nil {
		panic(err)
	}
}
