#include "input.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <linux/input.h>

#ifndef BITS_PER_LONG
#define BITS_PER_LONG (sizeof(long) * 8)
#endif
#ifndef NBITS
#define NBITS(x) ((((x) - 1) / BITS_PER_LONG) + 1)
#endif
#ifndef TEST_BIT
#define TEST_BIT(bit, array) ((array[(bit) / BITS_PER_LONG] & (1UL << ((bit) % BITS_PER_LONG))) != 0)
#endif

static char keycode_to_ascii(uint16_t code, int shift) {
    if (code >= KEY_1 && code <= KEY_9) {
        const char *norm = "123456789";
        const char *shft = "!@#$%^&*(";
        return shift ? shft[code - KEY_1] : norm[code - KEY_1];
    }
    if (code == KEY_0) return shift ? ')' : '0';
    if (code == KEY_MINUS) return shift ? '_' : '-';
    if (code == KEY_EQUAL) return shift ? '+' : '=';
    if (code == KEY_Q) return shift ? 'Q' : 'q';
    if (code == KEY_W) return shift ? 'W' : 'w';
    if (code == KEY_E) return shift ? 'E' : 'e';
    if (code == KEY_R) return shift ? 'R' : 'r';
    if (code == KEY_T) return shift ? 'T' : 't';
    if (code == KEY_Y) return shift ? 'Y' : 'y';
    if (code == KEY_U) return shift ? 'U' : 'u';
    if (code == KEY_I) return shift ? 'I' : 'i';
    if (code == KEY_O) return shift ? 'O' : 'o';
    if (code == KEY_P) return shift ? 'P' : 'p';
    if (code == KEY_A) return shift ? 'A' : 'a';
    if (code == KEY_S) return shift ? 'S' : 's';
    if (code == KEY_D) return shift ? 'D' : 'd';
    if (code == KEY_F) return shift ? 'F' : 'f';
    if (code == KEY_G) return shift ? 'G' : 'g';
    if (code == KEY_H) return shift ? 'H' : 'h';
    if (code == KEY_J) return shift ? 'J' : 'j';
    if (code == KEY_K) return shift ? 'K' : 'k';
    if (code == KEY_L) return shift ? 'L' : 'l';
    if (code == KEY_Z) return shift ? 'Z' : 'z';
    if (code == KEY_X) return shift ? 'X' : 'x';
    if (code == KEY_C) return shift ? 'C' : 'c';
    if (code == KEY_V) return shift ? 'V' : 'v';
    if (code == KEY_B) return shift ? 'B' : 'b';
    if (code == KEY_N) return shift ? 'N' : 'n';
    if (code == KEY_M) return shift ? 'M' : 'm';
    if (code == KEY_ENTER) return '\n';
    if (code == KEY_BACKSPACE) return '\b';
    if (code == KEY_TAB) return '\t';
    if (code == KEY_SPACE) return ' ';
    if (code == KEY_DOT) return shift ? '>' : '.';
    if (code == KEY_COMMA) return shift ? '<' : ',';
    if (code == KEY_SLASH) return shift ? '?' : '/';
    if (code == KEY_SEMICOLON) return shift ? ':' : ';';
    if (code == KEY_APOSTROPHE) return shift ? '"' : '\'';
    return 0;
}

int aweos_input_init(aweos_input_state_t *st, int max_x, int max_y) {
    memset(st, 0, sizeof(*st));
    st->kbd_fd = -1;
    st->mouse_fd = -1;
    st->mouse_x = max_x / 2;
    st->mouse_y = max_y / 2;

    // Discover input devices in /dev/input/
    char path[64];
    for (int i = 0; i < 10; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd >= 0) {
            unsigned long keybit[NBITS(KEY_MAX)] = {0};
            unsigned long relbit[NBITS(REL_MAX)] = {0};
            ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybit)), keybit);
            ioctl(fd, EVIOCGBIT(EV_REL, sizeof(relbit)), relbit);

            if (st->kbd_fd < 0 && (TEST_BIT(KEY_A, keybit) || TEST_BIT(KEY_ENTER, keybit))) {
                st->kbd_fd = fd;
            } else if (st->mouse_fd < 0 && (TEST_BIT(REL_X, relbit) || TEST_BIT(BTN_LEFT, keybit))) {
                st->mouse_fd = fd;
            } else {
                close(fd);
            }
        }
    }

    // Fallback to /dev/input/mice if evdev mouse not found
    if (st->mouse_fd < 0) {
        int mfd = open("/dev/input/mice", O_RDONLY | O_NONBLOCK);
        if (mfd >= 0) st->mouse_fd = mfd;
    }

    return (st->kbd_fd >= 0 || st->mouse_fd >= 0) ? 0 : -1;
}

