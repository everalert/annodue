#include <fstream>
#include <thread>
#include <windows.h>
#include <vector>
#include <cmath>
#include <format>
#include <bit>
#include <map>
#include <optional>
#include <algorithm>

#include <initguid.h>

#include <d3d.h>
#include <ddraw.h>

// headers are from https://github.com/tim-tim707/SW_RACER_RE
#define INCLUDE_DX_HEADERS

#include "types.h"
#include "globals.h"

// functions, also from https://github.com/tim-tim707/SW_RACER_RE
auto stdDisplay_Update = (int (*)())0x00489ab0; // <-- will be hooked
auto swrModel_UnkDraw = (void (*)(int x))0x00483A90; // <-- will be hooked

auto rdMaterial_InvertTextureAlphaR4G4B4A4 = (void (*)(RdMaterial*))0x00431CF0; // <-- will be hooked
auto rdMaterial_InvertTextureColorR4G4B4A4 = (void (*)(RdMaterial*))0x00431DF0; // <-- will be hooked
auto rdMaterial_RemoveTextureAlphaR5G5B5A1 = (void (*)(RdMaterial*))0x00431EF0; // <-- will be hooked
auto rdMaterial_RemoveTextureAlphaR4G4B4A4 = (void (*)(RdMaterial*))0x00431FD0; // <-- will be hooked
auto rdMaterial_SaturateTextureR4G4B4A4 = (void (*)(RdMaterial*))0x004320B0; // <-- will be hooked

const auto swrModel_NodeGetTransform = (void (*)(const swrModel_NodeTransformed* node, rdMatrix44* matrix))0x004316A0;
const auto swrEvent_GetItem = (void* (*)(int event, int index))0x00450b30;
const auto std3D_SetRenderState = (void (*)(Std3DRenderState rdflags))0x0048a450;
const auto stdDisplay_BackBufferFill =
    (void (*)(unsigned int r, unsigned int b, unsigned int g, LECRECT* lpRect))0x00489cd0;
const auto rdCache_Flush = (void (*)(void))0x0048dce0;

// math functions, not strictly needed, it would be better to reimplement them for performance reasons.
const auto rdMatrix_Multiply44 = (void (*)(rdMatrix44* out, const rdMatrix44* mat1, const rdMatrix44* mat2))0x0042fb70;
const auto rdVector_Sub3 = (void (*)(rdVector3* v1, const rdVector3* v2, const rdVector3* v3))0x0042f860;
const auto rdVector_Normalize3Acc = (float (*)(rdVector3* v1))0x0042f9b0;
const auto rdVector_Scale3 = (void (*)(rdVector3* v1, float scale, const rdVector3* v2))0x0042fa50;
const auto rdVector_Scale3Add3 =
    (void (*)(rdVector3* v1, const rdVector3* v2, float scale, const rdVector3* v3))0x0042fa80;
const auto rdVector_Cross3 = (void (*)(rdVector3* v1, const rdVector3* v2, const rdVector3* v3))0x0042f9f0;
const auto rdMatrix_Copy44_34 = (void (*)(rdMatrix44* dest, const rdMatrix34* src))0x0044bad0;
const auto rdMatrix_SetIdentity44 = (void (*)(rdMatrix44* mat))0x004313d0;

#include "collision_viewer.h"

static CollisionViewerState* global_state = nullptr;

void render_collision_meshes();

struct Color
{
    uint8_t b, g, r, a = 255;
};
struct D3DVertex
{
    float x, y, z;
    Color c;
};

