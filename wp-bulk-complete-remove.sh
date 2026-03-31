#!/bin/bash
#===============================================================================
# wp-bulk-complete-remove.sh v2.1
#
# ลบ WordPress sites แบบ completely — ไม่เหลือขยะแม้แต่ชิ้นเดียว
# ใช้ cPanel UAPI ลบ DB/User (ชัวกว่า mysql ตรง — cPanel record ไม่เสียหาย)
# ใช้ rm -rf ลบ files (เร็วที่สุด — cPanel ไม่ track files)
#
# สิ่งที่ลบ (11 จุด):
#   ①  WordPress files + domain folder ทั้งหมด (rm -rf รวม cgi-bin/, error_log)
#   ②  WordPress database (cPanel UAPI → ไม่เสียหาย database map)
#   ③  Database user (cPanel UAPI → ไม่เหลือ ghost entry ใน cPanel GUI)
#   ④  WP Toolkit instance record (detach) → หายจาก WP Toolkit GUI
#   ⑤  Softaculous record (.ini) → หายจาก Softaculous GUI
#   ⑥  .wp-toolkit/ directories
#   ⑦  .wp-toolkit-ignore file
#   ⑧  .lscache/ (LiteSpeed cache)
#   ⑨  wordpress-backups/
#   ⑩  wp-cron entries จาก user crontab
#   ⑪  WP Toolkit log files
#   ✗  Addon domain (ใช้ script อีกตัวแยก)
#
# CSV Format: domain,cpanel_user
# Log retention: 1 วัน (ลบ log เก่าอัตโนมัติ)
#
# GitHub: https://github.com/AnonymousVS/WP-Bulk-Complete-Remove
# Author: AnonymousVS
#===============================================================================

set -uo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
SCRIPT_NAME="wp-bulk-complete-remove.sh"
WPTK="/usr/local/bin/wp-toolkit"

GH_USER="AnonymousVS"
GH_REPO="WP-Bulk-Complete-Remove"
GH_BRANCH="main"
GH_LIST_URL="https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/${GH_BRANCH}/remove-domains-list.csv"

LOCAL_LIST="/usr/local/sbin/remove-domains-list.csv"

LOG_DIR="/var/log/wp-bulk-remove"
LOG_RETENTION_DAYS=1
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/remove-${TIMESTAMP}.log"
REPORT_FILE="${LOG_DIR}/report-${TIMESTAMP}.txt"
START_TIME=$(date +%s)

# Colors (dollar-single-quote = real ANSI codes)
R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'
C=$'\033[0;36m'; W=$'\033[1;37m'; DIM=$'\033[2m'; N=$'\033[0m'

SPIN_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPIN_PID=""

# Cleanup on exit (Ctrl+C, error) — kill spinner ถ้าค้าง
cleanup_on_exit() {
    [[ -n "$SPIN_PID" ]] && kill "$SPIN_PID" 2>/dev/null
    printf "\r\033[K"
}
trap cleanup_on_exit EXIT

declare -i TOTAL=0 REMOVED=0 FAILED=0 NOT_FOUND=0
DRY_RUN=false
AUTO_YES=false
USE_LOCAL=false

declare -a DOMAIN_LIST=()
declare -A CPUSER_MAP=()
DB_NAME=""; DB_USER=""

# ==============================================================================
# Usage
# ==============================================================================
usage() {
    cat << EOF

WP Bulk Complete Remove v2.1 — ลบ WordPress sites แบบ completely

Usage: ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
  --dry-run    ทดสอบก่อน ไม่ลบจริง
  --yes        ไม่ถาม confirm
  --local      ใช้ไฟล์ ${LOCAL_LIST} แทนดึงจาก GitHub
  --help       แสดงข้อความนี้

CSV FORMAT:
  domain,cpanel_user
  example.com,y2026m03sv01

EOF
    exit 0
}

