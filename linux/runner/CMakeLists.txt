cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID, and for the program name.
#
# **They are two strings because they answer two different questions**, and that is the point of
# splitting them -- the long note is in `linux/CMakeLists.txt`: the application id must contain a dot
# or GLib rejects it, and the program name must not contain one or WSLg's icon lookup can never match
# the key it derives from the desktop file's name.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
add_definitions(-DPRGNAME="${PRGNAME}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
