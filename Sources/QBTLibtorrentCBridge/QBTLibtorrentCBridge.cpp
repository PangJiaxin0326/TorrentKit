#include "QBTLibtorrentCBridge.h"

#include <CommonCrypto/CommonDigest.h>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/address.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/peer_class_type_filter.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/socket.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iterator>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

constexpr int QBTDefaultListenPort = 49889;
constexpr int QBTDefaultMaximumConnections = 500;
constexpr int QBTDefaultMaximumConnectionsPerTorrent = 100;
constexpr char const *QBTDefaultDHTBootstrapNodes =
    "dht.libtorrent.org:25401,dht.transmissionbt.com:6881,router.bittorrent.com:6881";

struct BridgeFailure: std::runtime_error {
    int32_t code;

    BridgeFailure(int32_t code, std::string message)
        : std::runtime_error(std::move(message))
        , code(code) {}
};

[[noreturn]] void ThrowBridgeError(int32_t code, std::string message) {
    throw BridgeFailure(code, std::move(message));
}

std::string StringFromCString(char const *value) {
    return value == nullptr ? "" : std::string(value);
}

struct JSONValue {
    using Array = std::vector<JSONValue>;
    using Object = std::vector<std::pair<std::string, JSONValue>>;

    std::variant<std::nullptr_t, bool, std::int64_t, double, std::string, Array, Object> value;

    JSONValue()
        : value(nullptr) {}

    JSONValue(std::nullptr_t)
        : value(nullptr) {}

    JSONValue(bool value)
        : value(value) {}

    JSONValue(int value)
        : value(static_cast<std::int64_t>(value)) {}

    JSONValue(std::int64_t value)
        : value(value) {}

    JSONValue(std::uint64_t value)
        : value(static_cast<std::int64_t>(std::min<std::uint64_t>(
            value,
            static_cast<std::uint64_t>((std::numeric_limits<std::int64_t>::max)())
        ))) {}

    JSONValue(float value)
        : value(static_cast<double>(value)) {}

    JSONValue(double value)
        : value(value) {}

    JSONValue(char const *value)
        : value(StringFromCString(value)) {}

    JSONValue(std::string value)
        : value(std::move(value)) {}

    JSONValue(Array value)
        : value(std::move(value)) {}

    JSONValue(Object value)
        : value(std::move(value)) {}
};

using JSONObject = JSONValue::Object;
using JSONArray = JSONValue::Array;

void Set(JSONObject& object, std::string key, JSONValue value) {
    auto iterator = std::find_if(object.begin(), object.end(), [&](auto const& entry) {
        return entry.first == key;
    });
    if (iterator == object.end()) {
        object.emplace_back(std::move(key), std::move(value));
    } else {
        iterator->second = std::move(value);
    }
}

JSONValue const *ValueForKey(JSONObject const& object, std::string const& key) {
    auto iterator = std::find_if(object.begin(), object.end(), [&](auto const& entry) {
        return entry.first == key;
    });
    return iterator == object.end() ? nullptr : &iterator->second;
}

bool BoolForKey(JSONObject const& object, std::string const& key) {
    JSONValue const *value = ValueForKey(object, key);
    if (value == nullptr) {
        return false;
    }

    if (auto boolValue = std::get_if<bool>(&value->value)) {
        return *boolValue;
    }
    return false;
}

std::int64_t IntForKey(JSONObject const& object, std::string const& key) {
    JSONValue const *value = ValueForKey(object, key);
    if (value == nullptr) {
        return 0;
    }

    if (auto intValue = std::get_if<std::int64_t>(&value->value)) {
        return *intValue;
    }
    if (auto doubleValue = std::get_if<double>(&value->value)) {
        return static_cast<std::int64_t>(*doubleValue);
    }
    return 0;
}

std::string StringForKey(JSONObject const& object, std::string const& key) {
    JSONValue const *value = ValueForKey(object, key);
    if (value == nullptr) {
        return "";
    }

    if (auto stringValue = std::get_if<std::string>(&value->value)) {
        return *stringValue;
    }
    return "";
}

void AppendJSONString(std::string& output, std::string const& value) {
    output.push_back('"');
    for (unsigned char character : value) {
        switch (character) {
        case '"':
            output += "\\\"";
            break;
        case '\\':
            output += "\\\\";
            break;
        case '\b':
            output += "\\b";
            break;
        case '\f':
            output += "\\f";
            break;
        case '\n':
            output += "\\n";
            break;
        case '\r':
            output += "\\r";
            break;
        case '\t':
            output += "\\t";
            break;
        default:
            if (character < 0x20) {
                char buffer[7];
                std::snprintf(buffer, sizeof(buffer), "\\u%04x", character);
                output += buffer;
            } else {
                output.push_back(static_cast<char>(character));
            }
        }
    }
    output.push_back('"');
}

void AppendJSONValue(std::string& output, JSONValue const& value);

void AppendJSONArray(std::string& output, JSONArray const& array) {
    output.push_back('[');
    for (std::size_t index = 0; index < array.size(); index += 1) {
        if (index > 0) {
            output.push_back(',');
        }
        AppendJSONValue(output, array[index]);
    }
    output.push_back(']');
}

void AppendJSONObject(std::string& output, JSONObject const& object) {
    output.push_back('{');
    for (std::size_t index = 0; index < object.size(); index += 1) {
        if (index > 0) {
            output.push_back(',');
        }
        AppendJSONString(output, object[index].first);
        output.push_back(':');
        AppendJSONValue(output, object[index].second);
    }
    output.push_back('}');
}

void AppendJSONValue(std::string& output, JSONValue const& value) {
    std::visit([&](auto const& stored) {
        using Stored = std::decay_t<decltype(stored)>;
        if constexpr (std::is_same_v<Stored, std::nullptr_t>) {
            output += "null";
        } else if constexpr (std::is_same_v<Stored, bool>) {
            output += stored ? "true" : "false";
        } else if constexpr (std::is_same_v<Stored, std::int64_t>) {
            output += std::to_string(stored);
        } else if constexpr (std::is_same_v<Stored, double>) {
            if (std::isfinite(stored)) {
                std::ostringstream stream;
                stream << std::setprecision(17) << stored;
                output += stream.str();
            } else {
                output += "0";
            }
        } else if constexpr (std::is_same_v<Stored, std::string>) {
            AppendJSONString(output, stored);
        } else if constexpr (std::is_same_v<Stored, JSONArray>) {
            AppendJSONArray(output, stored);
        } else if constexpr (std::is_same_v<Stored, JSONObject>) {
            AppendJSONObject(output, stored);
        }
    }, value.value);
}

std::string SerializeEvents(std::vector<JSONObject> const& events) {
    JSONArray array;
    array.reserve(events.size());
    for (JSONObject const& event : events) {
        array.emplace_back(event);
    }

    std::string output;
    AppendJSONArray(output, array);
    return output;
}

char *CopyCString(std::string const& value) {
    char *copy = static_cast<char *>(std::malloc(value.size() + 1));
    if (copy == nullptr) {
        return nullptr;
    }

    std::memcpy(copy, value.c_str(), value.size() + 1);
    return copy;
}

QBTLibtorrentBridgeResult Success(std::vector<JSONObject> const& events) {
    return {
        QBTLibtorrentBridgeErrorNone,
        nullptr,
        CopyCString(SerializeEvents(events))
    };
}

QBTLibtorrentBridgeResult Success() {
    return {
        QBTLibtorrentBridgeErrorNone,
        nullptr,
        nullptr
    };
}