# ==============================================================================
# Spinner
# ==============================================================================
spinner_start() {
    local msg="$1"
    {
        local i=0
        while true; do
            printf "\r  ${C}%s${N} %s" "${SPIN_CHARS:i%${#SPIN_CHARS}:1}" "$msg"
            sleep 0.1; ((i++))
        done
    } &
    SPIN_PID=$!; disown "$SPIN_PID" 2>/dev/null
}

spinner_stop() {
    if [[ -n "$SPIN_PID" ]] && kill -0 "$SPIN_PID" 2>/dev/null; then
        kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null
    fi
    SPIN_PID=""
    printf "\r  ${G}[✓]${N} "
}

# ==============================================================================
# Elapsed time
# ==============================================================================
elapsed() {
    local d=$(( $(date +%s) - START_TIME ))
    (( d/60 > 0 )) && echo "$((d/60))m$((d%60))s" || echo "${d}s"
}

# ==============================================================================
# Progress bar
# ==============================================================================
progress() {
    local cur=$1 tot=$2 domain=$3 status=$4
    local pct=0
    (( tot > 0 )) && pct=$(( cur * 100 / tot ))
    local filled=$(( pct * 25 / 100 ))
    local empty=$(( 25 - filled ))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf "\r\033[K  ${C}[%3d%%]${N} ${C}%s${N} %d/%d ${DIM}%s${N}  %-30s %s" \
        "$pct" "$bar" "$cur" "$tot" "$(elapsed)" "$domain" "$status"
}

# ==============================================================================
# Logging
# ==============================================================================
log() { echo "$(date '+%H:%M:%S') [$1] $2" >> "$LOG_FILE"; }
report_line() { echo "$1" >> "$REPORT_FILE"; }

# ==============================================================================
# Log rotation — ลบ log เก่ากว่า 1 วัน
# ==============================================================================
rotate_logs() {
    [[ -d "$LOG_DIR" ]] || return
    find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.txt" \) -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null
}

# ==============================================================================
# Pre-checks
# ==============================================================================
check_requirements() {
    [[ $EUID -ne 0 ]] && { echo -e "${R}Error: ต้องรัน root${N}"; exit 1; }
    mkdir -p "$LOG_DIR"

    # ตรวจว่ามี uapi command
    if ! command -v uapi &>/dev/null; then
        echo -e "${R}Error: ไม่พบ uapi command — ต้องใช้บน cPanel/WHM server${N}"
        exit 1
    fi

    # wp-toolkit เป็น optional (ใช้สำหรับ detach เท่านั้น)
    [[ ! -x "$WPTK" ]] && WPTK=""

    rotate_logs
}

