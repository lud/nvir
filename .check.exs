[
  parallel: true,
  skipped: false,
  fix: false,
  retry: false,

  ## list of tools (see `mix check` docs for a list of default curated tools)
  tools: [
    {:compiler, true},
    {:doctor, false},
    {:credo, "mix credo --all --strict"},
    {:"deps.audit", "mix deps.audit --format human"}

    ## custom new tools may be added (Mix tasks or arbitrary commands)
    # {:my_task, "mix my_task", env: %{"MIX_ENV" => "prod"}},
    # {:my_tool, ["my_tool", "arg with spaces"]}
  ]
]
