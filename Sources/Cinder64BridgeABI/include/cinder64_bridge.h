#ifndef CINDER64_BRIDGE_H
#define CINDER64_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    CINDER64_BRIDGE_ABI_VERSION = 1,
};

typedef enum Cinder64Status {
    CINDER64_STATUS_OK = 0,
    CINDER64_STATUS_INVALID_ARGUMENT = 1,
    CINDER64_STATUS_INVALID_STATE = 2,
    CINDER64_STATUS_RUNTIME_ERROR = 3,
    CINDER64_STATUS_NOT_READY = 4,
    CINDER64_STATUS_TIMEOUT = 5,
    CINDER64_STATUS_PANIC = 6,
    CINDER64_STATUS_ABI_MISMATCH = 7
} Cinder64Status;

typedef struct Cinder64Error {
    uint32_t code;
    uint32_t reserved;
    const char *message;
} Cinder64Error;

typedef struct Cinder64Metrics {
    uint64_t pump_tick_count;
    uint64_t vi_count;
    uint64_t render_frame_count;
    uint64_t present_count;
    double frame_rate_hz;
    uint64_t pending_command_count;
    int32_t runtime_state;
    uint32_t reserved;
} Cinder64Metrics;

typedef struct Cinder64SurfaceDescriptor {
    uint64_t surface_id;
    uint64_t generation;
    uintptr_t window_handle;
    uintptr_t view_handle;
    int32_t logical_width;
    int32_t logical_height;
    int32_t pixel_width;
    int32_t pixel_height;
    double backing_scale_factor;
    uint64_t revision;
} Cinder64SurfaceDescriptor;

typedef struct Cinder64Settings {
    int32_t fullscreen;
    int32_t mute_audio;
    int32_t speed_percent;
    int32_t upscale_multiplier;
    int32_t integer_scaling;
    int32_t crt_filter;
} Cinder64Settings;

typedef struct Cinder64OpenROMRequest {
    const char *rom_path;
    const char *config_dir;
    const char *data_dir;
    const char *cache_dir;
    const char *molten_vk_library;
    struct Cinder64Settings settings;
} Cinder64OpenROMRequest;

typedef struct Cinder64BridgeAPI {
    uint32_t abi_version;
    uint32_t struct_size;
    uint32_t surface_descriptor_size;
    uint32_t settings_size;
    uint32_t open_rom_request_size;
    uint32_t metrics_size;
    uint32_t error_size;
    uint32_t reserved;
    uintptr_t create_session;
    uintptr_t destroy_session;
    uintptr_t attach_surface;
    uintptr_t update_surface;
    uintptr_t open_rom;
    uintptr_t pause;
    uintptr_t resume;
    uintptr_t reset;
    uintptr_t save_state;
    uintptr_t load_state;
    uintptr_t update_settings;
    uintptr_t set_keyboard_key;
    uintptr_t stop;
    uintptr_t pump_events;
    uintptr_t get_last_error;
    uintptr_t get_metrics;
    uintptr_t version;
    uintptr_t renderer_name;
    uintptr_t surface_event;
} Cinder64BridgeAPI;

int32_t cinder64_bridge_get_api(
    uint32_t requested_abi_version,
    uint32_t api_struct_size,
    struct Cinder64BridgeAPI *out_api
);

#ifdef __cplusplus
}
#endif

#endif
