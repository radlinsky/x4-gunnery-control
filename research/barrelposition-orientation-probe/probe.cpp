#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <intrin.h>

#include <x4native_extension.h>

#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {

constexpr char kFunctionName[] = "BarrelpositionConnectionTransform";
constexpr uintptr_t kTargetRva = 0x0081c960;
constexpr uintptr_t kCallerRva = 0x007c6eb1;
constexpr uintptr_t kPropertyCallRva = 0x00d045cf;
constexpr size_t kCapacity = 32768;

constexpr uint8_t kExpectedTarget[] = {
    0x4c, 0x8b, 0xdc, 0x55, 0x53, 0x57, 0x41, 0x56,
    0x49, 0x8d, 0x6b, 0xa1, 0x48, 0x81, 0xec, 0x88,
};
constexpr uint8_t kExpectedCaller[] = {
    0x4c, 0x8b, 0xc0, 0x48, 0x8b, 0xd6, 0x48, 0x8b,
    0xcf, 0xff, 0xd3, 0x48, 0x8b, 0x5c, 0x24, 0x30,
};
constexpr uint8_t kExpectedPropertyCall[] = {
    0xe8, 0xac, 0x28, 0xac, 0xff,
};
constexpr uint8_t kExpectedSha256[] = {
    0x19, 0x75, 0x0a, 0x65, 0x63, 0x88, 0x9a, 0x97,
    0x0f, 0x43, 0x4b, 0x55, 0x66, 0xeb, 0x39, 0x6c,
    0x6b, 0x2d, 0xc2, 0x9f, 0xf8, 0x14, 0xbd, 0x3e,
    0x33, 0x6f, 0x83, 0x81, 0x76, 0xad, 0x68, 0x91,
};

struct Capture {
    volatile LONG ready;
    uint64_t sequence;
    uintptr_t weapon;
    uintptr_t connection;
    uintptr_t caller_rva;
    float matrix[16];
};

using TransformFn = void* (*)(void*, void*, void*);

X4NativeAPI* g_api = nullptr;
TransformFn g_original = nullptr;
Capture g_captures[kCapacity]{};
volatile LONG64 g_reserved = 0;
volatile LONG64 g_dropped = 0;
volatile LONG g_recording = 0;
uint64_t g_flushed = 0;
uint64_t g_reported_dropped = 0;
int g_frame_subscription = -1;
int g_hook_owner = -1;

void log_line(int level, const char* message) {
    auto fn = reinterpret_cast<void (*)(int, const char*, void*)>(
        g_api ? g_api->_ext_log_fn : nullptr);
    if (fn) {
        fn(level, message, g_api);
    } else if (g_api && g_api->log) {
        g_api->log(level, message);
    }
}

bool hash_executable(uint8_t output[32]) {
    wchar_t path[MAX_PATH];
    if (!GetModuleFileNameW(nullptr, path, MAX_PATH)) return false;

    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    PUCHAR object = nullptr;
    DWORD object_size = 0;
    DWORD result_size = 0;
    bool ok = false;

    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM,
                                    nullptr, 0) < 0) goto done;
    if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                          reinterpret_cast<PUCHAR>(&object_size),
                          sizeof(object_size), &result_size, 0) < 0) goto done;
    object = static_cast<PUCHAR>(HeapAlloc(GetProcessHeap(), 0, object_size));
    if (!object) goto done;
    if (BCryptCreateHash(algorithm, &hash, object, object_size,
                         nullptr, 0, 0) < 0) goto done;

    uint8_t buffer[65536];
    for (;;) {
        DWORD read = 0;
        if (!ReadFile(file, buffer, sizeof(buffer), &read, nullptr)) goto done;
        if (!read) break;
        if (BCryptHashData(hash, buffer, read, 0) < 0) goto done;
    }
    if (BCryptFinishHash(hash, output, 32, 0) < 0) goto done;
    ok = true;

done:
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    if (object) HeapFree(GetProcessHeap(), 0, object);
    CloseHandle(file);
    return ok;
}

bool guard_image() {
    if (!g_api || g_api->api_version < X4NATIVE_API_VERSION ||
        g_api->game_types_build != 900 || !g_api->exe_base) return false;
    if (g_api->exe_base != reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)))
        return false;

    auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(g_api->exe_base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
    auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(
        g_api->exe_base + static_cast<uintptr_t>(dos->e_lfanew));
    if (nt->Signature != IMAGE_NT_SIGNATURE ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC ||
        nt->OptionalHeader.SizeOfImage <= kPropertyCallRva + sizeof(kExpectedPropertyCall))
        return false;

    uint8_t digest[32];
    if (!hash_executable(digest) ||
        std::memcmp(digest, kExpectedSha256, sizeof(digest)) != 0) return false;
    const auto* base = reinterpret_cast<const uint8_t*>(g_api->exe_base);
    return std::memcmp(base + kTargetRva, kExpectedTarget,
                       sizeof(kExpectedTarget)) == 0 &&
           std::memcmp(base + kCallerRva - 11, kExpectedCaller,
                       sizeof(kExpectedCaller)) == 0 &&
           std::memcmp(base + kPropertyCallRva, kExpectedPropertyCall,
                       sizeof(kExpectedPropertyCall)) == 0;
}

