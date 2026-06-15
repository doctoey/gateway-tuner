#!/bin/bash
# =================================================================
# doctoey :: Split-Tunnel Network Controller (Modern Minimalist v4.2)
# Detects active LAN, injects internal subnet routes via gateway.
# CONNECT: LAN reachable → inject routes + tune metrics
# CLEAN  : LAN absent/unreachable → remove routes, reset metrics
# =================================================================

set -euo pipefail

# -- Configuration (Replace with your own internal network targets)
GW="10.0.0.254"
NETS=("10.1.0.0/16" "10.2.0.0/16" "10.3.0.0/16" \
      "172.16.0.0/16" "172.17.0.0/16" "192.168.1.0/24")

# -- Colors & Styles (Cyberpunk Neon Scheme) ----------------------
B='\033[1;34m'; G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; C='\033[1;36m'; W='\033[1;37m'; NC='\033[0m'
T_GRAY='\033[90m'; T_VIOLET='\033[35m'; T_CYAN='\033[36m'

clear
echo -e "${C}● ${W}Initializing Network Controller...${NC}"
echo -e "${B}────────────────────────────────────────────────────────${NC}"
sudo -v || exit 1

# -- Interface Detection ------------------------------------------
ACTIVE_LAN=$(route get "$GW" 2>/dev/null | awk '/interface:/{print $2}' || true)
WIFI_IF=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}' || true)

# Grab the default external Wi-Fi gateway IP for enhanced telemetry summary
WIFI_GW=$(route get default 2>/dev/null | awk '/gateway:/{print $2}' || echo "UNKNOWN")

# -- Interrupt Handler -------------------------------------------
# Triggers on Ctrl+C or SIGTERM to rollback all network mutations
_cleanup() {
    echo -e "\n${R} ⚠  INTERRUPTED — Rolling back changes...${NC}"
    [[ -n "${ACTIVE_LAN:-}" ]] && sudo ifconfig "$ACTIVE_LAN" metric 0 2>/dev/null || true
    [[ -n "${WIFI_IF:-}" ]] && sudo ifconfig "$WIFI_IF" metric 0 2>/dev/null || true
    for n in "${NETS[@]}"; do
        sudo route -n delete "$n" >/dev/null 2>&1 || true
    done
    exit 1
}
trap '_cleanup' INT TERM

# -- Mode Decision ------------------------------------------------
# CONNECT requirements: LAN interface exists, is not Wi-Fi, and gateway responds
MODE="CLEAN"
if [[ -n "${ACTIVE_LAN:-}" && "${ACTIVE_LAN:-}" != "${WIFI_IF:-}" ]]; then
    if ping -c 1 -W 2000 "$GW" >/dev/null 2>&1; then
        MODE="CONNECT"
    fi
fi

# Output current link discovery status (Upper section)
if [[ "$MODE" == "CONNECT" ]]; then
    echo -e "${T_CYAN} ➔ ${NC}LINK STATUS    ${T_GRAY}.......${NC} LAN: ${G}$ACTIVE_LAN${NC} ┃ WIFI: ${WIFI_IF:-N/A}"
else
    echo -e "${T_CYAN} ➔ ${NC}LINK STATUS    ${T_GRAY}.......${NC} LAN: ${Y}INACTIVE${NC} ┃ WIFI: ${WIFI_IF:-N/A}"
fi

# =================================================================
# CLEAN MODE — Purge managed routes and restore standard metrics
# =================================================================
if [[ "$MODE" == "CLEAN" ]]; then
    echo -e "${T_CYAN} ➔ ${NC}RESETTING NET  ${T_GRAY}.......${NC} ${T_CYAN}Working...${NC}"

    # Reset Wi-Fi interface metric back to default
    [[ -n "${WIFI_IF:-}" ]] && sudo ifconfig "$WIFI_IF" metric 0 2>/dev/null || true

    # Restore LAN interface metric — fallback to alternative physical if cable was pulled
    if [[ -z "${ACTIVE_LAN:-}" ]]; then
        if [[ -n "${WIFI_IF:-}" ]]; then
            PHYSICAL_IF=$(networksetup -listallhardwareports | grep -A 1 "Hardware Port:" | grep "Device:" | grep -v "$WIFI_IF" | head -n 1 | awk '{print $2}' || true)
        else
            PHYSICAL_IF=$(networksetup -listallhardwareports | grep -A 1 "Hardware Port:" | grep "Device:" | head -n 1 | awk '{print $2}' || true)
        fi
        [[ -n "${PHYSICAL_IF:-}" ]] && sudo ifconfig "$PHYSICAL_IF" metric 0 2>/dev/null || true
    else
        sudo ifconfig "$ACTIVE_LAN" metric 0 2>/dev/null || true
    fi

    # Remove all internally managed subnet routes
    for n in "${NETS[@]}"; do
        sudo route -n delete "$n" >/dev/null 2>&1 || true
    done

    echo -e "   ${T_GRAY}└─${NC} Flushing routes ${T_GRAY}........................${NC} [ ${G}✔ OK${NC} ]"

    # Flush macOS native DNS resolver cache
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true

    # ---- MINIMALIST SUMMARY (CLEAN MODE) ----
    echo ""
    echo -e "${B}─ ${W}NETWORK STATUS SUMMARY ${B}──────────────────────────────${NC}"
    printf "  %-18s : %b%s${NC}\n" "CURRENT STATE" "$Y" "DEFAULT ROUTING"
    printf "  %-18s : %bWi-Fi (%b%s%b)${NC}\n" "PRIMARY UPLINK" "$W" "$C" "${WIFI_IF:-UNKNOWN}" "$W"
    printf "  %-18s : %b%s${NC}\n" "ROUTING MODE" "$Y" "STANDARD"
    echo -e "${B}────────────────────────────────────────────────────────${NC}"
    exit 0
