# rhuanbarreto/securo

A fork of [securo-finance/securo](https://github.com/securo-finance/securo) that
runs at money.rhuan.no. `main` mirrors upstream. Every change is a branch with
its own upstream PR, and production runs the `deploy` branch.

The deployment side (Coolify compose, database backups, rollout) is documented in
[BarretoTech/tatuicloud](https://github.com/BarretoTech/tatuicloud):
`docs/runbook.md`, section "Deploy a Securo change", and
`coolify/services/securo/README.md`.

## The `deploy` branch

`deploy` is built in three layers:

1. the latest upstream release tag;
2. the branches in [`fork/carried-branches.txt`](fork/carried-branches.txt),
   cherry-picked in order;
3. one commit with the fork's own files: this file, `fork/` and
   `.github/workflows/fork-images.yml`.

The branch is rebuilt, never merged into, so it always reads as "release +
patches", and it is force-pushed.

It tracks releases, not upstream `main`. `main` carries unreleased migrations,
and once a migration has run against the live database there is no way back to
the release images.

## Producing a fix or feature

Remotes: `origin` is upstream and `fork` is this repository. Work in a worktree
under `.claude/worktrees/`, never in the checkout that holds another branch.

1. Branch off upstream `main`:

   ```bash
   git fetch origin
   git worktree add -b fix/<topic> .claude/worktrees/<topic> origin/main
   ```

2. Make the change and run what upstream CI runs:

   ```bash
   cd backend && uv sync --all-extras && uv run --no-sync ruff check . && uv run --no-sync pytest -n auto --dist loadfile -W error
   cd frontend && npm ci && npm run lint -- --max-warnings=0 && npm run build && npm test
   ```

   - A user-facing string needs all 15 locales; `src/locales/i18n.test.ts`
     fails otherwise.
   - On Windows, `test_a_line_taller_than_a_page_still_finishes` (it needs
     `signal.SIGALRM`) and the date-dependent
     `test_a_deduction_settles_without_being_received` fail regardless of the
     change.

3. Push to `fork` and open a PR against `securo-finance/securo:main`.
   - Use conventional commit titles (`fix(scope): …`, `feat(scope): …`) and
     upstream's PR template.
   - CONTRIBUTING asks that larger features be discussed in an issue or on
     Discord first.

4. Address review comments (CodeRabbit reviews every PR) with new commits on
   the same branch, and reply on each thread with the commit or the reason for
   declining. Never amend or force-push a branch under review.

5. Carry the branch into production: add it to `fork/carried-branches.txt` on
   `deploy`, then rebuild (next section). Review fixes pushed later reach
   production the same way, through a rebuild.

## Rebuilding `deploy`

Rebuild when upstream tags a release, when a carried branch gains commits, or
when the carry list changes.

```bash
git fetch fork && git switch deploy && git reset --hard fork/deploy
# edit fork/carried-branches.txt if needed, then:
git commit --amend --no-edit -a                       # keep a single fork commit
fork/rebuild-deploy.sh                                # latest release tag
fork/rebuild-deploy.sh v0.17.0                        # or a specific release
git log --oneline "$(git tag --list 'v*' --sort=-v:refname | head -n1)"..deploy
git push --force-with-lease fork deploy
```

The script takes the carry list and the fork's files from the commit it starts
on, so a local edit is picked up before anything is pushed.

- **Cherry-pick conflict:** the script stops. Resolve the conflict, run
  `git cherry-pick --continue`, pick the remaining branches by hand, then
  restore the fork files with
  `git checkout <start commit> -- FORK.md fork .github/workflows/fork-images.yml`
  and commit them.
- **When a release includes a carried PR:** remove its branch from the carry
  list. The script flags branches whose PR is merged upstream, and branches
  with nothing beyond upstream `main`.

## Images

Every push to `deploy` runs the `Fork images` workflow:

1. It runs the backend and frontend checks.
2. It publishes `ghcr.io/rhuanbarreto/securo-backend` and `securo-frontend`
   for linux/amd64, with two tags:
   - `<version>-fork.<short sha>`, where the version is read from
     `frontend/package.json` because this repository does not mirror
     upstream's tags;
   - `deploy`.

The packages are public, inherited from this public repository, so Coolify
pulls them without credentials.

Production pins the `<version>-fork.<short sha>` tag in tatuicloud. A push here
never reaches money.rhuan.no on its own.
