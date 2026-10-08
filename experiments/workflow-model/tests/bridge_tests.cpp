#include "RescueDemoBridge.h"
#include <cstdlib>
#include <iostream>
#include <string>

void require(bool ok, const char* message) { if (!ok) { std::cerr << message << '\n'; std::exit(1); } }
std::string snapshot(rc_session* s) {
    char* p = rc_snapshot(s); require(p != nullptr, "snapshot allocation");
    std::string value(p); rc_free(p); return value;
}
int main() {
    require(rc_snapshot(nullptr) == nullptr, "null snapshot");
    require(rc_perform(nullptr, RC_SOS, "", "") == -1, "null session");
    rc_destroy(nullptr); rc_free(nullptr);
    for (int i=0; i<100; ++i) {
        auto* s = rc_create(); require(s != nullptr, "create");
        require(rc_perform(s, -1, "", "") == 2, "invalid action");
        require(rc_perform(s, RC_SOS, nullptr, "") == 2, "null value");
        require(rc_set_connected(s, 2) == -1, "invalid connection value");
        std::string large(2049, 'x');
        require(rc_perform(s, RC_SOS, large.c_str(), "") == 2, "value bound");
        require(rc_perform(s, RC_SOS, "Training floor", "") == 0, "send after rejection");
        require(snapshot(s).find("\"originalDelivery\":1") != std::string::npos, "device receipt");
        require(rc_set_connected(s, 0) == 0, "disconnect");
        for (int j=0; j<64; ++j) require(rc_perform(s, RC_FOLLOWUP, "Sample update", "") == 0, "queue capacity");
        require(rc_perform(s, RC_FOLLOWUP, "Overflow", "") == 6, "queue bound");
        require(snapshot(s).find("\"pendingTransfers\":64") != std::string::npos, "retained queued updates");
        require(rc_set_connected(s, 1) == 0, "reconnect");
        // The responder's bounded store eventually fills. Unreceived updates must stay queued.
        require(snapshot(s).find("\"pendingTransfers\":0") == std::string::npos, "no false delivery when store full");
        rc_destroy(s);
    }
}
