# Releasing Animated

A release is a zip of `Animated.app` attached to a GitHub release. The download link in the README points at the latest release, so publishing one is what delivers a new version to users.

You need push access to the repository. No Apple Developer account is involved: the app is signed ad hoc and is not notarized, which is why users click "Open Anyway" on first launch.

## Names and numbers

| Thing | Format | Example |
| --- | --- | --- |
| Version (`CFBundleShortVersionString`) | `X.Y.Z` — raise `Z` for fixes, `Y` for features | `1.0.2` |
| Build number (`CFBundleVersion`) | A whole number, one higher with every release | `3` |
| Git tag | `vX.Y.Z` | `v1.0.2` |
| Zip file | `Animated-X.Y.Z.zip` | `Animated-1.0.2.zip` |
| Release title | `Animated X.Y.Z` | `Animated 1.0.2` |

## Steps

### 1. Start from a clean `master`

Everything that should ship is committed on `master`, and `git status` shows nothing.

### 2. Stamp the version

Edit the two version lines in `project.yml`:

```yaml
        CFBundleShortVersionString: 1.0.2
        CFBundleVersion: "3"
```

Then regenerate and commit. `xcodegen generate` rewrites `Sources/Info.plist` from `project.yml`, so both files change:

```sh
xcodegen generate
git add project.yml Sources/Info.plist
git commit -m "Stamp version 1.0.2"
```

### 3. Build the release

```sh
xcodebuild -project Animated.xcodeproj -scheme Animated -configuration Release -derivedDataPath build build
```

The app is at `build/Build/Products/Release/Animated.app`.

### 4. Test that exact build

Quit the running app, copy the new build over the installed one, and open it:

```sh
pkill -x Animated
ditto build/Build/Products/Release/Animated.app /Applications/Animated.app
open /Applications/Animated.app
```

Go through the testing checklist in [CONTRIBUTING.md](CONTRIBUTING.md#testing-checklist). The lock screen can only be checked by locking the Mac and looking, twice in a row. Do not rebuild after testing: the zip must contain the build you tested.

### 5. Package

```sh
ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/Animated.app build/Animated-1.0.2.zip
```

`ditto` is Apple's tool for zipping an app bundle. `--keepParent` puts `Animated.app` at the top of the zip, which is what the install instructions expect.

Check the zip by unpacking it somewhere else:

```sh
ditto -x -k build/Animated-1.0.2.zip /tmp/animated-check
codesign --verify --deep --strict /tmp/animated-check/Animated.app && echo "signature ok"
defaults read /tmp/animated-check/Animated.app/Contents/Info.plist CFBundleShortVersionString
shasum -a 256 build/Animated-1.0.2.zip
```

Keep the checksum from the last line for step 8.

### 6. Push

```sh
git push origin master
```

### 7. Publish the GitHub release

Write the release notes first, using the [template](#release-notes-template) below.

**With the GitHub CLI**

```sh
gh release create v1.0.2 build/Animated-1.0.2.zip --target master --title "Animated 1.0.2" --notes-file notes.md
```

This creates the tag as well. The CLI must be signed in to an account that can write to the repository. To check, this must print `true`:

```sh
gh api repos/vlzuiev/animated --jq .permissions.push
```

**On the website**

1. Open [Releases → Draft a new release](https://github.com/vlzuiev/animated/releases/new).
2. Click **Choose a tag**, type `v1.0.2`, and **click the entry in the list** ("Create new tag: v1.0.2 on publish"). Typing the name is not enough. If the tag is not selected, publishing fails with "tag name can't be blank".
3. Leave the target on `master`.
4. Fill in the title and paste the release notes.
5. Drag the zip into "Attach binaries" and wait for the upload to finish.
6. Click **Publish release**.

If the tag selector gives trouble, push the tag yourself and then pick it from the list:

```sh
git tag v1.0.2
git push origin v1.0.2
```

### 8. Verify

The repository is public, so these work from any account:

```sh
gh api repos/vlzuiev/animated/releases/latest --jq .tag_name
gh api repos/vlzuiev/animated/releases/tags/v1.0.2 --jq '.assets[] | {name, size, digest}'
git ls-remote --tags origin v1.0.2
```

Check three things:

- The first command prints the new tag, so the README download link serves the new version.
- The `digest` equals the checksum from step 5, so the uploaded zip is the one you tested.
- The tag points at the "Stamp version" commit.

## Release notes template

Past releases use this shape. The Install section stays the same apart from the file name; update the last line when the supported macOS versions change.

````markdown
## What's new

- 🔒 **Fixed: short name of the problem** — what the user saw, and what happens now
- ✨ **New: short name of the feature** — what it does

## Install

1. Download `Animated-X.Y.Z.zip`, unzip, move `Animated.app` to Applications (replace the old one)
2. First launch: **System Settings → Privacy & Security → "Open Anyway"** (one-time — the app is open source and not notarized)
3. Menu bar ✦ → **Choose Video…**, and enable **Start at Login**

Requires macOS 26 (Tahoe) or macOS 27, and one Apple aerial downloaded in System Settings → Wallpaper.
````

Write the "What's new" lines for someone using the app, not for someone reading the code: what they saw before, and what they get now.

## If something goes wrong

- **The wrong zip was uploaded.** Edit the release, delete the file, and upload the right one under the same name. Then repeat step 8.
- **The release itself is broken.** Fix the problem and publish a new version with the next number. Do not replace the zip of a version people may already have downloaded; two different apps with the same version number are hard to tell apart in bug reports.
