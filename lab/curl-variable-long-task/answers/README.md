# Visible reference answer

Demo mode downloads and verifies the public upstream implementation:

- curl commit: `2e160c9c652504e147f474ed920ae891481e299c`
- URL: <https://github.com/curl/curl/commit/2e160c9c652504e147f474ed920ae891481e299c>

After `./scripts/demo.sh prepare`, the complete patch is available under
`.demo/curl-2e160c9c652504e147f474ed920ae891481e299c.patch`.

Use:

```bash
./scripts/demo.sh answer demo-large --show
./scripts/demo.sh answer demo-large --apply
```

The reference patch remains under curl's license; see
`../licenses/curl-LICENSE`.
