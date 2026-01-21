test:
  mix test

_mix_check:
  mix check

format:
  mix format

docs:
  mix docs

_git_status:
  git status

readmix:
  mix rdmx.update README.md
  rg rdmx guides -l0 | xargs -0 -n 1 mix rdmx.update

check: format _mix_check docs readmix _git_status