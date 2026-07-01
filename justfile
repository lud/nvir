_mix_deps:
  mix deps.get

test:
  mix test

_libdev_check:
  mix libdev.check

format:
  mix format --migrate

docs:
  mix docs

_git_status:
  git status

readmix:
  mix rdmx.update README.md
  rg rdmx guides -l0 | xargs -0 -n 1 mix rdmx.update

check: _mix_deps format readmix _libdev_check _git_status