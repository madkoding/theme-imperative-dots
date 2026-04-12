#!/usr/bin/env bash

ACTION="${1:-}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
mkdir -p "$RUNTIME_DIR" >/dev/null 2>&1

json_bool() {
    if [[ "$1" == "1" || "$1" == "true" ]]; then
        printf "true"
    else
        printf "false"
    fi
}

emit_result() {
    local ok="$1"
    local running="$2"
    local message="$3"
    jq -nc \
        --argjson ok "$(json_bool "$ok")" \
        --argjson running "$(json_bool "$running")" \
        --arg message "$message" \
        '{ok: $ok, running: $running, message: $message}'
}

float_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'
}

safe_port() {
    local raw="$1"
    local fallback="$2"
    if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw > 0 && raw < 65536 )); then
        printf "%s" "$raw"
    else
        printf "%s" "$fallback"
    fi
}

port_listening() {
    local port="$1"
    if [[ -z "$port" || "$port" == "0" ]]; then
        return 1
    fi
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E "[:.]${port}$" >/dev/null 2>&1
}

wait_for_running() {
    local timeout_ms="$1"
    shift
    local waited=0
    while (( waited < timeout_ms )); do
        if "$@"; then
            return 0
        fi
        sleep 0.25
        waited=$((waited + 250))
    done
    "$@"
}

