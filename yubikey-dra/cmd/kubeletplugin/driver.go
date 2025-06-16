package kubeletplugin

import (
	"context"
	"encoding/json"
	"fmt"
	"path"
	"slices"
	"sync/atomic"

	"github.com/cockroachdb/pebble/v2"
	"github.com/rs/zerolog/log"
	resourceapi "k8s.io/api/resource/v1beta1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/dynamic-resource-allocation/kubeletplugin"
	"k8s.io/dynamic-resource-allocation/resourceslice"
	"k8s.io/utils/keymutex"
	configapi "pythoner6.dev/homelab/yubikey-dra/api/pythoner6.dev/resource/v1alpha1"
	"pythoner6.dev/homelab/yubikey-dra/pkg/config"
	"pythoner6.dev/homelab/yubikey-dra/pkg/discovery"
)

type driver struct {
	client     kubernetes.Interface
	helper     *kubeletplugin.Helper
	nodeName   string
	driverName string
	devices    atomic.Value
	state      *pebble.DB
	cdi        *CDIHandler
	mu         keymutex.KeyMutex
}

func NewDriver(ctx context.Context, config config.KubeletpluginConfig) (*driver, error) {
	k8sConfig, err := rest.InClusterConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to get in-cluster config: %w", err)
	}

	client, err := kubernetes.NewForConfig(k8sConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create k8s client: %w", err)
	}

	cdi, err := NewCDIHandler(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create cdi handler: %w", err)
	}

	pluginPath := path.Join(config.DriverPluginPath, config.DriverName)
	statePath := path.Join(pluginPath, "state")

	state, err := pebble.Open(statePath, &pebble.Options{})
	if err != nil {
		return nil, fmt.Errorf("failed to open state db: %w", err)
	}

	driver := &driver{
		client:     client,
		nodeName:   config.NodeName,
		driverName: config.DriverName,
		state:      state,
		cdi:        cdi,
		mu:         keymutex.NewHashed(0),
	}

	helper, err := kubeletplugin.Start(
		ctx,
		driver,
		kubeletplugin.KubeClient(client),
		kubeletplugin.NodeName(config.NodeName),
		kubeletplugin.DriverName(config.DriverName),
		kubeletplugin.RegistrarDirectoryPath(config.RegistrarDirectoryPath),
		kubeletplugin.PluginDataDirectoryPath(pluginPath),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to start kubelet plugin: %w", err)
	}
	driver.helper = helper

	return driver, nil
}

type OpaqueDeviceConfig struct {
	Requests []string
	Config   runtime.Object
}

// GetOpaqueDeviceConfigs returns an ordered list of the configs contained in possibleConfigs for this driver.
//
// Configs can either come from the resource claim itself or from the device
// class associated with the request. Configs coming directly from the resource
// claim take precedence over configs coming from the device class. Moreover,
// configs found later in the list of configs attached to its source take
// precedence over configs found earlier in the list for that source.
//
// All of the configs relevant to the driver from the list of possibleConfigs
// will be returned in order of precedence (from lowest to highest). If no
// configs are found, nil is returned.
func (d *driver) getOpaqueDeviceConfigs(
	decoder runtime.Decoder,
	possibleConfigs []resourceapi.DeviceAllocationConfiguration,
) ([]*OpaqueDeviceConfig, error) {
	// Collect all configs in order of reverse precedence.
	var classConfigs []resourceapi.DeviceAllocationConfiguration
	var claimConfigs []resourceapi.DeviceAllocationConfiguration
	var candidateConfigs []resourceapi.DeviceAllocationConfiguration
	for _, config := range possibleConfigs {
		switch config.Source {
		case resourceapi.AllocationConfigSourceClass:
			classConfigs = append(classConfigs, config)
		case resourceapi.AllocationConfigSourceClaim:
			claimConfigs = append(claimConfigs, config)
		default:
			return nil, fmt.Errorf("invalid config source: %v", config.Source)
		}
	}
	candidateConfigs = append(candidateConfigs, classConfigs...)
	candidateConfigs = append(candidateConfigs, claimConfigs...)

	// Decode all configs that are relevant for the driver.
	var resultConfigs []*OpaqueDeviceConfig
	for _, config := range candidateConfigs {
		// If this is nil, the driver doesn't support some future API extension
		// and needs to be updated.
		if config.Opaque == nil {
			return nil, fmt.Errorf("only opaque parameters are supported by this driver")
		}

		// Configs for different drivers may have been specified because a
		// single request can be satisfied by different drivers. This is not
		// an error -- drivers must skip over other driver's configs in order
		// to support this.
		if config.Opaque.Driver != d.driverName {
			continue
		}

		decodedConfig, err := runtime.Decode(decoder, config.Opaque.Parameters.Raw)
		if err != nil {
			return nil, fmt.Errorf("error decoding config parameters: %w", err)
		}

		resultConfig := &OpaqueDeviceConfig{
			Requests: config.Requests,
			Config:   decodedConfig,
		}

		resultConfigs = append(resultConfigs, resultConfig)
	}

	return resultConfigs, nil
}

func (d *driver) Shutdown(ctx context.Context) {
	d.helper.Stop()
	d.state.Close()
}

func (d *driver) PrepareResourceClaims(ctx context.Context, claims []*resourceapi.ResourceClaim) (map[types.UID]kubeletplugin.PrepareResult, error) {
	result := make(map[types.UID]kubeletplugin.PrepareResult)

	for _, claim := range claims {
		result[claim.UID] = d.prepareResourceClaim(ctx, claim)
	}

	return result, nil
}

