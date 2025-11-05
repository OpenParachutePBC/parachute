# CI/CD Pipeline Documentation

**Last Updated:** November 5, 2025

---

## Overview

Parachute uses GitHub Actions for continuous integration and deployment. The CI/CD pipeline automatically runs tests, performs code quality checks, and builds artifacts on every push and pull request.

## Workflows

### Backend CI (`backend-ci.yml`)

**Triggers:**
- Push to `main` branch (when `backend/` files change)
- Pull requests to `main` (when `backend/` files change)

**Jobs:**

#### 1. Test Job
- **Go Version:** 1.25
- **Steps:**
  1. Checkout code
  2. Set up Go with dependency caching
  3. Install dependencies (`go mod download`)
  4. Run `go fmt` check (fails if code is not formatted)
  5. Run `go vet` (static analysis)
  6. Run tests with race detection and coverage (`go test -v -race -coverprofile=coverage.out ./...`)
  7. Upload coverage to Codecov
  8. Generate HTML coverage report
  9. Upload coverage report as artifact (30-day retention)

#### 2. Build Job
- **Steps:**
  1. Checkout code
  2. Set up Go with dependency caching
  3. Build server binary (`go build -v -o bin/server cmd/server/main.go`)
  4. Upload binary as artifact (7-day retention)

**Artifacts:**
- `backend-coverage-report` - HTML coverage report (30 days)
- `backend-binary` - Compiled server binary (7 days)

---

### Frontend CI (`frontend-ci.yml`)

**Triggers:**
- Push to `main` branch (when `app/` files change)
- Pull requests to `main` (when `app/` files change)

**Jobs:**

#### 1. Analyze Job
- **Flutter Version:** 3.24.5 (stable)
- **Steps:**
  1. Checkout code
  2. Set up Flutter with caching
  3. Install dependencies (`flutter pub get`)
  4. Verify formatting (`dart format --set-exit-if-changed .`)
  5. Run static analysis (`flutter analyze --fatal-infos`)

#### 2. Test Job
- **Steps:**
  1. Checkout code
  2. Set up Flutter with caching
  3. Install dependencies
  4. Run tests with coverage (`flutter test --coverage`)
  5. Upload coverage to Codecov
  6. Upload coverage report as artifact (30-day retention)

#### 3. Build Android Job
- **Platform:** Ubuntu (Linux)
- **Java Version:** 17 (Zulu distribution)
- **Steps:**
  1. Checkout code
  2. Set up Flutter and Java
  3. Install dependencies
  4. Build debug APK (`flutter build apk --debug`)
  5. Upload APK as artifact (7-day retention)

#### 4. Build macOS Job
- **Platform:** macOS (latest)
- **Steps:**
  1. Checkout code
  2. Set up Flutter
  3. Install dependencies
  4. Build debug macOS app (`flutter build macos --debug`)
  5. Upload app as artifact (7-day retention)

**Artifacts:**
- `frontend-coverage-report` - Test coverage data (30 days)
- `android-debug-apk` - Debug APK for Android (7 days)
- `macos-debug-app` - Debug app for macOS (7 days)

---

## Code Coverage

Coverage reports are automatically uploaded to [Codecov](https://codecov.io/gh/ParachuteLabs/parachute) for:
- Backend (Go)
- Frontend (Flutter/Dart)

**Viewing Coverage:**
1. Visit https://codecov.io/gh/ParachuteLabs/parachute
2. View coverage trends over time
3. See file-level coverage details
4. Compare coverage between branches

**Note:** Codecov integration requires the `CODECOV_TOKEN` secret to be configured in repository settings.

---

## Status Badges

The README includes status badges showing:
- Backend CI status
- Frontend CI status  
- Overall code coverage

Badges automatically update based on latest workflow runs.

---

## Local Testing

### Backend

Before pushing, run locally:

```bash
cd backend

# Format code
go fmt ./...

# Run static analysis
go vet ./...

# Run tests
go test -v ./...

# Run tests with coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### Frontend

Before pushing, run locally:

```bash
cd app

# Format code
dart format .

# Analyze code
flutter analyze

# Run tests
flutter test

# Run tests with coverage
flutter test --coverage
```

---

## Artifacts

Workflow artifacts are automatically uploaded and can be downloaded from the Actions tab:

**Backend:**
- Coverage reports (HTML) - 30 days
- Server binary - 7 days

**Frontend:**
- Coverage reports (LCOV) - 30 days
- Android APK - 7 days
- macOS app - 7 days

**Accessing Artifacts:**
1. Go to repository → Actions tab
2. Click on a workflow run
3. Scroll to "Artifacts" section
4. Download desired artifact

---

## Troubleshooting

### Workflow Fails on `go fmt` Check

**Issue:** Code is not formatted according to Go standards.

**Solution:**
```bash
cd backend
go fmt ./...
git add .
git commit -m "Format code"
```

### Workflow Fails on `flutter analyze`

**Issue:** Code has linting errors or warnings.

**Solution:**
```bash
cd app
flutter analyze
# Fix reported issues
```

### Workflow Fails on Tests

**Issue:** Tests are failing.

**Solution:**
1. Run tests locally to reproduce the issue
2. Fix failing tests
3. Verify tests pass locally before pushing

### Codecov Upload Fails

**Issue:** `CODECOV_TOKEN` not configured or invalid.

**Solution:**
1. Get token from https://codecov.io
2. Add as repository secret: Settings → Secrets → Actions → New repository secret
3. Name: `CODECOV_TOKEN`
4. Re-run workflow

---

## Configuration

### Required Secrets

**Optional:**
- `CODECOV_TOKEN` - For uploading coverage reports to Codecov (recommended)

**None required for basic functionality** - workflows will run without secrets but skip optional steps like coverage upload.

---

## Future Enhancements

Planned improvements (see [Issue #2](https://github.com/ParachuteLabs/parachute/issues/2)):

**Phase 2:**
- [ ] Set minimum coverage thresholds
- [ ] Add coverage trend tracking
- [ ] Fail builds if coverage drops significantly

**Phase 3:**
- [ ] Integration tests in CI (requires running backend)
- [ ] E2E tests with Playwright
- [ ] Automated dependency updates (Dependabot)
- [ ] Automated releases (versioning, changelog)
- [ ] Deploy preview environments for PRs

---

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Go with GitHub Actions](https://github.com/actions/setup-go)
- [Flutter with GitHub Actions](https://github.com/subosito/flutter-action)
- [Codecov Documentation](https://docs.codecov.com/)

---

**Related Issues:**
- [Issue #1](https://github.com/ParachuteLabs/parachute/issues/1) - Fix test compilation failures (COMPLETED)
- [Issue #2](https://github.com/ParachuteLabs/parachute/issues/2) - Set up CI/CD pipeline (THIS DOCUMENT)
