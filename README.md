# dummer.us

Static site content for [dummer.us](https://dummer.us), deployed with Cloudflare
Workers and Wrangler.

## Hosting

`www.dummer.us` is served by a Cloudflare Worker with static assets from
`content/`. The apex domain should redirect to `https://www.dummer.us` with a
Cloudflare redirect rule so the zone can stay on **Full (strict)** while other
subdomains continue to use the ALB.

## Deploy with Wrangler

1. Install Wrangler locally for this repo:
   ```bash
   npm install
   ```
2. Log in to Cloudflare from this machine:
   ```bash
   npx wrangler login
   ```
3. Deploy the Worker and the static assets in `content/`:
   ```bash
   npx wrangler deploy
   ```

Wrangler uses `wrangler.toml`, which already points the Worker at
`www.dummer.us` and uploads the static site from `content/`.

## One-time Cloudflare setup

1. Keep `www.dummer.us` managed in Cloudflare.
2. Create a redirect rule from `dummer.us/*` to `https://www.dummer.us/$1`.
3. Keep SSL/TLS mode on **Full (strict)**.
