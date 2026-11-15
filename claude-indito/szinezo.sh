# Kézzel indított `claude` és `codex` színezése (nem kötelező).
# A terminál hátterét és szövegszínét a repó színére állítja (OSC 11/10), kilépéskor
# visszaállítja (OSC 111/110). Csak VTE-terminálban (Ptyxis, GNOME Terminal) dolgozik,
# és kimarad, ha az ablakot már a Claude indító nyitotta a repó saját profiljával.
#
# Bekapcsolás: a ~/.bashrc végére
#   . "/út/a/claude-indito/szinezo.sh"

_ci_py="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/szinprofil.py"
_ci_state="${XDG_DATA_HOME:-$HOME/.local/share}/claude-indito/profilok.tsv"

_ci_szinez() {
    local prog=$1 bg="" fg="" rc
    shift
    if [ -t 1 ] && [ -n "${VTE_VERSION:-}" ] &&
        ! { [ -n "${PTYXIS_PROFILE:-}" ] && grep -qs "^$PTYXIS_PROFILE" "$_ci_state"; }; then
        read -r bg fg < <(python3 "$_ci_py" szin "$PWD" 2>/dev/null)
        [ -n "$bg" ] && printf '\033]11;%s\033\\\033]10;%s\033\\' "$bg" "$fg"
    fi
    command "$prog" "$@"
    rc=$?
    [ -n "$bg" ] && printf '\033]111\033\\\033]110\033\\'
    return $rc
}

claude() { _ci_szinez claude "$@"; }
codex() { _ci_szinez codex "$@"; }