func (d *driver) prepareResourceClaim(_ context.Context, claim *resourceapi.ResourceClaim) kubeletplugin.PrepareResult {
	if claim.Status.Allocation == nil {
		return kubeletplugin.PrepareResult{
			Err: fmt.Errorf("claim not yet allocated"),
		}
	}

	var prepResult kubeletplugin.PrepareResult
	key := "claim/" + string(claim.UID)
	d.mu.LockKey(key)
	defer d.mu.UnlockKey(key)

	existing, closer, err := d.state.Get([]byte(key))
	if closer != nil {
		defer closer.Close()
	}
	if err == nil {
		var state SaveState
		err = json.Unmarshal(existing, &state)
		if err != nil {
			return kubeletplugin.PrepareResult{Err: fmt.Errorf("error unmarshalling saved state: %w", err)}
		}

		log.Info().Str("claimUID", string(claim.UID)).Msg("claim already prepared")
		return kubeletplugin.PrepareResult{
			Devices: state.GetDevices(),
		}
	} else if err != pebble.ErrNotFound {
		return kubeletplugin.PrepareResult{Err: fmt.Errorf("error checking saved state: %w", err)}
	}

	configs, err := d.getOpaqueDeviceConfigs(configapi.Decoder, claim.Status.Allocation.Devices.Config)
	configs = slices.Insert(configs, 0, &OpaqueDeviceConfig{
		Requests: []string{},
		Config:   configapi.DefaultYubikeyConfig(),
	})

	configResultsMap := make(map[runtime.Object][]*resourceapi.DeviceRequestAllocationResult)
	devices := d.devices.Load().(map[string]discovery.Device)
	for _, result := range claim.Status.Allocation.Devices.Results {
		_, exists := devices[result.Device]
		if !exists {
			return kubeletplugin.PrepareResult{Err: fmt.Errorf("no such device: %v", result.Device)}
		}

		for _, c := range slices.Backward(configs) {
			if len(c.Requests) == 0 || slices.Contains(c.Requests, result.Request) {
				configResultsMap[c.Config] = append(configResultsMap[c.Config], &result)
				break
			}
		}
	}

	state := SaveState{
		V1: &PreparedClaimV1{
			Status:          claim.Status,
			PreparedDevices: []PreparedDeviceV1{},
		},
	}
	for _, results := range configResultsMap {
		for _, result := range results {
			state.V1.PreparedDevices = append(state.V1.PreparedDevices, PreparedDeviceV1{
				Info: devices[result.Device],
				Device: kubeletplugin.Device{
					Requests:     []string{result.Request},
					PoolName:     result.Pool,
					DeviceName:   result.Device,
					CDIDeviceIDs: d.cdi.GetClaimDevices(string(claim.UID), []string{devices[result.Device].Name}),
				},
			})
		}
	}

	err = d.cdi.CreateClaimSpecFile(string(claim.UID), state.V1.PreparedDevices)
	if err != nil {
		return kubeletplugin.PrepareResult{Err: fmt.Errorf("failed to create cdi spec: %w", err)}
	}

	serialized, err := json.Marshal(state)
	if err != nil {
		return kubeletplugin.PrepareResult{Err: fmt.Errorf("failed to serialize claim state: %w", err)}
	}
	d.state.Set([]byte(key), serialized, &pebble.WriteOptions{Sync: true})
	prepResult.Devices = state.GetDevices()

	return prepResult
}

func (d *driver) UnprepareResourceClaims(ctx context.Context, claims []kubeletplugin.NamespacedObject) (map[types.UID]error, error) {
	result := make(map[types.UID]error)

	for _, claim := range claims {
		result[claim.UID] = d.unprepareResourceClaim(ctx, claim)
	}

	return result, nil
}

func (d *driver) unprepareResourceClaim(_ context.Context, claim kubeletplugin.NamespacedObject) error {
	key := "claim/" + string(claim.UID)
	d.mu.LockKey(key)
	defer d.mu.UnlockKey(key)

	_, closer, err := d.state.Get([]byte(key))
	if closer != nil {
		closer.Close()
	}
	if err == pebble.ErrNotFound {
		log.Warn().Str("claimUID", string(claim.UID)).Msg("claim already unprepared")
		return nil
	} else if err != nil {
		return fmt.Errorf("error checking saved state: %w", err)
	}

	d.cdi.DeleteClaimSpecFile(string(claim.UID))

	return d.state.Delete([]byte(key), &pebble.WriteOptions{Sync: true})
}

func (d *driver) UpdateDevices(ctx context.Context, devices map[string]discovery.Device) error {
	resourceDevices := []resourceapi.Device{}
	byComputedName := map[string]discovery.Device{}

	for _, device := range devices {
		resourceDevices = append(resourceDevices, resourceapi.Device{
			Name: device.Name,
			Basic: &resourceapi.BasicDevice{
				Attributes: map[resourceapi.QualifiedName]resourceapi.DeviceAttribute{
					"pythoner6.dev/syspath": {
						StringValue: &device.Syspath,
					},
				},
				NodeName: &d.nodeName,
			},
		})
		byComputedName[device.Name] = device
	}

	d.devices.Store(byComputedName)

	resources := resourceslice.DriverResources{
		Pools: map[string]resourceslice.Pool{
			d.nodeName: {
				Slices: []resourceslice.Slice{
					{
						Devices: resourceDevices,
					},
				},
			},
		},
	}

	return d.helper.PublishResources(ctx, resources)
}
