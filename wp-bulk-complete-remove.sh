#!/bin/bash
#===============================================================================
# wp-bulk-complete-remove.sh v1.0
#
# ลบ WordPress sites แบบ completely — ไม่เหลือขยะแม้แต่ชิ้นเดียว
# รองรับทั้ง WP Toolkit และ Softaculous installations
#
# สิ่งที่ลบ:
#   ✓ WordPress files ทั้งหมด
#   ✓ WordPress database
#   ✓ Database user (orphaned)
#   ✓ WP Toolkit instance record
#   ✓ WP Toolkit log files
#   ✓ .wp-toolkit/ directories
#   ✓ .wp-toolkit-ignore file
#   ✓ Softaculous record (ถ้ามี)
#   ✓ .lscache/ (LiteSpeed cache)
#   ✓ wordpress-backups/
#   ✓ wp-content/cache/, upgrade/, tmp/
#   ✓ wp-cron entries จาก crontab
#   ✗ Addon domain (ใช้ script อีกตัวที่มีอยู่แล้ว)
#
# รองรับ 2 path structures:
#   /home/USERNAME/DOMAIN/
#   /home/USERNAME/public_html/DOMAIN/
#
# Install:
#   curl -sL https://raw.githubusercontent.com/AnonymousVS/WP-Bulk-Complete-Remove/main/wp-bulk-complete-remove.sh -o /usr/local/sbin/wp-bulk-complete-remove.sh && chmod +x /usr/local/sbin/wp-bulk-complete-remove.sh && echo "✓ Installed"
#
# Usage:
#   wp-bulk-complete-remove.sh                # ดึง list จาก GitHub + ลบ
#   wp-bulk-complete-remove.sh --local        # ใช้ local file แทน GitHub
#   wp-bulk-complete-remove.sh --dry-run      # ทดสอบก่อน ไม่ลบจริง
#   wp-bulk-complete-remove.sh --yes          # ไม่ถาม confirm
#
# GitHub: https://github.com/AnonymousVS/WP-Bulk-Complete-Remove
# Author: AnonymousVS
#===============================================================================

set -uo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
SCRIPT_NAME="wp-bulk-complete-remove.sh"
SCRIPT_PATH="/usr/local/sbin/${SCRIPT_NAME}"
WPTK="/usr/local/bin/wp-toolkit"
USERDOMAINS="/etc/userdomains"

GH_USER="AnonymousVS"
GH_REPO="WP-Bulk-Complete-Remove"
GH_BRANCH="main"
GH_LIST_URL="https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/${GH_BRANCH}/remove-domains-list.txt"

LOCAL_LIST="/usr/local/sbin/remove-domains-list.txt"

LOG_DIR="/var/log/wp-bulk-remove"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/remove-${TIMESTAMP}.log"
REPORT_FILE="${LOG_DIR}/report-${TIMESTAMP}.txt"
START_TIME=$(date +%s)

# Colors
R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'
B=$'\033[0;34m'; C=$'\033[0;36m'; W=$'\033[1;37m'; DIM=$'\033[2m'; N=$'\033[0m'

SPIN_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPIN_PID=""

declare -i TOTAL=0 REMOVED=0 CLEANED=0 FAILED=0 NOT_FOUND=0

DRY_RUN=false
AUTO_YES=false
USE_LOCAL=false

declare -a DOMAIN_LIST=()

# DB vars per domain
DB_NAME="" ; DB_USER=""

# ==============================================================================
# Usage
# ==============================================================================
usage() {
    cat << EOF

WP Bulk Complete Remove — ลบ WordPress sites แบบ completely

Usage: ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
  --dry-run    ทดสอบก่อน ไม่ลบจริง
  --yes        ไม่ถาม confirm
  --local      ใช้ไฟล์ ${LOCAL_LIST} แทนดึงจาก GitHub
  --help       แสดงข้อความนี้

FLOW:
  1) แก้ไข remove-domains-list.txt บน GitHub → Commit
  2) SSH เข้าเซิร์ฟเวอร์
  3) รัน: wp-bulk-complete-remove.sh
  4) Script ดึง list → แสดง → ถาม confirm → ลบ → report

EOF
    exit 0
}

# ==============================================================================
# Helpers
# ==============================================================================
spinner_start() {
    {
        local i=0
        while true; do
            printf "\r  ${C}%s${N} %s" "${SPIN_CHARS:i%${#SPIN_CHARS}:1}" "$1"
            sleep 0.1; ((i++))
        done
    } &
    SPIN_PID=$!; disown "$SPIN_PID" 2>/dev/null
}

