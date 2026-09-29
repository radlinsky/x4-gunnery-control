#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <bcrypt.h>
#include <intrin.h>
#include <x4native_extension.h>
#include <cmath>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {
constexpr char kHash[] = "19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891";
constexpr uintptr_t kPass = 0xe176b0, kIcon = 0xda7a50, kPick = 0x22fd50;
constexpr uintptr_t kPassCaller = 0xe1669a, kIconCaller = 0xe1814b;
constexpr size_t kMaxConnections = 512;
struct State { float value[7]; };
struct Pick { const char* type; size_t slot; };
struct Pair { uintptr_t owner, connection; };
struct RawState { float translation[4], orientation[12], distance; };
struct Request {
    char id[64], macro[128];
    uint64_t map_id, ship_id, component_id;
    size_t slot;
    uintptr_t map, view;
    Pair pair;
    size_t ordinal;
    bool joined;
    DWORD thread;
    ULONGLONG deadline;
};
struct Capture {
    uint64_t sequence;
    DWORD thread;
    uintptr_t transform, helper, renderer, resource, glyph, macro, expected_camera, expected_helper, expected_extra;
    float slot[16], camera[16], extra[16], matrices[6][16], parameters[5];
    float scalars[4], radius;
    bool flags[7], has_extra;
    State before, after;
    RawState raw_before, raw_after;
    unsigned icons, dropped;
    const char* error;
};
using PassFn = void (*)(void*, void*, void*, void*, void*);
using IconFn = float (*)(void*, uintptr_t, void*, uintptr_t, void*, bool, bool, bool,
                        float, float, bool, void*, float, void*, void*, void*, float,
                        bool, bool, bool);
using PickFn = bool (*)(uint64_t, uint64_t, uint64_t, const char*, bool, Pick*);
using StateFn = void (*)(uint64_t, State*);
using ComponentFn = uint64_t (*)(uint64_t, const char*, size_t);
using LookupFn = void* (*)(void*, uint64_t, uint32_t);
X4NativeAPI* g_api;
PassFn g_pass;
IconFn g_icon;
PickFn g_pick;
StateFn g_state;
ComponentFn g_component;
Request g_request{};
Capture g_capture{};  // One record; duplicate target submissions are rejected.
struct JoinDiag { const char* step; int64_t picked_slot, macro_type, class_flags, connections, models, ordinal, base_flags, vector; };
JoinDiag g_join{};  // Last public-pick join attempt; -1 = not reached.
volatile LONG g_phase = 0;  // idle / armed / inside pass / result ready
volatile LONG g_cancel = 0;
uint64_t g_sequence = 0;
thread_local Capture* g_context = nullptr;
int g_hooks[3] = {-1, -1, -1}, g_subscription = -1;

