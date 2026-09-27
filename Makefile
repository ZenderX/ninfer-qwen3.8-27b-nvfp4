# versioned name: upstream uses the same file name for v2 and v3, so v3 must not overwrite the v2 file
MODEL := models/qwen3_8_27b_nvfp4.v3-f0b43ad.ninfer
CONTAINER := ninfer-serve

NINFER_REPO := https://github.com/Neroued/ninfer.git
# pinned ninfer commit
NINFER_REF := e31bc99b13f517c8aae70b997b7c4a49b4dcdc5d
# must follow NINFER_REF so a command-line NINFER_REF override also changes the tag
IMAGE := ninfer:$(shell printf '%.8s' '$(NINFER_REF)')
MODEL_REPO := neroued/Qwen3.8-27B-nvfp4-NInfer
MODEL_FILE := qwen3_8_27b_nvfp4.ninfer
# pins the v3 artifact matching MODEL_SHA256
MODEL_REV := f0b43ad436b9fa8142c6ed6647c470a6fe409484
MODEL_URL := https://huggingface.co/$(MODEL_REPO)/resolve/$(MODEL_REV)/$(MODEL_FILE)
MODEL_SHA256 := 74d2c57145e6ff11d1d2faa79594477f9bc903a611af1fb20218189fbbb77d82

.PHONY: build serve stop setup clone model verify

setup: clone model
	@echo "Setup complete. Next step: make build"

build:
	docker build --tag $(IMAGE) ninfer

serve:
	@test -f "$(MODEL)" || { echo "Missing $(MODEL) - download it first."; exit 1; }
	@mkdir -p logs
	@docker rm --force $(CONTAINER) >/dev/null 2>&1 || true
# host trap is only a fallback (native Windows make may kill this shell first); the container itself exits when ninfer-serve exits or the attached stdin closes
	trap 'docker rm --force $(CONTAINER) >/dev/null 2>&1; echo "Stopped $(CONTAINER)."' EXIT; \
	trap 'exit 130' INT TERM; \
	MSYS_NO_PATHCONV=1 docker run --rm \
		--name $(CONTAINER) \
		--init \
		--env TINI_KILL_PROCESS_GROUP=1 \
		--interactive \
		--gpus '"device=0"' \
		--publish 8080:8080 \
		--volume "$(PWD)/models:/models:ro" \
		--volume "$(PWD)/logs:/logs" \
		$(IMAGE) \
		bash -c 'set -o pipefail; trap : INT TERM; exec 3<&0; \
			{ ninfer-serve "$$@" 2>&1 | tee -a /logs/serve.log; } & \
			cat <&3 >/dev/null 3<&- & wd=$$!; exec 3<&-; \
			wait -n -p done; st=$$?; [ "$$done" = "$$wd" ] && st=143; \
			kill 0 2>/dev/null; wait; exit $$st' _ \
		/$(MODEL) \
		--model-id qwen3.8-27b-nvfp4 \
		--host 0.0.0.0 \
		--max-context 165000 \
		--kv-capacity 165000 \
		--max-concurrency 2 \
		--pending-timeout-ms 2147483647 \
		--max-pending-requests 64 \
		--kv-dtype int8 \
		--spec dflash2 --draft-tokens 7 --lm-head-draft \
		--temperature 0.6 \
		--top-k 20 \
		--top-p 0.95 \
		--min-p 0 \
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
