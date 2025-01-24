#include "ReShade.fxh"

// ------------------------------------------------------------------------------------------------------------------------
// Magnification Settings
// ------------------------------------------------------------------------------------------------------------------------

    uniform float2 UI_Size <
        ui_label = "Size";
        ui_type = "drag";
        ui_min = 0.0;
        ui_max = BUFFER_WIDTH;
        ui_step = 1.0;
    > = float2(500.0, 500.0);

    uniform float2 Offset <
        ui_label = "Offset";
        ui_type = "drag";
        ui_min = -BUFFER_WIDTH;
        ui_max = BUFFER_WIDTH;
        ui_step = 1.0;
    > = float2(0.0, 0.0);

    uniform float UI_Magnification <
        ui_label = "Magnification";
        ui_type = "drag";
        ui_min = 0.1;
        ui_max = 10.0;
        ui_step = 0.1;
    > = 1.5;

    uniform float UI_Transition <
        ui_label = "Transition";
        ui_type = "drag";
        ui_min = 0.0;
        ui_max = BUFFER_WIDTH;
        ui_step = 1.0;
    > = 0.0;

    uniform int Shape <
        ui_label = "Shape";
        ui_type = "combo";
        ui_items = "Ellipse\0Rectangle\0";
    > = 0;

    uniform float EdgeRounding <
        ui_label = "Edge Rounding";
        ui_type = "drag";
        ui_min = 0.0;
        ui_max = BUFFER_WIDTH;
        ui_step = 1.0;
    > = 0.0;

    uniform int Hotkey <
        ui_type = "combo";
        ui_label = "Hotkey";
        ui_items = "None\0Left Mouse Button\0Right Mouse Button\0Middle Mouse Button\0X1 Mouse Button (Back Mouse Button)\0X2 Mouse Button (Forward Mouse Button)\0Custom Hotkey\0";
        ui_tooltip = "Select the mouse button or keyboard key code to trigger hotkey behavior.\nScrolling with this key held will increase/decrease zoom. Default custom key code is 0x5A corresponding to the Z key.";
    > = 0;
    
    



    uniform bool IsFollowCursor <
        ui_label = "Follow Cursor";
        ui_tooltip = "Center magnification around cursor position, not the center of the screen.";
    > = true;

// ------------------------------------------------------------------------------------------------------------------------
// Variables
// ------------------------------------------------------------------------------------------------------------------------

    static const float2 CenterPoint = BUFFER_SCREEN_SIZE / 2.0;
    static const float PI = 3.141592;
    
    uniform float2 MousePoint < source = "mousepoint"; >;
    uniform float2 mouse_value < source = "mousewheel"; min = 0.0; max = 10.0; > = 1.0;
    uniform bool MouseLeft_Down < source = "mousebutton"; keycode = 0; mode = ""; >;
    uniform bool MouseLeft_Press < source = "mousebutton"; keycode = 0; mode = "press"; >;
    uniform bool MouseRight_Down < source = "mousebutton"; keycode = 1; mode = ""; >;
    uniform bool MouseRight_Press < source = "mousebutton"; keycode = 1; mode = "press"; >;
    uniform bool MouseMiddle_Down < source = "mousebutton"; keycode = 2; mode = ""; >;
    uniform bool MouseMiddle_Press < source = "mousebutton"; keycode = 2; mode = "press"; >;
    uniform bool MouseBack_Down < source = "mousebutton"; keycode = 3; mode = ""; >;
    uniform bool MouseBack_Press < source = "mousebutton"; keycode = 3; mode = "press"; >;
    uniform bool MouseForward_Down < source = "mousebutton"; keycode = 4; mode = ""; >;
    uniform bool MouseForward_Press < source = "mousebutton"; keycode = 4; mode = "press"; >;
    // modifiers
    uniform bool shift_down < source = "key"; keycode = 0x10; mode = ""; >;
    uniform bool ctrl_down < source = "key"; keycode = 0x11; mode = ""; >;
    uniform bool alt_down < source = "key"; keycode = 0x12; mode = ""; >;
	
    #ifndef CUSTOM_HOTKEY_KEYCODE
        #define CUSTOM_HOTKEY_KEYCODE 0x5A
    #endif

    uniform bool CustomKey_Down <source = "key"; keycode = CUSTOM_HOTKEY_KEYCODE; mode = ""; >;
    uniform bool CustomKey_Press <source = "key"; keycode = CUSTOM_HOTKEY_KEYCODE; mode = "press"; >;

