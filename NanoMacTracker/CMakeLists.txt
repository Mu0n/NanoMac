cmake_minimum_required(VERSION 3.28)
project(NanoMacTracker)

enable_language(C ASM) 
 

add_application(NanoMacTracker
    nanomactracker.c
    wc_mod.s
    nanomactracker.r
   )

    # make the result as small as possible
    # by removing unused code (gc-sections)
    # and by removing macsbug function names on 68K
    # (don't do this when debugging...)
set_target_properties(NanoMacTracker PROPERTIES COMPILE_OPTIONS -ffunction-sections)
if(CMAKE_SYSTEM_NAME MATCHES Retro68)
    set_target_properties(NanoMacTracker PROPERTIES LINK_FLAGS "-Wl,-gc-sections -Wl,--mac-strip-macsbug")
else()
    set_target_properties(NanoMacTracker PROPERTIES LINK_FLAGS "-Wl,-gc-sections")
endif()
