add_definitions(-DTRANSLATION_DOMAIN="kwin_effects_stageanim")

set(stageanim_SOURCES
    stageanim.cpp
    main.cpp
)

add_library(stageanim13 MODULE ${stageanim_SOURCES})
target_link_libraries(stageanim13 PRIVATE
    KF6::ConfigGui
    KWin::kwin
)
install(TARGETS stageanim13 DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins)
