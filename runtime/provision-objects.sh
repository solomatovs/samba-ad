#!/bin/bash
# Идемпотентное наполнение AD по декларативному конфигу.
# Запускается init-хуком entrypoint (когда AD поднят) или вручную.
# Сам ничего «своего» не знает — все объекты описаны в domain-objects.conf
# (рядом со скриптом, либо путь в $OBJECTS_CONF).
#
# Формат конфига (источается как bash) — см. domain-objects.conf:
#   AD_GROUPS=( имя ... )
#   AD_USERS=( "имя:пароль:группа1,группа2" ... )
#   AD_SERVICES=( "имя:пароль:spn1,spn2:delegation:keytab" ... )
#       delegation:
#         ""              — без делегирования
#         "any"           — неограниченное (for-any-service / unconstrained)
#         "to=spn1,spn2"  — ограниченное (constrained), только Kerberos
#         "proto=spn1,..." — ограниченное + protocol transition (for-any-protocol)
#       keytab:     путь для экспорта keytab принципалов SPN, либо пусто
#   ВНИМАНИЕ: пароль не должен содержать двоеточие ':'.
set -uo pipefail

REALM="${REALM:?REALM не задан}"
OBJECTS_CONF="${OBJECTS_CONF:-$(dirname "$0")/domain-objects.conf}"

log() { echo "[provision-objects] $*"; }

if [ ! -f "${OBJECTS_CONF}" ]; then
    log "конфиг ${OBJECTS_CONF} не найден — нечего создавать"
    exit 0
fi

# ждём готовности AD (на случай прямого запуска вне entrypoint)
log "жду готовности AD ..."
for _ in $(seq 1 90); do
    samba-tool user list >/dev/null 2>&1 && break
    sleep 2
done
if ! samba-tool user list >/dev/null 2>&1; then
    log "AD недоступен — объекты не созданы"
    exit 0
fi

# shellcheck source=/dev/null
. "${OBJECTS_CONF}"

user_exists()  { samba-tool user list  2>/dev/null | grep -qx "$1"; }
group_exists() { samba-tool group list 2>/dev/null | grep -qx "$1"; }

export_keytab() {
    local keytab="$1"; shift
    local dir; dir="$(dirname "${keytab}")"
    if [ ! -d "${dir}" ]; then
        log "каталог ${dir} не смонтирован — keytab ${keytab} пропущен"
        return 0
    fi
    rm -f "${keytab}"
    local spn
    for spn in "$@"; do
        [ -n "${spn}" ] || continue
        samba-tool domain exportkeytab "${keytab}" --principal="${spn}@${REALM}" >/dev/null 2>&1
    done
    chmod 0644 "${keytab}" 2>/dev/null || true
    log "keytab -> ${keytab}"
}

# --- группы ---
for g in "${AD_GROUPS[@]:-}"; do
    [ -n "${g}" ] || continue
    group_exists "${g}" || { log "group add ${g}"; samba-tool group add "${g}"; }
done

# --- пользователи: имя:пароль:группы ---
for spec in "${AD_USERS[@]:-}"; do
    [ -n "${spec}" ] || continue
    IFS=: read -r name pass groups <<<"${spec}"
    user_exists "${name}" || { log "user create ${name}"; samba-tool user create "${name}" "${pass}"; }
    IFS=, read -ra grps <<<"${groups}"
    for grp in "${grps[@]}"; do
        [ -n "${grp}" ] && samba-tool group addmembers "${grp}" "${name}" 2>/dev/null || true
    done
done

# --- сервисные учётки: имя:пароль:spn1,spn2:delegation:keytab ---
for spec in "${AD_SERVICES[@]:-}"; do
    [ -n "${spec}" ] || continue
    IFS=: read -r name pass spns deleg keytab <<<"${spec}"
    user_exists "${name}" || { log "service create ${name}"; samba-tool user create "${name}" "${pass}"; }
    samba-tool user setexpiry "${name}" --noexpiry 2>/dev/null || true

    IFS=, read -ra spn_list <<<"${spns}"
    for spn in "${spn_list[@]}"; do
        [ -n "${spn}" ] || continue
        samba-tool spn list "${name}" 2>/dev/null | grep -q "${spn}" \
            || { log "spn add ${spn} -> ${name}"; samba-tool spn add "${spn}" "${name}"; }
    done

    case "${deleg}" in
        "" )
            : # без делегирования
            ;;
        any )
            log "delegation unconstrained (for-any-service) ${name}"
            samba-tool delegation for-any-service "${name}" on 2>/dev/null || true
            ;;
        to=* | proto=* )
            if [ "${deleg%%=*}" = "proto" ]; then
                log "delegation protocol-transition (for-any-protocol) ${name}"
                samba-tool delegation for-any-protocol "${name}" on 2>/dev/null || true
            fi
            IFS=, read -ra deleg_targets <<<"${deleg#*=}"
            for tgt in "${deleg_targets[@]}"; do
                [ -n "${tgt}" ] || continue
                log "delegation add-service ${tgt} -> ${name}"
                samba-tool delegation add-service "${name}" "${tgt}" 2>/dev/null || true
            done
            ;;
        * )
            log "WARN: неизвестный режим делегирования '${deleg}' для ${name} — пропущен"
            ;;
    esac

    [ -n "${keytab}" ] && export_keytab "${keytab}" "${spn_list[@]}"
done

log "готово"
