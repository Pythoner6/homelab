package config

import (
	"github.com/spf13/viper"
	"reflect"
	"strings"
)

type Config struct {
	Kubeletplugin KubeletpluginConfig
}

type KubeletpluginConfig struct {
	DriverName             string
	NodeName               string
	RegistrarDirectoryPath string
	DriverPluginPath       string
	CDIRoot                string
}

func BindEnvs() {
	bindEnvs(Config{})
}

func bindEnvs(iface any, parts ...string) {
	ifv := reflect.ValueOf(iface)
	ift := reflect.TypeOf(iface)
	for i := range ift.NumField() {
		fieldv := ifv.Field(i)
		t := ift.Field(i)
		name := strings.ToLower(t.Name)
		tag, ok := t.Tag.Lookup("mapstructure")
		if ok {
			name = tag
		}
		path := append(parts, name)
		switch fieldv.Kind() {
		case reflect.Struct:
			bindEnvs(fieldv.Interface(), path...)
		default:
			viper.BindEnv(strings.Join(path, "."))
		}
	}
}
