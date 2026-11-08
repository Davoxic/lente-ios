# Lente

App iOS che analizza **il tuo** profilo Instagram partendo dai dati che l'account ti mette già a disposizione. Tutto il calcolo avviene sul telefono: nessun server, nessuna API privata, nessun login a Instagram dentro l'app.

Progetto indipendente, non affiliato né approvato da Instagram o Meta.

---

## Cosa calcola

**Dall'export dei dati** (sorgente principale)

| | |
|---|---|
| Reciprocità | chi non ti segue indietro, chi ti segue senza essere seguito, reciproci |
| Movimenti | smessi di seguire di recente, richieste inviate in sospeso, richieste ricevute |
| Crescita | curva follower nel tempo, ricostruita dalle date di inizio follow |
| Attenzione | a chi dai più like e commenti, attenzione a senso unico, follower con cui non interagisci mai |
| Abitudini | ora e giorno in cui pubblichi di più, like messi e contenuti pubblicati mese per mese |
| Confronti | ogni import salva uno snapshot: dal secondo in poi vedi guadagnati, persi e saldo |

**Dall'API ufficiale** (fallback): conteggi follower/seguiti/contenuti, reach, visualizzazioni, interazioni totali e visite al profilo degli ultimi 28 giorni, classifica dei tuoi contenuti per interazioni.

**Da inserimento manuale** (ultima rete): incolli le liste di nomi utente e ottieni reciprocità e confronti tra snapshot.

## Cosa non calcola, e perché

- **Chi visita il tuo profilo.** Instagram non espone questo dato a nessuna app. Le app che promettono gli "stalker" tirano a indovinare o usano API private.
- **Chi ti ha tolto il follow, in tempo reale.** Lo ricavi confrontando due import successivi, non c'è altro modo pulito.
- **La lista follower via API ufficiale.** L'API dà i conteggi, non i nomi. Per la reciprocità serve l'export.

---

## Le tre sorgenti, in ordine

### 1. Export dati — consigliata

Nell'app Instagram: **Impostazioni → Centro gestione account → Le tue informazioni e autorizzazioni → Scarica le tue informazioni**.

- formato **JSON** (l'HTML non è leggibile dall'app)
- intervallo: tutto il periodo
- categorie minime: *Follower e seguiti* + *La tua attività su Instagram*
- puoi escludere foto e video: pesano molto e qui non servono

Instagram manda un link via email, in genere entro qualche ora. Scarichi lo ZIP sul telefono e lo apri dalla scheda **Dati**.

Il parser non dipende da percorsi fissi: cerca i file per nome ovunque nell'archivio e tollera i vari formati che Instagram ha usato negli anni. Se una parte manca, te lo dice invece di fallire.

### 2. API ufficiale

Serve un account professionale (Business o Creator) e un'app su `developers.facebook.com` con il prodotto Instagram. Generi un token a lunga durata con i permessi di lettura su profilo e insights, e lo incolli nell'app. Il token finisce nel portachiavi del dispositivo, non altrove.

I nomi delle metriche cambiano tra una versione e l'altra dell'API: il client prova una lista di metriche e, se il server ne rifiuta qualcuna, scende automaticamente a un set più conservativo invece di mostrare un errore.

### 3. Inserimento manuale

Incolli i nomi utente, uno per riga. Accetta `@nome` e i link completi ai profili. Senza date non c'è curva storica, ma gli snapshot successivi si confrontano comunque tra loro.

---

## Compilare l'IPA su GitHub

Non serve un Mac né un account sviluppatore Apple.

1. Crea un repository e carica questa cartella.
2. **Actions → Build IPA non firmato → Run workflow** (parte anche da sola a ogni push su `main`).
3. A fine build scarichi `Lente-unsigned-ipa` dagli artifact della run.

Se spingi un tag che inizia per `v` (`git tag v1.0.0 && git push --tags`), la pipeline crea anche una release con l'IPA allegato — comodo perché AltStore e SideStore installano direttamente da URL.

Cosa fa la pipeline: runner macOS → `brew install xcodegen` → genera `Lente.xcodeproj` dal `project.yml` → `xcodebuild` in Release con la firma disattivata → impacchetta la `.app` in `Payload/` dentro uno ZIP rinominato `.ipa`.

```bash
# in locale, se hai un Mac
brew install xcodegen
xcodegen generate
open Lente.xcodeproj
```

## Installare sul telefono

L'IPA **non è firmato**: va firmato al momento dell'installazione da uno strumento di sideload.

| Strumento | Come |
|---|---|
| **AltStore / SideStore** | aggiungi l'IPA (o l'URL della release) e installa |
| **Sideloadly** | colleghi l'iPhone al computer, trascini l'IPA, inserisci l'Apple ID |
| **Xcode** | apri il progetto e premi Run con il tuo team selezionato |

Con un Apple ID gratuito l'app scade dopo 7 giorni e va reinstallata; con un account sviluppatore a pagamento dura un anno.

## Privacy

- L'archivio ZIP viene letto in locale e scartato: non viene copiato né caricato da nessuna parte.
- Gli snapshot salvano solo nomi utente e conteggi, in un JSON nella cartella Documenti dell'app.
- Il token dell'API sta nel portachiavi, marcato come non sincronizzabile.
- Le uniche connessioni di rete che l'app apre sono verso `graph.instagram.com`, e solo se configuri la sorgente 2.
- **Cancella tutti i dati locali** nella scheda Dati rimuove tutto.

## Struttura

```
project.yml                     spec XcodeGen (il .xcodeproj è generato, non versionato)
Support/Info.plist              generato da project.yml
Resources/Assets.xcassets       icona e colore accento
Sources/
  App/        LenteApp, AppState
  Models/     Account, Snapshot, AnalysisResult
  Import/     ZipArchive, ExportParser, ManualImport
  Analysis/   Analyzer, SnapshotStore
  Remote/     GraphAPIClient, TokenStore
  UI/         schermate SwiftUI
.github/workflows/build-ipa.yml pipeline di build
```

`ZipArchive` è un lettore ZIP scritto da zero sul framework `Compression`: niente dipendenze esterne, quindi la build non scarica nulla e non si rompe se un pacchetto sparisce. Gestisce deflate, stored e ZIP64.

## Licenza

MIT.
