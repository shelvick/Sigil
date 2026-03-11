[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  inputs: ["{mix,.formatter,.credo}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
