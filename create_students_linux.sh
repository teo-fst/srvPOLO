#!/usr/bin/env bash
# Script: create_students_linux.sh
# Scopo: creare utenti Linux per una classe a partire da un CSV,
#        assegnare una password di default fissa e forzare il cambio
#        password al primo login.
# Uso:   sudo ./create_students_linux.sh studenti.csv CLASSE

# Abilita modalità rigorosa (interrompe lo script in caso di errore, variabili non definite, pipe fallite).
set -euo pipefail

# Verifica che lo script sia eseguito come root (necessario per creare utenti e cambiare password).
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERRORE] Devi eseguire questo script come root (o con sudo)." >&2
  exit 1
fi

# Verifica che siano stati passati esattamente due argomenti: file CSV e classe.
if [ "$#" -ne 2 ]; then
  echo "Uso: $0 studenti.csv CLASSE" >&2
  exit 1
fi

# Assegna i parametri a variabili leggibili.
CSV_FILE="$1"   # Percorso del file CSV con l'elenco studenti (formato cognome;nome).
CLASSE="$2"     # Identificativo della classe (es. 3A).

# Verifica che il file CSV esista e sia leggibile.
if [ ! -f "$CSV_FILE" ]; then
  echo "[ERRORE] File CSV '$CSV_FILE' non trovato." >&2
  exit 1
fi

if [ ! -r "$CSV_FILE" ]; then
  echo "[ERRORE] File CSV '$CSV_FILE' non leggibile." >&2
  exit 1
fi

# Calcola l'anno corrente (es. 2026) per costruire il percorso base delle home.
ANNO="$(date +%Y)"

# Definisce la base delle home degli studenti, ad es. /as_2026/3A.
BASE_DIR="/home/root/as_${ANNO}/${CLASSE}"

# Definisce il gruppo primario per gli studenti della classe, es. studenti_3A.
GRUPPO="studenti_${CLASSE}"

# Definisce la password di default fissa richiesta.
DEFAULT_PASS="1234567890abcdef"

# Crea il gruppo se non esiste già.
if ! getent group "$GRUPPO" > /dev/null 2>&1; then
  echo "[INFO] Creo il gruppo '$GRUPPO'..."
  groupadd "$GRUPPO"
fi

# Crea la gerarchia di directory base per l'anno e la classe.
mkdir -p "$BASE_DIR"

# Imposta permessi e proprietà sulle directory base.
# /as_<ANNO> e /as_<ANNO>/<CLASSE> sono di root; le singole home avranno permessi 700.
mkdir -p "/home/root/as_${ANNO}"
chown root:root "/home/root/as_${ANNO}"
chmod 755 "/home/root/as_${ANNO}"

chown root:root "$BASE_DIR"
chmod 755 "$BASE_DIR"

# File di output con l'elenco degli utenti creati e la password iniziale (uguale per tutti).
OUTPUT_PASS_FILE="studenti_passwords_${CLASSE}.csv"

echo "username;password;classe" > "$OUTPUT_PASS_FILE"

# Legge il CSV riga per riga usando ';' come separatore di campo.
# Formato atteso: cognome;nome
while IFS=';' read -r COGNOME NOME; do
  # Se la riga è vuota (nessun cognome), la salta.
  if [ -z "${COGNOME}" ]; then
    continue
  fi

  # Salta l'eventuale riga di intestazione (cognome;nome).
  if [ "$COGNOME" = "cognome" ] || [ "$COGNOME" = "Cognome" ]; then
    continue
  fi

  # Normalizza cognome e nome: minuscolo, spazi in '_', rimozione caratteri non alfanumerici/underscore.
  U_COGNOME="$(echo "$COGNOME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')"
  U_NOME="$(echo "$NOME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')"

  # Costruisce l'username nel formato cognome_nome, ad es. rossi_mario.
  USERNAME="${U_COGNOME}_${U_NOME}"

  # Definisce la home dell'utente, ad es. /as_2026/3A/rossi_mario.
  HOME_DIR="${BASE_DIR}/${USERNAME}"

  # Se l'utente esiste già, lo segnala e passa al prossimo studente.
  if id "$USERNAME" > /dev/null 2>&1; then
    echo "[INFO] Utente $USERNAME esiste già, salto la creazione." >&2

    # In ogni caso, forza la password di default e il cambio al primo login se vuoi riallineare la classe.
    echo "${USERNAME}:${DEFAULT_PASS}" | chpasswd
    chage -d 0 "$USERNAME"

    echo "${USERNAME};${DEFAULT_PASS};${CLASSE}" >> "$OUTPUT_PASS_FILE"
    continue
  fi

  echo "[INFO] Creo utente $USERNAME con home $HOME_DIR..."

  # Crea l'utente con:
  # - home dedicata (-m -d),
  # - shell bash (-s /bin/bash),
  # - gruppo primario della classe (-g "$GRUPPO").
  useradd -m -d "$HOME_DIR" -s /bin/bash -g "$GRUPPO" "$USERNAME"

  # Imposta permessi restrittivi sulla home (solo l'utente può leggere/scrivere).
  chmod 700 "$HOME_DIR"
  chown "$USERNAME:$GRUPPO" "$HOME_DIR"

  # Imposta la password di default per l'utente.
  echo "${USERNAME}:${DEFAULT_PASS}" | chpasswd

  # Forza il cambio password al primo login impostando la data di ultimo cambio a 0.
  chage -d 0 "$USERNAME"

  # Registra username e password nel file di output.
  echo "${USERNAME};${DEFAULT_PASS};${CLASSE}" >> "$OUTPUT_PASS_FILE"

done < "$CSV_FILE"

# Messaggio finale con riepilogo.
echo "[OK] Elaborazione completata per la classe ${CLASSE}."
echo "[OK] Elenco utenti e password iniziale salvato in: ${OUTPUT_PASS_FILE}"