wait_for_stopped() {
    local timeout_ms="$1"
    shift
    local waited=0
    while (( waited < timeout_ms )); do
        if ! "$@"; then
            return 0
        fi
        sleep 0.25
        waited=$((waited + 250))
    done
    ! "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

opencode_running() {
    local host="$1"
    local port="$2"

    if ! pgrep -x opencode >/dev/null 2>&1; then
        return 1
    fi

    if [[ -n "$port" && "$port" != "0" ]]; then
        if port_listening "$port"; then
            return 0
        fi
    fi

    if [[ -n "$host" ]]; then
        pgrep -af '^opencode serve' 2>/dev/null | grep -F -- "--hostname ${host}" >/dev/null 2>&1 && return 0
    fi

    pgrep -af '^opencode serve' >/dev/null 2>&1
}

ollama_running() {
    local port="$1"

    if ! pgrep -x ollama >/dev/null 2>&1; then
        return 1
    fi

    if [[ -n "$port" && "$port" != "0" ]]; then
        port_listening "$port" && return 0
        return 1
    fi

    pgrep -af '^ollama serve' >/dev/null 2>&1
}

openclaw_running() {
    local pattern="${1:-openclaw.*gateway}"
    local line
    local pid
    local cmd

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pid="${line%% *}"
        cmd="${line#* }"

        [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
        [[ "$cmd" == *"ia_services.sh"* ]] && continue
        [[ "$cmd" == *"pgrep -af"* ]] && continue

        return 0
    done < <(pgrep -af -- "$pattern" 2>/dev/null || true)

    return 1
}

array_to_json() {
    if [[ "$#" -eq 0 ]]; then
        printf '[]'
    else
        printf '%s\n' "$@" | jq -R -s 'split("\n")[:-1]'
    fi
}

detect_vram_action() {
    local detected="false"
    local source="none"
    local gib="0.0"

    if command_exists nvidia-smi; then
        local total_mib
        total_mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk 'BEGIN{s=0} /^[0-9]+/ {s+=$1} END{if (s>0) print s}')"
        if [[ -n "$total_mib" ]]; then
            gib="$(awk -v mib="$total_mib" 'BEGIN { printf "%.1f", mib/1024 }')"
            detected="true"
            source="nvidia-smi"
        fi
    fi

    if [[ "$detected" != "true" ]]; then
        local total_bytes
        total_bytes="$(awk 'BEGIN{s=0} {if ($1 ~ /^[0-9]+$/) s+=$1} END{if (s>0) print s}' /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null)"
        if [[ -n "$total_bytes" ]]; then
            gib="$(awk -v b="$total_bytes" 'BEGIN { printf "%.1f", b/1073741824 }')"
            detected="true"
            source="sysfs-drm"
        fi
    fi

    if [[ "$detected" != "true" ]] && command_exists rocm-smi; then
        local rocm_bytes
        rocm_bytes="$(rocm-smi --showmeminfo vram --json 2>/dev/null | jq -r '[.. | objects | .["VRAM Total Memory (B)"]? | select(.) | tonumber] | add // 0' 2>/dev/null)"
        if [[ -n "$rocm_bytes" && "$rocm_bytes" != "0" && "$rocm_bytes" != "null" ]]; then
            gib="$(awk -v b="$rocm_bytes" 'BEGIN { printf "%.1f", b/1073741824 }')"
            detected="true"
            source="rocm-smi"
        fi
    fi

    jq -nc \
        --argjson detected "$(json_bool "$detected")" \
        --arg source "$source" \
        --argjson gib "$gib" \
        '{detected: $detected, source: $source, gib: $gib}'
}

recommended_models_for_vram() {
    local vram="${1:-0.0}"
    if float_ge "$vram" "24"; then
        printf '%s\n' "qwen2.5:14b" "llama3.1:8b" "gemma2:9b" "phi4:14b"
    elif float_ge "$vram" "16"; then
        printf '%s\n' "llama3.1:8b" "qwen2.5:7b" "mistral:7b" "gemma2:9b"
    elif float_ge "$vram" "12"; then
        printf '%s\n' "qwen2.5:7b" "llama3.2:3b" "mistral:7b" "phi3.5:3.8b"
    elif float_ge "$vram" "8"; then
        printf '%s\n' "llama3.2:3b" "qwen2.5:3b" "phi3:mini" "gemma2:2b"
    elif float_ge "$vram" "6"; then
        printf '%s\n' "qwen2.5:1.5b" "llama3.2:1b" "gemma2:2b" "phi3:mini"
    else
        printf '%s\n' "llama3.2:1b" "qwen2.5:0.5b" "tinyllama:1.1b" "gemma2:2b"
    fi
}

ollama_models_action() {
    local vram_raw="${1:-0.0}"
    local vram
    vram="$(awk -v x="$vram_raw" 'BEGIN { if (x+0 == x) printf "%.1f", x; else print "0.0" }')"

    local recommended=()
    local installed=()
    local candidates=()

    while IFS= read -r model; do
        [[ -n "$model" ]] && recommended+=("$model")
    done < <(recommended_models_for_vram "$vram")

    if command_exists ollama; then
        while IFS= read -r model; do
            [[ -n "$model" ]] && installed+=("$model")
        done < <(ollama list 2>/dev/null | awk 'NR > 1 {print $1}' | awk 'NF' | sort -u)
    fi

    if [[ "${#installed[@]}" -gt 0 && "${#recommended[@]}" -gt 0 ]]; then
        declare -A recommended_lookup=()
        local model
        for model in "${recommended[@]}"; do
            recommended_lookup["$model"]=1
        done
        for model in "${installed[@]}"; do
            if [[ -n "${recommended_lookup[$model]+x}" ]]; then
                candidates+=("$model")
            fi
        done
    fi

    if [[ "${#candidates[@]}" -eq 0 ]]; then
        if [[ "${#recommended[@]}" -gt 0 ]]; then
            candidates=("${recommended[@]}")
        elif [[ "${#installed[@]}" -gt 0 ]]; then
            candidates=("${installed[@]}")
        else
            candidates=("llama3.2:1b")
        fi
    fi

    local recommended_json
    local installed_json
    local candidates_json
    recommended_json="$(array_to_json "${recommended[@]}")"
    installed_json="$(array_to_json "${installed[@]}")"
    candidates_json="$(array_to_json "${candidates[@]}")"

    jq -nc \
        --argjson vram "$vram" \
        --argjson recommended "$recommended_json" \
        --argjson installed "$installed_json" \
        --argjson candidates "$candidates_json" \
        '{vram: $vram, recommended: $recommended, installed: $installed, candidates: $candidates}'
}

status_action() {
    local op_host="${1:-0.0.0.0}"
    local op_port
    op_port="$(safe_port "${2:-4096}" "4096")"
    local ol_host="${3:-127.0.0.1}"
    local ol_port
    ol_port="$(safe_port "${4:-11434}" "11434")"
    local oc_match="${5:-openclaw.*gateway}"
    local oc_start="${6:-openclaw gateway --port 18789}"

    local op_running="false"
    local ol_running="false"
    local oc_running="false"
    local op_available="false"
    local ol_available="false"
    local oc_available="true"

    opencode_running "$op_host" "$op_port" && op_running="true"
    ollama_running "$ol_port" && ol_running="true"
    openclaw_running "$oc_match" && oc_running="true"

    command_exists opencode && op_available="true"
    command_exists ollama && ol_available="true"

    if [[ "$oc_start" =~ ^[[:space:]]*openclaw([[:space:]]|$) ]] && ! command_exists openclaw; then
        oc_available="false"
    fi

    jq -nc \
        --arg op_host "$op_host" \
        --argjson op_port "$op_port" \
        --arg ol_host "$ol_host" \
        --argjson ol_port "$ol_port" \
        --arg oc_match "$oc_match" \
        --argjson op_running "$(json_bool "$op_running")" \
        --argjson ol_running "$(json_bool "$ol_running")" \
        --argjson oc_running "$(json_bool "$oc_running")" \
        --argjson op_available "$(json_bool "$op_available")" \
        --argjson ol_available "$(json_bool "$ol_available")" \
        --argjson oc_available "$(json_bool "$oc_available")" \
        '{
            opencode: {running: $op_running, available: $op_available, host: $op_host, port: $op_port},
            ollama: {running: $ol_running, available: $ol_available, host: $ol_host, port: $ol_port},
            openclaw: {running: $oc_running, available: $oc_available, match: $oc_match}
        }'
}

