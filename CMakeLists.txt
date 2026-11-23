# MySQL MCP components (RFC 0001 in askdba/mysql-mcp-server).
#
# This project builds component_mcp_guard (MySQL 8.4, 9.7, 26.x) against a MySQL server source
# tree that has been configured (for its generated headers), without building the server:
#
#   cmake -B build -DMYSQL_SOURCE_DIR=/path/to/mysql-server -DMYSQL_BUILD_DIR=/path/to/bld
#
# component_mcp (MySQL 26.10+) links MySQL Router's HTTP libraries, so it is built inside the
# server tree instead (src/mcp/endpoint, scripts/build-components-docker.sh).
cmake_minimum_required(VERSION 3.16)
project(MySQLMcpComponents LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED MYSQL_SOURCE_DIR OR
   NOT EXISTS "${MYSQL_SOURCE_DIR}/include/mysql/components/component_implementation.h")
  message(FATAL_ERROR
    "MYSQL_SOURCE_DIR must point to a MySQL server source root (containing "
    "include/mysql/components/component_implementation.h). "
    "Example: cmake -DMYSQL_SOURCE_DIR=/path/to/mysql-server ..")
endif()
set(MYSQL_SOURCE_DIR "${MYSQL_SOURCE_DIR}" CACHE PATH "MySQL server source root")

set(MCP_INCLUDE_DIRS
  "${MYSQL_SOURCE_DIR}/include"
  "${MYSQL_SOURCE_DIR}"
  "${MYSQL_SOURCE_DIR}/libs"
)
if(EXISTS "${MYSQL_SOURCE_DIR}/libbinlogevents/include")
  list(APPEND MCP_INCLUDE_DIRS "${MYSQL_SOURCE_DIR}/libbinlogevents/include")
endif()
if(DEFINED MYSQL_BUILD_DIR AND EXISTS "${MYSQL_BUILD_DIR}/include")
  set(MYSQL_BUILD_DIR "${MYSQL_BUILD_DIR}" CACHE PATH "MySQL server build dir")
  list(APPEND MCP_INCLUDE_DIRS "${MYSQL_BUILD_DIR}/include")
else()
  message(FATAL_ERROR
    "MYSQL_BUILD_DIR must point to a configured MySQL build dir (its include/ holds "
    "generated headers such as mysql_version.h)")
endif()

# A component built like MySQL's own: hidden visibility (its service placeholders,
# mysql_service_<name>, must not resolve to mysqld's globals of the same names) and, with GCC,
# the C++ runtime linked statically so the .so runs on the official images.
function(mcp_component target)
  set_target_properties(${target} PROPERTIES
    PREFIX ""
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)
  target_include_directories(${target} PRIVATE ${MCP_INCLUDE_DIRS})
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set_property(TARGET ${target} APPEND_STRING PROPERTY LINK_FLAGS
      " -static-libstdc++ -static-libgcc")
  endif()
endfunction()

add_library(component_mcp_guard SHARED src/mcp/guard/component_mcp_guard.cc)
mcp_component(component_mcp_guard)
install(TARGETS component_mcp_guard
  LIBRARY DESTINATION lib/plugin
  RUNTIME DESTINATION lib/plugin)
install(FILES src/mcp/guard/mcp_guard.json DESTINATION share/mysql/component)

# Test only, not installed: runs SQL in impersonated command-service sessions, as
# component_mcp does, for scripts/test-mcp-guard.sh.
find_package(Threads REQUIRED)
add_library(component_mcp_session_probe SHARED src/mcp/guard/test/component_mcp_session_probe.cc)
mcp_component(component_mcp_session_probe)
target_link_libraries(component_mcp_session_probe PRIVATE Threads::Threads)
