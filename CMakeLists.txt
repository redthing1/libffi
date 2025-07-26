cmake_minimum_required(VERSION 3.15)

project(libffi
  VERSION 3.5.1
  DESCRIPTION "Foreign Function Interface library"
  LANGUAGES C ASM)

# Enable modern C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Options
option(FFI_DEBUG "Enable FFI debugging" OFF)
option(FFI_BUILD_TESTS "Build libffi tests" OFF)
option(FFI_BUILD_DOCS "Build libffi documentation" OFF)
option(FFI_EXEC_STATIC_TRAMP "Enable static trampolines" OFF)
option(FFI_MMAP_EXEC_EMUTRAMP_PAX "Enable PaX emulated trampolines" OFF)
option(FFI_NO_RAW_API "Disable raw FFI API" OFF)
option(FFI_NO_STRUCTS "Disable FFI struct support" OFF)
option(FFI_PURIFY_BUILD "Build with purify support" OFF)
option(BUILD_SHARED_LIBS "Build shared libraries" ON)

# Include required modules
include(GNUInstallDirs)
include(CheckIncludeFile)
include(CheckFunctionExists)
include(CheckTypeSize)
include(TestBigEndian)
include(CheckCSourceCompiles)
include(CheckCCompilerFlag)

# Enable position independent code by default
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Set up assembly preprocessor flags
set(CMAKE_ASM_FLAGS "${CMAKE_C_FLAGS} -DLIBFFI_ASM")
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS} -x assembler-with-cpp")
endif()

# Detect platform and architecture
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  set(FFI_SYSTEM_DARWIN 1)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(FFI_SYSTEM_LINUX 1)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR WIN32)
  set(FFI_SYSTEM_WINDOWS 1)
  # Detect Windows environment
  if(MINGW)
    set(FFI_WINDOWS_MINGW 1)
  elseif(CYGWIN)
    set(FFI_WINDOWS_CYGWIN 1)
  elseif(MSYS)
    set(FFI_WINDOWS_MSYS 1)
  endif()
endif()