opencode_start_action() {
    local host="${1:-0.0.0.0}"
    local port
    port="$(safe_port "${2:-4096}" "4096")"
    local extra_args="${3:-}"

    if ! command_exists opencode; then
        emit_result false false "OpenCode no esta instalado en PATH."
        return
    fi

    if opencode_running "$host" "$port"; then
        emit_result true true "OpenCode ya esta activo."
        return
    fi

    local cmd="opencode serve --hostname $(printf '%q' "$host") --port $(printf '%q' "$port")"
    if [[ -n "$extra_args" ]]; then
        cmd+=" ${extra_args}"
    fi

    nohup bash -lc "$cmd" >"${RUNTIME_DIR}/opencode-serve.log" 2>&1 &

    if wait_for_running 12000 opencode_running "$host" "$port"; then
        emit_result true true "OpenCode activo en ${host}:${port}."
    else
        pkill -x opencode >/dev/null 2>&1 || true
        emit_result false false "Fallo al levantar OpenCode. Revisa ${RUNTIME_DIR}/opencode-serve.log"
    fi
}

opencode_stop_action() {
    local host="${1:-0.0.0.0}"
    local port
    port="$(safe_port "${2:-4096}" "4096")"

    if ! opencode_running "$host" "$port"; then
        emit_result true false "OpenCode ya estaba apagado."
        return
    fi

    pkill -x opencode >/dev/null 2>&1 || true

    if wait_for_stopped 8000 opencode_running "$host" "$port"; then
        emit_result true false "OpenCode detenido."
    else
        emit_result false true "No se pudo detener OpenCode."
    fi
}

