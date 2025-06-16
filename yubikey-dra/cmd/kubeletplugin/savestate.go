package kubeletplugin

import (
	resourceapi "k8s.io/api/resource/v1beta1"
	"k8s.io/dynamic-resource-allocation/kubeletplugin"
	"pythoner6.dev/homelab/yubikey-dra/pkg/discovery"
)

type SaveState struct {
	V1 *PreparedClaimV1 `json:"v1,omitempty"`
}

type PreparedClaimV1 struct {
	Status          resourceapi.ResourceClaimStatus `json:"status"`
	PreparedDevices []PreparedDeviceV1              `json:"preparedDevices,omitempty"`
}

type PreparedDeviceV1 struct {
	Info   discovery.Device     `json:"info"`
	Device kubeletplugin.Device `json:"device"`
}

func (state *SaveState) GetDevices() []kubeletplugin.Device {
	if state.V1 != nil {
		devices := []kubeletplugin.Device{}
		for _, device := range state.V1.PreparedDevices {
			devices = append(devices, device.Device)
		}
		return devices
	}

	return nil
}
