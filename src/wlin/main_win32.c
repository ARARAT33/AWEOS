#include "wlin.h"
#include "../core/logging.h"
#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#include <windows.h>

static wlin_state_t g_wlin_st;
static HWND g_hwnd_status;
static HWND g_hwnd_iso;

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            CreateWindow("STATIC", "WLIN AWEOS Migration & Installation Tool (Windows Native)",
                         WS_CHILD | WS_VISIBLE, 20, 20, 500, 20, hwnd, NULL, NULL, NULL);

            CreateWindow("STATIC", "Selected AWEOS ISO Image:",
                         WS_CHILD | WS_VISIBLE, 20, 60, 200, 20, hwnd, NULL, NULL, NULL);

            g_hwnd_iso = CreateWindow("EDIT", "AWEOS-x86_64.iso",
                                      WS_CHILD | WS_VISIBLE | WS_BORDER, 200, 60, 300, 24, hwnd, (HMENU)101, NULL, NULL);

            CreateWindow("BUTTON", "Validate ISO & Detect Disks",
                         WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 20, 100, 220, 32, hwnd, (HMENU)102, NULL, NULL);

            CreateWindow("BUTTON", "Stage USB-less Install & Reboot",
                         WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 260, 100, 240, 32, hwnd, (HMENU)103, NULL, NULL);

            g_hwnd_status = CreateWindow("STATIC", "Status: Ready to initialize...",
                                         WS_CHILD | WS_VISIBLE, 20, 160, 500, 60, hwnd, NULL, NULL, NULL);
            break;
        }
        case WM_COMMAND: {
            if (LOWORD(wParam) == 102) {
                char path[256] = "AWEOS-x86_64.iso";
                GetWindowText(g_hwnd_iso, path, sizeof(path));
                if (wlin_init(&g_wlin_st, path) == AWEOS_OK) {
                    char buf[256];
                    snprintf(buf, sizeof(buf), "Status: Valid ISO (v%s). Discovered %d disk(s). Boot mode: %s",
                             g_wlin_st.manifest.version, g_wlin_st.storage.disk_count,
                             g_wlin_st.boot_mode == BOOT_MODE_UEFI ? "UEFI" : "BIOS");
                    SetWindowText(g_hwnd_status, buf);
                } else {
                    SetWindowText(g_hwnd_status, "Status: ISO Validation Failed!");
                }
            } else if (LOWORD(wParam) == 103) {
                if (wlin_execute(&g_wlin_st) == AWEOS_OK) {
                    SetWindowText(g_hwnd_status, "Status: Offline Boot Staging Complete! Ready to reboot.");
                    MessageBox(hwnd, "AWEOS offline boot staging complete!\nYour system is configured to boot into AWEOS Installer.",
                               "WLIN Migration Ready", MB_OK | MB_ICONINFORMATION);
                } else {
                    SetWindowText(g_hwnd_status, "Status: Staging / Execution Failed!");
                }
            }
            break;
        }
        case WM_DESTROY:
            PostQuitMessage(0);
            break;
        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
    }
    return 0;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance; (void)lpCmdLine;
    WNDCLASS wc = {0};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "WLINWin32Class";

    RegisterClass(&wc);

    HWND hwnd = CreateWindow("WLINWin32Class", "WLIN AWEOS Windows Installer",
                             WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                             CW_USEDEFAULT, CW_USEDEFAULT, 560, 280, NULL, NULL, hInstance, NULL);

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    return (int)msg.wParam;
}
#endif

int main(int argc, char *argv[]) {
    LOGI("WLIN Cross-OS Installation Tool v1.0.0 (Windows Native Core)");

    const char *iso_path = (argc >= 2) ? argv[1] : "AWEOS-x86_64.iso";
    wlin_state_t st;
    if (wlin_init(&st, iso_path) != AWEOS_OK) {
        fprintf(stderr, "WLIN Win32 initialization failed for %s\n", iso_path);
        return 1;
    }

    if (wlin_execute(&st) != AWEOS_OK) {
        fprintf(stderr, "WLIN Win32 execution failed!\n");
        return 1;
    }

    printf("WLIN Win32 installation & staging completed successfully!\n");
    return 0;
}