# Detect architecture
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$")
  set(FFI_ARCH_X86_64 1)
  # Check for X32 ABI
  check_c_source_compiles("
    int main() { 
      #ifdef __x86_64__
        return 0;
      #else
        #error not x86_64
      #endif
    }" IS_X86_64)
  if(IS_X86_64 AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(FFI_ARCH_X32 1)
  endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(i[3-6]86|x86)$")
  set(FFI_ARCH_X86 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(FFI_ARCH_AARCH64 1)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^arm")
  set(FFI_ARCH_ARM 1)
endif()

# Compiler feature detection
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  # Check for hidden visibility attribute
  check_c_source_compiles("
    __attribute__((visibility(\"hidden\"))) void foo(void) {}
    int main() { return 0; }
  " HAVE_HIDDEN_VISIBILITY_ATTRIBUTE)
  
  # Check for CFI pseudo-op support
  check_c_source_compiles("
    int main() {
      __asm__ volatile(\".cfi_startproc\\n.cfi_endproc\\n\");
      return 0;
    }
  " HAVE_AS_CFI_PSEUDO_OP)
endif()

# Configure compiler flags
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra -fexceptions)
  if(FFI_SYSTEM_DARWIN)
    add_compile_options(-fno-common)
  endif()
  
  # Check for and enable maximum optimization
  if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    check_c_compiler_flag(-O3 HAVE_O3_FLAG)
    if(HAVE_O3_FLAG)
      add_compile_options(-O3)
    endif()
  endif()
  
  # Check for -fno-lto support (sometimes needed for assembly)
  check_c_compiler_flag(-fno-lto HAVE_NO_LTO_FLAG)
  
elseif(MSVC)
  add_compile_options(/W3)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
  set(MSVC 1)
  if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    add_compile_options(/O2)
  endif()
  # Ensure proper runtime library selection
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

# Special handling for Windows assembly
if(MSVC AND CMAKE_GENERATOR MATCHES "Visual Studio")
  enable_language(ASM_MASM)
  set(CMAKE_ASM_MASM_FLAGS "${CMAKE_ASM_MASM_FLAGS} /safeseh")
endif()

# System checks
check_include_file(alloca.h HAVE_ALLOCA_H)
check_include_file(sys/memfd.h HAVE_SYS_MEMFD_H)
check_include_file(sys/mman.h HAVE_SYS_MMAN_H)
check_include_file(string.h HAVE_STRING_H)
check_include_file(stdlib.h HAVE_STDLIB_H)
check_include_file(unistd.h HAVE_UNISTD_H)

check_function_exists(memfd_create HAVE_MEMFD_CREATE)
check_function_exists(memcpy HAVE_MEMCPY)
check_function_exists(mmap HAVE_MMAP)
check_function_exists(mkostemp HAVE_MKOSTEMP)
check_function_exists(mkstemp HAVE_MKSTEMP)

# Check for mmap variants
include(CheckCSourceCompiles)
if(HAVE_MMAP)
  check_c_source_compiles("
    #include <sys/mman.h>
    #include <unistd.h>
    int main() {
      void *p = mmap(0, getpagesize(), PROT_READ|PROT_WRITE, MAP_ANON|MAP_PRIVATE, -1, 0);
      return p == MAP_FAILED;
    }" HAVE_MMAP_ANON)
    
  check_c_source_compiles("
    #include <sys/mman.h>
    #include <fcntl.h>
    #include <unistd.h>
    int main() {
      int fd = open(\"/dev/zero\", O_RDONLY);
      void *p = mmap(0, getpagesize(), PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
      return p == MAP_FAILED;
    }" HAVE_MMAP_DEV_ZERO)
endif()

check_type_size("double" SIZEOF_DOUBLE)
check_type_size("long double" SIZEOF_LONG_DOUBLE)
check_type_size("size_t" SIZEOF_SIZE_T)
check_type_size("void*" SIZEOF_VOID_P)

test_big_endian(WORDS_BIGENDIAN)

# Check for long double support
set(HAVE_LONG_DOUBLE 0)
set(HAVE_LONG_DOUBLE_VARIANT 0)
if(SIZEOF_LONG_DOUBLE GREATER 0 AND NOT SIZEOF_DOUBLE EQUAL SIZEOF_LONG_DOUBLE)
  set(HAVE_LONG_DOUBLE 1)
endif()

# Set up include directories
set(FFI_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")
set(FFI_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src")

# Core source files
set(FFI_CORE_SOURCES
  ${FFI_SOURCE_DIR}/prep_cif.c
  ${FFI_SOURCE_DIR}/types.c
  ${FFI_SOURCE_DIR}/raw_api.c
  ${FFI_SOURCE_DIR}/java_raw_api.c
  ${FFI_SOURCE_DIR}/closures.c
  ${FFI_SOURCE_DIR}/tramp.c
)

if(FFI_DEBUG)
  list(APPEND FFI_CORE_SOURCES ${FFI_SOURCE_DIR}/debug.c)
endif()

# Platform and architecture specific configuration
set(FFI_PLATFORM_SOURCES)
set(FFI_TARGET)
set(FFI_TARGETDIR)
set(FFI_MMAP_EXEC_WRIT 0)
set(FFI_EXEC_TRAMPOLINE_TABLE 0)

# Platform-specific closure handling
if(FFI_SYSTEM_DARWIN OR CMAKE_SYSTEM_NAME MATCHES "BSD" OR 
   CMAKE_SYSTEM_NAME STREQUAL "SunOS" OR ANDROID)
  set(FFI_MMAP_EXEC_WRIT 1)
endif()

# x86/x86_64 configurations
if(FFI_ARCH_X86_64 OR FFI_ARCH_X32)
  set(FFI_TARGETDIR "x86")
  
  if(FFI_SYSTEM_WINDOWS)
    if(FFI_ARCH_X32 OR SIZEOF_VOID_P EQUAL 4)
      set(FFI_TARGET "X86_WIN32")
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/ffi.c)
      if(MSVC)
        list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv_intel.S)
      else()
        list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv.S)
      endif()
    else()
      set(FFI_TARGET "X86_WIN64")
      list(APPEND FFI_PLATFORM_SOURCES 
        ${FFI_SOURCE_DIR}/x86/ffiw64.c)
      if(MSVC)
        list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/win64_intel.S)
      else()
        list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/win64.S)
      endif()
    endif()
  elseif(FFI_SYSTEM_DARWIN)
    if(SIZEOF_VOID_P EQUAL 4)
      set(FFI_TARGET "X86_DARWIN")
      list(APPEND FFI_PLATFORM_SOURCES 
        ${FFI_SOURCE_DIR}/x86/ffi.c
        ${FFI_SOURCE_DIR}/x86/sysv.S)
    else()
      set(FFI_TARGET "X86_64")
      list(APPEND FFI_PLATFORM_SOURCES 
        ${FFI_SOURCE_DIR}/x86/ffi64.c
        ${FFI_SOURCE_DIR}/x86/unix64.S
        ${FFI_SOURCE_DIR}/x86/ffi.c)
    endif()
  else() # Linux/Unix
    if(FFI_ARCH_X32)
      set(FFI_TARGET "X86_64")
      set(TARGET_X32 1)
    elseif(SIZEOF_VOID_P EQUAL 4)
      set(FFI_TARGET "X86")
    else()
      set(FFI_TARGET "X86_64")
    endif()
    list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/ffi.c)
    if(FFI_TARGET STREQUAL "X86_64")
      list(APPEND FFI_PLATFORM_SOURCES 
        ${FFI_SOURCE_DIR}/x86/ffi64.c
        ${FFI_SOURCE_DIR}/x86/unix64.S)
    else()
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv.S)
    endif()
  endif()
  
elseif(FFI_ARCH_X86)
  set(FFI_TARGETDIR "x86")
  list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/ffi.c)
  
  if(FFI_SYSTEM_WINDOWS)
    set(FFI_TARGET "X86_WIN32")
    if(MSVC)
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv_intel.S)
    else()
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv.S)
    endif()
  elseif(FFI_SYSTEM_DARWIN)
    set(FFI_TARGET "X86_DARWIN")
    list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv.S)
  else()
    set(FFI_TARGET "X86")
    list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/x86/sysv.S)
  endif()

# ARM64/AArch64 configurations
elseif(FFI_ARCH_AARCH64)
  set(FFI_TARGETDIR "aarch64")
  list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/aarch64/ffi.c)
  
  if(FFI_SYSTEM_WINDOWS)
    set(FFI_TARGET "ARM_WIN64")
    if(MSVC)
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/aarch64/win64_armasm.S)
    else()
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/aarch64/sysv.S)
    endif()
  else()
    set(FFI_TARGET "AARCH64")
    list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/aarch64/sysv.S)
    
    # Special handling for Apple platforms
    if(FFI_SYSTEM_DARWIN)
      set(FFI_EXEC_TRAMPOLINE_TABLE 1)
      
      # Check for pointer authentication
      check_c_source_compiles("
        #ifdef __clang__
        # if __has_feature(ptrauth_calls)
        #  define HAVE_ARM64E_PTRAUTH 1
        # endif
        #endif
        #ifndef HAVE_ARM64E_PTRAUTH
        # error Pointer authentication not supported
        #endif
        int main() { return 0; }
      " HAVE_ARM64E_PTRAUTH)
    endif()
  endif()

# ARM configurations  
elseif(FFI_ARCH_ARM)
  set(FFI_TARGETDIR "arm")
  list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/arm/ffi.c)
  
  if(FFI_SYSTEM_WINDOWS)
    set(FFI_TARGET "ARM_WIN32")
    if(MSVC)
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/arm/sysv_msvc_arm32.S)
    else()
      list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/arm/sysv.S)
    endif()
  else()
    set(FFI_TARGET "ARM")
    list(APPEND FFI_PLATFORM_SOURCES ${FFI_SOURCE_DIR}/arm/sysv.S)
    
    # Special handling for Apple platforms
    if(FFI_SYSTEM_DARWIN)
      set(FFI_EXEC_TRAMPOLINE_TABLE 1)
    endif()
  endif()
  
