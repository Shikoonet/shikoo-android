// The Windows core's side of OpenVPN 3: shikoo_ovpn3.cpp's session behind a C interface that Go calls without cgo. The
// tunnel (wintun, routes, DNS) stays Go's; OpenVPN 3 only hands packets across.
#include <client/ovpncli.cpp>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

using namespace openvpn;
using namespace openvpn::ClientAPI;

extern "C" {
// Go's windows.NewCallback takes and returns uintptr only.
struct ShikooOvpnCallbacks {
    uintptr_t (*protect)(uintptr_t socket, uintptr_t ipv6);
    uintptr_t (*establish)(const char *spec);
    uintptr_t (*write)(const std::uint8_t *packet, uintptr_t size);
    uintptr_t (*event)(const char *name, const char *info, uintptr_t error);
};
}

namespace {
std::string list(const std::vector<std::string> &items) {
    std::string out = "[";
    for (const auto &item : items) out += (out.size() > 1 ? ",\"" : "\"") + item + "\"";
    return out + "]";
}

class GoTun;

std::mutex runningMu;
struct Client *running = nullptr;
GoTun *active = nullptr;
std::atomic<int> backlog{0};

struct Client : OpenVPNClient {
    const ShikooOvpnCallbacks *go = nullptr;
    std::vector<std::string> addresses, dns;
    int mtu = 0;

    bool tun_builder_new() override {
        addresses.clear();
        dns.clear();
        mtu = 0;
        return true;
    }

    bool tun_builder_set_remote_address(const std::string &, bool) override { return true; }

    bool tun_builder_set_session_name(const std::string &) override { return true; }

    bool tun_builder_add_address(const std::string &address, int prefix, const std::string &, bool, bool) override {
        addresses.push_back(address + "/" + std::to_string(prefix));
        return true;
    }

    // Every family with an address goes all through the tunnel (core/shikoo_ovpn.go): pushed routes change nothing.
    bool tun_builder_add_route(const std::string &, int, int, bool) override { return true; }

    bool tun_builder_exclude_route(const std::string &, int, int, bool) override { return true; }

    bool tun_builder_reroute_gw(bool, bool, unsigned int) override { return true; }

    bool tun_builder_set_dns_options(const openvpn::DnsOptions &options) override {
        for (const auto &server : options.servers)
            for (const auto &address : server.second.addresses) dns.push_back(address.address);
        return true;
    }

    bool tun_builder_set_mtu(int value) override {
        mtu = value;
        return true;
    }

    bool tun_builder_add_proxy_bypass(const std::string &) override { return true; }

    bool tun_builder_set_proxy_auto_config_url(const std::string &) override { return true; }

    bool tun_builder_set_proxy_http(const std::string &, int) override { return true; }

    bool tun_builder_set_proxy_https(const std::string &, int) override { return true; }

    bool tun_builder_add_wins_server(const std::string &) override { return true; }

    bool establish() {
        std::string spec = "{\"addresses\":" + list(addresses) + ",\"dns\":" + list(dns) +
                           ",\"mtu\":" + std::to_string(mtu) + "}";
        return go->establish(spec.c_str()) == 0;
    }

    // Go binds the socket to the physical interface, as physicalBind does for WireGuard.
    bool socket_protect(openvpn_io::detail::socket_type socket, std::string, bool ipv6) override {
        return go->protect(static_cast<uintptr_t>(socket), ipv6) != 0;
    }

    TunClientFactory *new_tun_factory(const ExternalTun::Config &conf, const OptionList &) override;

    bool pause_on_connection_timeout() override { return false; }

    void event(const ClientAPI::Event &ev) override { go->event(ev.name.c_str(), ev.info.c_str(), ev.error); }

    void acc_event(const AppCustomControlMessageEvent &) override {}

    // The engine logs the server's certificates, host and address: debug builds only, as on Android.
    void log(const LogInfo &line) override {
#ifndef NDEBUG
        go->event("LOG", line.text.c_str(), 0);
#endif
    }

    void external_pki_cert_request(ExternalPKICertRequest &request) override {
        request.error = true;
        request.errorText = "no external PKI";
    }

    void external_pki_sign_request(ExternalPKISignRequest &request) override {
        request.error = true;
        request.errorText = "no external PKI";
    }
};

class GoTun : public TunClient {
  public:
    GoTun(openvpn_io::io_context &io, TunClientParent &parent, const ExternalTun::Config &config, Client &client)
        : io(io), parent(parent), config(config), client(client), state(new TunProp::State()) {}

    ~GoTun() override { stop(); }

    void tun_start(const OptionList &opt, TransportClient &transcli, CryptoDCSettings &) override {
        client.tun_builder_new();
        parent.tun_pre_tun_config();
        TunProp::configure_builder(&client, state.get(), config.stats.get(), transcli.server_endpoint_addr(),
                                   config.tun_prop, opt, nullptr, false);
        if (!client.establish()) {
            parent.tun_error(openvpn::Error::TUN_IFACE_CREATE, "the core did not build the tunnel");
            return;
        }
        {
            std::lock_guard<std::mutex> lock(runningMu);
            active = this;
        }
        parent.tun_connected();
    }