# ==============================================================================
# Fetch + parse CSV
# ==============================================================================
fetch_domain_list() {
    if $USE_LOCAL; then
        [[ ! -f "$LOCAL_LIST" ]] && { echo -e "  ${R}[✗]${N} ไม่พบ ${LOCAL_LIST}"; exit 1; }
        spinner_start "อ่านจาก ${LOCAL_LIST}..."
    else
        spinner_start "ดึง domain list จาก GitHub..."
        local tmp="/tmp/remove-domains-${TIMESTAMP}.csv"
        if ! curl -sL "$GH_LIST_URL" -o "$tmp" 2>/dev/null; then
            spinner_stop; echo -e "${R}ดึงจาก GitHub ไม่สำเร็จ${N}"; exit 1
        fi
        if head -1 "$tmp" | grep -qi "<!DOCTYPE\|<html\|404\|Not Found"; then
            spinner_stop; echo -e "${R}ไม่พบไฟล์บน GitHub — ตรวจ repo/branch${N}"; exit 1
        fi
        LOCAL_LIST="$tmp"
    fi

    local line_num=0 errors=0 header_skipped=false
    while IFS= read -r line; do
        ((line_num++))
        line=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue

        # ข้าม header row
        if ! $header_skipped; then
            header_skipped=true
            echo "$line" | grep -qi "domain\|cpanel\|user" && continue
        fi

        # บังคับต้องมี comma
        if [[ "$line" != *","* ]]; then
            local d_only
            d_only=$(echo "$line" | tr -d '[:space:]' | sed 's|https\?://||;s|/.*||')
            echo -e "\n  ${R}[✗]${N} บรรทัด ${line_num}: ${d_only} — ไม่ได้ระบุ cPanel user"
            echo -e "      ${DIM}format: domain.com,cpanel_username${N}"
            ((errors++)); continue
        fi

        local domain cpuser
        domain=$(echo "$line" | cut -d',' -f1 | tr -d '[:space:]')
        cpuser=$(echo "$line" | cut -d',' -f2 | tr -d '[:space:]')
        domain=$(echo "$domain" | sed 's|https\?://||;s|/.*||')
        [[ -z "$domain" ]] && continue

        if [[ -z "$cpuser" ]]; then
            echo -e "\n  ${R}[✗]${N} บรรทัด ${line_num}: ${domain} — ไม่ได้ระบุ cPanel user"
            ((errors++)); continue
        fi

        if [[ ! -d "/home/${cpuser}" ]]; then
            echo -e "\n  ${R}[✗]${N} บรรทัด ${line_num}: ${domain} — ไม่พบ /home/${cpuser}"
            ((errors++)); continue
        fi

        DOMAIN_LIST+=("$domain")
        CPUSER_MAP["$domain"]="$cpuser"
    done < "$LOCAL_LIST"

    spinner_stop

    if [[ $errors -gt 0 ]]; then
        echo -e "${R}พบ ${errors} errors ในไฟล์ CSV — แก้ไขแล้วลองใหม่${N}"
        exit 1
    fi

    echo "โหลด domain list: ${C}${#DOMAIN_LIST[@]}${N} domains ${DIM}($(elapsed))${N}"
}

# ==============================================================================
# Helpers
# ==============================================================================
find_wp_root() {
    local u="$1" d="$2"
    local p="/home/${u}/${d}"
    [[ -f "${p}/wp-config.php" ]] && { echo "$p"; return 0; }
    p="/home/${u}/public_html/${d}"
    [[ -f "${p}/wp-config.php" ]] && { echo "$p"; return 0; }
    return 1
}

read_wp_config() {
    local c="${1}/wp-config.php"
    [[ ! -f "$c" ]] && return 1
    DB_NAME=$(grep "DB_NAME" "$c" 2>/dev/null | head -1 | grep -oP "(?<=')[^']+(?='[^']*$)" || true)
    DB_USER=$(grep "DB_USER" "$c" 2>/dev/null | head -1 | grep -oP "(?<=')[^']+(?='[^']*$)" || true)
    [[ -n "$DB_NAME" ]] && return 0 || return 1
}

