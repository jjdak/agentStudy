cmake_minimum_required(VERSION 3.20)
project(coding_agent_repair_demo C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

add_library(safe_ops src/safe_ops.c)
target_include_directories(safe_ops PUBLIC include)
target_compile_options(safe_ops PRIVATE -Wall -Wextra -Wpedantic -Werror)

enable_testing()
add_executable(public_tests tests/public_tests.c)
target_link_libraries(public_tests PRIVATE safe_ops)
target_compile_options(public_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_test(NAME public_tests COMMAND public_tests)
