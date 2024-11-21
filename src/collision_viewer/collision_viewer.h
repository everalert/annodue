#pragma once

#include <stdbool.h>

typedef struct CollisionViewerSettings
{
    bool show_visual_mesh;
    float collision_mesh_opacity;
    float collision_mesh_brightness;
    float collision_line_opacity;
    float collision_line_brightness;
    bool depth_test;
    bool cull_backfaces;
} CollisionViewerSettings;

typedef struct CollisionViewerState
{
    bool enabled;
    bool show_collision_mesh;
    bool show_triggers;
    bool show_active_collision_only;
    CollisionViewerSettings settings;
    float depth_bias;
    bool show_spline;
} CollisionViewerState;