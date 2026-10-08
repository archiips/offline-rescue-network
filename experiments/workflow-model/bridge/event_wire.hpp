#pragma once
#include "workflow.hpp"
#include <span>
#include <vector>
namespace rescue_wire {
std::vector<unsigned char> encode(const rescue::Event&);
rescue::Event decode(std::span<const unsigned char>);
}