QBTLibtorrentBridgeResult Failure(int32_t code, std::string message) {
    return {
        code,
        CopyCString(std::move(message)),
        nullptr
    };
}

template <typename Operation>
QBTLibtorrentBridgeResult CaptureEvents(Operation operation) {
    try {
        return Success(operation());
    } catch (BridgeFailure const& failure) {
        return Failure(failure.code, failure.what());
    } catch (std::exception const& exception) {
        return Failure(QBTLibtorrentBridgeErrorUnexpected, exception.what());
    } catch (...) {
        return Failure(QBTLibtorrentBridgeErrorUnexpected, "Unknown libtorrent bridge failure.");
    }
}

template <typename Operation>
QBTLibtorrentBridgeResult CaptureVoid(Operation operation) {
    try {
        operation();
        return Success();
    } catch (BridgeFailure const& failure) {
        return Failure(failure.code, failure.what());
    } catch (std::exception const& exception) {
        return Failure(QBTLibtorrentBridgeErrorUnexpected, exception.what());
    } catch (...) {
        return Failure(QBTLibtorrentBridgeErrorUnexpected, "Unknown libtorrent bridge failure.");
    }
}

std::string StateName(lt::torrent_status::state_t state) {
    switch (static_cast<int>(state)) {
    case 0:
        return "queued_for_checking";
    case 1:
        return "checking_files";
    case 2:
        return "downloading_metadata";
    case 3:
        return "downloading";
    case 4:
        return "finished";
    case 5:
        return "seeding";
    case 6:
        return "allocating";
    case 7:
        return "checking_resume_data";
    default:
        return "unknown";
    }
}

std::string AddressString(lt::address const& address) {
    return address.to_string();
}

std::string EndpointString(lt::address const& address, int port) {
    std::string addressString = AddressString(address);
    if (address.is_v6()) {
        return "[" + addressString + "]:" + std::to_string(port);
    }
    return addressString + ":" + std::to_string(port);
}

std::string EndpointString(lt::tcp::endpoint const& endpoint) {
    return EndpointString(endpoint.address(), endpoint.port());
}

std::string InfoHashString(lt::info_hash_t const& infoHashes) {
    if (!infoHashes.has_v1() && !infoHashes.has_v2()) {
        return "";
    }

    lt::sha1_hash hash = infoHashes.get_best();
    return lt::aux::to_hex(std::string(hash.data(), lt::sha1_hash::size()));
}

lt::torrent_status CurrentStatus(lt::torrent_handle const& handle) {
    return handle.status(
        lt::torrent_handle::query_name
        | lt::torrent_handle::query_save_path
        | lt::torrent_handle::query_accurate_download_counters
    );
}