ollama_start_action() {
    local host="${1:-127.0.0.1}"
    local port
    port="$(safe_port "${2:-11434}" "11434")"
    local model="${3:-}"
    local auto_pull="${4:-1}"

    if ! command_exists ollama; then
        emit_result false false "Ollama no esta instalado en PATH."
        return
    fi

    local hostport="${host}:${port}"
    if ollama_running "$port"; then
        emit_result true true "Ollama ya esta activo en ${hostport}."
        return
    fi

    local cmd="OLLAMA_HOST=$(printf '%q' "$hostport") ollama serve"
    nohup bash -lc "$cmd" >"${RUNTIME_DIR}/ollama-serve.log" 2>&1 &

    if wait_for_running 12000 ollama_running "$port"; then
        if [[ "$auto_pull" == "1" && -n "$model" ]]; then
            local pull_cmd="OLLAMA_HOST=$(printf '%q' "$hostport") ollama pull $(printf '%q' "$model")"
            nohup bash -lc "$pull_cmd" >"${RUNTIME_DIR}/ollama-pull.log" 2>&1 &
        fi
        emit_result true true "Ollama activo en ${hostport}."
    else
        pkill -x ollama >/dev/null 2>&1 || true
        emit_result false false "Fallo al levantar Ollama. Revisa ${RUNTIME_DIR}/ollama-serve.log"
    fi
}

ollama_stop_action() {
    local port
    port="$(safe_port "${2:-11434}" "11434")"

    if ! ollama_running "$port"; then
        emit_result true false "Ollama ya estaba apagado."
        return
    fi

    pkill -x ollama >/dev/null 2>&1 || true

    if wait_for_stopped 8000 ollama_running "$port"; then
        emit_result true false "Ollama detenido."
    else
        emit_result false true "No se pudo detener Ollama."
    fi
}

openclaw_start_action() {
    local start_cmd="${1:-openclaw gateway --port 18789}"
    local match="${2:-openclaw.*gateway}"

    if [[ -z "$start_cmd" ]]; then
        emit_result false false "Define un comando de inicio para OpenClaw."
        return
    fi

    if [[ "$start_cmd" =~ ^[[:space:]]*openclaw([[:space:]]|$) ]] && ! command_exists openclaw; then
        emit_result false false "OpenClaw no esta instalado en PATH."
        return
    fi

    if openclaw_running "$match"; then
        emit_result true true "OpenClaw ya esta activo."
        return
    fi

    nohup bash -lc "$start_cmd" >"${RUNTIME_DIR}/openclaw-gateway.log" 2>&1 &

    if wait_for_running 12000 openclaw_running "$match"; then
        emit_result true true "OpenClaw activo."
    else
        emit_result false false "Fallo al levantar OpenClaw. Revisa ${RUNTIME_DIR}/openclaw-gateway.log"
    fi
}

openclaw_stop_action() {
    local match="${1:-openclaw.*gateway}"
    local stop_cmd="${2:-}"

    if [[ -n "$stop_cmd" ]]; then
        bash -lc "$stop_cmd" >/dev/null 2>&1 || true
    else
        pkill -f -- "$match" >/dev/null 2>&1 || true
    fi

    if wait_for_stopped 8000 openclaw_running "$match"; then
        emit_result true false "OpenClaw detenido."
    else
        emit_result false true "No se pudo detener OpenClaw."
    fi
}

case "$ACTION" in
    detect-vram)
        detect_vram_action
        ;;

    ollama-models)
        ollama_models_action "${2:-0.0}"
        ;;

    status)
        status_action "${2:-0.0.0.0}" "${3:-4096}" "${4:-127.0.0.1}" "${5:-11434}" "${6:-openclaw.*gateway}" "${7:-openclaw gateway --port 18789}"
        ;;

    opencode-start)
        opencode_start_action "${2:-0.0.0.0}" "${3:-4096}" "${4:-}"
        ;;

    opencode-stop)
        opencode_stop_action "${2:-0.0.0.0}" "${3:-4096}"
        ;;

    ollama-start)
        ollama_start_action "${2:-127.0.0.1}" "${3:-11434}" "${4:-}" "${5:-1}"
        ;;

    ollama-stop)
        ollama_stop_action "${2:-127.0.0.1}" "${3:-11434}"
        ;;

    openclaw-start)
        openclaw_start_action "${2:-openclaw gateway --port 18789}" "${3:-openclaw.*gateway}"
        ;;

    openclaw-stop)
        openclaw_stop_action "${2:-openclaw.*gateway}" "${3:-}"
        ;;

    *)
        emit_result false false "Accion desconocida: ${ACTION}"
        ;;
esac
