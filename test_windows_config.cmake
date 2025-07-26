# Test script to verify Windows configurations
# Run with: cmake -P test_windows_config.cmake

# Simulate Windows x64 with MSVC
message(STATUS "Testing Windows x64 MSVC configuration:")
set(CMAKE_SYSTEM_NAME "Windows")
set(CMAKE_SYSTEM_PROCESSOR "AMD64")
set(MSVC 1)
set(SIZEOF_VOID_P 8)

# Expected values:
# FFI_TARGET should be X86_WIN64
# Should use ffiw64.c and win64_intel.S

# Simulate Windows x86 with MinGW
message(STATUS "\nTesting Windows x86 MinGW configuration:")
set(CMAKE_SYSTEM_NAME "Windows")
set(CMAKE_SYSTEM_PROCESSOR "x86")
set(MINGW 1)
set(MSVC 0)
set(SIZEOF_VOID_P 4)

# Expected values:
# FFI_TARGET should be X86_WIN32
# Should use ffi.c and sysv.S

# Simulate Windows ARM64 with MSVC
message(STATUS "\nTesting Windows ARM64 MSVC configuration:")
set(CMAKE_SYSTEM_NAME "Windows")
set(CMAKE_SYSTEM_PROCESSOR "arm64")
set(MSVC 1)
set(SIZEOF_VOID_P 8)

# Expected values:
# FFI_TARGET should be ARM_WIN64
# Should use ffi.c and win64_armasm.S

message(STATUS "\nAll configurations documented for manual verification")