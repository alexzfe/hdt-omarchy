/*
 * hdt-xerror-shim: keep Wine alive across unexpected X11 protocol errors.
 *
 * Proton's Wine (winex11.drv/mouse.c, update_device_mapping) queries the XInput 1
 * button mapping of the pointer slave device that last sent an event. Under XWayland
 * that device may have just been *disabled* (the compositor dropped the seat's pointer
 * capability, e.g. a touchpad toggle or a mouse going away). XOpenDevice accepts a
 * disabled device but X_GetDeviceButtonMapping answers XI_BadDevice. Wine's error
 * handler passes unexpected errors to Xlib's default handler, which prints
 * "X Error of failed request" and calls exit(1), taking the whole app down.
 *
 * Wine remembers the handler that XSetErrorHandler() returns as its fallback. This
 * shim wraps XSetErrorHandler so that, whenever Xlib's exiting default would be
 * returned, a logging, non-fatal handler is returned instead. Errors Wine already
 * expects or ignores are unaffected.
 *
 * Load with LD_PRELOAD (see launch-hdt). Built by linux/install.sh.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <sched.h>
#include <stdio.h>
#include <X11/Xlib.h>

typedef int (*handler_t)(Display *, XErrorEvent *);
typedef handler_t (*set_handler_t)(handler_t);

static set_handler_t real_set_handler;
static handler_t xlib_default;

static int tolerant_handler(Display *display, XErrorEvent *e)
{
	char text[256] = "";
	XGetErrorText(display, e->error_code, text, sizeof(text));
	fprintf(stderr, "hdt-xerror-shim: ignoring X error %d (%s) request %d.%d resource 0x%lx\n",
		e->error_code, text, e->request_code, e->minor_code, e->resourceid);
	return 0;
}

/* First-call initialisation, safe when several threads call XSetErrorHandler at once:
 * one thread resolves the real function and learns Xlib's default handler, the others wait.
 * Plain atomics only, so the shim needs nothing beyond libc inside the Steam runtime. */
static volatile int init_state; /* 0 = not started, 1 = in progress, 2 = done */

static void init_once(void)
{
	int expected = 0;
	if(__atomic_load_n(&init_state, __ATOMIC_ACQUIRE) == 2)
		return;
	if(!__atomic_compare_exchange_n(&init_state, &expected, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
	{
		while(__atomic_load_n(&init_state, __ATOMIC_ACQUIRE) != 2)
			sched_yield();
		return;
	}
	/* libX11 is not necessarily in the global scope (Wine dlopens winex11.so),
	 * so resolve it through the library itself rather than RTLD_NEXT. */
	void *libx11 = dlopen("libX11.so.6", RTLD_NOW | RTLD_NOLOAD);
	if(libx11)
		real_set_handler = (set_handler_t)dlsym(libx11, "XSetErrorHandler");
	if(!real_set_handler)
		real_set_handler = (set_handler_t)dlsym(RTLD_NEXT, "XSetErrorHandler");
	if(real_set_handler)
	{
		/* Learn Xlib's default handler without disturbing any handler already set:
		 * setting NULL selects the default, and the next call returns it. */
		handler_t current = real_set_handler(NULL);
		xlib_default = real_set_handler(current);
		if(current == xlib_default)
			real_set_handler(NULL);
		fprintf(stderr, "hdt-xerror-shim: active\n");
	}
	else
		fprintf(stderr, "hdt-xerror-shim: cannot find XSetErrorHandler\n");
	__atomic_store_n(&init_state, 2, __ATOMIC_RELEASE);
}

handler_t XSetErrorHandler(handler_t handler)
{
	init_once();
	if(!real_set_handler)
		return NULL;
	handler_t previous = real_set_handler(handler);
	if(previous == xlib_default)
		previous = tolerant_handler;
	return previous;
}