std::string Base64Encode(std::vector<char> const& bytes) {
    static constexpr char alphabet[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    std::string encoded;
    encoded.reserve(((bytes.size() + 2) / 3) * 4);

    for (std::size_t index = 0; index < bytes.size(); index += 3) {
        std::uint32_t octetA = static_cast<unsigned char>(bytes[index]);
        std::uint32_t octetB = (index + 1 < bytes.size()) ? static_cast<unsigned char>(bytes[index + 1]) : 0;
        std::uint32_t octetC = (index + 2 < bytes.size()) ? static_cast<unsigned char>(bytes[index + 2]) : 0;
        std::uint32_t triple = (octetA << 16) | (octetB << 8) | octetC;

        encoded.push_back(alphabet[(triple >> 18) & 0x3f]);
        encoded.push_back(alphabet[(triple >> 12) & 0x3f]);
        encoded.push_back(index + 1 < bytes.size() ? alphabet[(triple >> 6) & 0x3f] : '=');
        encoded.push_back(index + 2 < bytes.size() ? alphabet[triple & 0x3f] : '=');
    }

    return encoded;
}

std::string EncodedResumeData(lt::torrent_handle const& handle) {
    if (!handle.is_valid()) {
        return "";
    }

    try {
        lt::add_torrent_params parameters = handle.get_resume_data(lt::torrent_handle::save_info_dict);
        std::vector<char> bytes = lt::write_resume_data_buf(parameters);
        return bytes.empty() ? "" : Base64Encode(bytes);
    } catch (...) {
        return "";
    }
}

JSONArray FilePayloads(lt::torrent_handle const& handle, lt::torrent_status const& status) {
    JSONArray files;
    if (!status.has_metadata) {
        return files;
    }

    std::shared_ptr<const lt::torrent_info> torrentInfo = handle.torrent_file();
    if (!torrentInfo) {
        return files;
    }

    lt::file_storage const& storage = torrentInfo->files();
    std::vector<std::int64_t> completedBytes;
    try {
        completedBytes = handle.file_progress();
    } catch (...) {
        completedBytes.clear();
    }

    for (int index = 0; index < storage.num_files(); ++index) {
        lt::file_index_t fileIndex(index);
        std::int64_t size = storage.file_size(fileIndex);
        std::int64_t completed = index < static_cast<int>(completedBytes.size()) ? completedBytes[index] : 0;
        double progress = size > 0 ? static_cast<double>(completed) / static_cast<double>(size) : 1.0;

        files.emplace_back(JSONObject{
            {"path", storage.file_path(fileIndex)},
            {"size_bytes", size},
            {"completed_bytes", completed},
            {"progress", std::clamp(progress, 0.0, 1.0)},
            {"priority", "normal"}
        });
    }

    return files;
}

void AttachResumeData(JSONObject& payload, lt::torrent_handle const& handle) {
    std::string resumeData = EncodedResumeData(handle);
    if (!resumeData.empty()) {
        Set(payload, "resume_data", std::move(resumeData));
    }
}

JSONObject StatusPayload(lt::torrent_status const& status) {
    bool isPaused = static_cast<bool>(status.flags & lt::torrent_flags::paused);
    bool isAutoManaged = static_cast<bool>(status.flags & lt::torrent_flags::auto_managed);
    JSONObject payload{
        {"name", status.name},
        {"progress", status.progress},
        {"download_rate", status.download_rate},
        {"upload_rate", status.upload_rate},
        {"total_done", status.total_done},
        {"total_wanted", status.total_wanted},
        {"num_peers", status.num_peers},
        {"num_seeds", status.num_seeds},
        {"state", StateName(status.state)},
        {"is_seed", status.is_seeding},
        {"has_metadata", status.has_metadata},
        {"is_paused", isPaused},
        {"is_auto_managed", isAutoManaged},
        {"is_forced_start", !isAutoManaged && !isPaused},
        {"queue_position", static_cast<int>(status.queue_position)},
        {"available_pieces", status.num_pieces},
        {"distributed_copies", status.distributed_copies}
    };

    std::string infoHash = InfoHashString(status.info_hashes);
    if (!infoHash.empty()) {
        Set(payload, "info_hash", std::move(infoHash));
    }

    if (!status.save_path.empty()) {
        Set(payload, "save_path", status.save_path);
    }

    return payload;
}

JSONObject StatusPayload(lt::torrent_handle const& handle) {
    lt::torrent_status status = CurrentStatus(handle);
    JSONObject payload = StatusPayload(status);
    if (ValueForKey(payload, "info_hash") == nullptr) {
        std::string infoHash = InfoHashString(handle.info_hashes());
        if (!infoHash.empty()) {
            Set(payload, "info_hash", std::move(infoHash));
        }
    }
    if (status.has_metadata) {
        std::shared_ptr<const lt::torrent_info> torrentInfo = handle.torrent_file();
        if (torrentInfo) {
            Set(payload, "piece_count", torrentInfo->num_pieces());
            Set(payload, "files", FilePayloads(handle, status));
        }
    }
    Set(payload, "download_limit", handle.download_limit());
    Set(payload, "upload_limit", handle.upload_limit());
    Set(payload, "max_connections", handle.max_connections());
    AttachResumeData(payload, handle);
    return payload;
}

void AppendEvent(std::vector<JSONObject>& events, std::string event, JSONObject payload = {}) {
    JSONObject object;
    object.emplace_back("event", std::move(event));
    for (auto& entry : payload) {
        Set(object, std::move(entry.first), std::move(entry.second));
    }
    events.emplace_back(std::move(object));
}

struct NetworkBinding {
    std::string listenInterfaces;
    std::string outgoingInterfaces;
    bool allowIncomingConnections;
    bool portMappingEnabled;
};

NetworkBinding ProductionNetworkBinding() {
    return {
        "0.0.0.0:" + std::to_string(QBTDefaultListenPort) + ",[::]:" + std::to_string(QBTDefaultListenPort),
        "",
        true,
        true
    };
}

NetworkBinding ExplicitNetworkBinding(std::string listenInterfaces) {
    return {
        std::move(listenInterfaces),
        "",
        true,
        false
    };
}

lt::session MakeSession(NetworkBinding const& binding) {
    lt::settings_pack settings;
    settings.set_str(lt::settings_pack::user_agent, "QBTSwift/1.0");
    settings.set_bool(lt::settings_pack::enable_dht, true);
    settings.set_bool(lt::settings_pack::enable_lsd, true);
    settings.set_bool(lt::settings_pack::enable_upnp, binding.portMappingEnabled);
    settings.set_bool(lt::settings_pack::enable_natpmp, binding.portMappingEnabled);
    settings.set_bool(lt::settings_pack::use_dht_as_fallback, false);
    settings.set_bool(lt::settings_pack::listen_system_port_fallback, true);
    settings.set_bool(lt::settings_pack::announce_to_all_trackers, true);
    settings.set_bool(lt::settings_pack::announce_to_all_tiers, true);
    settings.set_bool(lt::settings_pack::enable_incoming_tcp, true);
    settings.set_bool(lt::settings_pack::enable_outgoing_tcp, true);
    settings.set_bool(lt::settings_pack::enable_incoming_utp, true);
    settings.set_bool(lt::settings_pack::enable_outgoing_utp, true);
    settings.set_str(lt::settings_pack::listen_interfaces, binding.listenInterfaces);
    if (!binding.outgoingInterfaces.empty()) {
        settings.set_str(lt::settings_pack::outgoing_interfaces, binding.outgoingInterfaces);
    }
    settings.set_str(lt::settings_pack::dht_bootstrap_nodes, QBTDefaultDHTBootstrapNodes);
    settings.set_int(lt::settings_pack::connections_limit, QBTDefaultMaximumConnections);
    settings.set_int(lt::settings_pack::active_downloads, -1);
    settings.set_int(lt::settings_pack::active_seeds, -1);
    settings.set_int(lt::settings_pack::active_limit, -1);
    settings.set_int(lt::settings_pack::active_tracker_limit, -1);
    settings.set_int(lt::settings_pack::active_dht_limit, -1);
    settings.set_int(lt::settings_pack::active_lsd_limit, -1);
    settings.set_int(
        lt::settings_pack::alert_mask,
        static_cast<int>(
            lt::alert::peer_notification
            | lt::alert::port_mapping_notification
            | lt::alert::tracker_notification
            | lt::alert::connect_notification
            | lt::alert::status_notification
            | lt::alert::error_notification
            | lt::alert::storage_notification
            | lt::alert::dht_notification
        )
    );
    return lt::session(settings);
}

struct SharedDownloadSession {
    NetworkBinding binding;
    lt::session session;
    std::vector<lt::torrent_handle> handles;
    std::mutex mutex;
    bool enablePeerExchange;
    int maximumConnectionsPerTorrent;

    SharedDownloadSession()
        : binding(ProductionNetworkBinding())
        , session(MakeSession(binding))
        , enablePeerExchange(true)
        , maximumConnectionsPerTorrent(QBTDefaultMaximumConnectionsPerTorrent) {}
};

SharedDownloadSession& DownloadSession() {
    static SharedDownloadSession state;
    return state;
}

void MarkTorrentReadyToStart(lt::add_torrent_params& parameters, bool forced) {
    parameters.flags &= ~lt::torrent_flags::paused;
    if (forced) {
        parameters.flags &= ~lt::torrent_flags::auto_managed;
    } else {
        parameters.flags |= lt::torrent_flags::auto_managed;
    }
}

void ApplyPeerExchangePreference(lt::add_torrent_params& parameters, bool enabled) {
    if (enabled) {
        parameters.flags &= ~lt::torrent_flags::disable_pex;
    } else {
        parameters.flags |= lt::torrent_flags::disable_pex;
    }
}

void ApplyPerTorrentSessionSettings(lt::torrent_handle const& handle,
                                    int maximumConnectionsPerTorrent,
                                    bool enablePeerExchange) {
    if (!handle.is_valid()) {
        return;
    }

    handle.set_max_connections(maximumConnectionsPerTorrent);
    if (enablePeerExchange) {
        handle.unset_flags(lt::torrent_flags::disable_pex);
    } else {
        handle.set_flags(lt::torrent_flags::disable_pex);
    }
}

void StartTorrent(lt::torrent_handle const& handle, bool forced) {
    if (forced) {
        handle.unset_flags(lt::torrent_flags::auto_managed);
    } else {
        handle.set_flags(lt::torrent_flags::auto_managed);
    }
    handle.resume();
    handle.force_reannounce(0);
    handle.force_dht_announce();
}

void PauseTorrent(lt::torrent_handle const& handle) {
    handle.unset_flags(lt::torrent_flags::auto_managed);
    handle.pause();
}

int TorrentLimitFromInt(int32_t limit) {
    if (limit <= 0) {
        return 0;
    }

    return static_cast<int>(std::min<int32_t>(limit, (std::numeric_limits<int>::max)()));
}

int UnlimitedLimitFromInt(int32_t limit) {
    if (limit <= 0) {
        return -1;
    }

    return static_cast<int>(std::min<int32_t>(limit, (std::numeric_limits<int>::max)()));
}

int PositiveSettingFromInt(int32_t value, int defaultValue) {
    if (value <= 0) {
        return defaultValue;
    }

    return static_cast<int>(std::min<int32_t>(value, (std::numeric_limits<int>::max)()));
}

void ApplyPeerClassRateFilters(lt::session& session,
                               bool limitUTPRate,
                               bool limitLocalPeerRates) {
    lt::peer_class_type_filter filter = session.get_peer_class_type_filter();

    auto applyToAllSocketTypes = [&](lt::peer_class_t peerClass, bool allowed) {
        using socket_type = lt::peer_class_type_filter::socket_type_t;
        socket_type const socketTypes[] = {
            socket_type::tcp_socket,
            socket_type::utp_socket,
            socket_type::ssl_tcp_socket,
            socket_type::ssl_utp_socket,
            socket_type::i2p_socket
        };

        for (socket_type const socketType : socketTypes) {
            if (allowed) {
                filter.allow(socketType, peerClass);
            } else {
                filter.disallow(socketType, peerClass);
            }
        }
    };

    if (limitUTPRate) {
        filter.allow(
            lt::peer_class_type_filter::utp_socket,
            lt::session_handle::global_peer_class_id
        );
        filter.allow(
            lt::peer_class_type_filter::ssl_utp_socket,
            lt::session_handle::global_peer_class_id
        );
    } else {
        filter.disallow(
            lt::peer_class_type_filter::utp_socket,
            lt::session_handle::global_peer_class_id
        );
        filter.disallow(
            lt::peer_class_type_filter::ssl_utp_socket,
            lt::session_handle::global_peer_class_id
        );
    }

    applyToAllSocketTypes(
        lt::session_handle::local_peer_class_id,
        !limitLocalPeerRates
    );

    session.set_peer_class_type_filter(filter);
}

int ListenPortFromInt(int32_t port) {
    if (port < 0 || port > 65535) {
        return QBTDefaultListenPort;
    }

    return static_cast<int>(port);
}

std::string ListenInterfacesForPort(int32_t port) {
    int listenPort = ListenPortFromInt(port);
    return "0.0.0.0:" + std::to_string(listenPort) + ",[::]:" + std::to_string(listenPort);
}

std::string TrimmedString(std::string value) {
    auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char character) {
        return std::isspace(character);
    });
    auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char character) {
        return std::isspace(character);
    }).base();

    if (first >= last) {
        return "";
    }
    return std::string(first, last);
}

