# ProxyClientGui

FMX GUI demo for comparing direct and proxy traffic.

Configure the first five fields as `proxy type`, `host`, `port`, `user`, and
`password`. Supported types are `direct`, `http`, `https`, `socks4`, and
`socks5`.

The buttons demonstrate:

- Google HTTPS GET
- Standard DNS-over-TCP lookup for `github.com`: direct via `223.5.5.5`, or through SOCKS5 via `8.8.8.8`
- The `IPv4/IPv6` button toggles the configured proxy host between `127.0.0.1` and `::1`; every proxy test uses the selected host.
- OS IPv4/IPv6 address resolution for `github.com`
- WebSocket echo, direct and through the selected proxy

The IPv4/IPv6 button intentionally reports OS `GetAddrInfo` results. The
Cross Socket HTTP/DoH/WebSocket paths use the selected proxy; DoH proxy mode is
The proxy DNS test currently uses SOCKS5 TCP CONNECT to the configured DNS server. It does not use an online DoH service.

IPv6 proxy verification requires the local proxy to listen on `::1`. The current v2ray listener must be configured for IPv6 separately; the observed `10808` listener was IPv4-only.
