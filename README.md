# Qwen3.8-27B on a single RTX 5090 — around 200 tokens/sec

[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE) [![Engine: NInfer](https://img.shields.io/badge/Engine-NInfer-000000)](https://github.com/Neroued/ninfer) [![Model: Hugging Face](https://img.shields.io/badge/Model-Hugging%20Face-FFD21E)](https://huggingface.co/neroued/Qwen3.8-27B-nvfp4-NInfer)

This is the setup I use to run Qwen3.8-27B locally on one RTX 5090, shared in case it is
useful to you. It gives you a private chat API on your own machine that most AI coding tools
can talk to, at roughly the speed of a paid cloud service.

Everything runs in Docker, so you are not installing a compiler or CUDA on your machine.

## Speed

Around **200 tokens/sec**, though it depends on what you ask for:

| Kind of task | Tokens/sec |
|---|---|
| Structured output (JSON, etc.) | ~267 |
| Code | ~191 |
| Translation | ~182 |
| Long reasoning | ~133–224 |
| Creative writing | ~84 |

Predictable text goes fastest. Numbers are from the engine's own benchmarks for this exact
configuration.

## What you need

- **An RTX 5090.** This is the one hard requirement — the engine is compiled for that chip only
  and will not build on anything else.
- **~27 GB of free disk** — 22 GB for the model, 5 GB for the Docker image.
- **Docker** — [Docker Desktop](https://docs.docker.com/desktop/install/windows-install/) on
  Windows, or [Docker Engine](https://docs.docker.com/engine/install/) plus the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  on Linux.
- **On Windows, [Git for Windows](https://git-scm.com/download/win)** — it provides `git` and
  `make`. Run the commands below in its Git Bash terminal, not PowerShell.
- A current [NVIDIA driver](https://www.nvidia.com/download/index.aspx).

I run this with 64 GB of RAM, but that is just what my machine has — it very likely works with
less, I have not tested where the floor is.

## Running it

```bash
git clone https://github.com/ZenderX/ninfer-qwen3.8-27b-nvfp4
cd ninfer-qwen3.8-27b-nvfp4

make setup   # downloads the 22 GB model — slow, but you only do it once
make build   # builds the Docker image
make serve   # starts the server
```

`make setup` can be interrupted and re-run; it picks up where it left off and skips the
download entirely if the model is already there.

`make serve` stays running in the terminal. Press Ctrl+C to stop it — the container shuts down
with it. If one is ever left behind, `make stop` clears it.

## Checking it works

With the server running, in another terminal:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen3.8-27b-nvfp4",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
```

A reply means you are up.

## Using it

The server speaks the same API as OpenAI, so most tools that let you set a custom API
endpoint will work. Point them at `http://127.0.0.1:8080/v1`, use the model name
`qwen3.8-27b-nvfp4`, and put anything you like as the API key — it is not checked.

For [pi](https://pi.dev), a package sets this up for you:

```bash
pi install npm:pi-localllm-provider
```

Then run `/localllm` inside pi, choose **＋ Add server**, and give it
`http://127.0.0.1:8080/v1`. It works out the rest on its own. After that you can start pi
directly on this model:

```bash
pi --model qwen3.8-27b-nvfp4
```

## Why it is fast

Three things, all already configured in the `Makefile`:

- **A 4-bit model (NVFP4).** Smaller numbers mean less memory traffic, which is what limits
  speed here. Quality loss is small.
- **A compressed memory cache (fp8).** The conversation history is stored at reduced precision,
  leaving room for very long chats — 185,000 tokens here.
- **Speculative decoding (DFlash2).** A small fast model drafts several tokens ahead and the
  big model checks them in one pass. This is why predictable text is so much faster than
  creative writing: easy guesses get accepted, surprising ones do not.

To change any of it, edit the `serve` target in the `Makefile`. Two limits to know if you do:
`--top-k` must be 20 or less, and there is no repetition penalty — the engine rejects it. The
full flag reference is in `ninfer/docs/cli.md`.

## Credit and licence

The hard part is [NInfer](https://github.com/Neroued/ninfer) by Neroued (Apache-2.0), a C++/CUDA
engine built for this GPU. This repository is only a Makefile around it. The model weights come
from the [Hugging Face model card](https://huggingface.co/neroued/Qwen3.8-27B-nvfp4-NInfer) and
carry their own licence. My wrapper is MIT — see [LICENSE](LICENSE).