fi

# =================================================================
# CONNECT MODE — Inject subnet routes and tune metrics for split-tunneling
# =================================================================
if [[ "$MODE" == "CONNECT" ]]; then

    echo -e "${T_CYAN} ➔ ${NC}GATEWAY CHECK  ${T_GRAY}.......${NC} ${G}ONLINE${NC} ($GW)"
    echo -e "${T_CYAN} ➔ ${NC}INJECTING RTM  ${T_GRAY}.......${NC} Executing..."

    # LAN metric 1 wins for internal targets; Wi-Fi metric 100 handles general internet
    sudo ifconfig "$ACTIVE_LAN" metric 1
    [[ -n "${WIFI_IF:-}" ]] && sudo ifconfig "$WIFI_IF" metric 100

    # Purge stale routing entries before injection phase
    for n in "${NETS[@]}"; do
        sudo route -n delete "$n" >/dev/null 2>&1 || true
    done

    # Execute atomic injection loop across predefined subnets
    SUCCESS=0
    for i in "${!NETS[@]}"; do
        n=${NETS[$i]}
        STATUS="[ ${R}FAIL${NC} ]"
        if sudo route -n add -net "$n" "$GW" -ifp "$ACTIVE_LAN" >/dev/null 2>&1; then
            STATUS="[  ${G}OK${NC}  ]"
            SUCCESS=$((SUCCESS + 1))
        fi

        if [ $i -eq $(( ${#NETS[@]} - 1 )) ]; then
            echo -e "   ${T_GRAY}└─${NC} $n ${T_GRAY}.........................${NC} $STATUS"
        else
            echo -e "   ${T_GRAY}├─${NC} $n ${T_GRAY}.........................${NC} $STATUS"
        fi
    done

    # Atomic Rollback: Flush all changes if any route registration fails
    if [[ "$SUCCESS" -ne "${#NETS[@]}" ]]; then
        echo -e "\n${R} ⚠  CRITICAL ERROR :: Partial Injection ($SUCCESS/${#NETS[@]})${NC}"
        echo -e "${Y}   Rolling back changes...${NC}"
        for n in "${NETS[@]}"; do sudo route -n delete "$n" >/dev/null 2>&1 || true; done
        sudo ifconfig "$ACTIVE_LAN" metric 0
        [[ -n "${WIFI_IF:-}" ]] && sudo ifconfig "$WIFI_IF" metric 0
        exit 1
    fi

    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true

    DEFAULT_IF=$(route get default 2>/dev/null | awk '/interface:/{print $2}' || echo "UNKNOWN")

    # ---- MINIMALIST SUMMARY (CONNECT MODE - FIXED PARSING BUG) ----
    echo ""
    echo -e "${B}─ ${W}NETWORK STATUS SUMMARY ${B}──────────────────────────────${NC}"
    
    printf "  %-18s : %b%s (Gateway: %s)${NC}\n" "INTERNAL PATH" "$G" "$ACTIVE_LAN" "$GW"
    
    if [[ "$DEFAULT_IF" == "$WIFI_IF" ]]; then
        printf "  %-18s : %b%s (Wi-Fi Gateway: %s)${NC}\n" "EXTERNAL PATH" "$C" "$WIFI_IF" "$WIFI_GW"
        
        printf "  %-18s : %b%s${NC}\n" "CURRENT STATE" "$G" "SECURE SPLIT-TUNNEL"
        echo -e "${B}────────────────────────────────────────────────────────${NC}"
    else
        # Fault isolation handler: Triggers if LAN hijacked the primary default route scope
        printf "  %-18s : %b%s (HIJACKED!)${NC}\n" "EXTERNAL PATH" "$R" "$DEFAULT_IF"
        printf "  %-18s : %b%s${NC}\n" "CURRENT STATE" "$R" "ERROR — ROLLING BACK"
        echo -e "${B}────────────────────────────────────────────────────────${NC}"

        for n in "${NETS[@]}"; do sudo route -n delete "$n" >/dev/null 2>&1 || true; done
        sudo ifconfig "$ACTIVE_LAN" metric 0
        [[ -n "${WIFI_IF:-}" ]] && sudo ifconfig "$WIFI_IF" metric 0
        exit 1
    fi
fi