// ------------------------------------------------------------------------------------------------------------------------
// Textures
// ------------------------------------------------------------------------------------------------------------------------
    texture2D MagnifyStatusTex { Width= 1; Height = 1; Format = R8; };
    sampler2D MagnifyStatus { Texture = MagnifyStatusTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

    texture2D MagnifyStatusCopyTex { Width= 1; Height = 1; Format = R8; };
    sampler2D MagnifyStatusCopy { Texture = MagnifyStatusCopyTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

// ------------------------------------------------------------------------------------------------------------------------
// Helper Functions
// ------------------------------------------------------------------------------------------------------------------------

float smoothScale(float x, float minVal, float maxVal) {
    // Normalize the value to a 0-1 range
    float normalized = (x - minVal) / (maxVal - minVal);

    // Apply the cosine function for smooth scaling
    float smoothed = 0.1 * (1 - cos(normalized * 3.14159265)); // Pi for cosine smoothing

    // Scale back to the original range
    return minVal + smoothed * (maxVal - minVal);
}

    float4 GetVertex(in uint id) {
		float sizeAdjust = ctrl_down ? clamp(smoothScale(mouse_value.x, 0.01, 10.0), 0.1, min(BUFFER_WIDTH, BUFFER_HEIGHT)) : 1;
		const float2 Size = UI_Size * sizeAdjust;
        float4 retval = 0.0;

        float2 offset = float2(Offset.x - Size.x / 2.0, Offset.y + Offset.y - Size.y / 2.0);
        if (id > 1) offset.x += Size.x;
        if (id == 1 || id == 3) offset.y += Size.y;

        if (IsFollowCursor) {
            retval.xy = (MousePoint + offset) / BUFFER_SCREEN_SIZE;
            retval.zw = (MousePoint + Offset) / BUFFER_SCREEN_SIZE;
        }
        else {
            retval.xy = (CenterPoint + offset) / BUFFER_SCREEN_SIZE;
            retval.zw = (CenterPoint + Offset) / BUFFER_SCREEN_SIZE;
        }

        return retval;
    }

    bool GetHotkey() {
        if (Hotkey > 0) {
            const bool hotkeyDown[6] = { MouseLeft_Down, MouseRight_Down, MouseMiddle_Down, MouseBack_Down, MouseForward_Down, CustomKey_Down };
            return hotkeyDown[Hotkey - 1];
        }
        return true;
    }

    bool GetHotkeyToggle() {
        if (Hotkey > 0) {
            const bool hotkeyPress[6] = { MouseLeft_Press, MouseRight_Press, MouseMiddle_Press, MouseBack_Press, MouseForward_Press, CustomKey_Press };
            bool status = tex2Dfetch(MagnifyStatusCopy, int2(0, 0), 0).r > 0.0;
            if (status && !hotkeyPress[Hotkey - 1] || !status && hotkeyPress[Hotkey - 1]) return true;
            return false;
        }
        return true;
    }

    // https://iquilezles.org/articles/distfunctions2d/
    float sdBox( in float2 p, in float2 b ) {
        float2 d = abs(p)-b;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    }

    float sdEllipse( in float2 p, in float2 ab ) {
        if (ab.x == ab.y) return length(p) - ab.x;
        
        p = abs(p);
        if( p.x > p.y ) {p=p.yx;ab=ab.yx;}
        float l = ab.y*ab.y - ab.x*ab.x;
        float m = ab.x*p.x/l;
        float m2 = m*m; 
        float n = ab.y*p.y/l;
        float n2 = n*n; 
        float c = (m2+n2-1.0)/3.0;
        float c3 = c*c*c;
        float q = c3 + m2*n2*2.0;
        float d = c3 + m2*n2;
        float g = m + m*n2;
        float co;
        if (d < 0.0)
        {
            float h = acos(q/c3)/3.0;
            float s = cos(h);
            float t = sin(h)*sqrt(3.0);
            float rx = sqrt( -c*(s + t + 2.0) + m2 );
            float ry = sqrt( -c*(s - t + 2.0) + m2 );
            co = (ry+sign(l)*rx+abs(g)/(rx*ry)- m)/2.0;
        }
        else
        {
            float h = 2.0*m*n*sqrt( d );
            float s = sign(q+h)*pow(abs(q+h), 1.0/3.0);
            float u = sign(q-h)*pow(abs(q-h), 1.0/3.0);
            float rx = -s - u - c*4.0 + 2.0*m2;
            float ry = (s - u)*sqrt(3.0);
            float rm = sqrt( rx*rx + ry*ry );
            co = (ry/sqrt(rm-rx)+2.0*g/rm-m)/2.0;
        }
        float2 r = ab * float2(co, sqrt(1.0-co*co));
        return length(r-p) * sign(p.y-r.y);
    }

    float sinLerp(float x, float y, float s) {
        return lerp(x, y, (sin(lerp(-PI/2.0, PI/2.0, s)) + 1.0) / 2.0);
    }

// ------------------------------------------------------------------------------------------------------------------------
// Vertex Shaders
// ------------------------------------------------------------------------------------------------------------------------
    void MagnifyStatusVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
    {
        texcoord.xy = 0.5;
        position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    void MagnifyVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD, out nointerpolation float2 center : TEXCOORD1)
    {   
        float4 vertex = GetVertex(id);
        texcoord = vertex.xy;
        center = vertex.zw;

        if (!GetHotkey()) {
            texcoord = 0.0;
            center = 0.0;
        }

	    position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    void MagnifyToggleVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD, out nointerpolation float2 center : TEXCOORD1)
    {   
        float4 vertex = GetVertex(id);
        texcoord = vertex.xy;
        center = vertex.zw;

        if (!GetHotkeyToggle()) {
            texcoord = 0.0;
            center = 0.0;
        }

	    position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

// ------------------------------------------------------------------------------------------------------------------------
// Pixel Shaders
// ------------------------------------------------------------------------------------------------------------------------


    float MagnifyStatusPS(float4 pos: SV_POSITION, float2 texCoord: TEXCOORD) : SV_TARGET {
        return GetHotkeyToggle() ? 1.0 : 0.0;
    }

    float MagnifyStatusCopyPS(float4 pos: SV_POSITION, float2 texCoord: TEXCOORD) : SV_TARGET {
        return tex2Dfetch(MagnifyStatus, int2(0, 0), 0).r;
    }

    float4 MagnifyPS(float4 pos: SV_POSITION, float2 texCoord: TEXCOORD, nointerpolation float2 center : TEXCOORD1) : SV_TARGET {

float magAdjust = !ctrl_down && !alt_down ? clamp( smoothScale(mouse_value.x, 0.01, 10.0) , 0.1, 400.0) : 1;
float sizeAdjust = ctrl_down && !alt_down ? clamp( smoothScale(mouse_value.x, 0.01, 10.0), 0.1, min(BUFFER_WIDTH, BUFFER_HEIGHT)) : 1;
const float2 Size = UI_Size * sizeAdjust;
const float Magnification = UI_Magnification * magAdjust;     
float transAdjust = alt_down && !ctrl_down ? clamp( smoothScale(5 * mouse_value.x, 0.01, 10.0), 0.1, max(BUFFER_WIDTH, BUFFER_HEIGHT)) : 1;
const float Transition = UI_Transition * transAdjust;
float2 target = center + (texCoord - center) / Magnification;
        float d;
        if (Shape == 0) d = sdEllipse((texCoord - center) * BUFFER_SCREEN_SIZE, Size / 2.0);
        else d = sdBox((texCoord - center) * BUFFER_SCREEN_SIZE, Size / 2.0 - EdgeRounding) - EdgeRounding;
        
        if (d > 0) discard;
        
        if (Transition > 0 && d > -Transition) target = center + (texCoord - center) / sinLerp(Magnification, 1.0, (Transition + d) / Transition);
        
        return tex2Dlod(ReShade::BackBuffer, float4(target, 0, 0));
    }
// ------------------------------------------------------------------------------------------------------------------------
// Passes
// ------------------------------------------------------------------------------------------------------------------------

technique Magnify
{
    pass Magnify
    {
        PrimitiveTopology = TRIANGLESTRIP;
        VertexCount = 4;
        VertexShader = MagnifyVS;
        PixelShader = MagnifyPS;
    }
}

technique Magnify_Toggle
{
    pass Magnify
    {
        PrimitiveTopology = TRIANGLESTRIP;
        VertexCount = 4;
        VertexShader = MagnifyToggleVS;
        PixelShader = MagnifyPS;
    }
    // ReShade cannot read and write to the same texture in a single pass, so we have to duplicate it.
    pass MagnifyStatus
    {
        PrimitiveTopology = POINTLIST;
        VertexShader = MagnifyStatusVS;
        PixelShader = MagnifyStatusPS;
        RenderTarget = MagnifyStatusTex;
    }
    pass MagnifyStatusCopy
    {
        PrimitiveTopology = POINTLIST;
        VertexShader = MagnifyStatusVS;
        PixelShader = MagnifyStatusCopyPS;
        RenderTarget = MagnifyStatusCopyTex;
    }
}