// Guarded POD reads only. Never catch/replace an exception from the original renderer.
bool copy(void* output, uintptr_t address, size_t size) {
    if (!address || address + size < address) return false;
    __try { std::memcpy(output, reinterpret_cast<void*>(address), size); return true; }
    __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
template<typename T> bool read(uintptr_t address, T& value) {
    return copy(&value, address, sizeof(value));
}
bool finite(const float* values, size_t count) {
    for (size_t i = 0; i < count; ++i) if (!std::isfinite(values[i])) return false;
    return true;
}
bool equal(Pair a, Pair b) { return a.owner == b.owner && a.connection == b.connection; }
bool same_string(const char* address, const char* expected) {
    for (size_t i = 0; i < 128; ++i) {
        char c;
        if (!read(reinterpret_cast<uintptr_t>(address) + i, c) || c != expected[i]) return false;
        if (!c) return true;
    }
    return false;
}
bool signature(uintptr_t rva, size_t size, uint64_t expected) {
    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(g_api->exe_base);
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(g_api->exe_base + dos->e_lfanew);
    if (rva + size > nt->OptionalHeader.SizeOfImage || size > 32) return false;
    uint8_t bytes[32];
    if (!copy(bytes, g_api->exe_base + rva, size)) return false;
    uint64_t hash = 14695981039346656037ULL;
    for (size_t i = 0; i < size; ++i) hash = (hash ^ bytes[i]) * 1099511628211ULL;
    return hash == expected;
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

bool guard() {
    if (!g_api || g_api->api_version != 1 || g_api->game_types_build != 900 ||
        g_api->exe_base != reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))) return false;
    IMAGE_DOS_HEADER dos{};
    IMAGE_NT_HEADERS64 nt{};
    if (!read(g_api->exe_base, dos) || dos.e_magic != IMAGE_DOS_SIGNATURE ||
        dos.e_lfanew <= 0 || dos.e_lfanew > 4096 ||
        !read(g_api->exe_base + dos.e_lfanew, nt) || nt.Signature != IMAGE_NT_SIGNATURE ||
        nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC ||
        nt.OptionalHeader.SizeOfImage <= 0x6cf1508) return false;
    uint8_t digest[32];
    if (!hash_executable(digest)) return false;
    char text[65];
    for (int i = 0; i < 32; ++i) std::snprintf(text + 2 * i, 3, "%02x", digest[i]);
    return std::strcmp(text, kHash) == 0 &&
        signature(kPass, 32, 0x524a0c06aee7ab0bULL) &&
        signature(kIcon, 32, 0xcf6933f9f8104076ULL) &&
        signature(kPick, 32, 0x9de6b6e051b9f9faULL) &&
        signature(kPassCaller - 5, 5, 0xed5eeb03aa2b9b21ULL) &&
        signature(kIconCaller - 5, 5, 0x1b7cbb9367b4e6e0ULL) &&
        signature(0xced70, 32, 0x2c770bae0598587cULL) &&
        signature(0x22dfc0, 32, 0xf746bfaeda75aa4eULL) &&
        signature(0x1ad010, 32, 0x19337bad735eb60dULL);
}
bool connections(uintptr_t view, uintptr_t& begin, size_t& count, uintptr_t& macro) {
    uintptr_t table, data, end, models, models_end;
    int32_t type;
    uint8_t flags;
    if (!read(view + 0x250, macro)) { g_join.step = "connections_macro_read"; return false; }
    if (!read(macro + 0x44, type)) { g_join.step = "connections_macro_type"; return false; }
    g_join.macro_type = static_cast<int64_t>(type);
    if (type < 0 || type >= 0x79) { g_join.step = "connections_macro_type"; return false; }
    if (!read(g_api->exe_base + 0x256d038 + static_cast<size_t>(type) * 8, table) ||
        !read(table + 0x1c, flags)) { g_join.step = "connections_class_flags"; return false; }
    g_join.class_flags = static_cast<int64_t>(flags);
    uintptr_t vector = 0x798;  // Engine 0x00E1775A: class +0x1c bit selects the +0x798 connection vector.
    if (!(flags & 0xc0)) {
        uint8_t base_flags;
        // Otherwise the engine's checked cast (0x0059BDB0) requires class +0x8 and uses +0xce0.
        if (!read(table + 0x8, base_flags)) { g_join.step = "connections_base_flags"; return false; }
        g_join.base_flags = static_cast<int64_t>(base_flags);
        if (!(base_flags & 0xc0)) { g_join.step = "connections_base_flags"; return false; }
        vector = 0xce0;
    }
    g_join.vector = static_cast<int64_t>(vector);
    if (!read(macro + 0x18, data)) { g_join.step = "connections_data_read"; return false; }
    if (!read(data + vector, begin) || !read(data + vector + 8, end) || end < begin || (end - begin) % 16) {
        g_join.step = "connections_vector"; return false;
    }
    if (!read(view + 0x4c0, models) || !read(view + 0x4c8, models_end) || models_end < models ||
        (models_end - models) % 8) { g_join.step = "connections_models"; return false; }
    count = (end - begin) / 16;
    g_join.connections = static_cast<int64_t>(count);
    g_join.models = static_cast<int64_t>((models_end - models) / 8);
    if (!(begin && count > 0 && count <= kMaxConnections && count == (models_end - models) / 8)) {
        g_join.step = "connections_count"; return false;
    }
    return true;
}
bool view_ok(uintptr_t view) {
    uintptr_t vtable, map, back;
    return read(view, vtable) && vtable == g_api->exe_base + 0x2c2cb60 &&
        read(view + 0x10, map) && map == g_request.map &&
        read(map + 0x2c0, back) && back == view;
}
bool raw_state(RawState& raw) {
    return copy(raw.translation, g_request.map + 0x320, sizeof(raw.translation)) &&
        copy(raw.orientation, g_request.map + 0x360, sizeof(raw.orientation)) &&
        read(g_request.map + 0x3dc, raw.distance) && finite(raw.translation, 4) &&
        finite(raw.orientation, 12) && std::isfinite(raw.distance) && raw.distance > 0;
}
bool state(State& state) {
    __try { g_state(g_request.map_id, &state); }
    __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    return finite(state.value, 7) && state.value[6] > 0;
}