else()
  message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

# Enable static trampolines on supported platforms
if(FFI_EXEC_STATIC_TRAMP)
  if(FFI_SYSTEM_LINUX)
    if(FFI_ARCH_X86_64 OR FFI_ARCH_X86 OR FFI_ARCH_AARCH64 OR FFI_ARCH_ARM)
      set(FFI_EXEC_STATIC_TRAMP_ENABLED 1)
    else()
      set(FFI_EXEC_STATIC_TRAMP_ENABLED 0)
    endif()
  elseif((FFI_WINDOWS_CYGWIN OR FFI_WINDOWS_MSYS) AND CMAKE_C_COMPILER_ID MATCHES "GNU")
    if(FFI_ARCH_X86_64 OR FFI_ARCH_X86)
      set(FFI_EXEC_STATIC_TRAMP_ENABLED 1)
    else()
      set(FFI_EXEC_STATIC_TRAMP_ENABLED 0)
    endif()
  else()
    set(FFI_EXEC_STATIC_TRAMP_ENABLED 0)
  endif()
else()
  set(FFI_EXEC_STATIC_TRAMP_ENABLED 0)
endif()

# Platform-specific assembler checks
if(FFI_TARGETDIR STREQUAL "x86")
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    # Check for PC-relative relocs
    check_c_source_compiles("
      int main() {
        __asm__ (\".text; foo: nop; .data; .long foo-.; .text\");
        return 0;
      }
    " HAVE_AS_X86_PCREL)
  endif()
endif()

# Configure fficonfig.h
configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/fficonfig.h.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/fficonfig.h
  @ONLY
)

# Configure ffi.h
set(VERSION ${PROJECT_VERSION})
set(TARGET ${FFI_TARGET})
set(HAVE_LONG_DOUBLE ${HAVE_LONG_DOUBLE})
set(HAVE_LONG_DOUBLE_VARIANT ${HAVE_LONG_DOUBLE_VARIANT})
set(FFI_VERSION_STRING ${PROJECT_VERSION})
set(FFI_VERSION_NUMBER 30501)

configure_file(
  ${FFI_INCLUDE_DIR}/ffi.h.in
  ${CMAKE_CURRENT_BINARY_DIR}/ffi.h
  @ONLY
)

# Function to configure FFI targets
function(configure_ffi_target target)
  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME ffi
    PUBLIC_HEADER "${CMAKE_CURRENT_BINARY_DIR}/ffi.h;${FFI_SOURCE_DIR}/${FFI_TARGETDIR}/ffitarget.h"
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    POSITION_INDEPENDENT_CODE ON
  )
  
  # Set version for shared libraries
  get_target_property(target_type ${target} TYPE)
  if(target_type STREQUAL "SHARED_LIBRARY")
    set_target_properties(${target} PROPERTIES
      VERSION ${PROJECT_VERSION}
      SOVERSION ${PROJECT_VERSION_MAJOR}
    )
    target_compile_definitions(${target} PRIVATE FFI_BUILDING_DLL)
  endif()
  
  # Include directories
  target_include_directories(${target}
    PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>
      $<BUILD_INTERFACE:${FFI_INCLUDE_DIR}>
      $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE
      ${FFI_SOURCE_DIR}
      ${FFI_SOURCE_DIR}/${FFI_TARGETDIR}
  )
  
  # Platform specific definitions
  target_compile_definitions(${target}
    PRIVATE
      ${FFI_TARGET}
      HAVE_CONFIG_H
  )
  
  # Add system defines
  if(HAVE_HIDDEN_VISIBILITY_ATTRIBUTE)
    target_compile_definitions(${target} PRIVATE HAVE_HIDDEN_VISIBILITY_ATTRIBUTE)
  endif()
  
  if(HAVE_AS_CFI_PSEUDO_OP)
    target_compile_definitions(${target} PRIVATE HAVE_AS_CFI_PSEUDO_OP)
  endif()
  
  if(HAVE_AS_X86_PCREL)
    target_compile_definitions(${target} PRIVATE HAVE_AS_X86_PCREL)
  endif()
  
  if(FFI_MMAP_EXEC_WRIT)
    target_compile_definitions(${target} PRIVATE FFI_MMAP_EXEC_WRIT)
  endif()
  
  if(FFI_EXEC_TRAMPOLINE_TABLE)
    target_compile_definitions(${target} PRIVATE FFI_EXEC_TRAMPOLINE_TABLE=${FFI_EXEC_TRAMPOLINE_TABLE})
  endif()
  
  if(FFI_EXEC_STATIC_TRAMP_ENABLED)
    target_compile_definitions(${target} PRIVATE FFI_EXEC_STATIC_TRAMP)
  endif()
  
  if(FFI_MMAP_EXEC_EMUTRAMP_PAX)
    target_compile_definitions(${target} PRIVATE FFI_MMAP_EXEC_EMUTRAMP_PAX)
  endif()
  
  if(HAVE_ARM64E_PTRAUTH)
    target_compile_definitions(${target} PRIVATE HAVE_ARM64E_PTRAUTH)
  endif()
  
  if(TARGET_X32)
    target_compile_definitions(${target} PRIVATE TARGET_X32)
  endif()
  
  if(FFI_NO_RAW_API)
    target_compile_definitions(${target} PRIVATE FFI_NO_RAW_API)
  endif()
  
  if(FFI_NO_STRUCTS)
    target_compile_definitions(${target} PRIVATE FFI_NO_STRUCTS)
  endif()
  
  if(FFI_PURIFY_BUILD)
    target_compile_definitions(${target} PRIVATE USING_PURIFY)
  endif()
  
  # Windows specific settings
  if(FFI_SYSTEM_WINDOWS)
    if(target_type STREQUAL "SHARED_LIBRARY")
      target_compile_definitions(${target} INTERFACE FFI_DLL)
    endif()
    # Add -no-undefined for shared libs
    if(target_type STREQUAL "SHARED_LIBRARY" AND NOT MSVC)
      target_link_options(${target} PRIVATE -no-undefined)
    endif()
    
    # Add Windows-specific target defines
    if(FFI_TARGET STREQUAL "X86_WIN32")
      target_compile_definitions(${target} PRIVATE X86_WIN32)
    elseif(FFI_TARGET STREQUAL "X86_WIN64")
      target_compile_definitions(${target} PRIVATE X86_WIN64)
    elseif(FFI_TARGET STREQUAL "ARM_WIN32")
      target_compile_definitions(${target} PRIVATE ARM_WIN32)
    elseif(FFI_TARGET STREQUAL "ARM_WIN64")
      target_compile_definitions(${target} PRIVATE ARM_WIN64)
    endif()
  endif()
  
  # Symbol versioning (for GNU/Linux systems)
  if(FFI_SYSTEM_LINUX AND CMAKE_C_COMPILER_ID STREQUAL "GNU" AND target_type STREQUAL "SHARED_LIBRARY")
    target_link_options(${target} PRIVATE 
      -Wl,--version-script=${CMAKE_CURRENT_BINARY_DIR}/libffi.map)
  endif()
