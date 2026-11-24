#!/bin/sh
# video_probe.sh — 一条命令判断「这个视频 iOS 能不能播」，用于定位黑屏
#
# 用法：
#   ./video_probe.sh /path/to/a.mkv
#   ./video_probe.sh "http://192.168.1.10:5666/xx/a.mp4" "user:password"
#
# 输出：容器 / 视频轨 / 音频轨 / 传输 / 结论（PASS、WARN、FAIL）
# 退出码：0 = 没有阻断项；1 = 有阻断项（基本可以确定黑屏原因）；2 = 文件读不到
#
# 依赖：ffprobe（macOS: brew install ffmpeg；飞牛 NAS 一般自带 ffmpeg）

SRC="$1"
AUTH="$2"
B64=""

if [ -z "$SRC" ]; then
    echo "用法: $0 <本地文件|http(s)地址> [user:password]"
    exit 2
fi
if ! command -v ffprobe >/dev/null 2>&1; then
    echo "缺少 ffprobe。macOS: brew install ffmpeg；或在飞牛 NAS 的 SSH 里直接跑本脚本。"
    exit 2
fi
if [ -n "$AUTH" ]; then
    B64=$(printf '%s' "$AUTH" | base64 | tr -d '\n')
fi

PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
warn() { WARN=$((WARN + 1)); printf '  [WARN] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; }

# ffprobe 三种调用（带/不带认证头），避免把含空格的 header 拼进变量被分词
probe_v() {
    if [ -n "$B64" ]; then
        ffprobe -headers "Authorization: Basic $B64" -rw_timeout 15000000 -v error \
            -select_streams v:0 -show_entries stream=codec_name,codec_tag_string,profile,level,pix_fmt,width,height,avg_frame_rate,nb_frames,duration -of default=nw=1 "$SRC" 2>/dev/null
    else
        ffprobe -rw_timeout 15000000 -v error \
            -select_streams v:0 -show_entries stream=codec_name,codec_tag_string,profile,level,pix_fmt,width,height,avg_frame_rate,nb_frames,duration -of default=nw=1 "$SRC" 2>/dev/null
    fi
}
probe_a() {
    if [ -n "$B64" ]; then
        ffprobe -headers "Authorization: Basic $B64" -rw_timeout 15000000 -v error \
            -select_streams a:0 -show_entries stream=codec_name,channels,sample_rate,profile -of default=nw=1 "$SRC" 2>/dev/null
    else
        ffprobe -rw_timeout 15000000 -v error \
            -select_streams a:0 -show_entries stream=codec_name,channels,sample_rate,profile -of default=nw=1 "$SRC" 2>/dev/null
    fi
}
probe_f() {
    if [ -n "$B64" ]; then
        ffprobe -headers "Authorization: Basic $B64" -rw_timeout 15000000 -v error \
            -show_entries format=format_name,format_long_name,duration,size,bit_rate:format_tags=major_brand -of default=nw=1 "$SRC" 2>/dev/null
    else
        ffprobe -rw_timeout 15000000 -v error \
            -show_entries format=format_name,format_long_name,duration,size,bit_rate:format_tags=major_brand -of default=nw=1 "$SRC" 2>/dev/null
    fi
}

get() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

V=$(probe_v); A=$(probe_a); F=$(probe_f)

V_CODEC=$(get "$V" codec_name)
V_TAG=$(get "$V" codec_tag_string)
V_PROFILE=$(get "$V" profile)
V_PIX=$(get "$V" pix_fmt)
V_W=$(get "$V" width)
V_H=$(get "$V" height)
V_FPS=$(get "$V" avg_frame_rate)
V_FRAMES=$(get "$V" nb_frames)
A_CODEC=$(get "$A" codec_name)
A_CH=$(get "$A" channels)
F_NAME=$(get "$F" format_name)
F_LONG=$(get "$F" format_long_name)
F_DUR=$(get "$F" duration)
F_SIZE=$(get "$F" size)
F_BRAND=$(get "$F" "TAG:major_brand")

if [ -z "$F_NAME" ] && [ -z "$V_CODEC" ]; then
    echo "读不到媒体信息：文件损坏、被截断，或地址/认证失败。"
    case "$SRC" in
        http://*|https://*)
            if command -v curl >/dev/null 2>&1; then
                if [ -n "$AUTH" ]; then
                    R=$(curl -sS -o /dev/null -m 15 -r 0-1023 -u "$AUTH" \
                        -w "HTTP %{http_code} · %{content_type} · 重定向 %{redirect_url}" "$SRC" 2>&1)
                else
                    R=$(curl -sS -o /dev/null -m 15 -r 0-1023 \
                        -w "HTTP %{http_code} · %{content_type} · 重定向 %{redirect_url}" "$SRC" 2>&1)
                fi
                echo "HTTP 探测：$R"
                echo "→ 401/403 = 认证头没送到或账号错；404 = 路径或中文名编码问题；200/206 但读不到 = 不是可识别的视频容器"
            fi
            ;;
        *)
            echo "→ 本地文件：看大小是否 0 或明显偏小；用「文件」App 里 QuickLook 预览一下能否出画面"
            ;;
    esac
    exit 2