// The phase is claimed before reading/writing request data, including on a
// rejected foreign thread. No polling callback can replace an in-use request.
bool join_pick(bool ok, uint64_t map, uint64_t ship, uint64_t module,
               const char* macro, bool ismodule, Pick* result) {
    if (map != g_request.map_id || ship != g_request.ship_id || module ||
        ismodule || !same_string(macro, g_request.macro)) return false;
    if (GetCurrentThreadId() != g_request.thread) {
        g_capture.error = "picker_thread_mismatch";
        return true;
    }
    if (GetTickCount64() > g_request.deadline) {
        g_capture.error = "native_deadline";
        return true;
    }
    if (!ok) { g_request.joined = false; return false; }
    Pick picked{};
    uintptr_t begin, native_macro;
    size_t count, ordinal;
    Pair pair{};
    if (!read(reinterpret_cast<uintptr_t>(result), picked)) {
        g_capture.error = "join_pick_result_unreadable";
        return true;
    }
    if (!same_string(picked.type, "turret")) {
        g_capture.error = "join_pick_type";
        return true;
    }
    g_join.picked_slot = static_cast<int64_t>(picked.slot);
    if (picked.slot != g_request.slot) {
        g_capture.error = "join_pick_slot";
        return true;
    }
    if (!view_ok(g_request.view)) {
        g_capture.error = "join_view";
        return true;
    }
    if (!connections(g_request.view, begin, count, native_macro)) {
        g_capture.error = g_join.step ? g_join.step : "join_connections";
        return true;
    }
    if (!read(g_request.view + 0x520, ordinal)) {
        g_capture.error = "join_ordinal_unreadable";
        return true;
    }
    g_join.ordinal = static_cast<int64_t>(ordinal);
    if (ordinal >= count) {
        g_capture.error = "join_ordinal_range";
        return true;
    }
    if (!read(begin + ordinal * 16, pair) || !pair.connection) {
        g_capture.error = "join_pair";
        return true;
    }
    if (g_request.joined && (!equal(pair, g_request.pair) || ordinal != g_request.ordinal)) {
        g_capture.error = "conflicting_public_slot_join";
        return true;
    } else {
        g_request.pair = pair;
        g_request.ordinal = ordinal;
        g_request.joined = true;
        g_join.step = "joined";
    }
    return false;
}
__declspec(noinline) bool pick_hook(uint64_t map, uint64_t ship, uint64_t module,
                                   const char* macro, bool ismodule, Pick* result) {
    const bool ok = g_pick(map, ship, module, macro, ismodule, result);
    if (InterlockedCompareExchange(&g_phase, 2, 1) != 1) return ok;
    const bool ready = join_pick(ok, map, ship, module, macro, ismodule, result);
    InterlockedExchange(&g_phase, InterlockedCompareExchange(&g_cancel, 0, 0) ? 0 : (ready ? 3 : 1));
    return ok;
}