# ==============================================================================
# Remove WordPress — Manual bash + cPanel UAPI
# ① อ่าน wp-config → ② UAPI DROP DB → ③ UAPI DROP USER
# ④ detach WP Toolkit → ⑤ ลบ Softaculous → ⑥ cron → ⑦ WP Toolkit logs
# ⑧ wordpress-backups → ⑨ rm -rf domain folder (สุดท้าย — ลบทุกอย่างรวม cgi-bin)
# ==============================================================================
remove_wordpress() {
    local domain="$1" wp_root="$2" cpuser="$3"
    local home="/home/${cpuser}"

    # ① อ่าน DB info จาก wp-config.php ก่อนลบ files
    read_wp_config "$wp_root" 2>/dev/null || true

    # ② DROP DATABASE ผ่าน cPanel UAPI (ไม่ทำให้ database map เสียหาย)
    if [[ -n "$DB_NAME" ]]; then
        uapi --user="$cpuser" Mysql delete_database name="$DB_NAME" &>/dev/null \
            && log OK "UAPI: DB dropped: ${DB_NAME}" \
            || log WARN "UAPI: DB drop failed: ${DB_NAME} (อาจถูกลบไปแล้ว)"
    fi

    # ③ DROP USER ผ่าน cPanel UAPI (ไม่เหลือ ghost entry ใน cPanel GUI)
    if [[ -n "$DB_USER" ]]; then
        uapi --user="$cpuser" Mysql delete_user name="$DB_USER" &>/dev/null \
            && log OK "UAPI: DB user dropped: ${DB_USER}" \
            || log WARN "UAPI: DB user drop failed: ${DB_USER} (อาจถูกลบไปแล้ว)"
    fi

    # ④ WP Toolkit — detach ออกจาก GUI (ก่อนลบ files — อาจต้องอ่าน path)
    #    detach จะสร้าง .wp-toolkit-ignore → rm -rf ข้อ ⑧ ลบทิ้งให้
    if [[ -n "$WPTK" ]]; then
        local iid
        iid=$($WPTK --list 2>/dev/null | grep -i "$domain" | awk '{print $1}' | head -1)
        if [[ -n "$iid" && "$iid" =~ ^[0-9]+$ ]]; then
            $WPTK --detach -instance-id "$iid" &>/dev/null \
                && log OK "WP Toolkit detached: ID ${iid}"
        fi
    fi

    # ⑤ Softaculous record — ลบ .ini ออกจาก GUI
    if [[ -d "/var/softaculous/installations" ]]; then
        local ini
        ini=$(find /var/softaculous/installations/ -name "*.ini" -exec grep -l "${domain}" {} \; 2>/dev/null || true)
        if [[ -n "$ini" ]]; then
            echo "$ini" | xargs rm -f 2>/dev/null
            log OK "Softaculous record removed"
        fi
    fi

    # ⑥ wp-cron entries จาก user crontab
    local user_cron="/var/spool/cron/${cpuser}"
    if [[ -f "$user_cron" ]] && grep -q "$domain" "$user_cron" 2>/dev/null; then
        sed -i "/${domain//./\\.}/d" "$user_cron" 2>/dev/null
    fi

    # ⑦ WP Toolkit log files
    [[ -d "/usr/local/cpanel/3rdparty/wp-toolkit/var/logs" ]] && \
        find /usr/local/cpanel/3rdparty/wp-toolkit/var/logs/ -name "*${domain}*" -delete 2>/dev/null

    # ⑧ wordpress-backups/ (เฉพาะ domain นี้ — อยู่คนละที่กับ domain folder)
    [[ -d "${home}/wordpress-backups/${domain}" ]] && rm -rf "${home}/wordpress-backups/${domain}"

    # ⑨ ลบ domain folder ทั้งหมด — ทำเป็นขั้นตอนสุดท้าย
    #    rm -rf ลบทุกอย่างใน folder: WordPress files, cgi-bin/, error_log,
    #    .wp-toolkit/, .wp-toolkit-ignore, .lscache/, wp-content/cache/ ฯลฯ
    local path1="/home/${cpuser}/${domain}"
    local path2="/home/${cpuser}/public_html/${domain}"
    [[ -d "$path1" ]] && rm -rf "$path1" && log OK "Removed: ${path1}"
    [[ -d "$path2" ]] && rm -rf "$path2" && log OK "Removed: ${path2}"

    return 0
}

