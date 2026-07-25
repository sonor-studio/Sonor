# Migration notice for binary filenames

> [!IMPORTANT]
[2024 Dec 20] Binaries have been renamed w/ a `sonor-` prefix. `main` is now `sonor-cli`, `server` is `sonor-server`, etc (https://github.com/ggerganov/sonor.cpp/pull/2648)

This migration was important, but it is a breaking change that may not always be immediately obvious to users.

Please update all scripts and workflows to use the new binary names.

| Old Filename | New Filename |
| ---- | ---- |
| main | sonor-cli |
| bench | sonor-bench |
| stream | sonor-stream |
| command | sonor-command |
| server | sonor-server |
| talk-llama | sonor-talk-llama |
