#!/usr/bin/env bash
# Abilita modalità rigorosa: interrompe lo script in caso di errore.
set -euo pipefail

# Verifica che siano stati passati esattamente due argomenti.
if [ "$#" -ne 2 ]; then
  echo "Uso: $0 CLASSE NOME_UTENTE" >&2
  echo "Esempio: $0 3A rossi_mario" >&2
  exit 1
fi

# Assegna i parametri a variabili leggibili.
CLASSE="$1"            # Identificativo della classe (es. 3A)
USERNAME="$2"          # Nome utente già formattato (es. rossi_mario)

# Calcola l'anno corrente (es. 2026).
ANNO="$(date +%Y)"

# Definisce la base delle home degli studenti.
BASE_DIR="/home/root/as_${ANNO}/${CLASSE}"

# Definisce il gruppo primario per gli studenti della classe.
GRUPPO="studenti_${CLASSE}"

# Crea il gruppo se non esiste già.
if ! getent group "$GRUPPO" > /dev/null 2>&1; then
  groupadd "$GRUPPO"
fi

# Crea la gerarchia di directory base per l'anno e la classe.
mkdir -p "$BASE_DIR"

# Imposta i permessi in modo che solo root e il proprietario delle sottodirectory possano accedere.
chmod 755 "/home/root/as_${ANNO}"        # Leggibile da tutti, scrivibile solo da root.
chown root:root "/home/root/as_${ANNO}"  # Necessario per eventuali chroot futuri.
chmod 755 "$BASE_DIR"          # Leggibile da tutti, scrivibile solo da root.
chown root:root "$BASE_DIR"    # Le home degli studenti saranno sottodirectory.

# Definisce la home dell'utente.
HOME_DIR="${BASE_DIR}/${USERNAME}"

# Se l'utente esiste già, lo segnala ed esce senza errori.
if id "$USERNAME" > /dev/null 2>&1; then
  echo "[INFO] Utente $USERNAME esiste già, nessuna operazione eseguita." >&2
  exit 0
fi

# Crea l'utente con home dedicata e shell bash.
useradd -m -d "$HOME_DIR" -s /bin/bash -g "$GRUPPO" "$USERNAME"

# Imposta permessi restrittivi sulla home.
chmod 700 "$HOME_DIR"            # Solo l'utente può leggere/scrivere.
chown "$USERNAME:$GRUPPO" "$HOME_DIR"  # Proprietario: utente, gruppo: classe.

# Definisce la password di default (stessa per tutti nella classe).
DEFAULT_PASS="1234567890abcdef"

# Imposta la password per l'utente.
echo "${USERNAME}:${DEFAULT_PASS}" | chpasswd

# Forza il cambio password al primo login.
chage -d 0 "$USERNAME"

# File di output con utenti e password iniziali.
OUTPUT_PASS_FILE="studenti_passwords_${CLASSE}.csv"

# Se il file delle password non esiste, crea l'intestazione
if [ ! -f "$OUTPUT_PASS_FILE" ]; then
  echo "username;password;classe" > "$OUTPUT_PASS_FILE"
fi

# Registra username e password nel file di output, accodando l'informazione.
echo "${USERNAME};${DEFAULT_PASS};${CLASSE}" >> "$OUTPUT_PASS_FILE"

# Messaggio finale.
echo "[OK] Utente $USERNAME creato per la classe ${CLASSE}. Dettagli salvati in ${OUTPUT_PASS_FILE}."
