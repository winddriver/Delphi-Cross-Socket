# ProxyClient demo

This console demo validates the enhanced `TCrossProxySettings` path against the
proxy shown in the v2rayN screenshot (`127.0.0.1:10808` is the default local
SOCKS listener).

The first argument selects the application protocol:

* `http`: HTTPS GET of `https://www.google.com/` (TCP + TLS)
* `doh`: DNS-over-HTTPS GET through the selected proxy (DNS over HTTP(S))
* `ws`: secure WebSocket echo connection (TCP + TLS + WebSocket)
* `udp`: UDP DNS probe to `8.8.8.8:53`; this requires v2rayN UDP/TUN routing

The second argument is `direct`, `http`, `https`, `socks4`, or `socks5`; the
remaining arguments are proxy host, port, optional username, and password.

Examples:

```text
ProxyClient http socks5 127.0.0.1 10808
ProxyClient doh socks5 127.0.0.1 10808
ProxyClient ws socks5 127.0.0.1 10808
  ProxyClient udp socks5 127.0.0.1 10808
```

The HTTP and WebSocket paths use the Cross Socket proxy API. The `udp` mode
implements a SOCKS5 UDP ASSOCIATE probe in the Demo itself (IPv4 relay and
no-authentication method), so it validates the UDP capability of the local
SOCKS5 listener shown in the screenshot. `doh` validates DNS over the selected
HTTP/TCP or SOCKS/TCP stream.