endfunction()

# Determine what to build
if(FFI_BUILD_BOTH_LIBS)
  # Build both static and shared
  add_library(ffi_static STATIC ${FFI_CORE_SOURCES} ${FFI_PLATFORM_SOURCES})
  add_library(ffi_shared SHARED ${FFI_CORE_SOURCES} ${FFI_PLATFORM_SOURCES})
  
  configure_ffi_target(ffi_static)
  configure_ffi_target(ffi_shared)
  
  # Create aliases
  add_library(libffi::libffi_static ALIAS ffi_static)
  add_library(libffi::libffi_shared ALIAS ffi_shared)
  add_library(libffi::libffi ALIAS ffi_shared)  # Default to shared
  
  # For installation, we'll need to handle both
  set(FFI_INSTALL_TARGETS ffi_static ffi_shared)
else()
  # Build based on BUILD_SHARED_LIBS
  add_library(ffi ${FFI_CORE_SOURCES} ${FFI_PLATFORM_SOURCES})
  configure_ffi_target(ffi)
  add_library(libffi::libffi ALIAS ffi)
  set(FFI_INSTALL_TARGETS ffi)
endif()

# Symbol versioning (for GNU/Linux systems)
if(FFI_SYSTEM_LINUX AND CMAKE_C_COMPILER_ID STREQUAL "GNU")
  # Generate libffi.map
  configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/libffi.map.in
    ${CMAKE_CURRENT_BINARY_DIR}/libffi.map
    @ONLY
  )