std::string Lowercased(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

std::optional<int> ProxyTypeFromKind(std::string kind) {
    std::string normalizedKind = Lowercased(TrimmedString(std::move(kind)));
    if (normalizedKind == "none") {
        return lt::settings_pack::none;
    }
    if (normalizedKind == "http") {
        return lt::settings_pack::http;
    }
    if (normalizedKind == "socks5") {
        return lt::settings_pack::socks5;
    }

    return std::nullopt;
}

std::string NormalizedInfoHash(std::string infoHash) {
    std::string normalized = Lowercased(std::move(infoHash));
    std::string prefix = "btih:";
    if (normalized.rfind(prefix, 0) == 0) {
        return normalized.substr(prefix.size());
    }
    return normalized;
}

std::optional<lt::add_torrent_params> AddTorrentParametersFromResumeData(
    std::uint8_t const *resumeData,
    std::size_t resumeDataCount
) {
    if (resumeData == nullptr || resumeDataCount == 0) {
        return std::nullopt;
    }

    lt::error_code resumeError;
    char const *bytes = reinterpret_cast<char const *>(resumeData);
    lt::add_torrent_params parameters = lt::read_resume_data(
        lt::span<char const>(bytes, resumeDataCount),
        resumeError
    );
    if (resumeError) {
        return std::nullopt;
    }

    return parameters;
}

void ApplyStartState(lt::add_torrent_params& parameters, bool startImmediately) {
    if (startImmediately) {
        MarkTorrentReadyToStart(parameters, false);
    } else {
        parameters.flags |= lt::torrent_flags::paused;
        parameters.flags &= ~lt::torrent_flags::auto_managed;
    }
}

std::vector<lt::torrent_handle>::iterator FindHandle(SharedDownloadSession& shared, std::string infoHash) {
    std::string wanted = NormalizedInfoHash(std::move(infoHash));
    return std::find_if(shared.handles.begin(), shared.handles.end(), [&](lt::torrent_handle const& candidate) {
        return candidate.is_valid() && InfoHashString(candidate.info_hashes()) == wanted;
    });
}

void TrackHandle(SharedDownloadSession& shared, lt::torrent_handle const& handle) {
    std::string infoHash = InfoHashString(handle.info_hashes());
    auto existing = std::find_if(shared.handles.begin(), shared.handles.end(), [&](lt::torrent_handle const& candidate) {
        return candidate.is_valid() && InfoHashString(candidate.info_hashes()) == infoHash;
    });

    if (existing == shared.handles.end()) {
        shared.handles.push_back(handle);
    }
}

void MarkPayloadPaused(JSONObject& payload) {
    Set(payload, "download_rate", 0);
    Set(payload, "upload_rate", 0);
    Set(payload, "is_paused", true);
    Set(payload, "is_auto_managed", false);
    Set(payload, "is_forced_start", false);
}

bool PayloadIsComplete(JSONObject const& payload) {
    std::int64_t totalWanted = IntForKey(payload, "total_wanted");
    std::int64_t totalDone = IntForKey(payload, "total_done");
    return BoolForKey(payload, "is_seed") || (totalWanted > 0 && totalDone >= totalWanted);
}

void MarkPayloadCompletedStopped(JSONObject& payload) {
    MarkPayloadPaused(payload);
    Set(payload, "progress", 1.0);
    Set(payload, "download_rate", 0);
    Set(payload, "upload_rate", 0);
    Set(payload, "num_peers", 0);
    Set(payload, "num_seeds", 0);
    Set(payload, "state", "completed");
    Set(payload, "is_seed", true);
}

bool StopCompletedTorrentIfNeeded(lt::torrent_handle const& handle, JSONObject& payload) {
    if (!PayloadIsComplete(payload)) {
        return false;
    }

    PauseTorrent(handle);
    MarkPayloadCompletedStopped(payload);
    return true;
}

std::optional<lt::tcp::endpoint> EndpointFromPeer(std::string const& peer) {
    std::size_t separator = peer.rfind(':');
    if (separator == std::string::npos || separator == 0 || separator + 1 >= peer.size()) {
        return std::nullopt;
    }

    std::string host = peer.substr(0, separator);
    std::string portString = peer.substr(separator + 1);
    int port = 0;
    try {
        port = std::stoi(portString);
    } catch (...) {
        return std::nullopt;
    }
    if (port <= 0 || port > 65535) {
        return std::nullopt;
    }

    lt::error_code error;
    lt::address address = lt::make_address(host, error);
    if (error) {
        return std::nullopt;
    }

    return lt::tcp::endpoint(address, static_cast<std::uint16_t>(port));
}

void ConnectPeerIfPresent(lt::torrent_handle& handle, std::optional<std::string> const& peer) {
    if (!peer) {
        return;
    }

    if (auto endpoint = EndpointFromPeer(*peer)) {
        handle.connect_peer(*endpoint);
    }
}

bool AppendLibtorrentAlert(std::vector<JSONObject>& events, lt::alert *alert) {
    if (auto *listen = lt::alert_cast<lt::listen_succeeded_alert>(alert)) {
        AppendEvent(events, "listen_succeeded", {
            {"endpoint", EndpointString(listen->address, listen->port)},
            {"port", listen->port},
            {"message", alert->message()}
        });
        return true;
    } else if (auto *listen = lt::alert_cast<lt::listen_failed_alert>(alert)) {
        AppendEvent(events, "listen_failed", {
            {"endpoint", EndpointString(listen->address, listen->port)},
            {"port", listen->port},
            {"listen_interface", StringFromCString(listen->listen_interface())},
            {"message", alert->message()}
        });
    } else if (auto *ip = lt::alert_cast<lt::external_ip_alert>(alert)) {
        AppendEvent(events, "external_ip", {
            {"external_address", AddressString(ip->external_address)},
            {"message", alert->message()}
        });
    } else if (lt::alert_cast<lt::dht_bootstrap_alert>(alert) != nullptr) {
        AppendEvent(events, "dht_bootstrap", {
            {"message", alert->message()}
        });
        return true;
    } else if (auto *announce = lt::alert_cast<lt::tracker_announce_alert>(alert)) {
        AppendEvent(events, "tracker_announce", {
            {"tracker_url", StringFromCString(announce->tracker_url())},
            {"endpoint", EndpointString(announce->local_endpoint)},
            {"message", alert->message()}
        });
        return true;
    } else if (auto *reply = lt::alert_cast<lt::tracker_reply_alert>(alert)) {
        AppendEvent(events, "tracker_reply", {
            {"tracker_url", StringFromCString(reply->tracker_url())},
            {"endpoint", EndpointString(reply->local_endpoint)},
            {"num_peers", reply->num_peers},
            {"message", alert->message()}
        });
        return true;
    } else if (auto *reply = lt::alert_cast<lt::dht_reply_alert>(alert)) {
        AppendEvent(events, "dht_reply", {
            {"num_peers", reply->num_peers},
            {"message", alert->message()}
        });
        return true;
    } else if (auto *trackerError = lt::alert_cast<lt::tracker_error_alert>(alert)) {
        AppendEvent(events, "tracker_error", {
            {"tracker_url", StringFromCString(trackerError->tracker_url())},
            {"endpoint", EndpointString(trackerError->local_endpoint)},
            {"message", alert->message()}
        });
    } else if (auto *peer = lt::alert_cast<lt::peer_connect_alert>(alert)) {
        AppendEvent(events, "peer_connected", {
            {"endpoint", EndpointString(peer->endpoint)},
            {"direction", peer->direction == lt::peer_connect_alert::direction_t::in ? "in" : "out"},
            {"message", alert->message()}
        });
        return true;
    } else if (auto *peer = lt::alert_cast<lt::peer_disconnected_alert>(alert)) {
        AppendEvent(events, "peer_disconnected", {
            {"endpoint", EndpointString(peer->endpoint)},
            {"message", alert->message()}
        });
    } else if (auto *portMap = lt::alert_cast<lt::portmap_alert>(alert)) {
        AppendEvent(events, "portmap_succeeded", {
            {"external_port", portMap->external_port},
            {"message", alert->message()}
        });
        return true;
    } else if (auto *portMap = lt::alert_cast<lt::portmap_error_alert>(alert)) {
        AppendEvent(events, "portmap_failed", {
            {"message", alert->message()}
        });
    } else if (static_cast<bool>(alert->category() & lt::alert_category::error)) {
        AppendEvent(events, "alert", {{"message", alert->message()}});
    }

    return false;
}

void EnsureDirectory(std::string const& path) {
    std::error_code error;
    std::filesystem::create_directories(std::filesystem::path(path), error);
    if (error) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorFileSystem, error.message());
    }
}

