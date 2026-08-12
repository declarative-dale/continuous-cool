# Continuwuity on Coolify

This repository deploys a small, federated [Continuwuity](https://continuwuity.org/) Matrix homeserver with Coolify v4. Coolify reads [`compose.yaml`](compose.yaml), provides HTTPS through its existing Traefik proxy, and owns the real environment values. GitHub Actions validates the deployment definition only; Coolify performs deployment through its GitHub integration or repository webhook.

OOYE is deliberately outside this stack. It runs as a native systemd service on the Debian host and is reached from Continuwuity through Docker's host gateway.

## Prerequisites

- A Coolify v4 server on Debian 13 (x86_64)
- A DNS A/AAAA record for the service hostname, such as `matrix.example.org`, pointing to the Coolify server
- Public ports 80 and 443 available to Coolify's proxy
- The public GitHub repository connected in Coolify
- A chosen, permanent Matrix server name
- OOYE installed separately on the VPS if Discord bridging is required

The server name determines every user and room ID and cannot practically be changed after initialization. It does not have to equal the service hostname: for example, `MATRIX_SERVER_NAME=example.org` gives users IDs such as `@alice:example.org`, while `MATRIX_SERVICE_HOSTNAME=matrix.example.org` exposes the server at `https://matrix.example.org`. Choose the server name before the first deployment.

## Coolify resource creation

1. Create a Coolify project and environment.
2. Add a resource from `declarative-dale/continuous-cool` using the public GitHub repository source.
3. Select **Docker Compose** as the build pack.
4. Set the Compose file to `/compose.yaml`.
5. Configure these Coolify environment values:

   ```text
   MATRIX_SERVER_NAME=example.org
   MATRIX_SERVICE_HOSTNAME=matrix.example.org
   CONTINUWUITY_VERSION=v26.7.3
   ```

6. Assign this domain to the `continuwuity` service:

   ```text
   https://matrix.example.org:8008
   ```

7. Confirm that Coolify detects persistent storage for:

   ```text
   continuwuity-data → /var/lib/continuwuity
   ```

8. Deploy and inspect the `continuwuity` service logs.

The `:8008` suffix in the Coolify domain tells its proxy which **internal** container port to use. Clients still connect to normal HTTPS port 443. The Compose file uses `expose`, not `ports`, so port 8008 is not published directly on the host.

### Empty Compose editor or environment list

Coolify performs Git and Compose operations by connecting from its container back to the managed server over SSH, including when Coolify runs on that same server. If **Load Compose File** leaves the editor and environment list empty, test the path from inside the Coolify container and inspect the Coolify application log for SSH timeouts.

With a default-deny UFW policy, permit only the Coolify Docker bridge subnet to reach the host's Docker-gateway address on port 22:

```bash
ufw allow in \
  on <coolify-bridge-interface> \
  from <coolify-ipv4-subnet> \
  to <docker-host-gateway-ip> \
  port 22 proto tcp \
  comment 'Coolify internal SSH'
```

Discover the installation-specific interface, subnet, and gateway rather than copying values from another server:

```bash
docker network inspect coolify
ip -brief address
```

This is an inbound container-to-host exception; it does not require exposing SSH on the public interface or permitting unrestricted outbound TCP port 22. Keep public administrative SSH restricted to the trusted interface, such as Tailscale.

Coolify 4.1 discovers variables in a service's `environment` mapping but does not reliably create a UI field for a variable referenced only in `image:`. `DEPLOYMENT_IMAGE_VERSION` therefore mirrors the non-secret `CONTINUWUITY_VERSION` pin as inert container metadata. Continuwuity does not use that metadata variable.

### Health monitoring

The official Continuwuity image contains the server binary and required runtime files but intentionally contains no shell, `wget`, or `curl`. For that reason, this stack does not define an in-container Compose health check or install runtime packages just to provide one. Configure Coolify or an external monitor to request:

```text
https://matrix.example.org/_matrix/client/versions
```

## First account

1. Read the one-time initial registration token from the first Continuwuity deployment logs in Coolify.
2. Configure Element (or another Matrix client supporting token registration) to use `https://matrix.example.org` as its homeserver.
3. Register the initial administrator with the one-time token.
4. Confirm that the account is invited to and joins the Continuwuity admin room.
5. Leave unrestricted registration disabled. `CONTINUWUITY_ALLOW_REGISTRATION=false` does not prevent the one-time bootstrap token from creating the first account.

Never put the initial token in GitHub issues, Actions output, commits, or documentation.

## OOYE application-service registration

Run OOYE natively under systemd on the VPS. The separate [`matrix-discord-bridge`](https://github.com/declarative-dale/matrix-discord-bridge) repository contains the pinned host installer, hardened service, backup/update scripts, and Coolify proxy template. Its generated application-service registration must advertise this URL for callbacks from Continuwuity:

```text
http://host.docker.internal:6693
```

OOYE must listen on the Docker bridge host address, or another address reachable through the host gateway; binding only to `127.0.0.1` is normally not reachable from a container. Restrict raw port 6693 with the host firewall so it is reachable from the Docker bridge but not from the public Internet. OOYE still needs a separate public HTTPS URL for its website and authenticated-media proxy; route that hostname through Coolify's Traefik proxy to the host service.

In the Continuwuity admin room, send the registration command followed by the complete OOYE registration YAML in a fenced code block:

````text
!admin appservices register
```
<paste the complete OOYE registration YAML>
```
````

Then verify registration:

```text
!admin appservices list
```

Do not commit OOYE's `registration.yaml`, Discord credentials, or application-service tokens. The registration contains shared secrets even when its callback URL is not public.

## Federation and delegation

This deployment serves both client and federation traffic through Coolify on HTTPS port 443. Matrix federation otherwise defaults to port 8448, so the Compose configuration asks Continuwuity to advertise `MATRIX_SERVICE_HOSTNAME` on port 443. It also configures client discovery to advertise that service hostname.

When `MATRIX_SERVER_NAME` and `MATRIX_SERVICE_HOSTNAME` differ, the server-name origin must serve the discovery documents. For the checked-in example, serve these at `https://example.org`:

`/.well-known/matrix/server`:

```json
{"m.server":"matrix.example.org:443"}
```

`/.well-known/matrix/client`:

```json
{"m.homeserver":{"base_url":"https://matrix.example.org"}}
```

The client document must include `Access-Control-Allow-Origin: *`. The apex website or proxy can serve these static responses or proxy only `/.well-known/matrix/*` to Continuwuity. Merely assigning `matrix.example.org` to the Coolify service does not configure `example.org`.

Verify discovery at the **server-name origin**:

```bash
curl https://example.org/.well-known/matrix/server
curl https://example.org/.well-known/matrix/client
```

If both variables are the same, cross-hostname delegation is unnecessary, but federation discovery still needs to advertise port 443. See Continuwuity's [delegation guide](https://continuwuity.org/advanced/delegation) before initialization.

After deployment, check the public endpoints:

```bash
curl https://matrix.example.org/_matrix/client/versions
curl https://matrix.example.org/_matrix/federation/v1/version
curl https://matrix.example.org/_continuwuity/server_version
```

The currently documented legacy server-version route is `/_conduwuit/server_version`; check it as a compatibility diagnostic if `/_continuwuity/server_version` is unavailable:

```bash
curl https://matrix.example.org/_conduwuit/server_version
```

Also test discovery from outside the VPS with a Matrix federation/connectivity tester and federate with at least one remote homeserver. A direct federation endpoint response alone does not prove that other servers can discover it.

## Backups

GitHub contains only deployment configuration. Back up these separately:

- The `continuwuity-data` named volume, containing the Continuwuity database
- The native OOYE directory, including its SQLite database, configuration, and registration data

Use an upstream-supported, application-consistent procedure. Do not make an ordinary filesystem copy of either database while it is active. Retain and test restoration of a backup before every upgrade; protect backups as secrets because they contain account and bridge data.

## Updating

Dependabot monitors GitHub Actions weekly. A separate scheduled workflow checks the official Continuwuity release API every Monday and opens or refreshes an `automation/continuwuity-update` pull request when the stable tag changes. It validates the proposed image and Compose configuration but never deploys it. Enable **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests** so it can open the PR (the workflow does not approve it).

Apply an approved Continuwuity update through this controlled process:

1. Review the [upstream release notes](https://forgejo.ellis.link/continuwuation/continuwuity/releases).
2. Take and retain an application-consistent database backup.
3. Review the automated version pull request, or change `CONTINUWUITY_VERSION` in `.env.example` and open one manually.
4. Let GitHub Actions validate the image and Compose file.
5. Change the Coolify `CONTINUWUITY_VERSION` value to the approved tag.
6. Merge the pull request.
7. Let Coolify redeploy through its GitHub integration/webhook, or redeploy manually.
8. Verify client access, federation, persistence, and OOYE bridging.

Do not use `latest` for deployment. Review upstream migration notes before changing versions, and do not assume a database downgrade is supported.

## Deployment flow

```text
Pull request
    ↓
GitHub Actions validation
    ↓
Merge to main
    ↓
Coolify GitHub webhook
    ↓
Coolify redeployment
```

The workflow has read-only repository permissions and contains no SSH key, Coolify token, or deploy webhook. If a GitHub-triggered Coolify webhook is ever needed as a fallback, store its URL/token only in GitHub Actions secrets—never in workflow YAML or repository documentation.

## Post-deployment checklist

- The service remains running and the external client-versions monitor passes.
- `/var/lib/continuwuity` is backed by the `continuwuity-data` named volume.
- The first administrator can sign in and enter the admin room.
- Public registration remains disabled.
- Federation works with at least one remote homeserver through port 443 discovery.
- `host.docker.internal` resolves inside the Continuwuity container.
- Continuwuity can reach OOYE at `host.docker.internal:6693`.
- OOYE appears in `!admin appservices list` and a test message bridges both ways.
- Redeploying the unchanged stack preserves accounts, rooms, and appservice registration.
- Host ports 8008 and 6693 are not publicly reachable.

## Local validation

The checked-in example contains non-secret, functional placeholders, so it can render the deployment without editing:

```bash
docker compose --env-file .env.example config --quiet
docker compose --env-file .env.example config
```

For a local run, copy `.env.example` to the ignored `.env` and replace both host values before initialization. Do not use the example domains for a real deployment.
