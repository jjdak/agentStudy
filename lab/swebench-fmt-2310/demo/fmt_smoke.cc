#include <fmt/format.h>

#include <iostream>
#include <limits>
#include <string>

namespace {

int failures = 0;

void check(const char* name, const std::string& actual,
           const std::string& expected) {
  if (actual == expected) {
    std::cout << "PASS " << name << '\n';
    return;
  }
  std::cerr << "FAIL " << name << ": expected [" << expected << "], got ["
            << actual << "]\n";
  ++failures;
}

}  // namespace

int main() {
  const double nan = std::numeric_limits<double>::quiet_NaN();
  const double inf = std::numeric_limits<double>::infinity();

  // The finite case protects the intended sign-aware zero-padding behavior.
  check("finite-zero-padding", fmt::format("{:+06}", 12), "+00012");

  // The bug applies zero fill to non-finite values. Explicit alignment must
  // still win when the zero option is present.
  check("nan-default", fmt::format("{:+06}", nan), "  +nan");
  check("nan-left", fmt::format("{:<+06}", nan), "+nan  ");
  check("nan-center", fmt::format("{:^+06}", nan), " +nan ");
  check("nan-right", fmt::format("{:>+06}", nan), "  +nan");
  check("inf-default", fmt::format("{:+06}", inf), "  +inf");

  if (failures != 0) {
    std::cerr << failures << " smoke check(s) failed\n";
    return 1;
  }
  std::cout << "fmt demo smoke test: PASS\n";
  return 0;
}
