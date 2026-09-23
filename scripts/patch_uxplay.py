#!/usr/bin/env python3
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parent.parent
uxplay = root / "Vendor" / "UxPlay"
patches = Path(__file__).resolve().parent / "patches"

if not uxplay.exists():
    sys.exit("missing UxPlay source")

changed = []

cpp = uxplay / "uxplay.cpp"
text = cpp.read_text()
old_log = """    vprintf(format, vargs);
    printf("\\n");
    va_end(vargs);
}"""
new_log = """    vprintf(format, vargs);
    printf("\\n");
    va_end(vargs);
    fflush(stdout);
}"""
if "fflush(stdout);" not in text and old_log in text:
    text = text.replace(old_log, new_log, 1)
    changed.append("uxplay.cpp logs")

old_main = """int main (int argc, char *argv[]) {
    LOGI("*=== Using gst_macos_main wrapper for GStreamer >= 1.22 on macOS ===*");
"""
new_main = """int main (int argc, char *argv[]) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IOLBF, 0);
    LOGI("*=== Using gst_macos_main wrapper for GStreamer >= 1.22 on macOS ===*");
"""
if "setvbuf(stdout, NULL, _IOLBF, 0);" not in text and old_main in text:
    text = text.replace(old_main, new_main, 1)
    changed.append("uxplay.cpp stdio")

if '#include "renderers/macos_window.h"' not in text:
    needle = '#include "renderers/video_renderer.h"\n'
    if needle not in text:
        sys.exit("uxplay.cpp include marker not found")
    text = text.replace(
        needle,
        needle + """#ifdef __APPLE__
#include "renderers/macos_window.h"
#endif
""",
        1,
    )
    changed.append("uxplay.cpp include")

old_destroy = """extern "C" void conn_destroy (void *cls) {
    //video_renderer_update_background(-1);
    open_connections--;
    LOGD("Open connections: %i", open_connections);
    if (open_connections == 0) {
        remote_clock_offset = 0;
        if (use_audio) {
            audio_renderer_stop();
        }
        if (dacpfile.length()) {
            remove (dacpfile.c_str());
        }
        if (mux_to_file) {
            mux_renderer_stop();
        }
    }
}"""
new_destroy = """extern "C" void conn_destroy (void *cls) {
    //video_renderer_update_background(-1);
    open_connections--;
    LOGD("Open connections: %i", open_connections);
    if (open_connections == 0) {
        remote_clock_offset = 0;
        if (use_audio) {
            audio_renderer_stop();
        }
        if (dacpfile.length()) {
            remove (dacpfile.c_str());
        }
        if (mux_to_file) {
            mux_renderer_stop();
        }
#ifdef __APPLE__
        macos_set_waiting(1);
#endif
    }
}"""
if "macos_set_waiting(1)" not in text:
    if old_destroy not in text:
        sys.exit("conn_destroy marker not found")
    text = text.replace(old_destroy, new_destroy, 1)
    changed.append("conn_destroy")

if "macos_video_bridge_send_end" not in text:
    waiting_only = """#ifdef __APPLE__
        macos_set_waiting(1);
#endif"""
    waiting_and_end = """#ifdef __APPLE__
        macos_set_waiting(1);
        macos_video_bridge_send_end();
#endif"""
    if waiting_only not in text:
        sys.exit("conn_destroy waiting marker not found")
    text = text.replace(waiting_only, waiting_and_end, 1)
    changed.append("conn_destroy end")

cpp.write_text(text)

renderers = uxplay / "renderers"
for name in ("macos_window.h", "macos_window.m"):
    shutil.copy2(patches / name, renderers / name)

cmake = renderers / "CMakeLists.txt"
cmake_text = cmake.read_text()
cmake_snippet = """
if (APPLE)
  target_sources(renderers PRIVATE macos_window.m)
  target_link_libraries(renderers PUBLIC "-framework Cocoa" "-framework Foundation")
  set_source_files_properties(macos_window.m PROPERTIES COMPILE_FLAGS "-fobjc-arc")
endif()
"""
if "macos_window.m" not in cmake_text:
    cmake.write_text(cmake_text.rstrip() + "\n" + cmake_snippet)
    changed.append("CMakeLists.txt")

