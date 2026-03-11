# Ambiente Docker sicuro per webapp studentesche in laboratorio

## Indice

1. [Panoramica e obiettivi](#panoramica-e-obiettivi)
2. [Architettura logica](#architettura-logica)
3. [Gestione utenti Linux su Debian 13](#gestione-utenti-linux-su-debian-13)
   1. [Prerequisiti](#prerequisiti-linux)
   2. [Formato CSV di input](#formato-csv-di-input)
   3. [Script `create_students_linux.sh`](#script-create_students_linuxsh)
   4. [Note su isolamento della home](#note-su-isolamento-della-home)
4. [Gestione utenti Portainer](#gestione-utenti-portainer)
   1. [Prerequisiti](#prerequisiti-portainer)
   2. [Script `create_students_portainer.sh`](#script-create_students_portainersh)
5. [Sicurezza di rete sulla VLAN di laboratorio](#sicurezza-di-rete-sulla-vlan-di-laboratorio)
   1. [Obiettivi di sicurezza](#obiettivi-di-sicurezza)
   2. [Esempio di configurazione `nftables`](#esempio-di-configurazione-nftables)
6. [Isolamento in Portainer e Docker CE](#isolamento-in-portainer-e-docker-ce)
   1. [Modello di permessi Portainer](#modello-di-permessi-portainer)
   2. [Linee guida per l’utilizzo di Docker CE](#linee-guida-per-lutilizzo-di-docker-ce)
7. [Checklist operativa](#checklist-operativa)

---

## Panoramica e obiettivi

Questa guida documenta un ambiente didattico sicuro in cui gli studenti sviluppano webapp containerizzate tramite Docker CE, gestite da Portainer, su una VM Debian 13 collocata in una VLAN dedicata ai laboratori.
L’obiettivo è fornire procedure ripetibili per:
- creare utenti di sistema e strutturare le home in modo ordinato;
- creare utenti Portainer e assegnarli ai team corrispondenti alle classi;
- isolare il traffico di rete della VLAN di laboratorio dalla rete scolastica principale;
- garantire che ogni studente lavori in modo isolato rispetto ai container e alle directory degli altri.

La guida è pensata per essere versione‑abile in Git e riutilizzabile per progetti simili in anni scolastici successivi.

---

## Architettura logica

Componenti principali:
- **VM Debian 13** su VLAN laboratorio, con Docker CE e Portainer già attivi.
- **Utenti Linux** con formato `cognome_nome` e home directory:
  - `/as_${anno_corrente}/${classe}/${cognome_nome}` (es. `/as_2026/3A/rossi_mario`).
- **Utenti Portainer** con formato `cognome.nome` (es. `rossi.mario`).
- **Team Portainer** corrispondenti alle classi (es. `3A`, `4B`), a cui sono associati gli utenti.
- **Ambiente Docker CE** esposto a Portainer tramite endpoint locale.

Assunzioni operative:
- Gli studenti **non** sono nel gruppo `docker` sulla VM e non eseguono comandi Docker direttamente.
- Tutta la gestione dei container avviene tramite Portainer (UI o stack file).
- L’accesso all’host viene concesso solo ai docenti/amministratori.

---

## Gestione utenti Linux su Debian 13

### Prerequisiti Linux

- Debian 13 aggiornato.
- Accesso root o `sudo` sulla VM.
- Pacchetti consigliati:
  - `sudo`, `coreutils`, `passwd` (normalmente già presenti);
  - `bash` (shell predefinita).
- File CSV con elenco studenti (vedi formato sotto).

> Nota: per semplicità lo script assume un file **CSV**. Eventuali file Excel (`.xlsx`) possono essere convertiti prima in CSV con strumenti esterni (es. LibreOffice, `ssconvert`).

### Formato CSV di input

Formato suggerito (separatore `;`):

```text
cognome;nome
Rossi;Mario
Bianchi;Luca
Verdi;Anna
```

Lo script accetta due argomenti:

1. `studenti.csv` — il file CSV come sopra;
2. `${classe}` — stringa identificativa della classe (es. `3A`).

Le home verranno create come:

```text
/as_${ANNO}/${CLASSE}/${cognome_nome}
```

### Script `create_students_linux.sh`

Script Bash per creare utenti Linux, con password di default uguale per tutti nella classe e obbligo di cambio al primo login.
Lo script stampa un file `studenti_passwords_${CLASSE}.csv` per uso amministrativo.

> **Sicurezza:** in produzione è preferibile generare password diverse per ogni studente; per uso didattico controllato la password unica per classe può essere accettabile se accompagnata da cambio obbligatorio al primo login.

```bash
#!/usr/bin/env bash
# Abilita modalità rigorosa: interrompe lo script in caso di errore.
set -euo pipefail

# Verifica che siano stati passati esattamente due argomenti.
if [ "$#" -ne 2 ]; then
  echo "Uso: $0 studenti.csv CLASSE" >&2
  exit 1
fi

# Assegna i parametri a variabili leggibili.
CSV_FILE="$1"          # Percorso del file CSV con l'elenco studenti.
CLASSE="$2"            # Identificativo della classe (es. 3A).

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

# File di output con utenti e password iniziali.
OUTPUT_PASS_FILE="studenti_passwords_${CLASSE}.csv"

echo "username;password;classe" > "$OUTPUT_PASS_FILE"

# Legge il CSV riga per riga usando ';' come separatore di campo.
while IFS=';' read -r COGNOME NOME; do
  # Salta righe vuote.
  if [ -z "${COGNOME}" ]; then
    continue
  fi

  # Salta l'eventuale riga di intestazione.
  if [ "$COGNOME" = "cognome" ] || [ "$COGNOME" = "Cognome" ]; then
    continue
  fi

  # Normalizza cognome e nome: minuscolo, spazi in '_', solo caratteri ammessi.
  U_COGNOME="$(echo "$COGNOME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')"
  U_NOME="$(echo "$NOME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')"

  # Costruisce l'username nel formato cognome_nome.
  USERNAME="${U_COGNOME}_${U_NOME}"

  # Definisce la home dell'utente.
  HOME_DIR="${BASE_DIR}/${USERNAME}"

  # Se l'utente esiste già, lo segnala e passa al prossimo.
  if id "$USERNAME" > /dev/null 2>&1; then
    echo "[INFO] Utente $USERNAME esiste già, salto." >&2
    continue
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

  # Registra username e password nel file di output.
  echo "${USERNAME};${DEFAULT_PASS};${CLASSE}" >> "$OUTPUT_PASS_FILE"

done < "$CSV_FILE"

# Messaggio finale.
echo "[OK] Utenti creati per la classe ${CLASSE}. Dettagli in ${OUTPUT_PASS_FILE}."
```

#### Esecuzione dello script

Esempio di esecuzione per la classe `6A`:

```bash
sudo bash create_students_linux.sh studenti_test.csv 6A
```

test per i nuovi utenti e test reset password:
`bash sudo su - rossi_mario` oppure eseguire nuova connessione `ssh rossi_mario@<IP_VM>`


Per rimuovere il test eseguire:
```bash
sudo getent groups #mostra gruppi utenti
sudo delgroup studenti_6A

sudo getent passwd #mostra utenti
sudo deluser rossi_mario
sudo deluser bianchi_luca
sudo deluser verdi_anna
```


### Note su isolamento della home

Con la configurazione sopra:
- ogni home ha permessi `700`, quindi solo il proprietario può leggere/scrivere;
- gli studenti **non** hanno privilegi `sudo` né appartengono al gruppo `docker`;
- l’accesso al sistema host dovrebbe essere limitato ai soli docenti/amministratori.

Questo garantisce l’isolamento dei dati fra studenti a livello di filesystem.
Per un isolamento ancora più spinto (es. chroot SFTP), si può:
- configurare `sshd` con `ChrootDirectory` puntato alla radice delle home degli studenti;
- usare `ForceCommand internal-sftp` per fornire solo accesso SFTP, senza shell.

Questa opzione richiede una progettazione più accurata dei percorsi (es. `/sftp/as_2026/...`) ed è consigliata solo se gli studenti devono accedere via SFTP alle loro directory.

---

## Gestione utenti Portainer

### Prerequisiti Portainer

- Portainer CE o Business già installato e funzionante sulla VM.
- Endpoint Docker locale già configurato in Portainer.
- Un **token API** Portainer con privilegi amministrativi.
- Strumenti sulla VM (o macchina di amministrazione):
  - `curl` per chiamate HTTP;
  - `jq` per la manipolazione JSON.

Assunzioni:
- Esistono già (o verranno creati) i team Portainer con nome uguale alla `${classe}` (es. `3A`).
- Lo stesso CSV usato per gli utenti Linux viene riutilizzato per gli utenti Portainer.

### Script `create_students_portainer.sh`

Script Bash che crea utenti Portainer nel formato `cognome.nome` e li assegna al team corrispondente alla classe.

```bash
#!/usr/bin/env bash
# Abilita modalità rigorosa per lo script.
set -euo pipefail

# Verifica numero di argomenti.
if [ "$#" -ne 2 ]; then
  echo "Uso: $0 studenti.csv CLASSE" >&2
  exit 1
fi

# Parametri.
CSV_FILE="$1"     # File CSV con elenco studenti.
CLASSE="$2"       # Nome della classe / team Portainer.

# Variabili di ambiente richieste per connettersi a Portainer.
: "${PORTAINER_URL:?Devi esportare PORTAINER_URL (es. https://portainer.scuola.lan)}"
: "${PORTAINER_TOKEN:?Devi esportare PORTAINER_TOKEN (token API di un admin Portainer)}"

# Funzione di utilità per effettuare richieste API.
portainer_api() {
  local METHOD="$1"   # Metodo HTTP (GET, POST,...).
  local PATH="$2"     # Percorso API (es. /api/users).
  local DATA="${3:-}" # Dati JSON opzionali.

  if [ -n "$DATA" ]; then
    curl -sS -X "$METHOD" \
      -H "Authorization: Bearer ${PORTAINER_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$DATA" \
      "${PORTAINER_URL}${PATH}"
  else
    curl -sS -X "$METHOD" \
      -H "Authorization: Bearer ${PORTAINER_TOKEN}" \
      "${PORTAINER_URL}${PATH}"
  fi
}

# Recupera l'ID del team corrispondente alla classe.
TEAM_ID="$(portainer_api GET "/api/teams" | jq \
  --arg CL "$CLASSE" '.[] | select(.Name == $CL) | .Id' | head -n1)"

# Verifica che il team esista.
if [ -z "$TEAM_ID" ]; then
  echo "[ERRORE] Nessun team Portainer trovato con nome '${CLASSE}'." >&2
  exit 1
fi

echo "[INFO] Team Portainer '${CLASSE}' con ID ${TEAM_ID}."

# Elabora il CSV riga per riga.
while IFS=';' read -r COGNOME NOME; do
  # Salta righe vuote.
  if [ -z "${COGNOME}" ]; then
    continue
  fi

  # Salta l'intestazione.
  if [ "$COGNOME" = "cognome" ] || [ "$COGNOME" = "Cognome" ]; then
    continue
  fi

  # Normalizza i campi: minuscolo, rimuove spazi.
  U_COGNOME="$(echo "$COGNOME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')"
  U_NOME="$(echo "$NOME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd 'a-z0-9_')"

  # Username Portainer nel formato cognome.nome.
  P_USERNAME="${U_COGNOME}.${U_NOME}"

  # Password iniziale per Portainer (può essere diversa da quella Linux).
  # Valuta se usare una password unica per utente o per classe.
  P_PASSWORD="Port!${CLASSE}"

  echo "[INFO] Creo utente Portainer ${P_USERNAME}..."

  # Crea l'utente in Portainer (Role 2 = standard user).
  USER_JSON="$(portainer_api POST "/api/users" \
    "{\"Username\":\"${P_USERNAME}\",\"Password\":\"${P_PASSWORD}\",\"Role\":2}")"

  # Estrae l'ID dell'utente appena creato.
  USER_ID="$(echo "$USER_JSON" | jq '.Id')"

  # Se USER_ID è nullo o vuoto, l'utente potrebbe esistere già.
  if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
    echo "[WARN] Impossibile creare utente ${P_USERNAME} (forse esiste già)." >&2
    continue
  fi

  echo "[INFO] Utente ${P_USERNAME} creato con ID ${USER_ID}."

  # Crea membership nel team.
  portainer_api POST "/api/team_memberships" \
    "{\"UserID\":${USER_ID},\"TeamID\":${TEAM_ID},\"Role\":1}" > /dev/null

  echo "[OK] Utente ${P_USERNAME} aggiunto al team ${CLASSE}."

done < "$CSV_FILE"
```

#### Esecuzione dello script

Esempio di esecuzione per la classe `3A`:

```bash
export PORTAINER_URL="https://portainer.laboratorio.lan"
export PORTAINER_TOKEN="<TOKEN_API_ADMIN>"

bash create_students_portainer.sh studenti_3A.csv 3A
```

---

## Sicurezza di rete sulla VLAN di laboratorio

### Obiettivi di sicurezza

A livello di rete, gli obiettivi principali sono:
- **Isolare la VLAN di laboratorio** dalla rete scolastica principale (salvo servizi esplicitamente autorizzati, es. proxy, DNS interno);
- **Impedire che i container degli studenti** possano essere usati come pivot per attacchi verso altre reti;
- **Limitare il traffico in uscita** a ciò che è necessario per l’attività didattica (es. HTTP/HTTPS verso Internet o un proxy dedicato);
- **Mantenere accessibile la VM** da postazioni di amministrazione per manutenzione.

Le implementazioni concrete dipendono dalla topologia dell’istituto (router, firewall centrali, ecc.).
Qui viene proposto un esempio con `nftables` direttamente sulla VM Debian, utile come ulteriore linea di difesa.

### Esempio di configurazione `nftables`

> **Prerequisiti:**
> - Pacchetto `nftables` installato (`apt install nftables`).
> - Conoscenza dell’interfaccia di rete della VLAN laboratorio (es. `enp0s8`).
> - Conoscenza delle subnet della rete scolastica principale (es. `10.0.0.0/16`).

Esempio di file `/etc/nftables.conf` semplificato:

```nft
table inet filter {
  chain input {
    type filter hook input priority 0;

    ct state established,related accept
    iif lo accept

    # Permetti SSH e HTTPS/HTTP solo dalla VLAN laboratorio
    iifname "enp0s8" tcp dport { 22, 80, 443, 9443 } accept

    # Permetti ping dalla VLAN laboratorio (opzionale)
    iifname "enp0s8" icmp type echo-request accept

    # Consenti altre porte solo se strettamente necessario

    # Droppa il resto
    counter drop
  }

  chain forward {
    type filter hook forward priority 0;

    ct state established,related accept

    # Blocca traffico dalla VLAN laboratorio verso la rete scolastica principale
    iifname "enp0s8" ip daddr 10.0.0.0/16 drop

    # Consenti traffico dalla VLAN laboratorio verso Internet (es. tramite router a monte)
    iifname "enp0s8" accept

    # Droppa tutto il resto per difetto
    counter drop
  }

  chain output {
    type filter hook output priority 0;
    # Politica permissiva in uscita dalla VM (può essere ulteriormente ristretta)
    accept
  }
}
```

Dopo aver modificato il file:

```bash
sudo systemctl enable nftables
sudo systemctl restart nftables
sudo nft list ruleset
```

Adatta interfacce e subnet ai parametri reali della tua infrastruttura.
L’idea è: la VM accetta solo ciò che serve dalla VLAN laboratorio ed evita di fungere da ponte verso la rete scolastica principale.

---

## Isolamento in Portainer e Docker CE

### Modello di permessi Portainer

Obiettivi di isolamento in Portainer:
- ogni studente vede e gestisce **solo** i propri container/stack;
- gli studenti non possono creare container privilegiati o montare percorsi sensibili dell’host;
- i docenti/amministratori mantengono la visibilità completa per supporto e manutenzione.

Linee guida operative:

1. **Endpoint Docker unico (locale)**
   - Configura un solo endpoint Docker (quello della VM) accessibile ai team/classe.
2. **Access control attivato**
   - In Portainer, assicurati che l’`Access control` sia attivo.
   - Quando crei uno stack o un container per conto di uno studente, imposta l’oggetto come **“Private”** e proprietario lo studente corrispondente.
3. **Ruolo utente**
   - Assegna agli studenti il ruolo **“Standard user”** (non admin).
   - Limita l’uso di template o stack predefiniti a quelli che non richiedono privilegi elevati.
4. **Team per classe**
   - Usa i team per semplificare la visibilità degli endpoint (es. il team `3A` vede solo l’endpoint `Docker-Lab`), ma assegna la **proprietà delle risorse a singoli utenti**, non al team, se vuoi evitare che gli studenti vedano i container dei compagni.

### Linee guida per l’utilizzo di Docker CE

Per ridurre il rischio che un container venga usato per compromettere l’host o altri container:

- **Divieti raccomandati** (da far rispettare tramite policy interne e revisione periodica):
  - niente container con `--privileged`;
  - evitare `--network host`;
  - evitare mount diretti di directory di sistema (es. `/`, `/var/run/docker.sock`, `/etc`, `/var/lib`).
- **Buone pratiche per i progetti didattici:**
  - usare immagini ufficiali o derivate (es. `nginx`, `httpd`, `python`, `node`);
  - esporre solo le porte HTTP/HTTPS necessarie (es. `80`, `8080`, `3000`);
  - usare volume/bind mount solo verso la home dello studente (es. `/as_2026/3A/rossi_mario/progetto1`).

Esempio di snippet `docker-compose.yml` consigliato per gli studenti:

```yaml
version: "3.8"
services:
  webapp:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./www:/usr/share/nginx/html:ro
    restart: unless-stopped
```

Gli studenti possono caricare questo file tramite Portainer (Stacks → Add stack) all’interno del proprio account.
Il docente potrà revisionare periodicamente gli stack per verificare il rispetto delle linee guida.

---

## Checklist operativa

1. **Preparazione CSV**
   - [ ] Genera il file CSV per ogni classe (`cognome;nome`).
2. **Creazione utenti Linux**
   - [ ] Copia lo script `create_students_linux.sh` sulla VM.
   - [ ] Esegui: `sudo bash create_students_linux.sh studenti_<CLASSE>.csv <CLASSE>`.
   - [ ] Archivia in modo sicuro il file `studenti_passwords_<CLASSE>.csv`.
3. **Creazione utenti Portainer**
   - [ ] Crea/controlla il team Portainer per la classe (es. `3A`).
   - [ ] Esporta `PORTAINER_URL` e `PORTAINER_TOKEN` sull’host di amministrazione.
   - [ ] Esegui: `bash create_students_portainer.sh studenti_<CLASSE>.csv <CLASSE>`.
4. **Sicurezza di rete**
   - [ ] Configura `nftables` (o equivalente) sulla VM o sui firewall di frontiera.
   - [ ] Verifica che dalla VLAN laboratorio non sia raggiungibile la rete scolastica principale (salvo eccezioni volute).
5. **Portainer e Docker CE**
   - [ ] Verifica che gli studenti siano utenti standard, non admin.
   - [ ] Definisci template/stack di esempio conformi alle linee guida di sicurezza.
   - [ ] Programma controlli periodici dei container/stack creati dagli studenti.

Questa guida può essere estesa con esempi specifici di progetti didattici (es. stack preconfezionati per webapp in Python, Node.js, PHP) mantenendo gli stessi principi di isolamento e sicurezza descritti sopra.