# ==============================================================================
# Process single domain
# ==============================================================================
process_domain() {
    local domain="$1" n="$2"
    DB_NAME=""; DB_USER=""

    local cpuser="${CPUSER_MAP[$domain]}"

    # หา WordPress root (เช็คทั้ง 2 paths)
    local wp_root
    wp_root=$(find_wp_root "$cpuser" "$domain")

    # ถ้าไม่เจอ wp-config → เช็คว่ามี folder ค้างไหม
    if [[ -z "$wp_root" ]]; then
        local f1="/home/${cpuser}/${domain}"
        local f2="/home/${cpuser}/public_html/${domain}"

        if [[ -d "$f1" || -d "$f2" ]]; then
            if ! $DRY_RUN; then
                [[ -d "$f1" ]] && rm -rf "$f1" && log OK "Leftover removed: ${f1}"
                [[ -d "$f2" ]] && rm -rf "$f2" && log OK "Leftover removed: ${f2}"
                # detach จาก WP Toolkit + Softaculous
                if [[ -n "$WPTK" ]]; then
                    local oid
                    oid=$($WPTK --list 2>/dev/null | grep -i "$domain" | awk '{print $1}' | head -1)
                    [[ -n "$oid" && "$oid" =~ ^[0-9]+$ ]] && $WPTK --detach -instance-id "$oid" &>/dev/null
                fi
                [[ -d "/var/softaculous/installations" ]] && \
                    find /var/softaculous/installations/ -name "*.ini" -exec grep -l "${domain}" {} \; 2>/dev/null | xargs rm -f 2>/dev/null
            fi
            progress $n $TOTAL "$domain" "${G}cleaned ✓${N}"
            report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "CLEANED" "leftover folder removed")"
            ((REMOVED++)); return
        fi

        # ไม่มี folder → เช็ค WP Toolkit
        if [[ -n "$WPTK" ]]; then
            local oid
            oid=$($WPTK --list 2>/dev/null | grep -i "$domain" | awk '{print $1}' | head -1)
            if [[ -n "$oid" && "$oid" =~ ^[0-9]+$ ]]; then
                ! $DRY_RUN && $WPTK --detach -instance-id "$oid" &>/dev/null
                progress $n $TOTAL "$domain" "${G}detached ✓${N}"
                report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "DETACHED" "WP Toolkit orphan")"
                ((REMOVED++)); return
            fi
        fi

        progress $n $TOTAL "$domain" "${Y}not found${N}"
        report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "NOT_FOUND" "ไม่พบใน /home/${cpuser}")"
        ((NOT_FOUND++)); return
    fi

    # Dry run
    if $DRY_RUN; then
        read_wp_config "$wp_root" 2>/dev/null || true
        progress $n $TOTAL "$domain" "${Y}[DRY] would remove${N}"
        report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "DRY_RUN" "DB:${DB_NAME:-?} User:${DB_USER:-?}")"
        ((REMOVED++)); return
    fi

    # ลบจริง
    progress $n $TOTAL "$domain" "${Y}removing...${N}"
    remove_wordpress "$domain" "$wp_root" "$cpuser"
    progress $n $TOTAL "$domain" "${G}done ✓${N}"
    report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "REMOVED" "DB:${DB_NAME:-?} User:${DB_USER:-?}")"
    log OK "Complete: ${domain} (DB:${DB_NAME:-?} User:${DB_USER:-?})"
    ((REMOVED++))
}

