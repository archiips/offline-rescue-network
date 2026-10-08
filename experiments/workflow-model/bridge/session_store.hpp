#pragma once
#include "workflow.hpp"
#include <deque>
#include <memory>
#include <string>
#include <vector>

struct SavedSession {
    std::vector<rescue::Event> publicEvents, responderEvents;
    std::deque<rescue::Event> pending;
    bool connected = true;
};
// A bounded synthetic-session store, not a production per-device inbox/outbox.
class SessionStore {
public:
    explicit SessionStore(const std::string& absolutePath);
    ~SessionStore();
    SessionStore(const SessionStore&) = delete;
    SessionStore& operator=(const SessionStore&) = delete;
    SavedSession load();
    void save(const SavedSession&);
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