// Exactly the twenty arguments at the documented entry ABI; no stack-frame offsets.
__declspec(noinline) float icon_hook(void* view, uintptr_t a2, void* resource, uintptr_t glyph,
    void* transform, bool b6, bool b7, bool b8, float f9, float f10, bool b11,
    void* color, float f13, void* camera, void* helper, void* extra, float f17,
    bool b18, bool b19, bool b20) {
    auto* capture = g_context;
    if (capture && reinterpret_cast<uintptr_t>(_ReturnAddress()) == g_api->exe_base + kIconCaller) {
        uintptr_t begin = 0, macro = 0;
        size_t count = 0, matches = 0;
        Pair found{};
        size_t ordinal = 0;
        bool good = view_ok(reinterpret_cast<uintptr_t>(view)) &&
            reinterpret_cast<uintptr_t>(view) == g_request.view &&
            connections(g_request.view, begin, count, macro);
        for (size_t i = 0; good && i < count; ++i) {
            Pair pair{};
            uintptr_t pivot = 0;
            good = read(begin + i * 16, pair) && pair.connection &&
                read(pair.connection + 0xa0, pivot);
            if (!good) break;
            if (!pivot) pivot = pair.connection + 0x60;
            if (pivot == reinterpret_cast<uintptr_t>(transform)) { ++matches; found = pair; ordinal = i; }
        }
        if (!good || matches != 1) capture->error = "ambiguous_transform_identity";
        else if (equal(found, g_request.pair)) {
            if (ordinal != g_request.ordinal) capture->error = "changed_connection_vector";
            if (capture->icons++) { ++capture->dropped; capture->error = "duplicate_target_submission"; }
            else {
                capture->transform = reinterpret_cast<uintptr_t>(transform);
                capture->macro = macro;
                capture->helper = reinterpret_cast<uintptr_t>(helper);
                capture->resource = reinterpret_cast<uintptr_t>(resource);
                capture->glyph = glyph;
                capture->has_extra = extra != nullptr;
                capture->flags[0] = b6; capture->flags[1] = b7; capture->flags[2] = b8;
                capture->flags[3] = b11; capture->flags[4] = b18; capture->flags[5] = b19; capture->flags[6] = b20;
                capture->scalars[0] = f9; capture->scalars[1] = f10;
                capture->scalars[2] = f13; capture->scalars[3] = f17;
                uintptr_t helper_map, render_object, map_render_object;
                good = a2 == 0 && b6 && b7 && b8 && b11 && !b18 && !b19 && !b20 &&
                    reinterpret_cast<uintptr_t>(camera) == capture->expected_camera &&
                    capture->helper == capture->expected_helper &&
                    reinterpret_cast<uintptr_t>(extra) == capture->expected_extra &&
                    read(capture->helper + 8, helper_map) && helper_map == g_request.map &&
                    read(capture->helper + 0x90, render_object) &&
                    read(g_request.map + 0x420, map_render_object) && render_object == map_render_object &&
                    read(capture->helper, capture->renderer) && capture->renderer && resource &&
                    copy(capture->slot, capture->transform, 64) &&
                    copy(capture->camera, reinterpret_cast<uintptr_t>(camera), 64) &&
                    (!extra || copy(capture->extra, reinterpret_cast<uintptr_t>(extra), 64)) &&
                    read(macro + 0x160, capture->radius);
                constexpr size_t offsets[] = {0, 0x40, 0xc0, 0x100, 0x140, 0x180};
                for (int i = 0; good && i < 6; ++i)
                    good = copy(capture->matrices[i], capture->renderer + 0x10 + offsets[i], 64) &&
                        finite(capture->matrices[i], 16);
                good = good && copy(capture->parameters, capture->renderer + 0x10 + 0xcc0, 20) &&
                    finite(capture->parameters, 5) && finite(capture->slot, 16) &&
                    finite(capture->camera, 16) && finite(capture->scalars, 4) &&
                    (!extra || finite(capture->extra, 16)) &&
                    std::isfinite(capture->radius) && capture->radius > 0 &&
                    capture->parameters[1] > capture->parameters[0] &&
                    capture->parameters[2] > 0 && capture->parameters[3] > 0 && capture->parameters[4] > 0;
                if (!good) capture->error = "icon_structure_or_nonfinite_data";
            }
        }
    }
    return g_icon(view, a2, resource, glyph, transform, b6, b7, b8, f9, f10, b11,
                  color, f13, camera, helper, extra, f17, b18, b19, b20);
}

