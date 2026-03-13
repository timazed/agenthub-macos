# CEF Runtime Bootstrap Troubleshooting

## Quick Start

```bash
git submodule update --init --recursive
scripts/bootstrap_cef_runtime.sh
```

## Common Issues

### Checksum mismatch

Symptoms:
- `error: SHA256 mismatch ...` during bootstrap.

Fix:
```bash
rm -rf Vendor/CEFRuntime/.downloads
scripts/bootstrap_cef_runtime.sh
```

### Missing runtime during Xcode build

Symptoms:
- Build phase fails with `Missing CEF runtime at ...`.

Fix:
```bash
scripts/bootstrap_cef_runtime.sh
```

### Wrong submodule revision

Symptoms:
- Header/API drift or wrapper compile mismatch.

Fix:
```bash
git submodule update --init --recursive
git -C Vendor/CEF rev-parse HEAD
```

Expected:
- `89c0a8c39a9fdc4d22b215c6d8c201e81afddb0d`