fi

echo "============================================================"
echo " 目标：$SRC"
echo "============================================================"

echo
echo "【容器】"
echo "  format : ${F_NAME:-未知}"
echo "  说明   : ${F_LONG:-未知}"
echo "  品牌   : ${F_BRAND:-—}"
echo "  大小   : ${F_SIZE:-未知} 字节"
echo "  时长   : ${F_DUR:-未知} 秒"
case "$F_NAME" in
    *mp4*|*mov*|*3gp*|*3g2*|*m4a*|*m4v*)
        case "$F_BRAND" in
            3gp4|3gp5|3gp6|3g2a) warn "3GP 容器：AVFoundation 支持不完整，可能只有画面无声音" ;;
            *) pass "MP4/MOV 家族容器，iOS 原生支持" ;;
        esac
        ;;
    *matroska*|*webm*) fail "Matroska/WebM 容器：iOS 播放器完全不支持 → 必然黑屏" ;;
    *avi*)             fail "AVI 容器：iOS 播放器不支持 → 必然黑屏" ;;
    *flv*)             fail "FLV 容器：iOS 播放器不支持 → 必然黑屏" ;;
    *mpegts*)          fail "MPEG-TS 容器：iOS 播放器不支持（.ts/.m2ts）→ 黑屏" ;;
    *asf*)             fail "ASF/WMV 容器：iOS 播放器不支持 → 黑屏" ;;
    *rm*)              fail "RealMedia 容器：iOS 播放器不支持 → 黑屏" ;;
    *ogg*)             fail "Ogg 容器：iOS 播放器不支持 → 黑屏" ;;
    *mpeg*)            fail "MPEG-PS 容器（.mpg/.vob）：iOS 播放器不支持 → 黑屏" ;;
    *)                 warn "未识别的容器：$F_NAME，建议转成 mp4" ;;
esac

