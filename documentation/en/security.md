# Security & remote access

Firewall, reverse proxy with login/MFA, and what may face the internet.

[← Back to overview](../../README-en.md) &nbsp;|&nbsp; [Deutsche Fassung](../de/sicherheit.md)

**Documentation:** [Installation & getting started](installation.md) · [Architecture & services](architecture.md) · [Tools for the LLM (MCP)](tools.md) · [Code sandbox](code-sandbox.md) · [Android development](android.md) · [Knowledge base (vault)](knowledge-base.md) · [Managing models](models.md) · [Operations & maintenance](operations.md) · **Security & remote access** · [Other stacks](other-stacks.md)

---

## Internet-facing deployments

By default, all services listen over plain HTTP. For internet-facing deployments, use the included Caddy overlay to add automatic HTTPS. In proxy mode, Caddy is the only public listener on ports `80` and `443`; the direct AnythingLLM and LiteLLM ports are rebound to `127.0.0.1`.

Prerequisites:

- Docker Compose `2.24.4+` (required for the proxy overlay's port override)
- A DNS `A`/`AAAA` record for your domain pointing to this server
- Inbound `80/tcp`, `443/tcp`, and ideally `443/udp` open in your firewall/security group
- No other service already using ports `80` or `443` on the host

**CPU stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

**CUDA stack:**

```bash
DOMAIN=chat.example.com ACME_EMAIL=you@example.com \
  docker compose -f docker-compose.cuda.yml -f docker-compose.proxy.yml up -d
```

Open `https://chat.example.com` (replace with your `DOMAIN`) to access AnythingLLM. In proxy mode, `http://127.0.0.1:3001` and `http://127.0.0.1:4000/ui` remain available on the host, but the direct `3001` and `4000` ports are not reachable from outside the server.

The standard compose files publish LiteLLM on port `4000`. The proxy overlay changes that direct port to localhost-only, and the included Caddyfile routes only AnythingLLM by default. Uncommenting the optional LiteLLM hostname block exposes LiteLLM through Caddy, so keep the LiteLLM master key secret.

Troubleshooting:

```bash
docker logs ai-stack-caddy
# Use the same -f files you used to start the stack
docker compose -f docker-compose.yml -f docker-compose.proxy.yml ps
```

If Caddy reports an unknown `request_body` directive, pull the current `caddy:2` image and restart the overlay.

For older Docker Compose versions or Podman, use a host-based reverse proxy instead: bind direct HTTP ports to localhost in the compose file (for example, `"127.0.0.1:3001:3001/tcp"` and `"127.0.0.1:4000:4000/tcp"`) and proxy to those localhost ports. For stack-specific Caddy and nginx examples, see the [Chat UI manual reverse proxy section](https://github.com/hwdsl2/self-hosted-ai-stack/tree/main/stacks/chat-ui).

When exposing services to the internet, use the generated API keys where present. For existing no-key deployments, set API keys via the relevant env files before publishing those services.
