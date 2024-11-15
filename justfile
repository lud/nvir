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

check: format _mix_check docs _git_status