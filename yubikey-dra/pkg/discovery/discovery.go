package discovery

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/rs/zerolog/log"
)

// #cgo pkg-config: libsystemd
// #cgo pkg-config: libpcsclite
// #include <systemd/sd-device.h>
// int discovery_sd_event_handler(sd_device_monitor*, sd_device*, void*);
import "C"

type Device struct {
	Name     string
	Syspath  string
	Devname  string
	Children []Device
}

type Monitor struct {
	eventCh    chan struct{}
	discoverCh chan struct{}
	discovered map[string]Device
	ctx        context.Context
	mut        sync.RWMutex
}

var mon atomic.Pointer[Monitor]

var (
	tag = C.CString("yubikey")
)

//export discovery_sd_event_handler
func discovery_sd_event_handler(_ *C.struct_sd_device_monitor, device *C.struct_sd_device, data *C.void) C.int {
	var action C.sd_device_action_t
	if ret := C.sd_device_get_action(device, &action); ret < 0 {
		log.Error().Int64("errno", int64(ret)).Msg("failed to call sd_device_get_action")
	}
	switch action {
	case C.SD_DEVICE_ADD, C.SD_DEVICE_REMOVE, C.SD_DEVICE_CHANGE:
		mon.Load().notify()
	default:
		break
	}
	return 0
}

func Init(ctx context.Context, wg *sync.WaitGroup) (error, *Monitor) {
	new := &Monitor{
		eventCh:    make(chan struct{}, 1),
		discoverCh: make(chan struct{}, 1),
		ctx:        ctx,
	}
	if !mon.CompareAndSwap(nil, new) {
		return fmt.Errorf("attempted to initialize monitor more than once"), nil
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		new.discoverDevices(wg)
	}()
	return nil, new
}

func (m *Monitor) Run(handler func(map[string]Device)) {
	for {
		devices := m.discover()
		// discover returns nil when ctx is canceled
		if devices == nil {
			break
		}
		handler(devices)
	}
}

func (m *Monitor) notify() {
	// If the channel is already full, we don't care,
	// since a re-enumeration is going to happen anyway
	select {
	case m.eventCh <- struct{}{}:
	default:
	}
}

func (m *Monitor) discover() map[string]Device {
	select {
	case <-m.ctx.Done():
		return nil
	case <-m.discoverCh:
	}
	m.mut.RLock()
	defer m.mut.RUnlock()
	return m.discovered
}

func (m *Monitor) update(discovered map[string]Device) {
	{
		m.mut.Lock()
		defer m.mut.Unlock()
		m.discovered = discovered
	}
	select {
	case m.discoverCh <- struct{}{}:
	default:
	}
}

func (*Monitor) enumerateDevices() (error, map[string]Device) {
	var enumerator *C.struct_sd_device_enumerator
	devices := map[string]Device{}

	ret := C.sd_device_enumerator_new(&enumerator)
	if ret < 0 {
		return fmt.Errorf("error calling sd_device_enumerator_new: %v", ret), nil
	}
	defer C.sd_device_enumerator_unref(enumerator)
	ret = C.sd_device_enumerator_add_match_tag(enumerator, tag)
	if ret < 0 {
		return fmt.Errorf("error calling sd_device_enumerator_add_match_tag: %v", ret), nil
	}
Outer:
	for device := C.sd_device_enumerator_get_device_first(enumerator); device != nil; device = C.sd_device_enumerator_get_device_next(enumerator) {
		var syspath *C.char
		ret = C.sd_device_get_syspath(device, &syspath)
		if ret < 0 {
			return fmt.Errorf("error calling sd_device_get_syspath: %v", ret), nil
		}
		log.Info().Str("syspath", C.GoString(syspath)).Msg("enumerated device")
		var devname *C.char
		ret = C.sd_device_get_devname(device, &devname)
		if ret < 0 {
			return fmt.Errorf("error calling sd_device_get_devname: %v", ret), nil
		}
		hasher := sha256.New()
		hasher.Write([]byte(C.GoString(devname)))
		hash := hasher.Sum(nil)
		newDevice := Device{
			Name:     "yubikey-" + hex.EncodeToString(hash)[:32],
			Syspath:  C.GoString(syspath),
			Devname:  C.GoString(devname),
			Children: make([]Device, 0),
		}
		for otherSyspath, otherDevice := range devices {
			if strings.HasPrefix(otherSyspath, newDevice.Syspath) {
				newDevice.Children = append(otherDevice.Children, otherDevice)
				delete(devices, otherSyspath)
				break
			} else if strings.HasPrefix(newDevice.Syspath, otherSyspath) {
				otherDevice.Children = append(otherDevice.Children, newDevice)
				devices[otherSyspath] = otherDevice
				// Continue the outer loop here so we don't add the new device
				// to the root map.
				continue Outer
			}
		}

		devices[newDevice.Syspath] = newDevice
	}
	return nil, devices
}

