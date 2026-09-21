MODEL := models/qwen3_8_27b_nvfp4.ninfer
IMAGE := ninfer:local
CONTAINER := ninfer-serve

NINFER_REPO := https://github.com/Neroued/ninfer.git
# pinned ninfer commit
NINFER_REF := b88c0f6fc7e999f13eb2fcf7fc9105ed79a91868
MODEL_REPO := neroued/Qwen3.8-27B-nvfp4-NInfer
MODEL_FILE := qwen3_8_27b_nvfp4.ninfer
# pins the v2 artifact matching MODEL_SHA256; upstream main moved to v3 on 2026-09-15
MODEL_REV := 11dbbbbbc33db198afe2f02c9232c771ff7031be
MODEL_URL := https://huggingface.co/$(MODEL_REPO)/resolve/$(MODEL_REV)/$(MODEL_FILE)
MODEL_SHA256 := 552c374c685dce302603b95fbe940fb04243c0cd44c083efc644ad3d980d462c

.PHONY: build serve stop setup clone model verify

setup: clone model
	@echo "Setup complete. Next step: make build"

build:
	docker build --tag $(IMAGE) ninfer

serve:
	@test -f "$(MODEL)" || { echo "Missing $(MODEL) - download it first."; exit 1; }
	@mkdir -p logs
	@docker rm --force $(CONTAINER) >/dev/null 2>&1 || true
	trap 'docker rm --force $(CONTAINER) >/dev/null 2>&1; echo "Stopped $(CONTAINER)."' INT TERM; \
	MSYS_NO_PATHCONV=1 docker run --rm \
		--name $(CONTAINER) \
		--gpus '"device=0"' \
		--publish 8080:8080 \
		--volume "$(PWD)/models:/models:ro" \
		--volume "$(PWD)/logs:/logs" \
		$(IMAGE) \
		bash -c 'set -o pipefail; ninfer-serve "$$@" 2>&1 | tee -a /logs/serve.log' _ \
		/models/qwen3_8_27b_nvfp4.ninfer \
		--model-id qwen3.8-27b-nvfp4 \
		--host 0.0.0.0 \
		--max-context 165000 \
		--kv-capacity 165000 \
		--max-concurrency 2 \
		--kv-dtype fp8 \
		--spec dflash2 --draft-tokens 7 --lm-head-draft \
		--temperature 0.7 \
		--top-k 20 \
		--top-p 0.95 \
		--min-p 0.05 \
		--presence-penalty 0 \
		--preserve-thinking \
		--vision

stop:
	@if docker ps --all --format '{{.Names}}' | grep -qx '$(CONTAINER)'; then \
		docker rm --force $(CONTAINER) >/dev/null && echo "Stopped $(CONTAINER)."; \
	else \
		echo "$(CONTAINER) is not running."; \
	fi

clone:
	@test -d ninfer/.git || git clone $(NINFER_REPO) ninfer
	@git -C ninfer cat-file -e $(NINFER_REF)^{commit} 2>/dev/null || git -C ninfer fetch --quiet origin
	@git -C ninfer checkout --quiet --detach $(NINFER_REF)
	@echo "ninfer at $(NINFER_REF)."

model:
	@mkdir -p models
	@if test -f "$(MODEL)" && echo "$(MODEL_SHA256)  $(MODEL)" | sha256sum --check --status; then \
		echo "$(MODEL) already present and verified."; \
	else \
		echo "Downloading $(MODEL_FILE) (~22 GiB, resumable)..."; \
		curl -L --fail --retry 3 -C - -o "$(MODEL).part" "$(MODEL_URL)" && \
		if echo "$(MODEL_SHA256)  $(MODEL).part" | sha256sum --check --status; then \
			mv "$(MODEL).part" "$(MODEL)" && echo "Downloaded and verified $(MODEL)."; \
		else \
			echo "Checksum mismatch; leaving $(MODEL).part in place for inspection."; \
			exit 1; \
		fi; \
	fi

verify:
	@test -f "$(MODEL)" || { echo "Missing $(MODEL) - run make model."; exit 1; }
	@if echo "$(MODEL_SHA256)  $(MODEL)" | sha256sum --check --status; then \
		echo "$(MODEL) checksum OK."; \
	else \
		echo "$(MODEL) checksum MISMATCH (expected $(MODEL_SHA256))."; \
		exit 1; \
	fi