video = renderers / "video_renderer.c"
video_text = video.read_text()
if '#include "macos_window.h"' not in video_text:
    needle = '#include "video_renderer.h"\n'
    insert = needle + """#ifdef __APPLE__
#include "macos_window.h"
#endif
"""
    if needle not in video_text:
        sys.exit("video_renderer.c include marker not found")
    video_text = video_text.replace(needle, insert, 1)
    changed.append("video_renderer.c include")

old_size = """void video_renderer_size(float *f_width_source, float *f_height_source, float *f_width, float *f_height) {
    width_source = (unsigned short) *f_width_source;
    height_source = (unsigned short) *f_height_source;
    width = (unsigned short) *f_width;
    height = (unsigned short) *f_height;
    logger_log(logger, LOGGER_DEBUG, "begin video stream wxh = %dx%d; source %dx%d", width, height, width_source, height_source);
}"""
new_size = """void video_renderer_size(float *f_width_source, float *f_height_source, float *f_width, float *f_height) {
    width_source = (unsigned short) *f_width_source;
    height_source = (unsigned short) *f_height_source;
    width = (unsigned short) *f_width;
    height = (unsigned short) *f_height;
    logger_log(logger, LOGGER_DEBUG, "begin video stream wxh = %dx%d; source %dx%d", width, height, width_source, height_source);
#ifdef __APPLE__
    {
        int lock_w = width > 0 ? (int) width : (int) width_source;
        int lock_h = height > 0 ? (int) height : (int) height_source;
        if (lock_w > 0 && lock_h > 0) {
            macos_lock_video_window(lock_w, lock_h);
        }
    }
#endif
}"""
if "macos_lock_video_window" not in video_text:
    if old_size not in video_text:
        sys.exit("video_renderer_size marker not found")
    video_text = video_text.replace(old_size, new_size, 1)
    changed.append("video_renderer_size")

if "macos_video_bridge_send_size" not in video_text:
    old_lock = """        if (lock_w > 0 && lock_h > 0) {
            macos_lock_video_window(lock_w, lock_h);
        }"""
    new_lock = """        if (lock_w > 0 && lock_h > 0) {
            if (macos_video_bridge_enabled()) {
                macos_video_bridge_send_size(lock_w, lock_h);
            } else {
                macos_lock_video_window(lock_w, lock_h);
            }
        }"""
    if old_lock not in video_text:
        sys.exit("macos_lock_video_window call marker not found")
    video_text = video_text.replace(old_lock, new_lock, 1)
    changed.append("video_bridge_size")

old_stream = """        if (first_packet) {
            logger_log(logger, LOGGER_INFO, "Begin streaming to GStreamer video pipeline");
            first_packet = false;
#ifdef __APPLE__
            macos_reapply_video_window();
#endif
        }"""
new_stream = """        if (first_packet) {
            logger_log(logger, LOGGER_INFO, "Begin streaming to GStreamer video pipeline");
            first_packet = false;
#ifdef __APPLE__
            macos_set_waiting(0);
            macos_reapply_video_window();
#endif
        }"""
if "macos_set_waiting(0)" not in video_text:
    if old_stream not in video_text:
        old_stream = """        if (first_packet) {
            logger_log(logger, LOGGER_INFO, "Begin streaming to GStreamer video pipeline");
            first_packet = false;
        }"""
        if old_stream not in video_text:
            sys.exit("first_packet marker not found")
    video_text = video_text.replace(old_stream, new_stream, 1)
    changed.append("first_packet")