void debug_render_mesh(const swrModel_Mesh* mesh, bool mirrored, const rdMatrix44& proj_mat, const rdMatrix44& view_mat,
                       const rdMatrix44& model_matrix)
{
    if (!mesh->collision_vertices)
        return;

    uint32_t vehicle_reaction_bitset = mesh->mapping ? mesh->mapping->vehicle_reaction : 0;

    static std::array<std::optional<Color>, 32> vehicle_reaction_colors = [] {
        std::array<std::optional<Color>, 32> colors;
        colors[std::countr_zero((uint32_t)ZOn)] = Color{ 255, 180, 50 };
        colors[std::countr_zero((uint32_t)ZOff)] = Color{ 100, 255, 100 };
        colors[std::countr_zero((uint32_t)Fast)] = Color{ 0, 255, 255 };
        colors[std::countr_zero((uint32_t)Slow)] = Color{ 255, 100, 170 };
        colors[std::countr_zero((uint32_t)Swst)] = Color{ 255, 0, 0 };
        colors[std::countr_zero((uint32_t)Slip)] = Color{ 255, 255, 127 };
        colors[std::countr_zero((uint32_t)Lava)] = Color{ 50, 50, 255 };
        colors[std::countr_zero((uint32_t)Fall)] = Color{ 0, 127, 255 };
        colors[std::countr_zero((uint32_t)NRSp)] = Color{ 255, 0, 255 };
        colors[std::countr_zero((uint32_t)Side)] = Color{ 0, 255, 0 };
        return colors;
    }();

    Color color{ 255, 255, 255 };
    for (int i = 0; i < 32; i++)
    {
        if ((vehicle_reaction_bitset & (1 << i)) && vehicle_reaction_colors[i])
        {
            color = *vehicle_reaction_colors[i];
            break;
        }
    }

    static std::vector<D3DVertex> vertices;
    vertices.resize(mesh->num_collision_vertices);

    static std::vector<uint16_t> indices;
    indices.clear();

    const auto& settings = global_state->settings;

    const Color line_color{
        uint8_t(color.b * settings.collision_line_brightness),
        uint8_t(color.g * settings.collision_line_brightness),
        uint8_t(color.r * settings.collision_line_brightness),
        uint8_t(255 * settings.collision_line_opacity),
    };

    const Color mesh_color{
        uint8_t(color.b * settings.collision_mesh_brightness),
        uint8_t(color.g * settings.collision_mesh_brightness),
        uint8_t(color.r * settings.collision_mesh_brightness),
        uint8_t(255 * settings.collision_mesh_opacity),
    };

    for (int i = 0; i < mesh->num_collision_vertices; i++)
    {
        const auto& v = mesh->collision_vertices[i];
        vertices[i] = { float(v.x), float(v.y), float(v.z), mesh_color };
    }

    switch (mesh->primitive_type)
    {
    case 3: {
        for (int i = 0; i < mesh->num_primitives; i++)
        {
            indices.push_back(3 * i + 0);
            indices.push_back(3 * i + 1);
            indices.push_back(3 * i + 2);
        }
        break;
    }
    case 4:
        for (int i = 0; i < mesh->num_primitives; i++)
        {
            indices.push_back(4 * i + 0);
            indices.push_back(4 * i + 1);
            indices.push_back(4 * i + 2);

            indices.push_back(4 * i + 0);
            indices.push_back(4 * i + 2);
            indices.push_back(4 * i + 3);
        }
        break;
    case 5: {
        int offset = 0;
        for (int i = 0; i < mesh->num_primitives; i++)
        {
            int s = mesh->primitive_sizes[i];

            for (int j = 0; j < s - 2; j++)
            {
                if (j % 2 == 0)
                {
                    indices.push_back(offset + j + 0);
                    indices.push_back(offset + j + 1);
                    indices.push_back(offset + j + 2);
                }
                else
                {
                    indices.push_back(offset + j + 1);
                    indices.push_back(offset + j + 0);
                    indices.push_back(offset + j + 2);
                }
            }

            offset += s;
        }
        break;
    }
    }

    std3D_pD3Device->SetTransform(D3DTRANSFORMSTATE_WORLD, (D3DMATRIX*)&model_matrix.vA.x);

    if (settings.collision_mesh_opacity != 0.0)
    {
        std3D_pD3Device->SetRenderState(D3DRENDERSTATE_FILLMODE, D3DFILL_SOLID);
        std3D_pD3Device->DrawIndexedPrimitive(D3DPT_TRIANGLELIST, D3DFVF_XYZ | D3DFVF_DIFFUSE, vertices.data(),
                                              vertices.size(), indices.data(), indices.size(), 0);
    }

    for (auto& v : vertices)
        v.c = line_color;

    if (settings.collision_line_opacity != 0.0)
    {
        std3D_pD3Device->SetRenderState(D3DRENDERSTATE_FILLMODE, D3DFILL_WIREFRAME);
        std3D_pD3Device->DrawIndexedPrimitive(D3DPT_TRIANGLELIST, D3DFVF_XYZ | D3DFVF_DIFFUSE, vertices.data(),
                                              vertices.size(), indices.data(), indices.size(), 0);
    }
}