echo
echo "【视频轨】"
echo "  编码   : ${V_CODEC:-无视频轨}"
echo "  封装标记: ${V_TAG:-—}（Apple 对 hev1/hvc1 敏感）"
echo "  profile: ${V_PROFILE:-—}"
echo "  像素格式: ${V_PIX:-—}"
echo "  分辨率 : ${V_W:-?}x${V_H:-?}"
echo "  帧率   : ${V_FPS:-—}"
echo "  帧数   : ${V_FRAMES:-—}"
case "$V_CODEC" in
    h264)
        case "$V_PROFILE" in
            *"4:2:2"*|*"4:4:4"*|*"High 10"*|*"High 4:2:2"*|*"High 4:4:4"*)
                fail "H.264 profile 为 $V_PROFILE：iOS 只支持 8bit 4:2:0 → 黑屏" ;;
            *) pass "H.264 8bit，iOS 硬解支持" ;;
        esac
        case "$V_PIX" in
            yuv420p|yuvj420p|nv12) : ;;
            "") : ;;
            *) fail "像素格式 $V_PIX：iOS 只吃 yuv420p/nv12 → 常见于转换失败的片子" ;;
        esac
        case "$V_TAG" in
            avc3) warn "标记 avc3（参数集在带内）：多数机型能播，个别黑屏；remux 成 avc1 即可" ;;
        esac
        ;;
    hevc)
        if [ "$V_TAG" = "hev1" ]; then
            fail "HEVC 标记为 hev1：Apple 只认 hvc1 → 典型「有声音、画面全黑」，可无损修复"
        else
            case "$V_PROFILE" in
                *"Main 10"*|Main) pass "HEVC ${V_PROFILE}：iPhone 7 以上硬解支持" ;;
                *) warn "HEVC profile 为 $V_PROFILE：非常规 profile 可能不解码" ;;
            esac
        fi
        ;;
    av1)        warn "AV1：只有 A17 Pro / M3 及更新机型有硬解，其余机型黑屏" ;;
    vp8|vp9)    fail "VP8/VP9：iOS 播放器不支持（Safari 可解但 AVPlayer 不行）→ 黑屏" ;;
    vc1|wmv3|wmv2|msmpeg4v3|msmpeg4v2) fail "$V_CODEC：Windows Media 系编码，iOS 不支持 → 黑屏" ;;
    mpeg2video|mpeg1video) fail "MPEG-1/2 视频：iOS 播放器不支持 → 黑屏" ;;
    rv40|rv30|rv20) fail "RealVideo：iOS 不支持 → 黑屏" ;;
    theora)     fail "Theora：iOS 不支持 → 黑屏" ;;
    mpeg4)      warn "MPEG-4 Part 2（Xvid/DivX 同族）：iOS 支持很不稳定，多半黑屏" ;;
    prores)     pass "ProRes：iOS 支持" ;;
    mjpeg)      warn "MJPEG：部分容器可播，多数黑屏" ;;
    "")         fail "没有视频轨：只有音频，界面会是纯黑（音频仍可播）" ;;
    *)          warn "编码 $V_CODEC：不在已知支持列表，大概率黑屏" ;;
esac
case "$V_W" in ""|0) fail "分辨率宽度为 0：文件损坏或没下完" ;; esac
if [ -n "$V_W" ] && [ -n "$V_H" ]; then
    if [ "$V_W" -gt 4096 ] 2>/dev/null || [ "$V_H" -gt 4096 ] 2>/dev/null; then
        warn "分辨率 ${V_W}x${V_H} 超过 4096：可能超出机型解码上限（画面黑、声音正常）"
    fi
fi

echo
echo "【音频轨】"
if [ -z "$A_CODEC" ]; then
    warn "没有音频轨（画面能出，但全程静音）"
else
    echo "  编码   : $A_CODEC  ${A_CH:-?} 声道"
    case "$A_CODEC" in
        aac|mp3|alac|flac|ac3|eac3|pcm_s16le|pcm_s24le|pcm_f32le|pcm_s16be)
            pass "音频 $A_CODEC：iOS 支持" ;;
        opus)   warn "Opus：仅部分容器/系统版本支持，可能静音" ;;
        dts|truehd|vorbis|wmav1|wmav2|wmapro)
            fail "音频 $A_CODEC：iOS 无解码器，常导致整条失败（黑屏 + 无声）" ;;
        *)      warn "音频 $A_CODEC：未验证，可能静音" ;;
    esac
fi

echo
echo "【时长/完整性】"
case "$F_DUR" in
    ""|N/A|0|0.0) fail "读不到时长：moov 缺失或文件截断（下载没下完、拷贝中断）" ;;
    *) case "$V_FRAMES" in
           0) warn "时长有但帧数为 0：索引损坏，可能播到一半黑" ;;
           *) pass "时长 ${F_DUR}s，索引可读" ;;
       esac ;;
esac

# 索引说"有时长"不等于数据齐全（moov 在头时截断文件照样能读出时长）。
# 用 copy 不解码地全量读一遍，能暴露 "partial file"。
if [ -f "$SRC" ] && command -v ffmpeg >/dev/null 2>&1; then
    SZ2=$(wc -c < "$SRC" | tr -d ' ')
    if [ "$SZ2" -lt 1610612736 ]; then
        echo
        echo "【数据完整性】"
        OUT=$(ffmpeg -v error -i "$SRC" -map 0:v? -map 0:a? -c copy -f null - 2>&1 | head -3)
        if [ -n "$OUT" ]; then
            fail "读到不完整数据：$(printf '%s' "$OUT" | head -1)"
            echo "        常见于「没下完 / 拷贝或上传中断」→ 重新拷一份再试"
        else
            pass "全量读取无报错，文件不残缺"
        fi
    fi