spinner_stop() {
    [[ -n "$SPIN_PID" ]] && kill "$SPIN_PID" 2>/dev/null && wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""; printf "\r  ${G}[✓]${N} "
}

elapsed() {
    local d=$(( $(date +%s) - START_TIME ))
    (( d/60 > 0 )) && echo "$((d/60))m$((d%60))s" || echo "${d}s"
}

progress() {
    local cur=$1 tot=$2 domain=$3 status=$4 pct=0
    (( tot > 0 )) && pct=$(( cur * 100 / tot ))
    local bar="" i filled=$(( pct*25/100 )) empty=$(( 25 - pct*25/100 ))
    for ((i=0;i<filled;i++)); do bar+="█"; done
    for ((i=0;i<empty;i++)); do bar+="░"; done
    printf "\r  ${C}[%3d%%]${N} %s %d/%d ${DIM}%s${N}  %-35s %s    " \
        "$pct" "$bar" "$cur" "$tot" "$(elapsed)" "$domain" "$status"
}

log() { echo "$(date '+%H:%M:%S') [$1] $2" >> "$LOG_FILE"; }
report_line() { echo "$1" >> "$REPORT_FILE"; }

# ==============================================================================
# Pre-checks
# ==============================================================================
check_requirements() {
    [[ $EUID -ne 0 ]] && { echo -e "${R}Error: ต้องรัน root${N}"; exit 1; }
    [[ ! -f "$USERDOMAINS" ]] && { echo -e "${R}Error: ไม่พบ ${USERDOMAINS}${N}"; exit 1; }
    mkdir -p "$LOG_DIR"
    [[ ! -x "$WPTK" ]] && { echo -e "  ${Y}[!]${N} ไม่พบ wp-toolkit CLI — จะข้าม WP Toolkit removal"; WPTK=""; }
}

# ==============================================================================
# Fetch domain list
# ==============================================================================
fetch_domain_list() {
    if $USE_LOCAL; then
        [[ ! -f "$LOCAL_LIST" ]] && { echo -e "  ${R}[✗]${N} ไม่พบ ${LOCAL_LIST}"; exit 1; }
        spinner_start "อ่านจาก ${LOCAL_LIST}..."
    else
        spinner_start "ดึง domain list จาก GitHub..."
        local tmp="/tmp/remove-domains-${TIMESTAMP}.txt"
        if ! curl -sL "$GH_LIST_URL" -o "$tmp" 2>/dev/null; then
            spinner_stop; echo -e "${R}ดึงจาก GitHub ไม่สำเร็จ${N}"; exit 1
        fi
        # ตรวจว่าเป็น HTML error page หรือไม่
        if head -1 "$tmp" | grep -qi "<!DOCTYPE\|<html\|404\|Not Found"; then
            spinner_stop; echo -e "${R}ไม่พบไฟล์บน GitHub — ตรวจ repo/branch ให้ถูกต้อง${N}"; exit 1
        fi
        LOCAL_LIST="$tmp"
    fi

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
        [[ -z "$line" ]] && continue
        line=$(echo "$line" | sed 's|https\?://||;s|/.*||')
        DOMAIN_LIST+=("$line")
    done < "$LOCAL_LIST"

    spinner_stop
    echo "โหลด domain list: ${C}${#DOMAIN_LIST[@]}${N} domains ${DIM}($(elapsed))${N}"
}

# ==============================================================================
# Lookup helpers
# ==============================================================================
find_cpanel_user() {
    grep -i "^${1}:" "$USERDOMAINS" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | tr -d '[:space:]'
}

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

find_wptk_instance() {
    [[ -z "$WPTK" ]] && return 1
    local id
    id=$($WPTK --list 2>/dev/null | grep -i "$1" | awk '{print $1}' | head -1)
    [[ -n "$id" && "$id" =~ ^[0-9]+$ ]] && { echo "$id"; return 0; }
    return 1
}