void debug_render_node(const swrModel_unk& current, const swrModel_Node* node, bool mirrored,
                       const rdMatrix44& proj_mat, const rdMatrix44& view_mat, rdMatrix44 model_mat, uint32_t col_flags)
{
    if (!node)
        return;

    if ((node->flags_2 & col_flags) != col_flags)
        return;

    if (node->type == NODE_TRANSFORMED || node->type == NODE_TRANSFORMED_WITH_PIVOT)
    {
        // this node has a transform.
        rdMatrix44 mat{};
        swrModel_NodeGetTransform((const swrModel_NodeTransformed*)node, &mat);
        if (node->type == NODE_TRANSFORMED_WITH_PIVOT && (node->flags_3 & 0x10))
        {
            // some kind of pivot point: the translation v is removed from the transform and then added untransformed.
            const rdVector3 v = ((const swrModel_NodeTransformedWithPivot*)node)->pivot;
            const rdVector3 v_transformed = {
                mat.vA.x * v.x + mat.vB.x * v.y + mat.vC.x * v.z,
                mat.vA.y * v.x + mat.vB.y * v.y + mat.vC.y * v.z,
                mat.vA.z * v.x + mat.vB.z * v.y + mat.vC.z * v.z,
            };
            mat.vD.x += v.x - v_transformed.x;
            mat.vD.y += v.y - v_transformed.y;
            mat.vD.z += v.z - v_transformed.z;
        }

        rdMatrix44 model_mat_new;
        rdMatrix_Multiply44(&model_mat_new, &mat, &model_mat);
        model_mat = model_mat_new;
    }
    else if (node->type == NODE_TRANSFORMED_COMPUTED)
    {
        const swrModel_NodeTransformedComputed* transformed_node = (const swrModel_NodeTransformedComputed*)node;
        rdMatrix34 transform{
            *(const rdVector3*)&model_mat.vA,
            *(const rdVector3*)&model_mat.vB,
            *(const rdVector3*)&model_mat.vC,
            *(const rdVector3*)&model_mat.vD,
        };

        switch (transformed_node->orientation_option)
        {
        case 0:
            break;
        case 1: {
            rdVector3 forward;
            rdVector_Sub3(&forward, &transform.scale, (const rdVector3*)&current.model_matrix.vD);
            rdVector_Normalize3Acc(&forward);

            // first transform up vector into the current coordinate system:
            rdVector3 up;
            rdVector_Scale3(&up, transformed_node->up_vector.x, &transform.rvec);
            rdVector_Scale3Add3(&up, &up, transformed_node->up_vector.y, &transform.lvec);
            rdVector_Scale3Add3(&up, &up, transformed_node->up_vector.z, &transform.uvec);
            float length = rdVector_Normalize3Acc(&up);

            // now build an orthonormal basis
            transform.uvec = up;
            // forward x up -> right
            rdVector_Cross3(&transform.rvec, &forward, &transform.uvec);
            rdVector_Normalize3Acc(&transform.rvec);
            // up x right -> forward
            rdVector_Cross3(&transform.lvec, &transform.uvec, &transform.rvec);
            // no normalize, because uvec and rvec are otrhogonal

            // scale
            rdVector_Scale3(&transform.rvec, length, &transform.rvec);
            rdVector_Scale3(&transform.lvec, length, &transform.lvec);
            rdVector_Scale3(&transform.uvec, length, &transform.uvec);
        }
        break;
        case 2: // TODO
        case 3: // TODO
        default:
            std::abort();
        }

        if (transformed_node->follow_model_position == 1)
            transform.scale = *(const rdVector3*)&current.model_matrix.vD;

        rdMatrix_Copy44_34(&model_mat, &transform);
    }

    if (node->flags_5 & 0x1)
        mirrored = !mirrored;

    if (node->type == NODE_MESH_GROUP)
    {
        for (int i = 0; i < node->num_children; i++)
            debug_render_mesh(node->meshes[i], mirrored, proj_mat, view_mat, model_mat);
    }
    else if (node->type == NODE_LOD_SELECTOR)
    {
        const swrModel_NodeLODSelector* lods = (const swrModel_NodeLODSelector*)node;
        // find correct lod node
        int i = 1;
        for (; i < 8; i++)
        {
            if (lods->lod_distances[i] == -1 || lods->lod_distances[i] >= 10)
                break;
        }
        if (i - 1 < node->num_children)
            debug_render_node(current, node->child_nodes[i - 1], mirrored, proj_mat, view_mat, model_mat, col_flags);
    }
    else if (node->type == NODE_SELECTOR)
    {
        const swrModel_NodeSelector* selector = (const swrModel_NodeSelector*)node;
        int child = selector->selected_child_node;
        switch (child)
        {
        case -2:
            // dont render any child node
            break;
        case -1:
            // render all child nodes
            for (int i = 0; i < node->num_children; i++)
                debug_render_node(current, node->child_nodes[i], mirrored, proj_mat, view_mat, model_mat, col_flags);
            break;
        default:
            if (child >= 0 && child < node->num_children)
                debug_render_node(current, node->child_nodes[child], mirrored, proj_mat, view_mat, model_mat,
                                  col_flags);

            break;
        }
    }
    else
    {
        for (int i = 0; i < node->num_children; i++)
            debug_render_node(current, node->child_nodes[i], mirrored, proj_mat, view_mat, model_mat, col_flags);
    }
}

