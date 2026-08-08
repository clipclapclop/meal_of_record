# GitHub backup mirror

The canonical Meal of Record repository, issue tracker, and release host are on
[Forgejo](https://git.oorangy.com/chad/meal_of_record). The repository at
[GitHub](https://github.com/clipclapclop/meal_of_record) is retained only as a
non-authoritative backup of the canonical `master` branch and Git tags.

Do not accept source changes, issues, or releases on GitHub. Future Android
releases and their assets remain Forgejo-owned. The historical GitHub releases
are left in place, but their assets are not copied forward or migrated. The
existing `gh-pages` branch continues to serve the documentation, and
`zapstore.yaml` remains inactive configuration.

## Safety boundaries

The backup operation must:

- read source refs from Forgejo, not from a developer's local branches;
- update only GitHub's `master` branch and matching Git tags;
- use neither force pushes nor deletion refspecs;
- leave `gh-pages`, GitHub Pages configuration, issues, Actions, releases, and
  release assets alone; and
- stop on a diverged branch, conflicting tag, authentication failure, or
  partial-update risk.

Do not use `git push --mirror`. A true Git mirror owns every remote ref and can
remove GitHub-only refs such as `gh-pages`.

## Trusted-host setup

Use a dedicated bare repository so local development branches and tags cannot
be copied accidentally. Keep its GitHub credential outside the project and
scope it to this repository's contents. A repository-specific deploy key with
write access is preferable to a broadly scoped personal credential.

```sh
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/meal-of-record-github-backup.git"
install -d -m 700 "$(dirname "$state_dir")"
git init --bare "$state_dir"
git -C "$state_dir" remote add forgejo \
  https://git.oorangy.com/chad/meal_of_record.git
git -C "$state_dir" remote add github-backup \
  git@github.com:clipclapclop/meal_of_record.git
```

Configure the dedicated SSH identity in the trusted host's SSH configuration;
do not place a token, private key, or credential-bearing URL in this repository.
Before each synchronization, confirm the fixed destinations:

```sh
git -C "$state_dir" remote get-url forgejo
git -C "$state_dir" remote get-url --push github-backup
```

The development checkout must continue to push to Forgejo:

```sh
git remote get-url --push origin
# ssh://git@git.oorangy.com:2222/chad/meal_of_record.git
```

## Synchronize the backup

Fetch only canonical long-lived refs into the dedicated repository, then push
those refs atomically without force or deletion:

```sh
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/meal-of-record-github-backup.git"

git -C "$state_dir" fetch --prune --prune-tags forgejo \
  '+refs/heads/master:refs/remotes/forgejo/master' \
  '+refs/tags/*:refs/tags/*'

git -C "$state_dir" push --atomic github-backup \
  'refs/remotes/forgejo/master:refs/heads/master' \
  'refs/tags/*:refs/tags/*'
```

Run this from the trusted host after canonical changes are merged and after a
Forgejo release adds a tag. A successful tag push backs up Git history only; it
does not create a GitHub release or copy a Forgejo APK.

Verify the resulting refs without relying on a working tree:

```sh
git -C "$state_dir" rev-parse refs/remotes/forgejo/master
git ls-remote https://github.com/clipclapclop/meal_of_record.git \
  refs/heads/master 'refs/tags/*'
```

The two `master` commit IDs must match, and newly published Forgejo tags must be
present on GitHub. GitHub's `gh-pages` ref is intentionally outside this
comparison.

## Failure handling

A non-fast-forward branch rejection or existing tag conflict means GitHub and
Forgejo disagree. Stop and inspect both refs; never resolve it with `--force`,
`--delete`, or `--mirror`. If the atomic push is unsupported or interrupted,
inspect the remote refs and rerun the same command only after confirming that
GitHub contains no unexpected source commits. Repository or release changes on
GitHub are not authoritative and must not be copied back to Forgejo.
