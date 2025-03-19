[
  parallel: true,
  skipped: false,
  fix: false,
  retry: false,
  tools: [
    {:compiler, true},
    {:doctor, false},
    {:docs, "mix docs"},
    {:credo, "mix credo --all --strict"},
    {:"deps.audit", "mix deps.audit --format human"}
  ]
]