void render_spline()
{
    auto hang = (const swrObjHang*)swrEvent_GetItem('Hang', 0);
    if (!hang)
        return;

    auto judge = (const swrObjJdge*)swrEvent_GetItem('Jdge', 0);
    if (!judge)
        return;

    const swrSpline* spline = judge->spline;
    if (!spline)
        return;

    int track_index = hang->track_index;

    struct PrecomputedSpline
    {
        std::vector<std::vector<D3DVertex>> segments;
    };
    static std::map<int, PrecomputedSpline> precomputed_splines;
    if (!precomputed_splines.contains(track_index))
    {
        PrecomputedSpline precomputed_spline;
        auto draw_cubic_bezier = [&](const rdVector3& p0, const rdVector3& p1, const rdVector3& p2,
                                     const rdVector3& p3) {
            const rdMatrix44 P{ p0.x, p1.x, p2.x, p3.x, p0.y, p1.y, p2.y, p3.y, p0.z, p1.z, p2.z, p3.z, 0, 0, 0, 0 };
            const rdMatrix44 bezier_matrix{ 1, -3, 3, -1, 0, 3, -6, 3, 0, 0, 3, -3, 0, 0, 0, 1 };

            rdMatrix44 r;
            rdMatrix_Multiply44(&r, &P, &bezier_matrix);

            const int BEZIER_RESOLUTION = 50;
            std::vector<D3DVertex> vertices(BEZIER_RESOLUTION);
            for (int k = 0; k < BEZIER_RESOLUTION; k++)
            {
                float t = k / float(BEZIER_RESOLUTION - 1);
                const rdVector3 p{
                    r.vA.x * 1 + r.vA.y * t + r.vA.z * t * t + r.vA.w * t * t * t,
                    r.vB.x * 1 + r.vB.y * t + r.vB.z * t * t + r.vB.w * t * t * t,
                    r.vC.x * 1 + r.vC.y * t + r.vC.z * t * t + r.vC.w * t * t * t,
                };
                vertices[k] = {
                    p.x,
                    p.y,
                    p.z,
                    Color{ 0, 255, 0, 255 },
                };
            }

            precomputed_spline.segments.emplace_back(std::move(vertices));
        };

        for (int i = 0; i < spline->num_control_points; i++)
        {
            const auto& point = spline->contrl_points[i];
            for (int j = 0; j < point.next_count; j++)
            {
                const auto& next = spline->contrl_points[(&point.next1)[j]];

                const auto& p0 = point.position;
                const auto& p1 = point.handle2;
                const auto& p2 = next.handle1;
                const auto& p3 = next.position;
                draw_cubic_bezier(p0, p1, p2, p3);
            }
        }

        precomputed_splines.emplace(track_index, std::move(precomputed_spline));
    }

    const auto& segments = precomputed_splines.at(track_index).segments;

    rdMatrix44 model_mat;
    rdMatrix_SetIdentity44(&model_mat);
    std3D_pD3Device->SetTransform(D3DTRANSFORMSTATE_WORLD, (D3DMATRIX*)&model_mat.vA.x);

    for (const auto& vertices : segments)
        std3D_pD3Device->DrawPrimitive(D3DPT_LINESTRIP, D3DFVF_XYZ | D3DFVF_DIFFUSE, (void*)vertices.data(),
                                       vertices.size(), 0);
}

