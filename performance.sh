#!/usr/bin/env bash
set -euo pipefail

GPU_CARD="card1"
GPU_SYSFS="/sys/class/drm/${GPU_CARD}/device"
GPU_PERF_LEVEL="high"
VERIFY_DELAY=3

log() { echo "[*] $*"; }
warn() { echo "[!] $*" >&2; }

if ! command -v ryzenadj &> /dev/null; then
    echo "Error: ryzenadj tidak ditemukan di PATH." >&2
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Script ini perlu root. Jalankan dengan sudo." >&2
    exit 1
fi

if [[ ! -e "${GPU_SYSFS}/power_dpm_force_performance_level" ]]; then
    echo "Error: sysfs GPU tidak ditemukan di ${GPU_SYSFS}" >&2
    echo "Cek ulang device dengan: ls /sys/class/drm/" >&2
    exit 1
fi

STOPPED_SERVICES=()
for svc in tlp power-profiles-daemon auto-cpufreq; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        warn "Service '${svc}' aktif dan akan maksa GPU perf level (low/auto)."
        warn "Menghentikan sementara: sudo systemctl stop ${svc}"
        systemctl stop "${svc}" && STOPPED_SERVICES+=("${svc}")
    fi
done

echo "== [1/3] Menerapkan power limit 25W ke AMD 3020e via ryzenadj =="
set +e
ryzenadj \
  --stapm-limit=25000 \
  --fast-limit=28000 \
  --slow-limit=25000 \
  --stapm-time=300 \
  --slow-time=90 \
  --tctl-temp=90 \
  --vrm-current=30000 \
  --vrmsoc-current=20000 \
  --vrmmax-current=40000 \
  --vrmsocmax-current=25000 \
  --psi0-current=5000 \
  --psi0soc-current=5000 \
  --max-socclk-frequency=1200 \
  --min-socclk-frequency=400 \
  --max-fclk-frequency=1200 \
  --min-fclk-frequency=400 \
  --max-vcn=1100 \
  --max-lclk=1200 \
  --min-lclk=400 \
  --max-gfxclk=1300 \
  --min-gfxclk=200 \
  --prochot-deassertion-ramp=10 \
  -i
ryzenadj_rc=$?
set -e
if [[ "${ryzenadj_rc}" -ne 0 ]]; then
    warn "ryzenadj keluar dengan exit code ${ryzenadj_rc} — cek output di atas."
fi

log "Tunggu SMU settle (${VERIFY_DELAY}s)..."
sleep "${VERIFY_DELAY}"

RUNTIME_STATUS_FILE="${GPU_SYSFS}/power/runtime_status"
if [[ -e "${RUNTIME_STATUS_FILE}" ]]; then
    rt_status="$(cat "${RUNTIME_STATUS_FILE}")"
    if [[ "${rt_status}" != "active" ]]; then
        warn "GPU runtime PM status: '${rt_status}' (bukan 'active')."
    fi
fi

SCLK_FILE="${GPU_SYSFS}/pp_dpm_sclk"
sclk_level_count=0
if [[ -e "${SCLK_FILE}" ]]; then
    sclk_level_count="$(wc -l < "${SCLK_FILE}")"
    if [[ "${sclk_level_count}" -le 1 ]]; then
        warn "pp_dpm_sclk cuma punya ${sclk_level_count} level."
    fi
fi

echo
echo "== [2/3] Set GPU (${GPU_CARD}) performance level ke '${GPU_PERF_LEVEL}' =="
echo "${GPU_PERF_LEVEL}" > "${GPU_SYSFS}/power_dpm_force_performance_level" \
    || warn "Write ke power_dpm_force_performance_level gagal (lihat dmesg)."

sleep "${VERIFY_DELAY}"

applied_level="$(cat "${GPU_SYSFS}/power_dpm_force_performance_level")"
echo "-- Status GPU performance level setelah verifikasi ulang: ${applied_level}"

if [[ "${applied_level}" != "${GPU_PERF_LEVEL}" ]]; then
    warn "Level yang diminta ('${GPU_PERF_LEVEL}') tidak nempel — sekarang '${applied_level}'."
    warn "Cek: dmesg | tail -30"
    echo
    echo "== [3/3] Fallback: coba mode 'manual' + pilih level sclk tertinggi =="
    if [[ -e "${SCLK_FILE}" ]]; then
        echo manual > "${GPU_SYSFS}/power_dpm_force_performance_level" || true
        sleep 1
        highest_index="$(awk -F: '{print $1}' "${SCLK_FILE}" | tail -n1 | tr -d ' ')"
        if [[ -n "${highest_index}" ]]; then
            echo "${highest_index}" > "${GPU_SYSFS}/pp_dpm_sclk" || \
                warn "Gagal menulis pp_dpm_sclk index ${highest_index}."
            log "Dipaksa ke level sclk index ${highest_index}."
        fi
    else
        warn "pp_dpm_sclk tidak tersedia, fallback manual dilewati."
    fi
else
    echo "== [3/3] Level '${GPU_PERF_LEVEL}' berhasil diterapkan, fallback dilewati =="
fi

echo
echo "-- Status akhir GPU performance level:"
cat "${GPU_SYSFS}/power_dpm_force_performance_level"

if [[ -e "${SCLK_FILE}" ]]; then
    echo
    echo "-- Level clock (pp_dpm_sclk), tanda [*] = level aktif sekarang:"
    cat "${SCLK_FILE}"
fi

echo
echo "== Selesai. =="
if [[ "${#STOPPED_SERVICES[@]}" -gt 0 ]]; then
    echo "Service berikut dihentikan sementara supaya nggak nimpa balik GPU:"
    printf '  - %s\n' "${STOPPED_SERVICES[@]}"
    echo "Kalau mau dihidupkan lagi nanti:"
    for s in "${STOPPED_SERVICES[@]}"; do
        echo "  sudo systemctl start ${s}"
    done
fi
echo "Pantau suhu (mis. 'sensors' atau 's-tui') beberapa menit ke depan."