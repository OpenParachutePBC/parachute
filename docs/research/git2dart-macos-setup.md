# git2dart macOS Setup Workaround

**Issue**: git2dart_binaries v1.9.16 has incomplete podspec causing runtime library loading errors on macOS

**Status**: ✅ Workaround implemented in `app/macos/Podfile`

---

## Problem

The `git2dart_binaries` package has two issues on macOS:

1. **Missing libssh2.1.dylib**: The podspec only includes `libgit2.dylib` in `vendored_libraries`, but `libgit2.dylib` depends on `libssh2.1.dylib`

2. **Library name mismatch**: The app links against `libgit2-experimental.1.9.dylib` but the podspec ships `libgit2.dylib`

### Error Messages

Without the workaround:

```
dyld[...]: Library not loaded: @rpath/libssh2.1.dylib
  Referenced from: .../libgit2.dylib
  Reason: image not found
```

And:

```
dyld[...]: Library not loaded: @rpath/libgit2-experimental.1.9.dylib
  Referenced from: .../app.debug.dylib
  Reason: image not found
```

---

## Solution

### Implemented in `app/macos/Podfile`

The `post_install` hook in the Podfile adds a custom build phase that:

1. Copies `libssh2.1.dylib` from pub-cache to the app's Frameworks folder
2. Creates a symlink: `libgit2-experimental.1.9.dylib` → `libgit2.dylib`

### Code

```ruby
post_install do |installer|
  # ... other post_install code ...

  # Fix git2dart_binaries: Copy libssh2.1.dylib to Frameworks
  pub_cache_base = File.expand_path('~/.pub-cache/hosted/pub.dev')
  git2dart_version = Dir.glob(File.join(pub_cache_base, 'git2dart_binaries-*')).sort.last
  libssh2_source = File.join(git2dart_version, 'macos', 'libssh2.1.dylib') if git2dart_version

  if libssh2_source && File.exist?(libssh2_source)
    runner_project = installer.aggregate_targets[0].user_project
    runner_target = runner_project.targets.find { |t| t.name == 'Runner' }

    if runner_target
      existing_phase = runner_target.shell_script_build_phases.find { |p| p.name == 'Copy Git Libraries' }

      unless existing_phase
        phase = runner_target.new_shell_script_build_phase('Copy Git Libraries')
        phase.shell_script = <<~SCRIPT
#!/bin/bash
# Copy libssh2 library (missing from git2dart_binaries podspec)
LIBSSH2_SOURCE="#{libssh2_source}"
LIBSSH2_DEST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libssh2.1.dylib"

if [ -f "$LIBSSH2_SOURCE" ]; then
    mkdir -p "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
    cp "$LIBSSH2_SOURCE" "$LIBSSH2_DEST"
    echo "✅ libssh2 copied successfully"
fi

# Create symlink for libgit2-experimental.1.9.dylib -> libgit2.dylib
cd "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
if [ -f "libgit2.dylib" ]; then
    ln -sf "libgit2.dylib" "libgit2-experimental.1.9.dylib"
    echo "✅ Created symlink: libgit2-experimental.1.9.dylib -> libgit2.dylib"
fi
        SCRIPT
        runner_project.save
      end
    end
  end
end
```

---

## Verification

After running `pod install`, check for the build phase:

```bash
cd app/macos
pod install
# Should see: ✅ Found libssh2 at: ~/.pub-cache/.../libssh2.1.dylib
# Should see: Adding 'Copy Git Libraries' build phase to Runner target
```

After building the app:

```bash
cd app
flutter build macos --debug

# Verify libraries are bundled
ls -la build/macos/Build/Products/Debug/app.app/Contents/Frameworks/ | grep -E "libgit2|libssh2"
```

Expected output:

```
lrwxr-xr-x  libgit2-experimental.1.9.dylib -> libgit2.dylib
-rw-r--r--  libgit2.dylib
-rw-r--r--  libssh2.1.dylib
```

---

## Why This Happens

### Root Cause

The `git2dart_binaries` podspec (`~/.pub-cache/.../macos/git2dart_binaries.podspec`) is incomplete:

```ruby
Pod::Spec.new do |s|
  # ...
  s.vendored_libraries = 'libgit2.dylib'  # ❌ Missing libssh2.1.dylib
  # ...
end
```

It should be:

```ruby
s.vendored_libraries = ['libgit2.dylib', 'libssh2.1.dylib']
```

###Library Name Mismatch

The Flutter plugin expects `libgit2-experimental.1.9.dylib` (based on libgit2 version), but the podspec ships the generic `libgit2.dylib` name.

---

## Manual Workaround (if Podfile fix doesn't work)

If the build phase doesn't apply (it persists from previous installs), manually copy libraries after each build:

```bash
# Copy libssh2
cp ~/.pub-cache/hosted/pub.dev/git2dart_binaries-*/macos/libssh2.1.dylib \
   app/build/macos/Build/Products/Debug/app.app/Contents/Frameworks/

# Create symlink
cd app/build/macos/Build/Products/Debug/app.app/Contents/Frameworks/
ln -sf libgit2.dylib libgit2-experimental.1.9.dylib
```

---

## Future Resolution

### Option 1: Upstream Fix

Submit PR to `git2dart_binaries` to fix the podspec:
- Add `libssh2.1.dylib` to `vendored_libraries`
- Consider renaming `libgit2.dylib` to `libgit2-experimental.1.9.dylib` at build time

**Repository**: https://github.com/DartGit-dev/git2dart_binaries

### Option 2: Fork

Maintain a fork of `git2dart_binaries` with the corrected podspec.

### Option 3: Alternative Library

Evaluate alternatives:
- `dart_git` (pure Dart, slower but no native dependencies)
- Git CLI wrapper (subprocess overhead, simpler)

**Verdict**: Current workaround is acceptable for POC. Revisit if git2dart becomes problematic.

---

## Related Issues

- POC Results: [docs/research/git-poc-results.md](git-poc-results.md)
- Git Libraries Comparison: [docs/research/git-libraries-comparison.md](git-libraries-comparison.md)
- Git Sync Strategy: [docs/architecture/git-sync-strategy.md](../architecture/git-sync-strategy.md)

---

**Last Updated**: November 5, 2025
**Next Review**: After git2dart_binaries updates or when issues arise