# ==============================================================================
# Step 1: Remove WordPress (sequential)
# ==============================================================================
step1_remove() {
    local domain="$1" wp_root="$2" cpuser="$3"

    # ลอง WP Toolkit --remove ก่อน
    local iid
    iid=$(find_wptk_instance "$domain") || iid=""
    if [[ -n "$iid" && -n "$WPTK" ]]; then
        if $WPTK --remove -instance-id "$iid" &>/dev/null; then
            log OK "WP Toolkit removed: ${domain} (ID:${iid})"
            echo "WPTK"; return 0
        fi
        log WARN "WP Toolkit remove failed for ${domain} — fallback to manual"
    fi

    # Manual removal
    read_wp_config "$wp_root" 2>/dev/null || true

    # Drop database
    [[ -n "$DB_NAME" ]] && mysql -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" 2>/dev/null \
        && log OK "DB dropped: ${DB_NAME}"

    # Drop DB user
    [[ -n "$DB_USER" ]] && mysql -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';" 2>/dev/null \
        && mysql -e "FLUSH PRIVILEGES;" 2>/dev/null \
        && log OK "DB user dropped: ${DB_USER}"

    # Delete files
    [[ -d "$wp_root" ]] && rm -rf "$wp_root" && log OK "Files removed: ${wp_root}"

    echo "MANUAL"; return 0
}

# ==============================================================================
# Step 2: Deep cleanup
# ==============================================================================
step2_cleanup() {
    local domain="$1" wp_root="$2" cpuser="$3"
    local home="/home/${cpuser}"
    local c=0

    # .wp-toolkit/ dirs
    for d in "${home}/${domain}/.wp-toolkit" "${home}/public_html/${domain}/.wp-toolkit"; do
        [[ -d "$d" ]] && rm -rf "$d" && ((c++))
    done

    # .wp-toolkit-ignore
    for f in "${home}/${domain}/.wp-toolkit-ignore" "${home}/public_html/${domain}/.wp-toolkit-ignore"; do
        [[ -f "$f" ]] && rm -f "$f" && ((c++))
    done

    # .lscache/
    for d in "${home}/${domain}/.lscache" "${home}/public_html/${domain}/.lscache"; do
        [[ -d "$d" ]] && rm -rf "$d" && ((c++))
    done

    # wordpress-backups/ (เฉพาะ domain นี้)
    [[ -d "${home}/wordpress-backups/${domain}" ]] && rm -rf "${home}/wordpress-backups/${domain}" && ((c++))

    # Leftover WP dirs
    for sub in "wp-content/cache" "wp-content/upgrade" "wp-content/tmp" "wp-content/ai1wm-backups" "wp-content/updraft"; do
        [[ -d "${wp_root}/${sub}" ]] && rm -rf "${wp_root}/${sub}" && ((c++))
    done

    # Softaculous records
    if [[ -d "/var/softaculous/installations" ]]; then
        local ini
        ini=$(find /var/softaculous/installations/ -name "*.ini" -exec grep -l "${domain}" {} \; 2>/dev/null || true)
        [[ -n "$ini" ]] && echo "$ini" | xargs rm -f 2>/dev/null && ((c++)) && log OK "Softaculous record removed"
    fi

    # wp-cron in user crontab
    local crontab="/var/spool/cron/${cpuser}"
    if [[ -f "$crontab" ]] && grep -q "$domain" "$crontab" 2>/dev/null; then
        sed -i "/${domain//./\\.}/d" "$crontab" 2>/dev/null && ((c++))
    fi

    # WP Toolkit logs
    [[ -d "/usr/local/cpanel/3rdparty/wp-toolkit/var/logs" ]] && \
        find /usr/local/cpanel/3rdparty/wp-toolkit/var/logs/ -name "*${domain}*" -delete 2>/dev/null && ((c++))

    # Orphaned DB user (ถ้า WP Toolkit ลบ DB แล้วแต่ไม่ลบ user)
    if [[ -n "${DB_USER:-}" ]]; then
        local exists
        exists=$(mysql -N -e "SELECT User FROM mysql.user WHERE User='${DB_USER}' AND Host='localhost';" 2>/dev/null || true)
        if [[ -n "$exists" ]]; then
            local db_exists
            db_exists=$(mysql -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME:-}';" 2>/dev/null || true)
            if [[ -z "$db_exists" ]]; then
                mysql -e "DROP USER IF EXISTS '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && ((c++))
                log OK "Orphaned DB user removed: ${DB_USER}"
            fi
        fi
    fi

    # Empty leftover directory
    if [[ -d "$wp_root" ]]; then
        local fc
        fc=$(find "$wp_root" -type f 2>/dev/null | wc -l)
        [[ $fc -eq 0 ]] && rm -rf "$wp_root" && ((c++))
    fi

    echo "$c"
}