std::vector<JSONObject> DownloadMagnetNative(
    std::string magnet,
    std::string savePath,
    std::uint8_t const *resumeData,
    std::size_t resumeDataCount,
    double timeout,
    bool metadataOnly,
    bool startImmediately,
    std::optional<std::string> peer
) {
    EnsureDirectory(savePath);

    lt::add_torrent_params parameters;
    if (auto resumedParameters = AddTorrentParametersFromResumeData(resumeData, resumeDataCount)) {
        parameters = std::move(*resumedParameters);
    } else {
        lt::error_code parseError;
        parameters = lt::parse_magnet_uri(magnet, parseError);
        if (parseError) {
            ThrowBridgeError(QBTLibtorrentBridgeErrorInvalidMagnet, parseError.message());
        }
    }

    parameters.save_path = savePath;
    ApplyStartState(parameters, startImmediately);

    SharedDownloadSession& shared = DownloadSession();
    lt::torrent_handle handle;
    std::string listenInterfaces;
    std::string outgoingInterfaces;
    std::string startedName;
    {
        std::unique_lock<std::mutex> lock(shared.mutex);
        ApplyPeerExchangePreference(parameters, shared.enablePeerExchange);
        lt::error_code addError;
        handle = shared.session.add_torrent(std::move(parameters), addError);
        if (addError) {
            ThrowBridgeError(QBTLibtorrentBridgeErrorAddTorrentFailed, addError.message());
        }

        TrackHandle(shared, handle);
        ApplyPerTorrentSessionSettings(handle, shared.maximumConnectionsPerTorrent, shared.enablePeerExchange);
        if (startImmediately) {
            StartTorrent(handle, false);
        } else {
            PauseTorrent(handle);
        }
        ConnectPeerIfPresent(handle, peer);
        listenInterfaces = shared.binding.listenInterfaces;
        outgoingInterfaces = shared.binding.outgoingInterfaces;
        startedName = StringForKey(StatusPayload(handle), "name");
    }

    std::vector<JSONObject> events;
    AppendEvent(events, startImmediately ? "started" : "paused", {
        {"save_path", savePath},
        {"listen_interfaces", listenInterfaces},
        {"outgoing_interfaces", outgoingInterfaces},
        {"name", startedName}
    });

    if (!startImmediately) {
        std::unique_lock<std::mutex> lock(shared.mutex);
        JSONObject payload = StatusPayload(handle);
        MarkPayloadPaused(payload);
        AppendEvent(events, "paused", payload);
        return events;
    }

    Clock::time_point deadline = Clock::now() + std::chrono::milliseconds(static_cast<int>(timeout * 1000));
    Clock::time_point startupDeadline = Clock::now() + std::chrono::seconds(8);
    Clock::time_point nextStatus = Clock::now();
    bool emittedMetadata = false;
    bool observedNetworkStartup = false;

    while (Clock::now() < deadline) {
        {
            std::unique_lock<std::mutex> lock(shared.mutex);
            std::vector<lt::alert *> alerts;
            shared.session.pop_alerts(&alerts);
            for (lt::alert *alert : alerts) {
                if (lt::alert_cast<lt::metadata_received_alert>(alert) != nullptr) {
                    emittedMetadata = true;
                    AppendEvent(events, "metadata_received", StatusPayload(handle));
                } else if (lt::alert_cast<lt::torrent_finished_alert>(alert) != nullptr) {
                    JSONObject payload = StatusPayload(handle);
                    StopCompletedTorrentIfNeeded(handle, payload);
                    AppendEvent(events, "finished", payload);
                    return events;
                } else {
                    observedNetworkStartup = AppendLibtorrentAlert(events, alert) || observedNetworkStartup;
                }
            }

            JSONObject payload = StatusPayload(handle);
            if (!emittedMetadata && BoolForKey(payload, "has_metadata")) {
                emittedMetadata = true;
                AppendEvent(events, "metadata_received", payload);
            }

            if (Clock::now() >= nextStatus) {
                AppendEvent(events, "status", payload);
                nextStatus = Clock::now() + std::chrono::seconds(1);

                if (metadataOnly && BoolForKey(payload, "has_metadata")) {
                    AppendEvent(events, "metadata_complete", payload);
                    return events;
                }

                if (StopCompletedTorrentIfNeeded(handle, payload)) {
                    AppendEvent(events, "finished", payload);
                    return events;
                }

                if (!metadataOnly && (observedNetworkStartup || Clock::now() >= startupDeadline)) {
                    AppendEvent(events, "session_active", payload);
                    return events;
                }
            }

            ConnectPeerIfPresent(handle, peer);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    {
        std::unique_lock<std::mutex> lock(shared.mutex);
        AppendEvent(events, "timeout", StatusPayload(handle));
    }
    return events;
}

std::vector<JSONObject> DownloadTorrentFileNative(
    std::string torrentFile,
    std::string savePath,
    std::uint8_t const *resumeData,
    std::size_t resumeDataCount,
    double timeout,
    bool startImmediately
) {
    (void)timeout;
    if (!std::filesystem::exists(std::filesystem::path(torrentFile))) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorFileSystem, "The torrent file does not exist.");
    }
    EnsureDirectory(savePath);

    lt::error_code infoError;
    auto torrentInfo = std::make_shared<lt::torrent_info>(torrentFile, infoError);
    if (infoError) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorInvalidMagnet, infoError.message());
    }

    lt::add_torrent_params parameters;
    if (auto resumedParameters = AddTorrentParametersFromResumeData(resumeData, resumeDataCount)) {
        parameters = std::move(*resumedParameters);
        if (!parameters.ti) {
            parameters.ti = torrentInfo;
        }
    } else {
        parameters.ti = torrentInfo;
    }
    parameters.save_path = savePath;
    ApplyStartState(parameters, startImmediately);

    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);
    ApplyPeerExchangePreference(parameters, shared.enablePeerExchange);
    lt::session& session = shared.session;
    NetworkBinding const& binding = shared.binding;
    lt::error_code addError;
    lt::torrent_handle handle = session.add_torrent(std::move(parameters), addError);
    if (addError) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorAddTorrentFailed, addError.message());
    }

    TrackHandle(shared, handle);
    ApplyPerTorrentSessionSettings(handle, shared.maximumConnectionsPerTorrent, shared.enablePeerExchange);
    if (startImmediately) {
        StartTorrent(handle, false);
    } else {
        PauseTorrent(handle);
    }

    std::vector<JSONObject> events;
    AppendEvent(events, startImmediately ? "started" : "paused", {
        {"save_path", savePath},
        {"listen_interfaces", binding.listenInterfaces},
        {"outgoing_interfaces", binding.outgoingInterfaces},
        {"name", StringForKey(StatusPayload(handle), "name")}
    });

    JSONObject payload = StatusPayload(handle);
    AppendEvent(events, "metadata_received", payload);
    if (StopCompletedTorrentIfNeeded(handle, payload)) {
        AppendEvent(events, "finished", payload);
        return events;
    }

    AppendEvent(events, "session_active", payload);
    return events;
}

