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

readme:
  mix rdmx.update README.md

check: format _mix_check docs readme _git_status