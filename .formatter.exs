[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_live_view],
  subdirectories: ["priv/*/migrations"],
  inputs: ["{mix,.formatter,.credo}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