void render_collision_meshes()
{
    if (!std3D_pD3Device || !rdCamera_pCurCamera)
        return;

    swrModel_Node* root_node = swrModel_unk_array[0].model_root_node;
    if (!root_node)
        return;

    const auto& settings = global_state->settings;
    auto hang = (const swrObjHang*)swrEvent_GetItem('Hang', 0);
    const auto& track_info = g_aTrackInfos[hang->track_index];
    const uint32_t col_flags = 0x2 | (1 << (4 + track_info.PlanetTrackNumber));
    const bool mirrored = (GameSettingFlags & 0x4000) != 0;

    IDirect3DViewport3* backup_viewport = nullptr;
    std3D_pD3Device->GetCurrentViewport(&backup_viewport);

    IDirect3DViewport3* viewport;
    std3D_pDirect3D->CreateViewport(&viewport, nullptr);

    // Setup viewport
    D3DVIEWPORT2 vp{};
    vp.dwSize = sizeof(D3DVIEWPORT2);
    vp.dwX = 0;
    vp.dwY = 0;
    vp.dwWidth = screen_width;
    vp.dwHeight = screen_height;
    vp.dvMinZ = -1.0f;
    vp.dvMaxZ = 1.0f;
    vp.dvClipX = -1;
    vp.dvClipY = 1;
    vp.dvClipWidth = 2;
    vp.dvClipHeight = 2;

    std3D_pD3Device->AddViewport(viewport);
    viewport->SetViewport2(&vp);
    std3D_pD3Device->SetCurrentViewport(viewport);

    std3D_SetRenderState(Std3DRenderState(STD3D_RS_UNKNOWN_1 | STD3D_RS_UNKNOWN_2 | STD3D_RS_UNKNOWN_200));
    std3D_pD3Device->SetRenderState(D3DRENDERSTATE_ZENABLE, settings.depth_test);

    std3D_pD3DTex = NULL;
    std3D_pD3Device->SetTexture(0, NULL);

    if (settings.cull_backfaces)
        std3D_pD3Device->SetRenderState(D3DRENDERSTATE_CULLMODE, mirrored ? D3DCULL_CCW : D3DCULL_CW);

    if (std3D_pD3Device->BeginScene() >= 0)
    {
        rdMatrix44 model_mat;
        rdMatrix_SetIdentity44(&model_mat);

        rdMatrix44 view_mat;
        rdMatrix_Copy44_34(&view_mat, &rdCamera_pCurCamera->view_matrix);

        rdMatrix44 rotation{
            { 1, 0, 0, 0 },
            { 0, 0, -1, 0 },
            { 0, 1, 0, 0 },
            { 0, 0, 0, 1 },
        };

        rdMatrix44 view_mat_corrected;
        rdMatrix_Multiply44(&view_mat_corrected, &view_mat, &rotation);

        const auto& frustum = rdCamera_pCurCamera->pClipFrustum;
        float f = frustum->zFar;
        float n = frustum->zNear;
        const float t = 1.0f / std::tan(0.5 * rdCamera_pCurCamera->fov / 180.0 * 3.14159);
        float a = float(screen_height) / screen_width;
        const rdMatrix44 proj_mat{
            { mirrored ? -t : t, 0, 0, 0 },
            { 0, t / a, 0, 0 },
            { 0, 0, -1, -1 },
            { 0, 0, -1 - global_state->depth_bias, 0 },
        };

        std3D_pD3Device->SetTransform(D3DTRANSFORMSTATE_VIEW, (D3DMATRIX*)&view_mat_corrected.vA.x);
        std3D_pD3Device->SetTransform(D3DTRANSFORMSTATE_PROJECTION, (D3DMATRIX*)&proj_mat.vA.x);

        if (global_state->show_collision_mesh)
            debug_render_node(swrModel_unk_array[0], root_node->child_nodes[3], mirrored, proj_mat, view_mat_corrected,
                              model_mat, col_flags);

        if (global_state->show_spline)
            render_spline();

        std3D_pD3Device->EndScene();
    }
    std3D_pD3Device->SetCurrentViewport(backup_viewport);
    std3D_pD3Device->DeleteViewport(viewport);

    std3D_pD3Device->SetRenderState(D3DRENDERSTATE_FILLMODE, D3DFILL_SOLID);
    std3D_pD3Device->SetRenderState(D3DRENDERSTATE_CULLMODE, D3DCULL_NONE);

    std3D_pD3Device->SetRenderState(D3DRENDERSTATE_ZENABLE, 1);

    viewport->Release();
}