    void stop() override {
        std::lock_guard<std::mutex> lock(runningMu);
        if (active == this) active = nullptr;
    }

    void set_disconnect() override {}

    bool tun_send(BufferAllocated &buf) override { return client.go->write(buf.c_data(), buf.size()) == 0; }

    std::string tun_name() const override { return "ShikooNet"; }

    std::string vpn_ip4() const override {
        return state->vpn_ip4_addr.defined() ? state->vpn_ip4_addr.to_string() : "";
    }

    std::string vpn_ip6() const override {
        return state->vpn_ip6_addr.defined() ? state->vpn_ip6_addr.to_string() : "";
    }

    int vpn_mtu() const override { return state->mtu; }

    // On a Go goroutine: the refcount is not thread-safe, so no Ptr; the session's thread checks active instead.
    // Drops as a NIC would: past what a tun read takes (writing it throws, ending the session) or a full queue.
    void post(const std::uint8_t *packet, size_t size) {
        if (size > (*config.frame)[Frame::READ_TUN].payload() || backlog >= 1024) return;
        ++backlog;
        openvpn_io::post(io, [tun = this, bytes = std::vector<std::uint8_t>(packet, packet + size)] {
            --backlog;
            {
                std::lock_guard<std::mutex> lock(runningMu);
                if (active != tun) return;
            }
            BufferPtr buf = tun->config.frame->prepare(Frame::READ_TUN);
            buf->write(bytes.data(), bytes.size());
            tun->parent.tun_recv(*buf);
        });
    }

  private:
    openvpn_io::io_context &io;
    TunClientParent &parent;
    ExternalTun::Config config;
    Client &client;
    TunProp::State::Ptr state;
};

class GoTunFactory : public TunClientFactory {
  public:
    GoTunFactory(const ExternalTun::Config &config, Client &client) : config(config), client(client) {}

    TunClient::Ptr new_tun_client_obj(openvpn_io::io_context &io, TunClientParent &parent, TransportClient *) override {
        return new GoTun(io, parent, config, client);
    }

    bool supports_epoch_data() override { return true; }

  private:
    ExternalTun::Config config;
    Client &client;
};

TunClientFactory *Client::new_tun_factory(const ExternalTun::Config &conf, const OptionList &) {
    return new GoTunFactory(conf, *this);
}

const std::string refused = "refused: ";

void answer(const std::string &text, char *out, uintptr_t cap) {
    if (cap == 0) return;
    size_t n = std::min<size_t>(text.size(), cap - 1);
    std::memcpy(out, text.data(), n);
    out[n] = 0;
}
} // namespace

// Blocks until the session ends: out is "" when stopped, else why. noexcept, as nothing may unwind into Go.
extern "C" __declspec(dllexport) void shikoo_ovpn3_run(const char *profile, const char *username,
                                                       const char *password, const ShikooOvpnCallbacks *go, char *out,
                                                       uintptr_t cap) noexcept {
    // Packets still queued when the last session ended went, uncounted, with its client's io_context.
    backlog = 0;
    try {
        Client client;
        client.go = go;
        Config config;
        config.content = profile;
        // The tunnel stays through the engine's own reconnects, so nothing leaks around it meanwhile.
        config.tunPersist = true;
        config.googleDnsFallback = true;
        config.compressionMode = "asym";
        config.enableNonPreferredDCAlgorithms = true;

        std::string error;
        EvalConfig evaluated = client.eval_config(config);
        // A profile with no client certificate (only a username and password) reads as external PKI unless told so.
        if (!evaluated.error && evaluated.externalPki) {
            config.disableClientCert = true;
            evaluated = client.eval_config(config);
        }
        if (evaluated.error) error = refused + evaluated.message;
        if (error.empty() && !evaluated.autologin) {
            ProvideCreds creds;
            creds.username = username;
            creds.password = password;
            Status status = client.provide_creds(creds);
            if (status.error) error = refused + status.message;
        }
        if (error.empty()) {
            {
                std::lock_guard<std::mutex> lock(runningMu);
                running = &client;
            }
            Status status = client.connect();
            {
                std::lock_guard<std::mutex> lock(runningMu);
                if (running == &client) running = nullptr;
            }
            if (status.error) error = status.status + ": " + status.message;
        }
        answer(error, out, cap);
    } catch (const std::exception &e) {
        answer(std::string("exception: ") + e.what(), out, cap);
    } catch (...) {
        answer("exception", out, cap);
    }
}

extern "C" __declspec(dllexport) void shikoo_ovpn3_halt() noexcept {
    std::lock_guard<std::mutex> lock(runningMu);
    if (running) running->stop();
}

extern "C" __declspec(dllexport) void shikoo_ovpn3_packet(const std::uint8_t *packet, uintptr_t size) noexcept {
    std::lock_guard<std::mutex> lock(runningMu);
    if (active) active->post(packet, size);
}
