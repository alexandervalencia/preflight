# Preflight

Preflight is a local-first Rails application for reviewing a branch like a GitHub
pull request before you push it upstream.

## What it does

- lets you register local git repositories by filesystem path
- compares a local branch against a base branch, defaulting to the selected
  repository's default branch (`main` when present)
- stores local pull request records with descriptions
- walks commit-by-commit through the branch history
- renders per-file diffs and supports inline comments on specific lines
- lets you mark files as viewed and flags `New changes` when later commits touch
  those files again

## Requirements

- [Devbox](https://www.jetify.com/devbox) 0.16 or newer

## Setup

```bash
devbox run -- bundle install
devbox run -- bin/rails db:prepare
```

## Run the app

```bash
devbox run -- bin/rails server
```

Open [http://localhost:3000](http://localhost:3000).

Add a repository from the home page by entering its local filesystem path, then
open that repository's compare page to create and review local pull requests.

## Test

```bash
devbox run -- bin/rails test
```
