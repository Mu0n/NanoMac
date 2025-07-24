cmake_minimum_required(VERSION 3.28)
project(NanoMacTracker)

enable_language(C ASM) 

add_application(NanoMacTracker
    nanomactracker.c
    font_16x8.c
    wc_mod.s
   )

set_target_properties(NanoMacTracker PROPERTIES COMPILE_OPTIONS -ffunction-sections)
if(CMAKE_SYSTEM_NAME MATCHES Retro68)
    set_target_properties(NanoMacTracker PROPERTIES LINK_FLAGS "-Wl,-gc-sections -Wl,--mac-strip-macsbug")
else()
    set_target_properties(NanoMacTracker PROPERTIES LINK_FLAGS "-Wl,-gc-sections")
endif()