void swrModel_UnkDraw_Hook(int x)
{
    if (!global_state || !global_state->enabled)
    {
        swrModel_UnkDraw(x);
        return;
    }

    auto* root_node = swrModel_unk_array[x].model_root_node;
    std::vector<swrModel_Node*> temp_children(root_node->child_nodes, root_node->child_nodes + root_node->num_children);

    // first render the terrain...
    if (global_state->settings.show_visual_mesh)
    {
        for (int i = 4; i < root_node->num_children; i++)
            root_node->child_nodes[i] = NULL;

        swrModel_UnkDraw(x);
    }
    else
    {
        stdDisplay_BackBufferFill(0, 0, 0, nullptr);
    }

    rdCache_Flush();
    render_collision_meshes();

    // ... and after the collision meshes render the rest:
    for (int i = 0; i < root_node->num_children; i++)
        root_node->child_nodes[i] = i < 4 ? NULL : temp_children[i];

    swrModel_UnkDraw(x);

    // restore node:
    std::copy(temp_children.begin(), temp_children.end(), root_node->child_nodes);
}

#define debug_print(string, ...)                                                                                       \
    {                                                                                                                  \
        printf("%s:%d: " string "\n", __func__, __LINE__, __VA_ARGS__);                                                \
        fflush(stdout);                                                                                                \
    }

template <typename F>
void modify_texture_data(RdMaterial* mat, const char* name, F&& mod)
{
    if (strncmp(mat->aName, name, strlen(name)) == 0)
        return;

    sprintf(mat->aName, "%s", name);

    tSystemTexture* tex = mat->aTextures;
    IDirectDrawSurface4* surf = NULL;
    if (tex->pD3DSrcTexture->QueryInterface(IID_IDirectDrawSurface4, (void**)&surf) != S_OK)
    {
        debug_print("material %p %s: QueryInterface failed.", mat, name);
        return;
    }

    DDSURFACEDESC2 desc = { 0 };
    desc.dwSize = sizeof(DDSURFACEDESC2);
    if (surf->Lock(NULL, &desc, DDLOCK_WAIT, NULL) != S_OK)
    {
        debug_print("material %p %s: Lock failed.", mat, name);
        return;
    }

    debug_print("material %p %s: width=%d height=%d pitch=%d lpSurface=%p", mat, name, desc.dwWidth, desc.dwHeight,
                desc.lPitch, desc.lpSurface);

    const int pitch = desc.dwFlags & DDSD_PITCH ? desc.lPitch : desc.dwWidth * 2;
    uint8_t* data = (uint8_t*)desc.lpSurface;
    for (int y = 0; y < desc.dwHeight; y++)
    {
        uint16_t* line_ptr = (uint16_t*)(data + pitch * y);
        for (int x = 0; x < desc.dwWidth; x++)
            line_ptr[x] = mod(line_ptr[x]);
    }

    debug_print("material %p %s modification finished.", mat, name);

    surf->Unlock(NULL);

    // this line is the only memory leak fix: release is missing in the original functions.
    surf->Release();

    debug_print("material %p %s cleanup finished.", mat, name);
}

void rdMaterial_InvertTextureAlphaR4G4B4A4_Hook(RdMaterial* mat)
{
    modify_texture_data(mat, "invert", [](uint16_t pixel) { return ~(pixel & 0xF000) | (pixel & 0xFFF); });
}

void rdMaterial_InvertTextureColorR4G4B4A4_Hook(RdMaterial* mat)
{
    modify_texture_data(mat, "invcol", [](uint16_t pixel) { return (pixel & 0xF000) | ~(pixel & 0xFFF); });
}

void rdMaterial_RemoveTextureAlphaR5G5B5A1_Hook(RdMaterial* mat)
{
    modify_texture_data(mat, "noalpha", [](uint16_t pixel) { return pixel | 0x8000; });
}

void rdMaterial_RemoveTextureAlphaR4G4B4A4_Hook(RdMaterial* mat)
{
    modify_texture_data(mat, "noalpha", [](uint16_t pixel) { return pixel | 0xF000; });
}

void rdMaterial_SaturateTextureR4G4B4A4_Hook(RdMaterial* mat)
{
    modify_texture_data(mat, "saturate", [](uint16_t pixel) { return pixel | 0x0FFF; });
}