__declspec(noinline) void* detour(void* weapon, void* output, void* connection) {
#ifdef _MSC_VER
    void* caller = _ReturnAddress();
#else
    void* caller = __builtin_return_address(0);
#endif
    void* result = g_original(weapon, output, connection);

    if (InterlockedCompareExchange(&g_recording, 0, 0) == 0 ||
        reinterpret_cast<uintptr_t>(caller) != g_api->exe_base + kCallerRva)
        return result;
    if (!output || !connection) return result;

    LONG64 slot_index = InterlockedIncrement64(&g_reserved) - 1;
    if (slot_index >= static_cast<LONG64>(kCapacity)) {
        InterlockedIncrement64(&g_dropped);
        return result;
    }

    Capture& capture = g_captures[slot_index];
    capture.sequence = static_cast<uint64_t>(slot_index);
    capture.weapon = reinterpret_cast<uintptr_t>(weapon);
    capture.connection = reinterpret_cast<uintptr_t>(connection);
    capture.caller_rva = kCallerRva;
    std::memcpy(capture.matrix, output, sizeof(capture.matrix));
    InterlockedExchange(&capture.ready, 1);
    return result;
}

int unused_hook_callback(X4HookContext*) {
    return 0;
}

void flush_captures() {
    LONG64 reserved = InterlockedCompareExchange64(&g_reserved, 0, 0);
    uint64_t available = reserved < static_cast<LONG64>(kCapacity)
                             ? static_cast<uint64_t>(reserved)
                             : kCapacity;
    char line[1024];
    while (g_flushed < available) {
        Capture& capture = g_captures[g_flushed];
        if (InterlockedCompareExchange(&capture.ready, 0, 0) == 0) break;
        int used = std::snprintf(
            line, sizeof(line),
            "CAPTURE {\"sequence\":%llu,\"weapon\":\"0x%llx\","
            "\"connection\":\"0x%llx\",\"caller_rva\":\"0x%llx\",\"matrix\":[",
            static_cast<unsigned long long>(capture.sequence),
            static_cast<unsigned long long>(capture.weapon),
            static_cast<unsigned long long>(capture.connection),
            static_cast<unsigned long long>(capture.caller_rva));
        for (int i = 0; i < 16 && used > 0 && used < static_cast<int>(sizeof(line)); ++i) {
            used += std::snprintf(line + used, sizeof(line) - used,
                                  i ? ",%.9g" : "%.9g", capture.matrix[i]);
        }
        if (used > 0 && used < static_cast<int>(sizeof(line) - 3)) {
            std::memcpy(line + used, "]}", 3);
            log_line(X4NATIVE_LOG_INFO, line);
        }
        ++g_flushed;
    }

    uint64_t dropped = static_cast<uint64_t>(
        InterlockedCompareExchange64(&g_dropped, 0, 0));
    if (dropped != g_reported_dropped) {
        std::snprintf(line, sizeof(line),
                      "OVERFLOW {\"capacity\":%llu,\"dropped\":%llu}",
                      static_cast<unsigned long long>(kCapacity),
                      static_cast<unsigned long long>(dropped));
        log_line(X4NATIVE_LOG_ERROR, line);
        g_reported_dropped = dropped;
    }
}

void on_frame(const char*, void*, void*) {
    flush_captures();
}

}  // namespace

X4NATIVE_EXPORT int x4native_api_version(void) {
    return X4NATIVE_API_VERSION;
}

X4NATIVE_EXPORT int x4native_init(X4NativeAPI* api) {
    g_api = api;
    auto init_log = reinterpret_cast<void (*)(const char*, void*)>(api->_ext_init_log_fn);
    if (init_log) init_log("barrel-orientation.log", api);

    if (!guard_image()) {
        log_line(X4NATIVE_LOG_ERROR, "STATUS {\"hooked\":false,\"reason\":\"build_or_byte_guard\"}");
        return X4NATIVE_ERROR;
    }

    void* resolved = api->resolve_internal(kFunctionName);
    if (resolved != reinterpret_cast<void*>(api->exe_base + kTargetRva)) {
        log_line(X4NATIVE_LOG_ERROR, "STATUS {\"hooked\":false,\"reason\":\"host_rva_resolution\"}");
        return X4NATIVE_ERROR;
    }

    g_frame_subscription = api->subscribe("on_native_frame_update", on_frame,
                                          nullptr, api);
    if (g_frame_subscription <= 0) {
        log_line(X4NATIVE_LOG_ERROR, "STATUS {\"hooked\":false,\"reason\":\"frame_subscription\"}");
        return X4NATIVE_ERROR;
    }

    g_hook_owner = api->hook_after(kFunctionName, unused_hook_callback,
                                   nullptr, api);
    if (g_hook_owner <= 0) {
        api->unsubscribe(g_frame_subscription);
        g_frame_subscription = -1;
        log_line(X4NATIVE_LOG_ERROR, "STATUS {\"hooked\":false,\"reason\":\"hook_ownership\"}");
        return X4NATIVE_ERROR;
    }

    void* trampoline = api->_ensure_detour(kFunctionName,
                                           reinterpret_cast<void*>(&detour));
    if (!trampoline) {
        api->unhook(g_hook_owner);
        api->unsubscribe(g_frame_subscription);
        g_hook_owner = -1;
        g_frame_subscription = -1;
        log_line(X4NATIVE_LOG_ERROR, "STATUS {\"hooked\":false,\"reason\":\"detour_install\"}");
        return X4NATIVE_ERROR;
    }

    g_original = reinterpret_cast<TransformFn>(trampoline);
    InterlockedExchange(&g_recording, 1);
    log_line(X4NATIVE_LOG_INFO,
             "STATUS {\"hooked\":true,\"target_rva\":\"0x81c960\",\"caller_rva\":\"0x7c6eb1\",\"capacity\":32768}");
    return X4NATIVE_OK;
}

X4NATIVE_EXPORT void x4native_shutdown(void) {
    InterlockedExchange(&g_recording, 0);
    flush_captures();
    if (g_hook_owner > 0) g_api->unhook(g_hook_owner);
    if (g_frame_subscription > 0) g_api->unsubscribe(g_frame_subscription);
}