std::vector<JSONObject> ActiveTorrentStatusesNative() {
    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);

    std::vector<lt::alert *> alerts;
    shared.session.pop_alerts(&alerts);

    std::vector<JSONObject> events;
    auto iterator = shared.handles.begin();
    while (iterator != shared.handles.end()) {
        lt::torrent_handle& handle = *iterator;
        if (!handle.is_valid()) {
            iterator = shared.handles.erase(iterator);
            continue;
        }

        JSONObject payload = StatusPayload(handle);
        if (StopCompletedTorrentIfNeeded(handle, payload)) {
            AppendEvent(events, "status", payload);
        } else if (BoolForKey(payload, "is_paused")) {
            MarkPayloadPaused(payload);
            AppendEvent(events, "status", payload);
        } else {
            AppendEvent(events, "status", payload);
        }
        ++iterator;
    }

    return events;
}

std::vector<JSONObject> SetTorrentPausedNative(std::string infoHash, bool paused) {
    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);

    auto handleIterator = FindHandle(shared, std::move(infoHash));
    if (handleIterator == shared.handles.end()) {
        ThrowBridgeError(
            QBTLibtorrentBridgeErrorMissingTorrent,
            "The selected torrent is not active in the current libtorrent session."
        );
    }

    lt::torrent_handle handle = *handleIterator;
    if (!paused) {
        JSONObject payload = StatusPayload(handle);
        if (StopCompletedTorrentIfNeeded(handle, payload)) {
            std::vector<JSONObject> events;
            AppendEvent(events, "finished", payload);
            return events;
        }
    }

    if (paused) {
        PauseTorrent(handle);
    } else {
        StartTorrent(handle, false);
    }

    JSONObject payload = StatusPayload(handle);
    if (paused) {
        MarkPayloadPaused(payload);
    }

    std::vector<JSONObject> events;
    if (paused) {
        AppendEvent(events, "paused", payload);
    } else {
        Set(payload, "is_paused", false);
        AppendEvent(events, "resumed", payload);
    }

    return events;
}

std::vector<JSONObject> ForceStartTorrentNative(std::string infoHash) {
    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);

    auto handleIterator = FindHandle(shared, std::move(infoHash));
    if (handleIterator == shared.handles.end()) {
        ThrowBridgeError(
            QBTLibtorrentBridgeErrorMissingTorrent,
            "The selected torrent is not active in the current libtorrent session."
        );
    }

    lt::torrent_handle handle = *handleIterator;
    JSONObject completedPayload = StatusPayload(handle);
    if (StopCompletedTorrentIfNeeded(handle, completedPayload)) {
        std::vector<JSONObject> events;
        AppendEvent(events, "finished", completedPayload);
        return events;
    }

    StartTorrent(handle, true);

    JSONObject payload = StatusPayload(handle);
    Set(payload, "is_paused", false);

    std::vector<JSONObject> events;
    AppendEvent(events, "resumed", payload);
    return events;
}

std::vector<JSONObject> MoveTorrentNative(std::string infoHash, std::string queueMove) {
    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);

    auto handleIterator = FindHandle(shared, std::move(infoHash));
    if (handleIterator == shared.handles.end()) {
        ThrowBridgeError(
            QBTLibtorrentBridgeErrorMissingTorrent,
            "The selected torrent is not active in the current libtorrent session."
        );
    }

    lt::torrent_handle handle = *handleIterator;
    if (queueMove == "top") {
        handle.queue_position_top();
    } else if (queueMove == "up") {
        handle.queue_position_up();
    } else if (queueMove == "down") {
        handle.queue_position_down();
    } else if (queueMove == "bottom") {
        handle.queue_position_bottom();
    } else {
        ThrowBridgeError(QBTLibtorrentBridgeErrorUnexpected, "Unknown queue move.");
    }

    std::vector<JSONObject> events;
    AppendEvent(events, "status", StatusPayload(handle));
    return events;
}

std::vector<JSONObject> SetTorrentLimitsNative(
    std::string infoHash,
    int32_t downloadLimitBytesPerSecond,
    int32_t uploadLimitBytesPerSecond
) {
    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);

    auto handleIterator = FindHandle(shared, std::move(infoHash));
    if (handleIterator == shared.handles.end()) {
        ThrowBridgeError(
            QBTLibtorrentBridgeErrorMissingTorrent,
            "The selected torrent is not active in the current libtorrent session."
        );
    }

    lt::torrent_handle handle = *handleIterator;
    handle.set_download_limit(TorrentLimitFromInt(downloadLimitBytesPerSecond));
    handle.set_upload_limit(TorrentLimitFromInt(uploadLimitBytesPerSecond));

    std::vector<JSONObject> events;
    AppendEvent(events, "status", StatusPayload(handle));
    return events;
}

