package kubeletplugin

import (
	"fmt"

	"pythoner6.dev/homelab/yubikey-dra/pkg/config"
	cdiapi "tags.cncf.io/container-device-interface/pkg/cdi"
	cdiparser "tags.cncf.io/container-device-interface/pkg/parser"
	cdispec "tags.cncf.io/container-device-interface/specs-go"
)

const cdiClass = "yubikey"

type CDIHandler struct {
	vendor string
	cache  *cdiapi.Cache
}

func NewCDIHandler(config config.KubeletpluginConfig) (*CDIHandler, error) {
	cache, err := cdiapi.NewCache(
		cdiapi.WithSpecDirs(config.CDIRoot),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create cdi cache: %w", err)
	}
	handler := &CDIHandler{
		cache:  cache,
		vendor: "k8s." + config.DriverName,
	}

	return handler, nil
}

func (cdi *CDIHandler) CreateClaimSpecFile(claimUID string, devices []PreparedDeviceV1) error {
	specName := cdiapi.GenerateTransientSpecName(cdi.vendor, cdiClass, claimUID)

	spec := &cdispec.Spec{
		Kind:    cdi.vendor + "/" + cdiClass,
		Devices: []cdispec.Device{},
	}

	for _, device := range devices {
		claimEdits := cdiapi.ContainerEdits{
			ContainerEdits: &cdispec.ContainerEdits{},
		}

		claimEdits.ContainerEdits.DeviceNodes = append(claimEdits.ContainerEdits.DeviceNodes, &cdispec.DeviceNode{
			Path: device.Info.Devname,
		})

		for _, child := range device.Info.Children {
			claimEdits.ContainerEdits.DeviceNodes = append(claimEdits.ContainerEdits.DeviceNodes, &cdispec.DeviceNode{
				Path: child.Devname,
			})
		}

		cdiDevice := cdispec.Device{
			Name:           fmt.Sprintf("%s-%s", claimUID, device.Info.Name),
			ContainerEdits: *claimEdits.ContainerEdits,
		}

		spec.Devices = append(spec.Devices, cdiDevice)
	}

	minVersion, err := cdiapi.MinimumRequiredVersion(spec)
	if err != nil {
		return fmt.Errorf("failed to get minimum required CDI spec version: %v", err)
	}
	spec.Version = minVersion

	return cdi.cache.WriteSpec(spec, specName)
}

func (cdi *CDIHandler) DeleteClaimSpecFile(claimUID string) error {
	specName := cdiapi.GenerateTransientSpecName(cdi.vendor, cdiClass, claimUID)
	return cdi.cache.RemoveSpec(specName)
}

func (cdi *CDIHandler) GetClaimDevices(claimUID string, devices []string) []string {
	cdiDevices := []string{}
	for _, device := range devices {
		cdiDevice := cdiparser.QualifiedName(cdi.vendor, cdiClass, fmt.Sprintf("%s-%s", claimUID, device))
		cdiDevices = append(cdiDevices, cdiDevice)
	}

	return cdiDevices
}