# ==============================================================================
# Process single domain
# ==============================================================================
process_domain() {
    local domain="$1" n="$2"
    DB_NAME=""; DB_USER=""

    local cpuser
    cpuser=$(find_cpanel_user "$domain")
    if [[ -z "$cpuser" ]]; then
        progress $n $TOTAL "$domain" "${Y}not in server${N}"
        report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "-" "NOT_FOUND" "ไม่พบใน /etc/userdomains")"
        ((NOT_FOUND++)); return
    fi

    local wp_root
    wp_root=$(find_wp_root "$cpuser" "$domain")
    if [[ -z "$wp_root" ]]; then
        progress $n $TOTAL "$domain" "${Y}no WordPress${N} "
        report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "NO_WP" "ไม่พบ wp-config.php")"
        ((NOT_FOUND++)); return
    fi

    # อ่าน DB info ก่อน (ใช้ใน cleanup)
    read_wp_config "$wp_root" 2>/dev/null || true

    if $DRY_RUN; then
        progress $n $TOTAL "$domain" "${Y}[DRY] would remove${N}"
        report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "DRY_RUN" "${wp_root}")"
        ((REMOVED++)); return
    fi

    # Step 1
    progress $n $TOTAL "$domain" "${Y}removing...${N}    "
    local method
    method=$(step1_remove "$domain" "$wp_root" "$cpuser")

    # Step 2
    progress $n $TOTAL "$domain" "${Y}cleaning...${N}    "
    local cleaned
    cleaned=$(step2_cleanup "$domain" "$wp_root" "$cpuser")

    progress $n $TOTAL "$domain" "${G}done ✓${N}         "
    report_line "$(printf '%-35s %-15s %-12s %s' "$domain" "$cpuser" "REMOVED" "via:${method} cleaned:${cleaned}")"
    log OK "Complete: ${domain} (${method}, cleaned:${cleaned})"
    ((REMOVED++)); ((CLEANED+=cleaned))
}

# ==============================================================================
# Summary
# ==============================================================================
print_summary() {
    local el; el=$(elapsed)
    {
        echo ""; echo "============================================================"
        echo "SUMMARY"; echo "============================================================"
        echo "Total: ${TOTAL}  Removed: ${REMOVED}  Cleaned: ${CLEANED}  Failed: ${FAILED}  Not found: ${NOT_FOUND}"
        echo "Elapsed: ${el}"
    } >> "$REPORT_FILE"

    echo ""
    echo -e "${C}══════════════════════════════════════════════════════════════════${N}"
    echo -e "${C}  RESULTS                                       ${DIM}elapsed: ${el}${N}"
    echo -e "${C}══════════════════════════════════════════════════════════════════${N}"
    echo ""
    echo -e "  Total domains:     ${W}${TOTAL}${N}"
    echo ""
    echo -e "  ${G}✓${N} Removed:           ${G}${REMOVED}${N}"
    echo -e "  ${G}✓${N} Items cleaned:     ${G}${CLEANED}${N}"
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
    echo -e "${C}  WP Bulk Complete Remove${N}"
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
    echo -e "  ${DIM}──────────────────────────────────────${N}"
    local i=0
    for d in "${DOMAIN_LIST[@]}"; do
        ((i++))
        (( i <= 20 )) && echo -e "  ${R}✗${N} ${d}"
        (( i == 21 && TOTAL > 20 )) && echo -e "  ${DIM}  ... และอีก $((TOTAL-20)) domains${N}"
    done
    echo -e "  ${DIM}──────────────────────────────────────${N}"
    echo ""

    # Confirm
    if ! $AUTO_YES; then
        echo -e "  ${R}⚠  การลบนี้ย้อนกลับไม่ได้ — files + database จะถูกลบถาวร${N}"
        echo ""
        read -p "  ลบทั้ง ${TOTAL} domains? (พิมพ์ yes): " confirm
        [[ "$confirm" != "yes" ]] && { echo "  ยกเลิก"; exit 0; }
        echo ""
    fi

    # Report header
    {
        echo "WP Bulk Complete Remove Report — $(date)"
        echo "Server: $(hostname) | Dry Run: ${DRY_RUN} | Total: ${TOTAL}"
        echo "============================================================"
        printf "%-35s %-15s %-12s %s\n" "DOMAIN" "USER" "STATUS" "DETAIL"
    } > "$REPORT_FILE"

    echo -e "  ${W}เริ่มลบ...${N}"
    echo ""

    # Process (sequential — ปลอดภัย)
    local n=0
    for d in "${DOMAIN_LIST[@]}"; do
        ((n++))
        process_domain "$d" "$n"
        sleep 0.2
    done

    printf "\r%100s\r" ""
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
