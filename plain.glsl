// Nothing at all: the picture as the game draws it. tableflip.py switches back to this when
// player 2 has gone quiet (curtain.glsl itself would black the screen out again).

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
    float lift = 1.0;
    vec3 c = COMPAT_TEXTURE(Texture, TEX0.xy).rgb;
    FragColor = vec4(c * lift, 1.0);
}
#endif
