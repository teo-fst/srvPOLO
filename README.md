# srvPOLO
---
A interface to manage creation and project of my student
---

## Fase 1: Isolamento a livello Proxmox (La Rete)

Prima di accendere Docker, dobbiamo assicurarci che la VM sia una "scatola chiusa".

1. **VLAN:** In Proxmox, assegna alla VM un **Tag VLAN** specifico (es. 50). Questo separa il traffico della VM dal traffico dei server della segreteria o dei registri elettronici.
2. **Firewall di Proxmox:** Vai su *VM > Firewall > Options* e attiva il firewall.
3. **Regole di sicurezza:**
* **Inbound:** Permetti porta `22` (SSH - solo per te), `80/443` (traffico web), `9443` (Portainer).
* **Outbound:** Crea una regola "DROP" verso i range IP della scuola (es. `10.0.0.0/8` o `192.168.1.0/24`) e una "ACCEPT" verso `0.0.0.0/0` (Internet).

> **Perché?** Se uno studente carica uno script malevolo, questo potrà scaricare pacchetti da Internet ma non potrà "pingare" o attaccare il server del Preside.

---
## Fase 2: Configurazione della VM e Hardening Docker

Installa Docker sulla VM (Ubuntu Server è la scelta più comune). Dopo l'installazione, dobbiamo limitare i "superpoteri" di Docker.

1. **Edita il file di configurazione:** `sudo nano /etc/docker/daemon.json`.
2. **Inserisci queste direttive:**
```json
{
  "icc": false,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

* **`icc: false`**: Impedisce ai container di "vedersi" tra loro. Fondamentale se lo studente A e lo studente B non devono interferire.
* **`no-new-privileges`**: Impedisce ai processi nei container di ottenere privilegi superiori (root escalation).

---
## Fase 3: Il Pannello di Controllo (Portainer)

Portainer sarà l'interfaccia degli studenti. Non dovranno mai usare la riga di comando.

1. **Avvia Portainer:** (Usa il comando fornito nella risposta precedente).
2. **Setup Gerarchico:**
* Crea un **Team** (es. `Classe_5B`).
* Crea gli **Utenti** (gli studenti) e assegnali al Team.
* In **Environments > Local > Manage Access**, dai l'accesso al Team come **Standard User**.

> **Risultato:** Quando lo studente "Rossi" entra, vede una dashboard pulita. Può creare i suoi container, ma non può vedere o fermare quelli dello studente "Bianchi".

---
## Fase 4: Reverse Proxy e Dominio (L'accesso URL)

Qui gestiamo i domini `<utente>.<dominio>`.

### Il DNS
Se hai acquistato il dominio, vai nel pannello del tuo registrar (es. Aruba, Namecheap, Cloudflare):

1. Crea un **Record A**.
2. Host: `*` (asterisco, significa "qualsiasi sottodominio").
3. Value: **L'IP pubblico della rete**.
4. Sul router della scuola, fai il "Port Forwarding" delle porte 80 e 443 verso l'IP della tua VM Proxmox.

Se è solo locale nella scuola, hai due opzioni:
1. Server DNS della scuola: Se hai accesso al server DNS della scuola (Windows Server, BIND, o il router principale), devi creare una Zona DNS chiamata <dominio> e aggiungere un record Wildcard (*) che punta all'IP della VM.
2. Configurazione locale/File Hosts: Se vuoi testarlo subito su un solo PC senza toccare il DNS centrale, modifica il file hosts di quel PC (su Windows: C:\Windows\System32\drivers\etc\hosts) aggiungendo:
  IP_DELLA_VM  <utente1>.<dominio> <utente2>.<dominio>

### Nginx Proxy Manager (NPM)

Installa NPM (come visto prima). NPM agisce come un vigile urbano:

* Arriva una richiesta per `<utente>.<dominio>`.
* NPM guarda la sua tabella: "Ah, Mario è il container sulla porta 8081".
* Inoltra il traffico internamente.

---
## Fase 5: Automazione con Script (Creazione Massiva)

Gestire 30 studenti a mano è faticoso. Usiamo uno script che legge i nomi da un file.

1. Crea un file `studenti.txt` con un nome per riga:
```text
mario.rossi
luca.bianchi
giovanna.verdi
```

2. Usa questo script Bash evoluto:
```bash
#!/bin/bash
# Configurazione
TOKEN="ptr_Eb+RAQrc7VxoWEGrxXL3Bpz4FwMOG7KGl+p0rSTp3V8="
PORTAINER_URL="https://localhost:9443/api"
TEAM_ID=2 # Trova l'ID nel pannello Team di Portainer

while IFS= read -r studente || [ -n "$studente" ]; do
    # Password temporanea basata sul nome + anno
    PASSWORD="${studente}2026!"
    
    echo "Sto creando l'account per: $studente"

    # Creazione Utente
    RESPONSE=$(curl -s -X POST "$PORTAINER_URL/users" \
        -H "X-API-Key: $TOKEN" \
        -d "{\"username\":\"$studente\", \"password\":\"$PASSWORD\", \"role\":2}")
    
    USER_ID=$(echo $RESPONSE | grep -oP '(?<="Id":)[0-9]+')

    # Associazione al Team
    curl -s -X POST "$PORTAINER_URL/team_memberships" \
        -H "X-API-Key: $TOKEN" \
        -d "{\"UserID\":$USER_ID, \"TeamID\":$TEAM_ID, \"Role\":2}")

    echo "Account $studente creato con successo (ID: $USER_ID)."
done < studenti.txt
```

---
## Workflow dello Studente (Esempio)

Ecco cosa farà lo studente durante la lezione:

1. Accede a `https://<dominio>:9443` con le sue credenziali.
2. Va su **Stacks** e incolla il suo file `docker-compose.yml`.
3. Nel file specifica una porta (es. `8080`).
4. Ti comunica il nome del progetto.
5. Tu (o lui, se gli dai i permessi su NPM) crei il Proxy Host su Nginx Proxy Manager:
* Domain: `mario.<dominio>`
* Forward: `IP_VM` port `8080`.

**Tutto è isolato, protetto dal firewall e ordinato sotto un unico dominio.**