__declspec(noinline) void pass_hook(void* view, void* camera, void* helper_a, void* helper_b, void* extra) {
    if (reinterpret_cast<uintptr_t>(_ReturnAddress()) != g_api->exe_base + kPassCaller ||
        InterlockedCompareExchange(&g_phase, 2, 1) != 1) {
        g_pass(view, camera, helper_a, helper_b, extra);
        return;
    }
    if (reinterpret_cast<uintptr_t>(view) != g_request.view ||
        (GetCurrentThreadId() == g_request.thread && !g_request.joined)) {
        InterlockedExchange(&g_phase, InterlockedCompareExchange(&g_cancel, 0, 0) ? 0 : 1);
        g_pass(view, camera, helper_a, helper_b, extra);
        return;
    }
    g_capture.sequence = ++g_sequence;
    g_capture.thread = GetCurrentThreadId();
    g_capture.expected_camera = reinterpret_cast<uintptr_t>(camera);
    g_capture.expected_helper = reinterpret_cast<uintptr_t>(helper_b);
    g_capture.expected_extra = reinterpret_cast<uintptr_t>(extra);
    if (GetTickCount64() > g_request.deadline) {
        g_capture.error = "native_deadline";
        g_pass(view, camera, helper_a, helper_b, extra);
        InterlockedExchange(&g_phase, 3);
        return;
    }
    if (g_capture.thread != g_request.thread) {
        g_capture.error = "render_thread_mismatch";
        g_pass(view, camera, helper_a, helper_b, extra);
        InterlockedExchange(&g_phase, 3);
        return;
    }
    if (!view_ok(g_request.view) || !state(g_capture.before) || !raw_state(g_capture.raw_before))
        g_capture.error = "before_state_or_view";
    if (!g_capture.error) g_context = &g_capture;
    g_pass(view, camera, helper_a, helper_b, extra);
    g_context = nullptr;
    uintptr_t begin, macro;
    size_t count;
    Pair pair{};
    if (!view_ok(g_request.view) || !state(g_capture.after) || !raw_state(g_capture.raw_after) ||
        !connections(g_request.view, begin, count, macro) || g_request.ordinal >= count ||
        !read(begin + g_request.ordinal * 16, pair) || !equal(pair, g_request.pair))
        g_capture.error = "after_state_or_identity";
    else if (std::memcmp(&g_capture.before, &g_capture.after, sizeof(State)) ||
             std::memcmp(&g_capture.raw_before, &g_capture.raw_after, sizeof(RawState)))
        g_capture.error = "camera_changed_during_pass";
    if (!g_capture.icons && !g_capture.error) g_capture.error = "no_target_icon_submission";
    InterlockedExchange(&g_phase, InterlockedCompareExchange(&g_cancel, 0, 0) ? 0 : 3);
}

