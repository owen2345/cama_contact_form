# Camaleon CMS Plugin
This is a plugin for Camaleon CMS to manage Contact Forms

## Testing

This plugin ships no test suite of its own. Its behaviour is a Camaleon CMS integration — the
save-time gate depends on the CMS's role/permission model (`contact_form_unfiltered_html`),
`CurrentRequest`, and the shared `UnsafeMarkup` detector — so it is exercised **host-side in the
[camaleon_cms](https://github.com/owen2345/camaleon-cms) repository**, which supplies the app,
database and request context the specs need. Clone that repo and run them with `bin/rspec`.

The specs that cover this plugin:

- [`spec/requests/security/contact_form_content_rejection_spec.rb`](https://github.com/owen2345/camaleon-cms/blob/master/spec/requests/security/contact_form_content_rejection_spec.rb)
  — untrusted content is refused on save, never rewritten (stored content always equals authored).
- [`spec/requests/security/contact_form_output_escaping_spec.rb`](https://github.com/owen2345/camaleon-cms/blob/master/spec/requests/security/contact_form_output_escaping_spec.rb)
  — reproduces the original output XSS (raw interpolation into the form markup) and pins the fix.
- [`spec/requests/security/contact_form_gate_soundness_spec.rb`](https://github.com/owen2345/camaleon-cms/blob/master/spec/requests/security/contact_form_gate_soundness_spec.rb)
  — the gate's soundness: the three ways a gate like this stops being sound.
- [`spec/models/contact_form_unfiltered_html_permission_spec.rb`](https://github.com/owen2345/camaleon-cms/blob/master/spec/models/contact_form_unfiltered_html_permission_spec.rb)
  — the `contact_form_unfiltered_html` permission (manager-family; distinct from `post_content_unfiltered_html`).
- [`spec/features/admin/contact_form_spec.rb`](https://github.com/owen2345/camaleon-cms/blob/master/spec/features/admin/contact_form_spec.rb)
  — the admin create/edit flow.

Browse the full set under [`spec/requests/security/`](https://github.com/owen2345/camaleon-cms/tree/master/spec/requests/security).

## Releasing

Releases are cut by the **Release** GitHub Actions workflow
([`.github/workflows/release_builder.yml`](.github/workflows/release_builder.yml)). It only runs
when you start it by hand — merging to `master` releases nothing. A single run does everything a
release needs, in this order:

1. verifies the release is safe to cut (see [What the workflow checks](#what-the-workflow-checks)),
2. builds the gem and inspects the built artifact,
3. pushes it to RubyGems,
4. creates the annotated git tag,
5. publishes the GitHub release, with notes taken from `CHANGELOG.md` and the `.gem` plus its
   checksums attached.

No tests run here — the [test suite](#testing) that covers this plugin lives in the
[camaleon_cms](https://github.com/owen2345/camaleon-cms) repository.

`lib/cama_contact_form/version.rb` is the single source of truth for the version. The tag, the
published gem and the GitHub release all derive from it, so they cannot disagree.

> **`0.1.12` below is only an example.** Every command, filename and heading in this section uses it
> as a stand-in for the version you are actually releasing — substitute yours as you go. This
> document is not updated each release, so do not expect the number here to be the next one.

### Before you start

- You need **write access** to this repository.
- The `RUBY_GEMS_PUBLISH_GEM_KEY` repository secret must exist — it is the RubyGems API key the
  workflow publishes with. It is already configured; you never need to see or handle its value.
- You do **not** need RubyGems credentials on your own machine for the automated release. You only
  need them for the [manual fallback](#fallback-releasing-entirely-by-hand).

### Step 1 — Open a release PR

Create a branch, bump the version, and describe the release:

```bash
git checkout master && git pull
git checkout -b release/0.1.12
```

Edit `lib/cama_contact_form/version.rb`:

```ruby
module CamaContactForm
  VERSION = "0.1.12"
end
```

Then add a matching section at the top of `CHANGELOG.md`, directly under the `# Change Log`
heading. If an `## Unreleased` section is already sitting there, rename it to the version you are
shipping and fold your notes into it rather than adding a second section.

**The heading must be exactly `## 0.1.12`** — the workflow copies everything between that heading
and the next `## ` into the GitHub release body, so an inexact heading (`## v0.1.12`,
`## 0.1.12 (2026-08-01)`, or a leftover `## Unreleased`) silently costs you your release notes and
falls back to a bare commit list:

```markdown
## 0.1.12

What changed and why it matters to someone upgrading.
[#65](https://github.com/owen2345/cama_contact_form/pull/65)
```

Commit, push, open the PR, and merge it once it is approved:

```bash
git commit -am "Release 0.1.12"
git push -u origin release/0.1.12
gh pr create --title "Release 0.1.12" --body "Bumps the version and adds the changelog entry."
```

### Step 2 — Run the Release workflow

Merging does **not** publish anything. Once the PR is merged:

1. Open the repository on GitHub.
2. Click the **Actions** tab (in the top row, next to *Pull requests*).
3. In the left sidebar, under *All workflows*, click **Release**.
4. On the right-hand side of the blue banner, click the **Run workflow** dropdown button.
5. Leave **Use workflow from** as `Branch: master`. The workflow refuses to run from any other
   branch, so a gem can never be published from unmerged code.
6. In **Version to release**, type the version exactly as it appears in `version.rb` — not the
   `0.1.12` of this example. A leading `v` is accepted and stripped, and a mismatch fails the run
   before anything is published.
7. Click the green **Run workflow** button.

The page takes a few seconds to show the new run; reload if it does not appear. Click into the run
to watch the three jobs — *Verify and build*, *Publish to RubyGems*, and *Tag and publish GitHub
release* — go green in turn.

> If the **Release** workflow is not listed in step 3, the workflow file has not reached `master`
> yet. GitHub only offers a manually-triggered workflow once its file exists on the default branch.
> Merge the PR first.

### Step 3 — Confirm

- **RubyGems**: <https://rubygems.org/gems/cama_contact_form/versions/0.1.12> — it can take a
  minute or two to appear.
- **GitHub**: the repository's *Releases* page should show *Release 0.1.12* with your changelog
  text and three attached files (`.gem`, `.sha256`, `.sha512`).
- Locally: `gem fetch cama_contact_form -v 0.1.12`

### What the workflow checks

Every check runs *before* anything is published, because pushing to RubyGems is the only step that
cannot be undone — a version can be yanked, but that version number can never be re-used. If a
check fails, nothing has been published and nothing has been tagged: fix the cause and start the
workflow again.

| Failure message | Cause | Fix |
| --- | --- | --- |
| `is not a valid gem version` | Typo in the input box | Re-run with the correct version |
| `Releases must be cut from master` | *Use workflow from* was not `master` | Re-run from `master` |
| `does not match lib/cama_contact_form/version.rb` | The typed version and `version.rb` disagree | Bump `version.rb`, or type the version it already has |
| `Tag <version> already exists` | That version was released before | Bump to a new version |
| `already published on RubyGems` | Same, but caught on the RubyGems side | Bump to a new version |
| `No release notes` | No `## <version>` section in `CHANGELOG.md` **and** no commits since the last tag | Add the changelog section |
| `gem build` fails under `--strict` | The gemspec has a warning (missing homepage, missing `required_ruby_version`, …) | Fix the gemspec |
| `Test files packaged into the gem` | `s.test_files` was re-added to the gemspec | Remove it — RubyGems merges `test_files` into `files` |
| `<file> is missing from the gem` | A filename in `s.files` no longer matches a real file | Correct the name in the gemspec |

The one failure that needs manual recovery is a job that fails *after* `gem push` succeeded — the
gem is public, but the tag and release were never created. Do not re-run the workflow, it would
stop at the "already published" check. Finish it by hand instead, using steps 5 and 6 of the
fallback below.

### Fallback: releasing entirely by hand

Use this if Actions is down, if the workflow is broken, or to finish a release that failed after
the gem was already pushed. It needs your own RubyGems credentials, and you must be an owner of the
gem on RubyGems.

As above, **`0.1.12` is a stand-in for the version you are releasing** — every command below needs
your own number substituted in, including the `.gem` filenames.

Sign in to RubyGems once per machine — this writes a token to `~/.gem/credentials`:

```bash
gem signin
```

Then, from a clean checkout of `master` with the correct version already in `version.rb`:

**1. Start from exactly what you intend to publish.**

```bash
git checkout master && git pull && git status
```

`git status` must report a clean tree — `gem build` packages the files on disk, so any stray local
edit would end up in the published gem.

**2. Build the gem.**

```bash
gem build cama_contact_form.gemspec --strict
```

**3. Inspect what you are about to publish.** This is the step the workflow automates; publishing
is irreversible, so it is worth the minute.

```bash
gem unpack cama_contact_form-0.1.12.gem --target /tmp/gem-check
find /tmp/gem-check -type f | sort
```

Expect about 26 files in total: `MIT-LICENSE`, `Rakefile`, `README.md`, and the rest under `app/`,
`config/`, `db/` and `lib/`. There must be **no `test/` directory** and no credentials of any kind.

**4. Push to RubyGems.** If your account has MFA enabled for publishing, this prompts for a
one-time code.

```bash
gem push cama_contact_form-0.1.12.gem
```

**5. Create and push the tag.** Annotated (`-a`), to match every existing tag in this repository:

```bash
git tag -a 0.1.12 -m "Release 0.1.12"
git push origin 0.1.12
```

**6. Publish the GitHub release.** Either with the CLI:

```bash
gh release create 0.1.12 --title "Release 0.1.12" --notes-file notes.md cama_contact_form-0.1.12.gem
```

where `notes.md` holds the changelog section for this version — or through the web interface:

1. On the repository's front page, click **Releases** in the right-hand sidebar.
2. Click **Draft a new release**.
3. In **Choose a tag**, select the `0.1.12` tag you pushed in step 5.
4. Set **Target** to `master`.
5. Set the title to `Release 0.1.12`.
6. Paste the `CHANGELOG.md` section for this version into the description box.
7. Drag `cama_contact_form-0.1.12.gem` into the *Attach binaries* area at the bottom.
8. Click **Publish release**.
