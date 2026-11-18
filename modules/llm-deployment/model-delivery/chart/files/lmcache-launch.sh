#!/usr/bin/env bash
# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
# Same container/IPC namespace and CUDA device visibility as the TP workers.
# Each Pod owns its disposable CPU tier; no host daemon or extra GPU request.
children=()
cleanup() {
  local code=$?
  trap - EXIT INT TERM
  if (( ${#children[@]} )); then
    kill "${children[@]}" 2>/dev/null || true
    wait "${children[@]}" 2>/dev/null || true
  fi
  exit "$code"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
python3 - "$LMCACHE_ADAPTER" <<'PY'
import importlib, os, sys
module = ('lmcache.integration.vllm.lmcache_mp_connector' if sys.argv[1]=='mp'
          else 'lmcache.integration.vllm.vllm_v1_adapter')
try:
    importlib.import_module(module)
except Exception as exc:
    raise SystemExit(f'LMCache adapter {module} cannot load in the selected serving image: {type(exc).__name__}: {exc}')
if os.environ.get('LMCACHE_REQUIRES_HMA', 'false') == 'true':
    try:
        from vllm.config import KVTransferConfig
        from vllm.distributed.kv_transfer.kv_connector.factory import KVConnectorFactory
        config = KVTransferConfig(
            kv_connector='LMCacheMPConnector' if sys.argv[1] == 'mp' else 'LMCacheConnectorV1',
            kv_role='kv_both',
            kv_connector_module_path=module if sys.argv[1] == 'mp' else None,
        )
        compatible = KVConnectorFactory.supports_hma_config(config)
    except Exception as exc:
        raise SystemExit(f'Cannot verify hybrid-cache support in the selected serving image: {type(exc).__name__}: {exc}')
    if not compatible:
        raise SystemExit(
            f'{config.kv_connector} in this serving image does not support the hybrid memory allocator required by this model. '
            'Select a compatible connector/model/image before loading weights. '
            'KV-aware routing is unavailable with the current router; MP offload and routing require separate compatibility checks.'
        )
PY
if [[ $LMCACHE_ADAPTER == mp ]]; then
  lmcache server --host 127.0.0.1 --port 5555 --l1-size-gb "$LMCACHE_CPU_MEMORY_GB" \
    --chunk-size "$LMCACHE_CHUNK_SIZE" --eviction-policy LRU &
  children+=("$!")
  # Fail before loading model weights if the companion never binds its socket.
  set +e
  python3 - "${children[0]}" <<'PY'
import os, socket, sys, time
for _ in range(120):
    try:
        os.kill(int(sys.argv[1]), 0)
        with socket.create_connection(('127.0.0.1', 5555), timeout=1):
            break
    except ProcessLookupError:
        raise SystemExit('LMCache server exited during startup')
    except OSError:
        time.sleep(1)
else:
    raise SystemExit('LMCache server did not bind 127.0.0.1:5555 within 120 seconds')
PY
  startup_code=$?
  set -e
  if (( startup_code != 0 )); then
    if ! kill -0 "${children[0]}" 2>/dev/null; then
      set +e
      wait "${children[0]}"
      startup_code=$?
      set -e
      (( startup_code != 0 )) || startup_code=1
    fi
    printf 'LMCache startup failed (status %s)\n' "$startup_code" >&2
    exit "$startup_code"
  fi
fi
vllm serve "$@" &
children+=("$!")
while :; do
  for child in "${children[@]}"; do
    if ! kill -0 "$child" 2>/dev/null; then
      set +e
      wait "$child"
      code=$?
      set -e
      break 2
    fi
  done
  sleep 0.2
done
# A clean cache-server exit must still fail the serving Pod.
(( code != 0 )) || code=1
printf 'LMCache/serving process exited; stopping the model container (status %s)\n' "$code" >&2
exit "$code"
