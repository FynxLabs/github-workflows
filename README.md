# github-workflows

Shared reusable GitHub Actions workflows and Docker infrastructure for FynxLabs Zig projects.

## Workflows

### zig-ci.yml

Standard build + test + lint pipeline. Uses [mise](https://mise.jdx.dev/) for Zig version management (reads `.mise.toml` or `.tool-versions` from the consuming repo).

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  ci:
    uses: fynxlabs/github-workflows/.github/workflows/zig-ci.yml@master
    with:
      system-deps: x11-base    # none | x11-base | x11-full
      build-args: ""            # extra args to zig build
      test-args: ""             # extra args to zig build test
      zig-fmt-paths: "src/"     # paths to lint (empty = skip)
```

**Package groups** (installed on the Ubuntu runner):

| Group | Packages |
|---|---|
| `none` | No system deps |
| `x11-base` | xcb, xcb-util-*, cairo, pango (what liminal needs) |
| `x11-full` | x11-base + librsvg, gdk-pixbuf, pipewire (what dusk needs) |

### zig-compat.yml

Multi-distro, multi-architecture Docker matrix testing. Builds per-distro Docker images with QEMU for cross-arch, then runs your test commands inside each container.

```yaml
# .github/workflows/compat.yml
name: Compat
on: [push, pull_request]

jobs:
  compat:
    uses: fynxlabs/github-workflows/.github/workflows/zig-compat.yml@master
    with:
      image-prefix: myproject-compat     # required
      package-group: x11-base            # x11-base | x11-full
      zig-version: "0.15.2"
      test-commands: |
        zig build
        zig build test
      x11-test-commands: |
        zig build test-x11
      # distros: '["arch","debian"]'     # override default matrix
```

**Default distro matrix** (14 variants):

| | amd64 | arm64 | riscv64 |
|---|---|---|---|
| Arch | arch | arch-arm64 | arch-riscv64 |
| Debian | debian | debian-arm64 | debian-riscv64 |
| Ubuntu | ubuntu | ubuntu-arm64 | ubuntu-riscv64 |
| Fedora | fedora | fedora-arm64 | fedora-riscv64 |
| OpenMandriva | openmandriva | openmandriva-arm64 | - |

## Dockerfiles

`dockerfiles/Dockerfile.<distro>` - one per distro/arch variant. Parameterized via build args:

- `PACKAGE_GROUP` - `x11-base` (default) or `x11-full`
- `ZIG_VERSION` - Zig version to install (default: `0.15.2`)

The entrypoint reads test commands from environment variables:

- `TEST_COMMANDS` - newline-separated commands run headless
- `X11_TEST_COMMANDS` - newline-separated commands run under Xvfb + Openbox

## Local Testing

Run the compat matrix locally from your project root:

```bash
# Clone this repo alongside your project
git clone https://github.com/fynxlabs/github-workflows .github-workflows

# Run all native distros
.github-workflows/scripts/run-all.sh

# Single distro
.github-workflows/scripts/run-all.sh arch

# Cross-arch (needs QEMU)
.github-workflows/scripts/run-all.sh --setup-qemu ubuntu-arm64

# Full deps for dusk
.github-workflows/scripts/run-all.sh --package-group x11-full --image-prefix dusk-compat

# Custom test commands
TEST_COMMANDS=$'zig build\nzig build test' \
X11_TEST_COMMANDS='zig build test-x11' \
.github-workflows/scripts/run-all.sh arch
```

## Example: Consuming from dusk

```yaml
# dusk/.github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  build-test:
    uses: fynxlabs/github-workflows/.github/workflows/zig-ci.yml@master
    with:
      system-deps: x11-full
      zig-fmt-paths: "src/"

  compat:
    uses: fynxlabs/github-workflows/.github/workflows/zig-compat.yml@master
    with:
      image-prefix: dusk-compat
      package-group: x11-full
      test-commands: |
        zig build
        zig build test
      x11-test-commands: |
        zig build test-x11
```

## Example: Consuming from liminal

```yaml
# liminal/.github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  build-test:
    uses: fynxlabs/github-workflows/.github/workflows/zig-ci.yml@master
    with:
      system-deps: x11-base
      zig-fmt-paths: "src/"

  compat:
    uses: fynxlabs/github-workflows/.github/workflows/zig-compat.yml@master
    with:
      image-prefix: liminal-compat
      package-group: x11-base
      test-commands: |
        zig build
        zig build test
```

## License

MIT - see [LICENSE](LICENSE).
