// Table versus. For head-to-head games that split the screen into two fields side by side
// (Puzzle Bobble's versus): the right-hand field, player 2's, is turned half round in
// place, so on a cocktail table each player sees their own field the right way up from
// their own seat. The left half is untouched. Everything else is the curtain (curtain.glsl):
// held black through the game's start-up test, then faded in.
//
// Only for games whose two fields are exactly the two halves of the picture, and only in
// versus: a one-player game with a single field in the middle would be cut in two.

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

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

uniform int FrameCount;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;

uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;

void main()
{
    float lift = clamp((float(FrameCount) - HOLD) / FADE, 0.0, 1.0);
    // where on the game's own picture this is, 0..1 each way (the picture sits in the
    // corner of a bigger texture)
    vec2 edge = InputSize / TextureSize;
    vec2 p = TEX0.xy / edge;
    if (p.x > 0.5) {
        // player 2's half: turned round about its own middle
        p = vec2(1.5 - p.x, 1.0 - p.y);
    }
    vec3 c = COMPAT_TEXTURE(Texture, p * edge).rgb;
    FragColor = vec4(c * lift, 1.0);
}
#endif