if "macos_video_bridge_send_packet" not in video_text:
    old_first_done = """        if (first_packet) {
            logger_log(logger, LOGGER_INFO, "Begin streaming to GStreamer video pipeline");
            first_packet = false;
#ifdef __APPLE__
            macos_set_waiting(0);
            macos_reapply_video_window();
#endif
        }
        if (!renderer || !(renderer->appsrc)) {"""
    new_first_done = """        if (first_packet) {
            logger_log(logger, LOGGER_INFO, "Begin streaming to GStreamer video pipeline");
            first_packet = false;
#ifdef __APPLE__
            macos_set_waiting(0);
            macos_reapply_video_window();
#endif
        }
#ifdef __APPLE__
        if (macos_video_bridge_enabled()) {
            int codec = (renderer && renderer->codec && strstr(renderer->codec, "h265")) ? 1 : 0;
            macos_video_bridge_send_packet(data, *data_len, *ntp_time, codec);
        }
#endif
        if (!renderer || !(renderer->appsrc)) {"""
    if old_first_done not in video_text:
        sys.exit("render_buffer first_packet marker not found")
    video_text = video_text.replace(old_first_done, new_first_done, 1)
    changed.append("video_bridge_packet")

if "macos_video_bridge_start();" not in video_text:
    old_logger_assign = "    logger = render_logger;\n"
    new_logger_assign = """    logger = render_logger;
#ifdef __APPLE__
    macos_video_bridge_start();
#endif
"""
    if old_logger_assign not in video_text:
        sys.exit("video_renderer_init logger marker not found")
    video_text = video_text.replace(old_logger_assign, new_logger_assign, 1)
    changed.append("video_bridge_start")

if "macos_video_bridge_enabled() && !jpeg_pipeline" not in video_text:
    old_launch_log = """            logger_log(logger, LOGGER_DEBUG, "GStreamer video pipeline %d:\\n\\"%s\\"", i + 1, launch->str);"""
    new_launch_log = """#ifdef __APPLE__
            if (macos_video_bridge_enabled() && !jpeg_pipeline && !rtp) {
                g_string_assign(launch, "appsrc name=video_source ! queue max-size-buffers=8 leaky=downstream ! fakesink sync=false");
                sync = false;
            }
#endif
            logger_log(logger, LOGGER_DEBUG, "GStreamer video pipeline %d:\\n\\"%s\\"", i + 1, launch->str);"""
    if old_launch_log not in video_text:
        sys.exit("video pipeline launch marker not found")
    video_text = video_text.replace(old_launch_log, new_launch_log, 1)
    changed.append("video_bridge_pipeline")

if "macos_start_watching" not in video_text:
    old_init_end = """            exit(1);
        }
    }
#ifdef __APPLE__
    macos_start_watching();
#endif
}

void video_renderer_pause()"""
    new_init_end = """            exit(1);
        }
    }
#ifdef __APPLE__
    if (!macos_video_bridge_enabled()) {
        macos_start_watching();
    }
#endif
}

void video_renderer_pause()"""
    # Fall through to the unpatched marker below if needed.
    if old_init_end not in video_text:
        old_init_end = """            exit(1);
        }
    }
}

void video_renderer_pause()"""
        new_init_end = """            exit(1);
        }
    }
#ifdef __APPLE__
    if (!macos_video_bridge_enabled()) {
        macos_start_watching();
    }
#endif
}

void video_renderer_pause()"""
    if old_init_end not in video_text:
        sys.exit("video_renderer_init end marker not found")
    video_text = video_text.replace(old_init_end, new_init_end, 1)
    changed.append("video_renderer_init")
elif "if (!macos_video_bridge_enabled())" not in video_text:
    old_watch = """#ifdef __APPLE__
    macos_start_watching();
#endif"""
    new_watch = """#ifdef __APPLE__
    if (!macos_video_bridge_enabled()) {
        macos_start_watching();
    }
#endif"""
    if old_watch not in video_text:
        sys.exit("macos_start_watching marker not found")
    video_text = video_text.replace(old_watch, new_watch, 1)
    changed.append("video_renderer_init bridge")

video.write_text(video_text)

if changed:
    print("patched: " + ", ".join(changed))
else:
    print("uxplay patches already applied")
