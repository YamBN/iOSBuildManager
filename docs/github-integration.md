# GitHub integration

The GitHub section signs in to your account and manages the selected project's
repository: see uncommitted changes, commit and push, publish a brand-new
repository, watch Actions runs, and cut a release with the latest build
attached.

## Signing in

There are two ways in, and you only need one.

### GitHub CLI (no setup)

If you already use [`gh`](https://cli.github.com), click **Use GitHub CLI**. The
app reads the token from `gh auth token`, so if `gh auth login` works in your
terminal, you're done.

### Browser sign-in (OAuth device flow)

**Sign in with Browser** uses GitHub's [device
flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow):
the app opens github.com, you approve there, and the app picks up the token
automatically.

Device flow needs an OAuth **client ID**. There's deliberately no shared one
baked into the app — each install registers its own:

1. Go to **github.com → Settings → Developer settings → OAuth Apps → New OAuth App**.
2. Give it any name (e.g. "iOS Build Manager"), and any homepage URL.
3. Create it, then on the app's page tick **Enable Device Flow** and save.
4. Copy the **Client ID** into Settings → GitHub in the app.

The client ID is public by design — device flow needs no client secret, which is
exactly why it suits an open-source desktop app. A client *secret* shipped
inside a distributed binary wouldn't be secret, so this app never asks for one.

## Where the token lives

The access token is stored in your login **Keychain**, never in
`settings.json` alongside ordinary preferences.

When pushing, the token is passed to `git push` as a one-shot authenticated URL
and is **never** written into `.git/config` — `origin` stays as the plain
`https://github.com/owner/name.git`. Any git error shown in the UI has the token
redacted out of it.

## What each action does

| Action | What runs |
| --- | --- |
| Commit & Push | `git add -A`, `git commit -m …`, `git push` to the current branch |
| Publish to GitHub | `git init` (if needed), creates the repo via the API, first commit, sets `origin`, pushes |
| Actions | Reads the repo's recent workflow runs |
| Publish Release | Creates a release and uploads the latest build artifact to it |

Pushing asks for confirmation first, and publishing a repository lets you choose
private or public — public repositories are visible to everyone.

## Scopes

Sign-in requests `repo`, `workflow`, and `read:org`, which is what pushing,
creating repositories, reading Actions, and publishing releases require.