# ==============================================================================
# Summary
# ==============================================================================
print_summary() {
    local el; el=$(elapsed)
    {
        echo ""; echo "============================================================"
        echo "SUMMARY"; echo "============================================================"
        echo "Total: ${TOTAL}  Removed: ${REMOVED}  Failed: ${FAILED}  Not found: ${NOT_FOUND}"
        echo "Elapsed: ${el}"
    } >> "$REPORT_FILE"

    printf "\r\033[K"
    echo ""
    echo -e "${C}══════════════════════════════════════════════════════════════════${N}"
    echo -e "${C}  RESULTS                                       ${DIM}elapsed: ${el}${N}"
    echo -e "${C}══════════════════════════════════════════════════════════════════${N}"
    echo ""
    echo -e "  Total domains:     ${W}${TOTAL}${N}"
    echo ""
    echo -e "  ${G}✓${N} Removed:           ${G}${REMOVED}${N}"
    echo -e "  ${R}✗${N} Failed:            ${R}${FAILED}${N}"
    echo -e "  ${Y}→${N} Not found:         ${Y}${NOT_FOUND}${N}"
    echo ""
    (( REMOVED > 0 )) && ! $DRY_RUN && echo -e "  ${G}✓ ลบเรียบร้อย ${REMOVED} domains — ไม่เหลือขยะ${N}" && echo ""
    (( FAILED > 0 )) && echo -e "  ${R}! ${FAILED} domains ลบไม่สำเร็จ — ดูใน report${N}" && echo ""
    echo -e "  ${DIM}Report: ${REPORT_FILE}${N}"
    echo -e "  ${DIM}Log:    ${LOG_FILE}${N}"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    echo -e "${C}══════════════════════════════════════════════════════════════════${N}"
    echo -e "${C}  WP Bulk Complete Remove ${DIM}v2.1${N}"
    echo -e "${C}  ลบ WordPress sites แบบ completely — ไม่เหลือขยะ${N}"
    echo -e "${C}══════════════════════════════════════════════════════════════════${N}"
    echo ""
    $DRY_RUN && echo -e "  ${Y}*** DRY RUN — ไม่ลบจริง ***${N}" && echo ""

    check_requirements
    fetch_domain_list
    TOTAL=${#DOMAIN_LIST[@]}

    [[ $TOTAL -eq 0 ]] && { echo -e "\n  ${Y}ไม่มี domain ในรายการ${N}"; exit 0; }

    # แสดง list
    echo ""
    echo -e "  ${W}รายชื่อ domain ที่จะลบ (${TOTAL} domains):${N}"
    echo -e "  ${DIM}──────────────────────────────────────────────────────${N}"
    printf "  ${DIM}%-35s %s${N}\n" "DOMAIN" "cPanel USER"
    echo -e "  ${DIM}──────────────────────────────────────────────────────${N}"
    local i=0
    for d in "${DOMAIN_LIST[@]}"; do
        ((i++))
        (( i <= 20 )) && printf "  ${R}✗${N} %-35s ${DIM}%s${N}\n" "$d" "${CPUSER_MAP[$d]}"
        (( i == 21 && TOTAL > 20 )) && echo -e "  ${DIM}  ... และอีก $((TOTAL-20)) domains${N}"
    done
    echo -e "  ${DIM}──────────────────────────────────────────────────────${N}"
    echo ""

    # Confirm
    if ! $AUTO_YES; then
        echo -e "  ${R}⚠  การลบนี้ย้อนกลับไม่ได้ — files + database จะถูกลบถาวร${N}"
        echo ""
        echo -e "  ${Y}Note: หากรันครั้งที่ 2 เป็นต้นไป โปรดตรวจสอบรายชื่อ domain ด้านบนให้ถูกต้อง${N}"
        echo -e "  ${Y}      GitHub อาจ cache ไฟล์เก่าไว้ หากรายชื่อไม่ตรง ให้รอ 5 นาทีแล้วรันใหม่${N}"
        echo ""
        read -p "  ลบทั้ง ${TOTAL} domains? (พิมพ์ yes): " confirm
        [[ "$confirm" != "yes" ]] && { echo "  ยกเลิก"; exit 0; }
        echo ""
    fi

    # Report header
    {
        echo "WP Bulk Complete Remove v2.1 Report — $(date)"
        echo "Server: $(hostname) | Dry Run: ${DRY_RUN} | Total: ${TOTAL}"
        echo "============================================================"
        printf "%-35s %-15s %-12s %s\n" "DOMAIN" "USER" "STATUS" "DETAIL"
    } > "$REPORT_FILE"

    echo -e "  ${W}เริ่มลบ...${N}"
    echo ""

    # Process (sequential)
    local n=0
    for d in "${DOMAIN_LIST[@]}"; do
        ((n++))
        process_domain "$d" "$n"
    done

    print_summary
}

# ==============================================================================
# Parse args
# ==============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --yes)     AUTO_YES=true; shift ;;
        --local)   USE_LOCAL=true; shift ;;
        --help|-h) usage ;;
        *)         echo -e "${R}Unknown: $1${N}"; exit 1 ;;
    esac
done

main