func (m *Monitor) monitorDevices(wg *sync.WaitGroup) (error, *C.struct_sd_event) {
	var monitor *C.struct_sd_device_monitor
	if ret := C.sd_device_monitor_new(&monitor); ret < 0 {
		return fmt.Errorf("error calling sd_device_monitor_new: %v", ret), nil
	}
	defer C.sd_device_monitor_unref(monitor)
	if ret := C.sd_device_monitor_filter_add_match_tag(monitor, tag); ret < 0 {
		return fmt.Errorf("error calling sd_device_monitor_add_filter_match_tag: %v", ret), nil
	}
	// Create a new sd_event to avoid any issues with the default loop being thread specific
	var event *C.struct_sd_event
	if ret := C.sd_event_new(&event); ret < 0 {
		return fmt.Errorf("error calling sd_event_new: %v", ret), nil
	}
	defer C.sd_event_unref(event)
	if ret := C.sd_event_set_signal_exit(event, 1); ret < 0 {
		return fmt.Errorf("error calling sd_event_set_signal_exit: %v", ret), nil
	}
	if ret := C.sd_device_monitor_attach_event(monitor, event); ret < 0 {
		return fmt.Errorf("error calling sd_device_monitor_attach_event: %v", ret), nil
	}
	if ret := C.sd_device_monitor_start(monitor, (C.sd_device_monitor_handler_t)(C.discovery_sd_event_handler), nil); ret < 0 {
		return fmt.Errorf("error calling sd_device_monitor_start: %v", ret), nil
	}

	C.sd_device_monitor_ref(monitor)
	wg.Add(1)
	go func() {
		defer wg.Done()
		defer C.sd_device_monitor_unref(monitor)
		log.Info().Msg("starting event loop")
		ret := C.sd_event_loop(event)
		if ret != 0 {
			log.Fatal().Int64("errno", int64(ret)).Msg("event loop stopped unexpectedly")
		}
		log.Info().Msg("event loop stopped")
	}()
	C.sd_event_ref(event)
	return nil, event
}

func (m *Monitor) discoverDevices(wg *sync.WaitGroup) {
	err, devices := m.enumerateDevices()
	if err != nil {
		panic(err)
	}
	m.update(devices)

	err, event := m.monitorDevices(wg)
	if err != nil {
		panic(err)
	}
	defer C.sd_event_unref(event)

Loop:
	for {
		select {
		case <-m.ctx.Done():
			log.Info().Msg("shutting down event loop")
			ret := C.sd_event_exit(event, 0)
			if ret < 0 {
				log.Error().Int64("errno", int64(ret)).Msg("error calling sd_event_exit")
			}
			break Loop
		case <-m.eventCh:
		}
		// When we get an event, wait a second so that we don't
		// rerun multiple times in a row for events that happen
		// in a burst
		time.Sleep(time.Second)
		// If any events came in in that second, clear it
		select {
		case <-m.eventCh:
		default:
		}
		err, devices = m.enumerateDevices()
		m.update(devices)
	}
}