std::string floats(const float* values, size_t count) {
    std::string result = "[";
    char text[64];
    for (size_t i = 0; i < count; ++i) {
        if (std::isfinite(values[i])) std::snprintf(text, sizeof(text), i ? ",%.9g" : "%.9g", values[i]);
        else std::snprintf(text, sizeof(text), i ? ",null" : "null");
        result += text;
    }
    return result + "]";
}
std::string pointer(uintptr_t value) {
    char text[32];
    std::snprintf(text, sizeof(text), "\"0x%llx\"", static_cast<unsigned long long>(value));
    return text;
}
void reply(const char* id, const char* status, const std::string& json) {
    const std::string message = std::string(id) + "|" + status + "|" + json;
    auto log = reinterpret_cast<void (*)(int, const char*, void*)>(g_api->_ext_log_fn);
    if (log) log(X4NATIVE_LOG_INFO, message.c_str(), g_api);
    else g_api->log(X4NATIVE_LOG_INFO, message.c_str());
    if (g_api->raise_lua_event("X4GunneryAnchor.Reply", message.c_str()))
        g_api->log(X4NATIVE_LOG_ERROR, "ANCHOR_INVALID native_reply_delivery");
}
std::string provenance() {
    return std::string("\"exe_sha256\":\"") + kHash + "\",\"build\":\"900-611726\",\"probe_sha\":\"" +
        PROBE_SHA + "\",\"probe_dirty\":" + (PROBE_DIRTY ? "true" : "false") +
        ",\"probe_source_sha256\":\"" + SOURCE_SHA + "\",\"lua_source_sha256\":\"" + LUA_SHA +
        "\",\"md_source_sha256\":\"" + MD_SHA + "\",\"fixture_template_sha256\":\"" + FIXTURE_SHA + "\"" +
        ",\"host_sha\":\"fc4b8e26d74365ca332c3b0749eb9bbe167c76a1\"";
}
void result() {
    Capture& c = g_capture;
    if (g_component(g_request.ship_id, "turret", g_request.slot) != g_request.component_id)
        c.error = "equipped_component_changed";
    std::string json = "{" + provenance() + ",\"capacity\":1,\"icons\":" + std::to_string(c.icons) +
        ",\"dropped\":" + std::to_string(c.dropped) + ",\"sequence\":" + std::to_string(c.sequence) +
        ",\"thread\":" + std::to_string(c.thread);
    json += ",\"request\":\"" + std::string(g_request.id) + "\",\"holomap_id\":\"" + std::to_string(g_request.map_id) +
        "\",\"ship_id\":\"" + std::to_string(g_request.ship_id) + "\",\"component_id\":\"" + std::to_string(g_request.component_id) +
        "\",\"pass_caller_rva\":\"0xe1669a\",\"icon_caller_rva\":\"0xe1814b\"";
    json += ",\"before\":" + floats(c.before.value, 7) + ",\"after\":" + floats(c.after.value, 7);
    json += std::string(",\"join\":{\"step\":\"") + (g_join.step ? g_join.step : "none") +
        "\",\"picked_slot\":" + std::to_string(g_join.picked_slot) +
        ",\"macro_type\":" + std::to_string(g_join.macro_type) +
        ",\"class_flags\":" + std::to_string(g_join.class_flags) +
        ",\"connections\":" + std::to_string(g_join.connections) +
        ",\"models\":" + std::to_string(g_join.models) +
        ",\"ordinal\":" + std::to_string(g_join.ordinal) +
        ",\"base_flags\":" + std::to_string(g_join.base_flags) +
        ",\"vector\":" + std::to_string(g_join.vector) + "}";
    if (c.error) json += std::string(",\"reason\":\"") + c.error + "\"";
    else {
        json += ",\"view\":" + pointer(g_request.view) + ",\"map\":" + pointer(g_request.map) +
            ",\"macro\":" + pointer(c.macro) +
            ",\"connection_pair\":[" + pointer(g_request.pair.owner) + "," + pointer(g_request.pair.connection) +
            "],\"ordinal\":" + std::to_string(g_request.ordinal) + ",\"public_type\":\"turret\",\"public_slot\":" +
            std::to_string(g_request.slot) + ",\"transform\":" + pointer(c.transform) +
            ",\"resource\":" + pointer(c.resource) + ",\"glyph\":" + pointer(c.glyph) +
            ",\"helper\":" + pointer(c.helper) + ",\"renderer\":" + pointer(c.renderer) +
            ",\"slot_pivot\":" + floats(c.slot, 3) + ",\"slot_transform\":" + floats(c.slot, 16) +
            ",\"camera_pose\":" + floats(c.camera, 16) +
            ",\"extra_transform\":" + (c.has_extra ? floats(c.extra, 16) : "null") +
            ",\"raw_before\":" + floats(c.raw_before.translation, 4) +
            ",\"orientation_before\":" + floats(c.raw_before.orientation, 12) +
            ",\"raw_after\":" + floats(c.raw_after.translation, 4) +
            ",\"orientation_after\":" + floats(c.raw_after.orientation, 12) +
            ",\"raw_distance_before\":" + floats(&c.raw_before.distance, 1) +
            ",\"raw_distance_after\":" + floats(&c.raw_after.distance, 1) +
            ",\"parameters\":" + floats(c.parameters, 5) + ",\"scalars\":" + floats(c.scalars, 4);
        constexpr const char* names[] = {"descriptor_camera", "view_matrix", "projection", "view_projection", "projection_variant", "variant_view_projection"};
        for (int i = 0; i < 6; ++i) json += std::string(",\"") + names[i] + "\":" + floats(c.matrices[i], 16);
        json += ",\"radius\":" + floats(&c.radius, 1) + ",\"flags\":[";
        for (int i = 0; i < 7; ++i) json += std::string(i ? "," : "") + (c.flags[i] ? "true" : "false");
        json += "]";
    }
    const bool invalid = c.error != nullptr;
    InterlockedExchange(&g_phase, 0);
    reply(g_request.id, invalid ? "invalid" : "ok", json + "}");
}
bool decimal_id(const char* text, uint64_t& value) {
    if (!*text) return false;
    for (const char* p = text; *p; ++p) if (*p < '0' || *p > '9') return false;
    char* end;
    errno = 0;
    value = std::strtoull(text, &end, 10);
    return !*end && errno != ERANGE && value != 0;
}
void command(const char*, void* data, void*) {
    const char* text = static_cast<const char*>(data);
    if (!text || std::strlen(text) > 511) return;
    char op = 0, id[64]{};
    if (std::sscanf(text, "%c|%63[^|]", &op, id) != 2) return;
    for (const char* p = id; *p; ++p) if (!((*p >= '0' && *p <= '9') || *p == '_' || *p == '.')) return;
    if (op == 'H') { reply(id, "ready", "{" + provenance() + "}"); return; }
    if (op == 'A') {
        if (InterlockedCompareExchange(&g_phase, 0, 0)) { reply(id, "invalid", "{\"reason\":\"native_busy\"}"); return; }
        Request request{};
        char map[32], ship[32], component[32], slot[32];
        uint64_t slot_value;
        if (std::sscanf(text, "A|%63[^|]|%31[^|]|%31[^|]|%31[^|]|%31[^|]|%127[^|]",
                request.id, map, ship, component, slot, request.macro) != 6 ||
            !decimal_id(map, request.map_id) || !decimal_id(ship, request.ship_id) ||
            !decimal_id(component, request.component_id) || !decimal_id(slot, slot_value) ||
            slot_value > kMaxConnections) { reply(id, "invalid", "{\"reason\":\"arm_payload\"}"); return; }
        request.slot = static_cast<size_t>(slot_value);
        request.thread = GetCurrentThreadId();
        request.deadline = GetTickCount64() + 5000;
        void* registry;
        if (!read(g_api->exe_base + 0x6cf1500, registry) || !registry) {
            reply(id, "invalid", "{\"reason\":\"map_registry\"}"); return;
        }
        request.map = reinterpret_cast<uintptr_t>(reinterpret_cast<LookupFn>(g_api->exe_base + 0xced70)(registry, request.map_id, 4));
        if (!read(request.map + 0x2c0, request.view)) {
            reply(id, "invalid", "{\"reason\":\"map_resolution\"}"); return;
        }
        g_request = request;
        g_capture = {};
        g_join = {nullptr, -1, -1, -1, -1, -1, -1, -1, -1};
        InterlockedExchange(&g_cancel, 0);
        if (!view_ok(request.view) || g_component(request.ship_id, "turret", request.slot) != request.component_id) {
            reply(id, "invalid", "{\"reason\":\"arm_view_or_component\"}"); return;
        }
        InterlockedExchange(&g_phase, 1);
        reply(id, "armed", "{" + provenance() + "}");
    } else if (std::strcmp(id, g_request.id) == 0) {
        LONG phase = InterlockedCompareExchange(&g_phase, 0, 0);
        if (op == 'P' && phase == 3) result();
        else if (op == 'C' && phase != 2) {
            InterlockedExchange(&g_phase, 0);
            reply(id, "invalid", "{\"reason\":\"cancelled_or_timeout\"}");
        } else if (op == 'C') InterlockedExchange(&g_cancel, 1);
    }
}
int unused(X4HookContext*) { return 0; }
void cleanup() {
    InterlockedExchange(&g_phase, 0);
    for (int& hook : g_hooks) { if (hook > 0) g_api->unhook(hook); hook = -1; }
    if (g_subscription > 0) g_api->unsubscribe(g_subscription);
    g_subscription = -1;
}
}  // namespace

