#include <fmt/format.h>
#include <fmt/ranges.h>

#include <iostream>
#include <string>
#include <tuple>
#include <vector>

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

template <typename Function>
void check_no_throw(const char* name, Function function,
                    const std::string& expected) {
  try {
    check(name, function(), expected);
  } catch (const fmt::format_error& error) {
    std::cerr << "FAIL " << name << ": unexpected format_error: "
              << error.what() << '\n';
    ++failures;
  }
}

}  // namespace

int main() {
  const std::vector<int> range_values{1, 2, 3};
  check("range-regression",
        fmt::format("{:02}", fmt::join(range_values, ", ")),
        "01, 02, 03");

  const auto integer_tuple = std::make_tuple(1, 2, 3);
  check_no_throw(
      "tuple-zero-padding",
      [&] { return fmt::format("{:02}", fmt::join(integer_tuple, ", ")); },
      "01, 02, 03");
  check_no_throw(
      "tuple-default",
      [&] { return fmt::format("{}", fmt::join(integer_tuple, " / ")); },
      "1 / 2 / 3");

  const auto mixed_tuple = std::make_tuple(7, "x", 2.5);
  check_no_throw(
      "heterogeneous-width",
      [&] { return fmt::format("{:>4}", fmt::join(mixed_tuple, "|")); },
      "   7|   x| 2.5");

  const std::tuple<> empty_tuple;
  check_no_throw(
      "empty-tuple",
      [&] { return fmt::format("{}", fmt::join(empty_tuple, ",")); }, "");

  if (failures != 0) {
    std::cerr << failures << " visible check(s) failed\n";
    return 1;
  }
  std::cout << "fmt tuple-join demo test: PASS\n";
  return 0;
}
