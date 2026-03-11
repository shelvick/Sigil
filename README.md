# FrontierOS

Tribe coordination tool for [EVE Frontier](https://evefrontier.com). Built for the March 2026 hackathon.

## Stack

- **Elixir / Phoenix / LiveView** — real-time server-rendered UI
- **Sui Move** — on-chain smart contracts for diplomacy enforcement
- **PostgreSQL** — local persistence and cache

## Development

```bash
mix deps.get
mix ecto.setup
iex -S mix phx.server   # http://localhost:4001
```

## License

All rights reserved during hackathon development.
