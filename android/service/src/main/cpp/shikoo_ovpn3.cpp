// OpenVpn.kt's native side: one OpenVPN 3 session per run(), whose VPN the Kotlin callbacks build.
#include <jni.h>
#include <android/log.h>
#include <mutex>
#include <string>
#include <vector>

#include "ovpncli.hpp"

using namespace openvpn::ClientAPI;

namespace {
JavaVM *vm;

JNIEnv *env() {
    JNIEnv *e = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&e), JNI_VERSION_1_6) != JNI_OK) vm->AttachCurrentThread(&e, nullptr);
    return e;
}

std::string str(JNIEnv *e, jstring s) {
    const char *c = e->GetStringUTFChars(s, nullptr);
    std::string out(c);
    e->ReleaseStringUTFChars(s, c);
    return out;
}

std::string list(const std::vector<std::string> &items) {
    std::string out = "[";
    for (const auto &item : items) out += (out.size() > 1 ? ",\"" : "\"") + item + "\"";
    return out + "]";
}

struct Client : OpenVPNClient {
    jobject engine = nullptr;
    jmethodID protectId = nullptr, establishId = nullptr, eventId = nullptr;
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

    int tun_builder_establish() override {
        JNIEnv *e = env();
        std::string spec = "{\"addresses\":" + list(addresses) + ",\"dns\":" + list(dns) +
                           ",\"mtu\":" + std::to_string(mtu) + "}";
        jstring s = e->NewStringUTF(spec.c_str());
        jint fd = e->CallIntMethod(engine, establishId, s);
        e->DeleteLocalRef(s);
        return fd;
    }

    bool socket_protect(openvpn_io::detail::socket_type fd, std::string, bool) override {
        return env()->CallBooleanMethod(engine, protectId, static_cast<jint>(fd));
    }

    bool pause_on_connection_timeout() override { return false; }

    void event(const Event &ev) override {
        JNIEnv *e = env();
        jstring name = e->NewStringUTF(ev.name.c_str());
        jstring info = e->NewStringUTF(ev.info.c_str());
        e->CallVoidMethod(engine, eventId, name, info, static_cast<jboolean>(ev.error));
        e->DeleteLocalRef(name);
        e->DeleteLocalRef(info);
    }

    void acc_event(const AppCustomControlMessageEvent &) override {}

    // The engine logs the server's certificates, host and address: debug builds only.
    void log(const LogInfo &line) override {
#ifndef NDEBUG
        __android_log_print(ANDROID_LOG_DEBUG, "ovpn3", "%s", line.text.c_str());
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

std::mutex runningMu;
Client *running = nullptr;

// The start's reason when the engine never started on this profile.
const std::string refused = "refused: ";
} // namespace

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM *v, void *) {
    vm = v;
    return JNI_VERSION_1_6;
}

// Blocks until the session ends: "" when stopped, else why.
extern "C" JNIEXPORT jstring JNICALL
Java_com_follow_clash_service_OpenVpn_run(JNIEnv *e, jobject self, jstring profile, jstring username, jstring password) {
    Client client;
    jclass type = e->GetObjectClass(self);
    client.engine = e->NewGlobalRef(self);
    client.protectId = e->GetMethodID(type, "protect", "(I)Z");
    client.establishId = e->GetMethodID(type, "establish", "(Ljava/lang/String;)I");
    client.eventId = e->GetMethodID(type, "event", "(Ljava/lang/String;Ljava/lang/String;Z)V");

    Config config;
    config.content = str(e, profile);
    // The VPN stays through the engine's own reconnects, so nothing leaks around it meanwhile.
    config.tunPersist = true;
    config.googleDnsFallback = true;
    config.compressionMode = "asym";
    // AES-CBC servers, which mihomo also carries.
    config.enableNonPreferredDCAlgorithms = true;

    std::string error;
    EvalConfig evaluated = client.eval_config(config);
    // A profile with no client certificate (username and password only) reads as external PKI unless told otherwise.
    if (!evaluated.error && evaluated.externalPki) {
        config.disableClientCert = true;
        evaluated = client.eval_config(config);
    }
    if (evaluated.error) error = refused + evaluated.message;
    if (error.empty() && !evaluated.autologin) {
        ProvideCreds creds;
        creds.username = str(e, username);
        creds.password = str(e, password);
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
            running = nullptr;
        }
        if (status.error) error = status.status + ": " + status.message;
    }
    e->DeleteGlobalRef(client.engine);
    return e->NewStringUTF(error.c_str());
}

extern "C" JNIEXPORT void JNICALL Java_com_follow_clash_service_OpenVpn_halt(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(runningMu);
    if (running) running->stop();
}
