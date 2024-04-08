cmake_minimum_required(VERSION 3.0)

if (WIN32)
	add_library(dinput SHARED dinput.c dinput.def)
	target_link_libraries(dinput PRIVATE winmm.lib)
	set_target_properties(dinput PROPERTIES PREFIX "")
	target_compile_definitions(dinput PUBLIC -DDLL=1)
endif()
