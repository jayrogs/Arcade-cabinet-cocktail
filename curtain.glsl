// The curtain. Every game spends its first few seconds on its own start-up test: a
// screen of garbled tiles while the old hardware checks itself. Real cabinets did that
// with the lights on and nobody minded; on a cabinet you have just picked a game on, it
// looks broken. So the picture is held black for the start-up and then faded in.
//
// Nothing else about the picture changes: once the curtain is up, the game's own pixels
// pass straight through.

#define HOLD 240.0     // frames of black, about four seconds
#define FADE 30.0      // frames to fade in, about half a second

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;
uniform mat4 MVPMatrix;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = TexCoord.xy;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#endif

uniform int FrameCount;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;

void main()
{
    float lift = clamp((float(FrameCount) - HOLD) / FADE, 0.0, 1.0);
    vec3 c = COMPAT_TEXTURE(Texture, TEX0.xy).rgb;
    FragColor = vec4(c * lift, 1.0);
}
#endif