fi

# moov 位置：只对本地 mp4/mov 家族检查（远端跳过）
if [ -f "$SRC" ]; then
    case "$F_NAME" in
        *mp4*|*mov*|*m4v*)
            HEAD_TMP=$(mktemp); TAIL_TMP=$(mktemp)
            dd if="$SRC" of="$HEAD_TMP" bs=1048576 count=4 2>/dev/null
            SZ=$(wc -c < "$SRC" | tr -d ' ')
            if [ "$SZ" -gt 4194304 ]; then
                SKIP=$((SZ / 1048576 - 4))
                dd if="$SRC" of="$TAIL_TMP" bs=1048576 skip="$SKIP" 2>/dev/null
            fi
            H_MOOV=$(LC_ALL=C grep -abo moov "$HEAD_TMP" 2>/dev/null | head -1 | cut -d: -f1)
            H_MDAT=$(LC_ALL=C grep -abo mdat "$HEAD_TMP" 2>/dev/null | head -1 | cut -d: -f1)
            T_MOOV=$(LC_ALL=C grep -abo moov "$TAIL_TMP" 2>/dev/null | head -1 | cut -d: -f1)
            rm -f "$HEAD_TMP" "$TAIL_TMP"
            echo
            echo "【索引位置】"
            if [ -n "$H_MOOV" ]; then
                pass "moov 在文件头（已 faststart）：边下边播没问题"
            elif [ -n "$T_MOOV" ]; then
                warn "moov 在文件尾部：本地能播；NAS 远端会先拉整段才出画面，大文件长时间黑屏属正常但很难用"
            else
                warn "没找到 moov：文件可能截断或不是标准 mp4"
            fi
            ;;
    esac
fi

# 远端：顺带做一次 HTTP 能力探测
case "$SRC" in
    http://*|https://*)
        echo
        echo "【HTTP 传输】"
        if command -v curl >/dev/null 2>&1; then
            if [ -n "$AUTH" ]; then
                CODE=$(curl -sS -o /dev/null -m 15 -r 0-1023 -u "$AUTH" \
                    -w "%{http_code} %{content_type} %{size_download} %{redirect_url}" "$SRC" 2>/dev/null)
            else
                CODE=$(curl -sS -o /dev/null -m 15 -r 0-1023 \
                    -w "%{http_code} %{content_type} %{size_download} %{redirect_url}" "$SRC" 2>/dev/null)
            fi
            echo "  探测结果: $CODE"
            set -- $CODE
            case "$1" in
                206) pass "支持 Range 分段请求（AVPlayer 边下边播正常）" ;;
                200) warn "不支持 Range，返回 200：AVPlayer 要整段下载，大文件会长时间黑屏" ;;
                301|302|307|308) warn "地址被重定向：认证头在跳转后可能丢失 → 401 黑屏" ;;
                401|403) fail "认证失败（$1）：认证头没送到，或账号/密码不对" ;;
                404) fail "文件不存在（404）：路径或文件名编码有问题" ;;
                000) fail "连不上：地址/端口/网络不通" ;;
                *) warn "HTTP 状态 $1，需进一步确认" ;;
            esac
        fi
        ;;
esac

echo
echo "============================================================"
if [ "$FAIL" -gt 0 ]; then
    echo " 结论：发现 $FAIL 个阻断项、$WARN 个风险项 → 黑屏原因基本可确定"
    if [ "$V_TAG" = "hev1" ]; then
        echo " 无损修复（不重新编码，几秒完成，画质音量不变）："
        echo "   ffmpeg -i \"input.mp4\" -map 0 -c copy -tag:v hvc1 -movflags +faststart \"output.mp4\""
    else
        echo " 建议转码（在电脑或 NAS 上执行）："
        echo "   ffmpeg -i \"input\" -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 20 \\"
        echo "          -preset medium -c:a aac -b:a 128k -movflags +faststart \"output.mp4\""
    fi
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo " 结论：$WARN 个风险项，无硬阻断 → 黑屏更可能是传输或渲染层问题，见排查手册第 4、5 步"
    exit 0
else
    echo " 结论：全部通过 → 这个文件 iOS 能播，黑屏问题在 App 侧（传输头/渲染层），见手册第 4、5 步"
    exit 0
fi
