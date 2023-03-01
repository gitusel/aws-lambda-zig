const std = @import("std");
const Allocator = std.mem.Allocator;

const aws = @import("aws");
const lambda_runtime = aws.lambda_runtime;
const Runtime = lambda_runtime.Runtime;
const InvocationRequest = lambda_runtime.InvocationRequest;
const InvocationResponse = lambda_runtime.InvocationResponse;

const AWSLOGO_PNG_LEN = 1451;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn binaryResponse(ir: InvocationRequest) !InvocationResponse {
    _ = ir;
    var png: [AWSLOGO_PNG_LEN + 1]u8 = [_]u8{0} ** (AWSLOGO_PNG_LEN + 1);
    var i: usize = 0;
    const awslogoPng_len: usize = awslogoPng.len;
    while (i < awslogoPng_len) : (i += 1) {
        png[i] = awslogoPng[i];
    }
    return try InvocationResponse.success(allocator, png[0..AWSLOGO_PNG_LEN :0], "image/png");
}

pub fn main() !void {
    defer _ = gpa.deinit();
    var runtime = Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.runHandler(binaryResponse);
}

const awslogoPng: [1451]u8 = [1451]u8{
    137, 80,  78,  71,  13,  10,  26,  10,  0,   0,   0,   13,  73,  72,  68,  82,
    0,   0,   0,   24,  0,   0,   0,   14,  8,   6,   0,   0,   0,   53,  248, 220,
    126, 0,   0,   0,   4,   103, 65,  77,  65,  0,   0,   177, 143, 11,  252, 97,
    5,   0,   0,   0,   32,  99,  72,  82,  77,  0,   0,   122, 38,  0,   0,   128,
    132, 0,   0,   250, 0,   0,   0,   128, 232, 0,   0,   117, 48,  0,   0,   234,
    96,  0,   0,   58,  152, 0,   0,   23,  112, 156, 186, 81,  60,  0,   0,   0,
    9,   112, 72,  89,  115, 0,   0,   11,  19,  0,   0,   11,  19,  1,   0,   154,
    156, 24,  0,   0,   1,   89,  105, 84,  88,  116, 88,  77,  76,  58,  99,  111,
    109, 46,  97,  100, 111, 98,  101, 46,  120, 109, 112, 0,   0,   0,   0,   0,
    60,  120, 58,  120, 109, 112, 109, 101, 116, 97,  32,  120, 109, 108, 110, 115,
    58,  120, 61,  34,  97,  100, 111, 98,  101, 58,  110, 115, 58,  109, 101, 116,
    97,  47,  34,  32,  120, 58,  120, 109, 112, 116, 107, 61,  34,  88,  77,  80,
    32,  67,  111, 114, 101, 32,  53,  46,  52,  46,  48,  34,  62,  10,  32,  32,
    32,  60,  114, 100, 102, 58,  82,  68,  70,  32,  120, 109, 108, 110, 115, 58,
    114, 100, 102, 61,  34,  104, 116, 116, 112, 58,  47,  47,  119, 119, 119, 46,
    119, 51,  46,  111, 114, 103, 47,  49,  57,  57,  57,  47,  48,  50,  47,  50,
    50,  45,  114, 100, 102, 45,  115, 121, 110, 116, 97,  120, 45,  110, 115, 35,
    34,  62,  10,  32,  32,  32,  32,  32,  32,  60,  114, 100, 102, 58,  68,  101,
    115, 99,  114, 105, 112, 116, 105, 111, 110, 32,  114, 100, 102, 58,  97,  98,
    111, 117, 116, 61,  34,  34,  10,  32,  32,  32,  32,  32,  32,  32,  32,  32,
    32,  32,  32,  120, 109, 108, 110, 115, 58,  116, 105, 102, 102, 61,  34,  104,
    116, 116, 112, 58,  47,  47,  110, 115, 46,  97,  100, 111, 98,  101, 46,  99,
    111, 109, 47,  116, 105, 102, 102, 47,  49,  46,  48,  47,  34,  62,  10,  32,
    32,  32,  32,  32,  32,  32,  32,  32,  60,  116, 105, 102, 102, 58,  79,  114,
    105, 101, 110, 116, 97,  116, 105, 111, 110, 62,  49,  60,  47,  116, 105, 102,
    102, 58,  79,  114, 105, 101, 110, 116, 97,  116, 105, 111, 110, 62,  10,  32,
    32,  32,  32,  32,  32,  60,  47,  114, 100, 102, 58,  68,  101, 115, 99,  114,
    105, 112, 116, 105, 111, 110, 62,  10,  32,  32,  32,  60,  47,  114, 100, 102,
    58,  82,  68,  70,  62,  10,  60,  47,  120, 58,  120, 109, 112, 109, 101, 116,
    97,  62,  10,  76,  194, 39,  89,  0,   0,   3,   188, 73,  68,  65,  84,  56,
    17,  101, 84,  111, 108, 83,  85,  20,  63,  231, 190, 215, 117, 242, 24,  26,
    36,  196, 193, 32,  10,  107, 39,  27,  163, 133, 164, 146, 41,  93,  187, 37,
    130, 198, 72,  12,  97,  67,  13,  74,  152, 145, 25,  163, 126, 34,  65,  9,
    201, 224, 131, 6,   53,  49,  70,  140, 193, 5,   37,  193, 200, 151, 197, 196,
    56,  208, 132, 96,  82,  186, 45,  104, 208, 108, 101, 86,  177, 171, 58,  112,
    9,   104, 132, 15,  186, 213, 186, 190, 119, 143, 191, 123, 203, 50,  255, 156,
    230, 220, 115, 207, 185, 191, 243, 247, 222, 87,  38,  80,  116, 125, 71,  76,
    116, 240, 42,  182, 43,  136, 105, 33,  107, 26,  213, 37,  111, 7,   121, 51,
    41,  38,  234, 173, 241, 213, 174, 124, 62,  51,  29,  141, 167, 31,  33,  9,
    122, 29,  151, 122, 190, 251, 122, 232, 106, 52,  158, 74,  136, 72,  159, 42,
    7,   143, 5,   97,  167, 67,  49,  189, 110, 226, 9,   209, 52,  43,  181, 175,
    48,  154, 57,  171, 172, 65,  203, 10,  4,   26,  85,  74,  237, 18,  150, 39,
    133, 105, 51,  123, 51,  111, 106, 210, 147, 142, 27,  218, 86,  118, 37,  97,
    113, 162, 119, 134, 106, 189, 7,   252, 10,  221, 91,  13,  164, 119, 67,  198,
    180, 231, 52,  48,  211, 199, 154, 248, 168, 98,  181, 133, 153, 223, 213, 90,
    219, 216, 138, 186, 186, 156, 137, 92,  230, 84,  33,  151, 125, 169, 254, 86,
    26,  43,  142, 14,  157, 67,  9,   111, 160, 138, 206, 31,  115, 195, 133, 192,
    175, 20,  29,  210, 105, 19,  16,  180, 116, 182, 92,  186, 64,  196, 73,  171,
    9,   167, 68,  232, 152, 47,  126, 201, 113, 92,  86,  34,  55,  46,  141, 101,
    38,  11,  99,  231, 250, 139, 185, 236, 25,  19,  27,  133, 99,  68,  173, 155,
    86,  145, 82,  199, 16,  180, 1,   234, 21,  200, 22,  28,  92,  157, 200, 101,
    55,  68,  226, 201, 119, 136, 84,  132, 57,  216, 43,  90,  29,  17,  146, 126,
    38,  222, 163, 197, 223, 174, 216, 45,  144, 166, 173, 19,  227, 217, 108, 52,
    150, 60,  36,  196, 7,   224, 255, 59,  248, 116, 197, 87,  123, 39,  243, 153,
    107, 182, 13,  173, 212, 9,   77,  180, 68,  9,   109, 145, 25,  239, 33,  98,
    62,  5,   80,  24,  76,  28,  168, 65,  18,  105, 208, 226, 236, 64,  224, 203,
    97,  223, 255, 20,  35,  88,  192, 236, 246, 224, 248, 103, 249, 211, 251, 210,
    224, 10,  185, 161, 62,  220, 213, 114, 140, 247, 57,  168, 247, 135, 66,  242,
    129, 177, 219, 4,   168, 118, 13,  120, 228, 251, 139, 217, 159, 138, 197, 207,
    254, 130, 113, 61,  186, 88,  108, 0,   33,  189, 244, 115, 136, 50,  139, 236,
    67,  245, 195, 249, 252, 249, 27,  184, 216, 235, 192, 191, 12,  62,  109, 240,
    209, 88,  231, 242, 166, 117, 237, 119, 225, 33,  92,  43,  142, 101, 63,  12,
    132, 78,  106, 45,  235, 140, 191, 107, 22,  18,  62,  140, 84,  175, 69,  98,
    237, 27,  240, 138, 202, 152, 235, 56,  156, 23,  71,  91,  211, 119, 231, 199,
    7,   46,  193, 158, 85,  202, 137, 251, 129, 140, 84,  241, 116, 193, 9,   133,
    54,  87,  130, 202, 39,  85,  247, 160, 25,  5,   29,  143, 196, 146, 83,  11,
    28,  246, 106, 88,  86,  223, 30,  166, 158, 31,  44,  248, 230, 146, 72,  164,
    18,  43,  215, 38,  119, 154, 74,  140, 233, 206, 150, 244, 29,  16,  182, 195,
    166, 166, 251, 234, 26,  215, 118, 174, 158, 211, 27,  27,  55,  46,  90,  21,
    111, 143, 64,  71,  29,  85,  90,  3,   189, 161, 181, 253, 113, 162, 142, 109,
    68,  79,  120, 115, 118, 70,  102, 188, 48,  243, 116, 231, 233, 224, 65,  82,
    96,  92,  139, 37,  19,  228, 159, 231, 255, 213, 111, 194, 170, 66,  190, 162,
    122, 26,  167, 182, 160, 28,  242, 28,  174, 124, 193, 114, 148, 158, 197, 209,
    52,  63,  67,  39,  230, 144, 130, 4,   223, 82,  139, 219, 76,  121, 147, 196,
    38,  234, 206, 119, 241, 192, 192, 64,  96,  48,  24,  33,  31,  234, 72,  59,
    125, 233, 140, 166, 102, 219, 133, 195, 221, 52,  91,  122, 187, 174, 45,  228,
    150, 183, 43,  10,  28,  197, 250, 97,  64,  103, 88,  222, 162, 69,  120, 47,
    175, 64,  217, 8,   54,  55,  127, 146, 123, 233, 55,  200, 255, 145, 73,  108,
    141, 125, 184, 53,  254, 87,  87,  214, 140, 88,  97,  170, 165, 110, 148, 116,
    25,  134, 133, 224, 23,  77,  187, 150, 164, 159, 182, 194, 197, 124, 234, 102,
    214, 195, 224, 65,  212, 118, 30,  207, 96,  130, 174, 208, 117, 158, 31,  153,
    197, 155, 69,  222, 163, 58,  10,  104, 37,  2,   222, 3,   236, 131, 48,  181,
    33,  198, 20,  228, 83,  40,  229, 121, 236, 191, 97,  91,  21,  218, 68,  139,
    213, 246, 251, 233, 81,  28,  188, 128, 192, 109, 246, 75,  40,  153, 72,  244,
    11,  214, 95,  193, 127, 128, 205, 200, 110, 1,   47,  1,   215, 83,  13,  126,
    179, 214, 54,  132, 36,  71,  120, 15,  125, 132, 152, 46,  45,  163, 253, 116,
    27,  29,  158, 239, 0,   70,  84,  233, 195, 201, 146, 188, 143, 63,  190, 89,
    74,  193, 105, 19,  12,  45,  72,  178, 12,  123, 211, 182, 185, 240, 105, 240,
    20,  118, 23,  33,  71,  200, 161, 12,  63,  109, 139, 128, 10,  192, 113, 170,
    229, 221, 84,  54,  251, 191, 1,   2,   157, 112, 116, 205, 42,  3,   21,  0,
    0,   0,   0,   73,  69,  78,  68,  174, 66,  96,  130,
};