void ApplySessionSettingsNative(QBTLibtorrentSessionSettings input) {
    std::optional<int> proxyType = ProxyTypeFromKind(StringFromCString(input.proxyKind));
    if (!proxyType) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorUnexpected, "Unknown proxy kind.");
    }

    std::string trimmedProxyHost = TrimmedString(StringFromCString(input.proxyHost));
    bool proxyIsUsable = (*proxyType != lt::settings_pack::none)
        && !trimmedProxyHost.empty()
        && input.proxyPort > 0
        && input.proxyPort <= 65535;
    bool proxyPeerConnections = input.proxyPeerConnections;
    bool proxyHostnames = input.proxyHostnames;
    int32_t proxyPort = input.proxyPort;
    if (!proxyIsUsable) {
        proxyType = lt::settings_pack::none;
        trimmedProxyHost = "";
        proxyPort = 0;
        proxyPeerConnections = false;
        proxyHostnames = false;
    }

    std::string bootstrapNodes = TrimmedString(StringFromCString(input.dhtBootstrapNodes));
    if (bootstrapNodes.empty()) {
        bootstrapNodes = QBTDefaultDHTBootstrapNodes;
    }

    std::string listenInterfaces = ListenInterfacesForPort(input.allowIncomingConnections ? input.listenPort : 0);
    bool shouldMapPorts = input.allowIncomingConnections && input.enablePortMapping;

    lt::settings_pack settings;
    settings.set_bool(lt::settings_pack::enable_dht, input.enableDHT);
    settings.set_bool(lt::settings_pack::enable_lsd, input.enableLocalServiceDiscovery);
    settings.set_bool(lt::settings_pack::enable_upnp, shouldMapPorts);
    settings.set_bool(lt::settings_pack::enable_natpmp, shouldMapPorts);
    settings.set_bool(lt::settings_pack::enable_incoming_tcp, input.allowIncomingConnections);
    settings.set_bool(lt::settings_pack::enable_incoming_utp, input.allowIncomingConnections);
    settings.set_bool(lt::settings_pack::rate_limit_ip_overhead, input.includeProtocolOverhead);
    settings.set_str(lt::settings_pack::listen_interfaces, listenInterfaces);
    settings.set_int(lt::settings_pack::connections_limit, UnlimitedLimitFromInt(input.maximumConnections));
    settings.set_int(lt::settings_pack::download_rate_limit, TorrentLimitFromInt(input.downloadLimitBytesPerSecond));
    settings.set_int(lt::settings_pack::upload_rate_limit, TorrentLimitFromInt(input.uploadLimitBytesPerSecond));
    settings.set_int(lt::settings_pack::connection_speed, PositiveSettingFromInt(input.connectionSpeed, 30));
    settings.set_int(lt::settings_pack::max_out_request_queue, PositiveSettingFromInt(input.requestQueueSize, 500));
    settings.set_str(lt::settings_pack::dht_bootstrap_nodes, bootstrapNodes);
    settings.set_int(lt::settings_pack::proxy_type, *proxyType);
    settings.set_str(lt::settings_pack::proxy_hostname, trimmedProxyHost);
    settings.set_int(lt::settings_pack::proxy_port, static_cast<int>(proxyPort));
    settings.set_bool(lt::settings_pack::proxy_peer_connections, proxyPeerConnections);
    settings.set_bool(lt::settings_pack::proxy_hostnames, proxyHostnames);
    if (*proxyType == lt::settings_pack::none) {
        settings.set_str(lt::settings_pack::proxy_username, "");
        settings.set_str(lt::settings_pack::proxy_password, "");
    }

    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);
    shared.binding = {
        listenInterfaces,
        "",
        input.allowIncomingConnections,
        shouldMapPorts
    };
    shared.enablePeerExchange = input.enablePeerExchange;
    int perTorrentLimit = UnlimitedLimitFromInt(input.maximumConnectionsPerTorrent);
    shared.maximumConnectionsPerTorrent = perTorrentLimit;
    shared.session.apply_settings(std::move(settings));
    ApplyPeerClassRateFilters(shared.session, input.limitUTPRate, input.limitLocalPeerRates);

    for (lt::torrent_handle const& handle : shared.handles) {
        ApplyPerTorrentSessionSettings(handle, perTorrentLimit, input.enablePeerExchange);
    }
}

std::vector<JSONObject> RemoveTorrentNative(std::string infoHash, bool deletingFiles) {
    SharedDownloadSession& shared = DownloadSession();
    std::unique_lock<std::mutex> lock(shared.mutex);

    auto handleIterator = FindHandle(shared, std::move(infoHash));
    if (handleIterator == shared.handles.end()) {
        ThrowBridgeError(
            QBTLibtorrentBridgeErrorMissingTorrent,
            "The selected torrent is not active in the current libtorrent session."
        );
    }

    lt::torrent_handle handle = *handleIterator;
    JSONObject payload = StatusPayload(handle);
    Set(payload, "deleting_files", deletingFiles);

    PauseTorrent(handle);
    shared.handles.erase(handleIterator);

    if (deletingFiles) {
        shared.session.remove_torrent(handle, lt::session_handle::delete_files);
    } else {
        shared.session.remove_torrent(handle, lt::session_handle::delete_partfile);
    }

    std::vector<JSONObject> events;
    AppendEvent(events, "removed", payload);
    return events;
}

