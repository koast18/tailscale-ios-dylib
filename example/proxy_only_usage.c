/*
 * Minimal example of using the proxy-only embedded Tailscale C API.
 *
 * Build against the header and dylib/static lib produced by this repo.
 */
#include <stdio.h>
#include <string.h>

#include "tailscale.h"

int main(void) {
    tailscale sd = tailscale_new();
    if (sd < 0) {
        fprintf(stderr, "tailscale_new failed\n");
        return 1;
    }

    /* Base node settings. */
    tailscale_set_dir(sd, "./tailscale-state");
    tailscale_set_hostname(sd, "ios-proxy-node");
    tailscale_set_authkey(sd, getenv("TS_AUTHKEY") ? getenv("TS_AUTHKEY") : "");
    tailscale_set_control_url(sd, "https://control.tailscale.com");

    /* Proxy-only / DERP-only mode. */
    tailscale_set_disable_p2p(sd, 1);
    tailscale_set_proxy(sd, getenv("HTTP_PROXY") ? getenv("HTTP_PROXY") : "http://127.0.0.1:8888");

    if (tailscale_up(sd) != 0) {
        char err[1024];
        tailscale_errmsg(sd, err, sizeof(err));
        fprintf(stderr, "up failed: %s\n", err);
        tailscale_close(sd);
        return 1;
    }

    char buf[65536];
    if (tailscale_get_status_json(sd, buf, sizeof(buf)) == 0) {
        puts(buf);
    }

    tailscale_close(sd);
    return 0;
}