X4NATIVE_EXPORT int x4native_api_version() { return X4NATIVE_API_VERSION; }
X4NATIVE_EXPORT int x4native_init(X4NativeAPI* api) {
    g_api = api;
    auto init_log = reinterpret_cast<void (*)(const char*, void*)>(api->_ext_init_log_fn);
    if (init_log) init_log("config-anchor.log", api);
    if (!guard()) { api->log(X4NATIVE_LOG_ERROR, "ANCHOR_INVALID build_or_signature_guard"); return X4NATIVE_ERROR; }
    g_state = reinterpret_cast<StateFn>(api->get_game_function("GetMapState"));
    g_component = reinterpret_cast<ComponentFn>(api->get_game_function("GetUpgradeSlotCurrentComponent"));
    if (reinterpret_cast<uintptr_t>(g_state) != api->exe_base + 0x22dfc0 ||
        reinterpret_cast<uintptr_t>(g_component) != api->exe_base + 0x1ad010 ||
        api->get_game_function("GetPickedMapMacroSlot") != reinterpret_cast<void*>(api->exe_base + kPick) ||
        api->resolve_internal("ConfigurationSlotPass") != reinterpret_cast<void*>(api->exe_base + kPass) ||
        api->resolve_internal("ConfigurationSlotIcon") != reinterpret_cast<void*>(api->exe_base + kIcon)) {
        api->log(X4NATIVE_LOG_ERROR, "ANCHOR_INVALID resolver_guard"); return X4NATIVE_ERROR;
    }
    const char* names[] = {"ConfigurationSlotPass", "ConfigurationSlotIcon", "GetPickedMapMacroSlot"};
    void* detours[] = {reinterpret_cast<void*>(&pass_hook), reinterpret_cast<void*>(&icon_hook), reinterpret_cast<void*>(&pick_hook)};
    void* originals[3]{};
    for (int i = 0; i < 3; ++i) {
        g_hooks[i] = api->hook_after(names[i], unused, nullptr, api);
        if (g_hooks[i] <= 0 || !(originals[i] = api->_ensure_detour(names[i], detours[i]))) {
            cleanup(); api->log(X4NATIVE_LOG_ERROR, "ANCHOR_INVALID detour_install"); return X4NATIVE_ERROR;
        }
    }
    g_pass = reinterpret_cast<PassFn>(originals[0]);
    g_icon = reinterpret_cast<IconFn>(originals[1]);
    g_pick = reinterpret_cast<PickFn>(originals[2]);
    g_subscription = api->subscribe("issue205_anchor_command", command, nullptr, api);
    if (g_subscription <= 0 || api->register_lua_bridge("X4GunneryAnchor.Request", "issue205_anchor_command")) {
        cleanup(); api->log(X4NATIVE_LOG_ERROR, "ANCHOR_INVALID lua_bridge"); return X4NATIVE_ERROR;
    }
    api->log(X4NATIVE_LOG_INFO, "ANCHOR_READY unarmed; LIVE behavior unverified");
    return X4NATIVE_OK;
}
X4NATIVE_EXPORT void x4native_shutdown() { cleanup(); }