void WritePayload(std::filesystem::path const& filePath, std::size_t size) {
    std::vector<std::uint8_t> bytes(size);
    std::mt19937 generator(42);
    std::uniform_int_distribution<int> distribution(0, 255);
    for (std::uint8_t& byte : bytes) {
        byte = static_cast<std::uint8_t>(distribution(generator));
    }

    std::ofstream output(filePath, std::ios::binary | std::ios::trunc);
    if (!output) {
        throw std::runtime_error("failed to open legal self-test payload");
    }
    output.write(reinterpret_cast<char const *>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    if (!output) {
        throw std::runtime_error("failed to write legal self-test payload");
    }
}

struct CreatedTorrent {
    std::vector<char> encoded;
    std::shared_ptr<lt::torrent_info> info;
    std::string magnet;
    std::string infoHash;
};

CreatedTorrent MakeTorrentForFile(std::filesystem::path const& filePath,
                                  std::filesystem::path const& sourceDirectory) {
    lt::file_storage storage;
    lt::add_files(storage, filePath.string().c_str());
    lt::create_torrent torrent(storage, 16 * 1024);

    lt::error_code hashError;
    lt::set_piece_hashes(torrent, sourceDirectory.string().c_str(), hashError);
    if (hashError) {
        throw std::runtime_error(hashError.message());
    }

    lt::entry generated = torrent.generate();
    std::vector<char> encoded;
    lt::bencode(std::back_inserter(encoded), generated);

    lt::error_code infoError;
    auto info = std::make_shared<lt::torrent_info>(encoded.data(), static_cast<int>(encoded.size()), infoError);
    if (infoError) {
        throw std::runtime_error(infoError.message());
    }

    lt::sha1_hash hash = info->info_hash();
    std::string hashBytes(hash.data(), lt::sha1_hash::size());

    return {
        encoded,
        info,
        lt::make_magnet_uri(*info),
        lt::aux::to_hex(hashBytes)
    };
}

int WaitForListenPort(lt::session& session) {
    Clock::time_point deadline = Clock::now() + std::chrono::seconds(10);

    while (Clock::now() < deadline) {
        std::vector<lt::alert *> alerts;
        session.pop_alerts(&alerts);
        for (lt::alert *alert : alerts) {
            if (auto *listen = lt::alert_cast<lt::listen_succeeded_alert>(alert)) {
                if (listen->socket_type == lt::socket_type_t::tcp) {
                    return listen->port;
                }
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    throw std::runtime_error("timed out waiting for libtorrent listen port");
}

std::string SHA256Hex(std::filesystem::path const& filePath) {
    std::ifstream input(filePath, std::ios::binary);
    if (!input) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorFileSystem, "Could not read self-test payload.");
    }

    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);

    std::array<char, 8192> buffer{};
    while (input) {
        input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        std::streamsize count = input.gcount();
        if (count > 0) {
            CC_SHA256_Update(&context, buffer.data(), static_cast<CC_LONG>(count));
        }
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);

    std::ostringstream output;
    output << std::hex << std::setfill('0');
    for (unsigned char byte : digest) {
        output << std::setw(2) << static_cast<int>(byte);
    }
    return output.str();
}

std::vector<JSONObject> RunSelfTestNative(std::string root, double timeout) {
    std::filesystem::path rootPath(root);
    std::filesystem::path sourceDirectory = rootPath / "source";
    std::filesystem::path downloadDirectory = rootPath / "download";
    std::filesystem::path sourceFile = sourceDirectory / "legal-self-test.bin";
    std::filesystem::path torrentFile = rootPath / "legal-self-test.torrent";

    EnsureDirectory(sourceDirectory.string());
    EnsureDirectory(downloadDirectory.string());

    WritePayload(sourceFile, 262144);
    CreatedTorrent created = MakeTorrentForFile(sourceFile, sourceDirectory);
    {
        std::ofstream output(torrentFile, std::ios::binary | std::ios::trunc);
        if (!output) {
            ThrowBridgeError(QBTLibtorrentBridgeErrorFileSystem, "Could not write self-test torrent.");
        }
        output.write(created.encoded.data(), static_cast<std::streamsize>(created.encoded.size()));
    }

    lt::session seedSession = MakeSession(ExplicitNetworkBinding("127.0.0.1:0"));
    lt::add_torrent_params seedParameters;
    seedParameters.ti = created.info;
    seedParameters.save_path = sourceDirectory.string();
    MarkTorrentReadyToStart(seedParameters, false);
    lt::error_code seedError;
    lt::torrent_handle seedHandle = seedSession.add_torrent(std::move(seedParameters), seedError);
    if (seedError) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorSelfTestFailed, seedError.message());
    }
    StartTorrent(seedHandle, false);
    int seedPort = WaitForListenPort(seedSession);

    lt::session downloadSession = MakeSession(ExplicitNetworkBinding("127.0.0.1:0"));
    lt::error_code parseError;
    lt::add_torrent_params downloadParameters = lt::parse_magnet_uri(created.magnet, parseError);
    if (parseError) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorSelfTestFailed, parseError.message());
    }
    downloadParameters.save_path = downloadDirectory.string();
    MarkTorrentReadyToStart(downloadParameters, false);

    lt::error_code addError;
    lt::torrent_handle downloadHandle = downloadSession.add_torrent(std::move(downloadParameters), addError);
    if (addError) {
        ThrowBridgeError(QBTLibtorrentBridgeErrorSelfTestFailed, addError.message());
    }

    StartTorrent(downloadHandle, false);
    std::string peer = "127.0.0.1:" + std::to_string(seedPort);
    ConnectPeerIfPresent(downloadHandle, peer);

    std::vector<JSONObject> events;
    AppendEvent(events, "self_test_started", {
        {"root", root},
        {"magnet", created.magnet},
        {"info_hash", created.infoHash},
        {"peer", peer}
    });

    Clock::time_point deadline = Clock::now() + std::chrono::milliseconds(static_cast<int>(timeout * 1000));
    Clock::time_point nextStatus = Clock::now();
    bool emittedMetadata = false;

    while (Clock::now() < deadline) {
        std::vector<lt::alert *> alerts;
        downloadSession.pop_alerts(&alerts);
        for (lt::alert *alert : alerts) {
            if (lt::alert_cast<lt::metadata_received_alert>(alert) != nullptr) {
                emittedMetadata = true;
                AppendEvent(events, "metadata_received", StatusPayload(downloadHandle));
            } else if (lt::alert_cast<lt::torrent_finished_alert>(alert) != nullptr) {
                AppendEvent(events, "finished", StatusPayload(downloadHandle));
            } else {
                AppendLibtorrentAlert(events, alert);
            }
        }

        JSONObject payload = StatusPayload(downloadHandle);
        if (!emittedMetadata && BoolForKey(payload, "has_metadata")) {
            emittedMetadata = true;
            AppendEvent(events, "metadata_received", payload);
        }

        if (Clock::now() >= nextStatus) {
            AppendEvent(events, "status", payload);
            nextStatus = Clock::now() + std::chrono::seconds(1);

            if (PayloadIsComplete(payload)) {
                std::filesystem::path downloadedFile = downloadDirectory / sourceFile.filename();
                std::string expected = SHA256Hex(sourceFile);
                std::string actual = SHA256Hex(downloadedFile);
                if (expected.empty() || actual.empty() || expected != actual) {
                    ThrowBridgeError(
                        QBTLibtorrentBridgeErrorSelfTestFailed,
                        "Downloaded self-test payload did not match the source hash."
                    );
                }

                AppendEvent(events, "self_test_finished", {
                    {"file", downloadedFile.string()},
                    {"sha256", actual}
                });
                return events;
            }
        }

        ConnectPeerIfPresent(downloadHandle, peer);
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    AppendEvent(events, "timeout", StatusPayload(downloadHandle));
    ThrowBridgeError(
        QBTLibtorrentBridgeErrorTimeout,
        "Timed out waiting for libtorrent self-test completion."
    );
}

std::optional<std::string> OptionalString(char const *value) {
    if (value == nullptr || value[0] == '\0') {
        return std::nullopt;
    }
    return std::string(value);
}

} // namespace

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_download_magnet(
    const char *magnet,
    const char *savePath,
    const uint8_t *resumeData,
    size_t resumeDataCount,
    double timeout,
    bool metadataOnly,
    bool startImmediately,
    const char *peer
) {
    return CaptureEvents([&] {
        return DownloadMagnetNative(
            StringFromCString(magnet),
            StringFromCString(savePath),
            resumeData,
            resumeDataCount,
            timeout,
            metadataOnly,
            startImmediately,
            OptionalString(peer)
        );
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_download_torrent_file(
    const char *torrentFile,
    const char *savePath,
    const uint8_t *resumeData,
    size_t resumeDataCount,
    double timeout,
    bool startImmediately
) {
    return CaptureEvents([&] {
        return DownloadTorrentFileNative(
            StringFromCString(torrentFile),
            StringFromCString(savePath),
            resumeData,
            resumeDataCount,
            timeout,
            startImmediately
        );
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_active_torrent_statuses(void) {
    return CaptureEvents([] {
        return ActiveTorrentStatusesNative();
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_start_torrent(const char *infoHash) {
    return CaptureEvents([&] {
        return SetTorrentPausedNative(StringFromCString(infoHash), false);
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_pause_torrent(const char *infoHash) {
    return CaptureEvents([&] {
        return SetTorrentPausedNative(StringFromCString(infoHash), true);
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_remove_torrent(
    const char *infoHash,
    bool deletingFiles
) {
    return CaptureEvents([&] {
        return RemoveTorrentNative(StringFromCString(infoHash), deletingFiles);
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_force_start_torrent(const char *infoHash) {
    return CaptureEvents([&] {
        return ForceStartTorrentNative(StringFromCString(infoHash));
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_move_torrent(
    const char *infoHash,
    const char *queueMove
) {
    return CaptureEvents([&] {
        return MoveTorrentNative(StringFromCString(infoHash), StringFromCString(queueMove));
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_set_torrent_limits(
    const char *infoHash,
    int32_t downloadLimitBytesPerSecond,
    int32_t uploadLimitBytesPerSecond
) {
    return CaptureEvents([&] {
        return SetTorrentLimitsNative(
            StringFromCString(infoHash),
            downloadLimitBytesPerSecond,
            uploadLimitBytesPerSecond
        );
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_apply_session_settings(
    QBTLibtorrentSessionSettings settings
) {
    return CaptureVoid([&] {
        ApplySessionSettingsNative(settings);
    });
}

extern "C" QBTLibtorrentBridgeResult qbt_libtorrent_run_self_test(
    const char *root,
    double timeout
) {
    return CaptureEvents([&] {
        return RunSelfTestNative(StringFromCString(root), timeout);
    });
}

extern "C" void qbt_libtorrent_bridge_result_destroy(QBTLibtorrentBridgeResult result) {
    std::free(result.message);
    std::free(result.payloadJSON);
}