endif()

# Installation
install(TARGETS ${FFI_INSTALL_TARGETS}
  EXPORT libffi-targets
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Also install common headers
install(FILES
  ${FFI_INCLUDE_DIR}/ffi_common.h
  ${FFI_INCLUDE_DIR}/ffi_cfi.h
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Export targets
install(EXPORT libffi-targets
  FILE libffi-targets.cmake
  NAMESPACE libffi::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/libffi
)

# Create config files
include(CMakePackageConfigHelpers)

configure_package_config_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/libffi-config.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/libffi-config.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/libffi
)

write_basic_package_version_file(
  ${CMAKE_CURRENT_BINARY_DIR}/libffi-config-version.cmake
  VERSION ${PROJECT_VERSION}
  COMPATIBILITY SameMajorVersion
)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/libffi-config.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/libffi-config-version.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/libffi
)

# pkg-config file
configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/libffi.pc.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/libffi.pc
  @ONLY
)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/libffi.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)

# Tests
if(FFI_BUILD_TESTS)
  enable_testing()
  add_subdirectory(testsuite)
endif()

# Documentation
if(FFI_BUILD_DOCS)
  add_subdirectory(doc)
endif()

# Summary
message(STATUS "")
message(STATUS "libffi configuration summary:")
message(STATUS "  Target: ${FFI_TARGET}")
message(STATUS "  Architecture directory: ${FFI_TARGETDIR}")
message(STATUS "  Compiler: ${CMAKE_C_COMPILER_ID}")
message(STATUS "  FFI_EXEC_TRAMPOLINE_TABLE: ${FFI_EXEC_TRAMPOLINE_TABLE}")
message(STATUS "  FFI_MMAP_EXEC_WRIT: ${FFI_MMAP_EXEC_WRIT}")
message(STATUS "  Static trampolines: ${FFI_EXEC_STATIC_TRAMP_ENABLED}")
message(STATUS "")