void detour_attach(void** pPointer, void* pDetour, int num_bytes_to_copy)
{
    if (num_bytes_to_copy < 5)
        abort();

    uint8_t* original_address = (uint8_t*)*pPointer;
    uint8_t* new_address = (uint8_t*)pDetour;
    DWORD old_protect;
    VirtualProtect(original_address, num_bytes_to_copy, PAGE_EXECUTE_READWRITE, &old_protect);

    int32_t offset = new_address - (original_address + 5);

    uint8_t* patch_memory = (uint8_t*)VirtualAlloc(nullptr, num_bytes_to_copy + 5, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    memcpy(patch_memory, original_address, num_bytes_to_copy);

    original_address[0] = 0xe9;
    memcpy(original_address + 1, &offset, 4);

    int32_t patch_offset = (original_address + num_bytes_to_copy) - (patch_memory + num_bytes_to_copy + 5);

    patch_memory[num_bytes_to_copy] = 0xe9;
    memcpy(patch_memory + num_bytes_to_copy + 1, &patch_offset, 4);

    *pPointer = patch_memory;
}

void detour_detach(void** pPointer, void* pDetour, int num_bytes_to_copy)
{
    if (num_bytes_to_copy < 5)
        abort();

    uint8_t* patch_memory = (uint8_t*)*pPointer;

    uint32_t patch_offset;
    memcpy(&patch_offset, patch_memory + num_bytes_to_copy + 1, 4);
    uint8_t* original_address = patch_offset + (patch_memory + num_bytes_to_copy + 5) - num_bytes_to_copy;

    memcpy(original_address, patch_memory, num_bytes_to_copy);
    VirtualFree(patch_memory, num_bytes_to_copy + 5, MEM_RELEASE);

    DWORD old_protect;
    VirtualProtect(original_address, num_bytes_to_copy, PAGE_EXECUTE_READ, &old_protect);

    *pPointer = original_address;
}

extern "C" void init_collision_viewer(CollisionViewerState* global_state)
{
    freopen("collision_viewer.log", "w", stdout);

    ::global_state = global_state;
    // collision viewer
    detour_attach((void**)&swrModel_UnkDraw, (void*)swrModel_UnkDraw_Hook, 5);

    // fix memory leaks
    detour_attach((void**)&rdMaterial_InvertTextureAlphaR4G4B4A4, (void*)rdMaterial_InvertTextureAlphaR4G4B4A4_Hook, 6);
    detour_attach((void**)&rdMaterial_InvertTextureColorR4G4B4A4, (void*)rdMaterial_InvertTextureColorR4G4B4A4_Hook, 6);
    detour_attach((void**)&rdMaterial_RemoveTextureAlphaR5G5B5A1, (void*)rdMaterial_RemoveTextureAlphaR5G5B5A1_Hook, 6);
    detour_attach((void**)&rdMaterial_RemoveTextureAlphaR4G4B4A4, (void*)rdMaterial_RemoveTextureAlphaR4G4B4A4_Hook, 6);
    detour_attach((void**)&rdMaterial_SaturateTextureR4G4B4A4, (void*)rdMaterial_SaturateTextureR4G4B4A4_Hook, 6);
}

extern "C" void deinit_collision_viewer()
{
    // collision viewer
    detour_detach((void**)&swrModel_UnkDraw, (void*)swrModel_UnkDraw_Hook, 5);

    // fix memory leaks
    detour_detach((void**)&rdMaterial_InvertTextureAlphaR4G4B4A4, (void*)rdMaterial_InvertTextureAlphaR4G4B4A4_Hook, 6);
    detour_detach((void**)&rdMaterial_InvertTextureColorR4G4B4A4, (void*)rdMaterial_InvertTextureColorR4G4B4A4_Hook, 6);
    detour_detach((void**)&rdMaterial_RemoveTextureAlphaR5G5B5A1, (void*)rdMaterial_RemoveTextureAlphaR5G5B5A1_Hook, 6);
    detour_detach((void**)&rdMaterial_RemoveTextureAlphaR4G4B4A4, (void*)rdMaterial_RemoveTextureAlphaR4G4B4A4_Hook, 6);
    detour_detach((void**)&rdMaterial_SaturateTextureR4G4B4A4, (void*)rdMaterial_SaturateTextureR4G4B4A4_Hook, 6);
}