void aweos_input_close(aweos_input_state_t *st) {
    if (st->kbd_fd >= 0) close(st->kbd_fd);
    if (st->mouse_fd >= 0) close(st->mouse_fd);
    memset(st, 0, sizeof(*st));
}

int aweos_input_poll(aweos_input_state_t *st, aweos_input_event_t *ev, int timeout_ms) {
    memset(ev, 0, sizeof(*ev));
    struct pollfd fds[2];
    int nfds = 0;

    if (st->kbd_fd >= 0) {
        fds[nfds].fd = st->kbd_fd;
        fds[nfds].events = POLLIN;
        nfds++;
    }
    if (st->mouse_fd >= 0) {
        fds[nfds].fd = st->mouse_fd;
        fds[nfds].events = POLLIN;
        nfds++;
    }

    if (nfds == 0) return 0;

    int ret = poll(fds, nfds, timeout_ms);
    if (ret <= 0) return 0;

    struct input_event ie;
    for (int i = 0; i < nfds; i++) {
        if (fds[i].revents & POLLIN) {
            if (fds[i].fd == st->kbd_fd) {
                if (read(st->kbd_fd, &ie, sizeof(ie)) == sizeof(ie)) {
                    if (ie.type == EV_KEY) {
                        if (ie.code == KEY_LEFTSHIFT || ie.code == KEY_RIGHTSHIFT) st->shift_pressed = (ie.value != 0);
                        if (ie.code == KEY_LEFTCTRL || ie.code == KEY_RIGHTCTRL) st->ctrl_pressed = (ie.value != 0);
                        if (ie.code == KEY_LEFTALT || ie.code == KEY_RIGHTALT) st->alt_pressed = (ie.value != 0);

                        ev->type = (ie.value != 0) ? EVENT_KEY_DOWN : EVENT_KEY_UP;
                        ev->keycode = ie.code;
                        ev->ascii = keycode_to_ascii(ie.code, st->shift_pressed);
                        return 1;
                    }
                }
            } else if (fds[i].fd == st->mouse_fd) {
                // Check if reading standard evdev or PS/2 mice
                char read_buf[sizeof(struct input_event)];
                ssize_t nread = read(st->mouse_fd, read_buf, sizeof(read_buf));
                if (nread == sizeof(struct input_event)) {
                    memcpy(&ie, read_buf, sizeof(ie));
                    if (ie.type == EV_REL) {
                        if (ie.code == REL_X) ev->mouse_dx = ie.value;
                        if (ie.code == REL_Y) ev->mouse_dy = ie.value;
                        ev->type = EVENT_MOUSE_MOVE;
                        return 1;
                    } else if (ie.type == EV_KEY) {
                        ev->type = EVENT_MOUSE_BTN;
                        if (ie.code == BTN_LEFT) {
                            if (ie.value) st->mouse_btn |= 1; else st->mouse_btn &= ~1;
                        } else if (ie.code == BTN_RIGHT) {
                            if (ie.value) st->mouse_btn |= 2; else st->mouse_btn &= ~2;
                        }
                        ev->mouse_buttons = st->mouse_btn;
                        return 1;
                    }
                } else if (nread >= 3) {
                    // PS/2 3-byte mouse packet
                    char dx = read_buf[1];
                    char dy = read_buf[2];
                    ev->type = EVENT_MOUSE_MOVE;
                    ev->mouse_dx = dx;
                    ev->mouse_dy = -dy;
                    st->mouse_btn = read_buf[0] & 0x07;
                    ev->mouse_buttons = st->mouse_btn;
                    return 1;
                }
            }
        }
    }
    return 0;
}
