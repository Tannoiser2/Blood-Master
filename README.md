# Blood Master — versione digitale in sviluppo

Gioca: https://tannoiser2.github.io/Blood-Master/

Trasposizione autorizzata dall’autore, sviluppata con Godot 4.7.

## Menu iniziale

Una sola schermata: a sinistra le sezioni, a destra il contenuto.
- **Scontro**: modalità (contro l'IA, stesso schermo, online con codice stanza Firebase), scenario e squadre.
- **Regole della casa**: le otto regole modificate, ognuna con il suo interruttore e la spiegazione sempre
  visibile; spente tutte si gioca con il regolamento originale. Sotto, i chiarimenti dell'autore.
- **Opzioni**: grafica (classica o Reborn), miniature 3D, griglia, nomi e barre, sangue, suoni, ritmo.
- **La forgia degli eroi**, **Regolamento**, **Crediti**.

L'interfaccia è tutta disegnata (cornici, pulsanti, frecce, croci, interruttori): nessuna immagine da scalare e
nessun simbolo che un carattere tipografico potrebbe non avere. `python3 tools/check_glyphs.py` controlla che ogni
carattere scritto nell'interfaccia esista in Alegreya e Cinzel.

Questa è una versione in sviluppo: la verifica completa delle magie, degli
scenari e della fedeltà al regolamento è ancora in corso. Le scansioni e la
grafica originale restano la presentazione del gioco.

## La forgia: eroi nuovi e varianti

- Un eroe nuovo nasce da caratteristiche, carattere, arma, scudo e armatura; le pedine si ritoccano una per una.
- **Apri un personaggio del gioco** mostra tutte le sue pedine con ogni valore (anche in tabella) e il suo valore
  totale in punti (100 = media dei guerrieri). Ritoccandolo si salva una **variante**: l'originale non cambia.
- Si salva anche **oltre i 100 punti** (resta segnalato come fuori budget).
- Le regole di costruzione delle pedine sono controllate (`BloodForge.validate`): un attacco ha lati rossi, una
  parata lati blu, fatica e riposo non stanno insieme, colpi e parate a destra e a sinistra sono speculari...
  Finché una pedina non le rispetta l'eroe non si salva. `tests/forge_rules.gd` le applica al cast e a 7.000 eroi.
- Eroi e varianti hanno pedine **disegnate con i loro valori veri** (non quelli stampati sul personaggio a cui
  somigliano), comprese doppio colpo, finta, contrattacco, sgambetto, colpo di scudo e rotazione.
- Le pedine con lati verdi su un colpo o una parata danno un passo prima o dopo l'azione: ora lo sceglie anche
  il giocatore, non solo l'IA.

## Miniature 3D

Durante la partita il tasto "Miniature 3D" nella barra in alto sostituisce le pedine
con miniature animate (Gascor, Ut e Shannon per i blu; Anteos, Nuchra e Ramok
per i rossi; gli altri personaggi restano pedine in piedi). Quando una tessera viene estratta la miniatura esegue la mossa
corrispondente, si sposta sulla nuova cella e rispetta il facing; chi viene
colpito reagisce. A fine scontro "Replay 3D" ripropone tutte le animazioni di
seguito, senza pause fra i turni. Tasto destro: ruota la vista · tasto centrale:
sposta · rotellina: zoom · "Inquadra" riattiva la camera che segue lo scontro.

## Animazioni: gesti costruiti

`scripts/gestures.gd` costruisce sullo scheletro comune (24 ossa) i gesti che le clip di libreria rendevano male:
colpo destro e sinistro, parata destra e sinistra, affondo, fendente, spazzata, rotazione, contrattacco, finta,
doppio colpo e i passi laterali, in diagonale e all'indietro. Ogni gesto è descritto da pochi comandi (torsione
del busto, dove va la mano, dove punta la lama, dove vanno i piedi) e risolto con una cinematica inversa a due
ossa: gomiti e ginocchia piegano dalla parte giusta e il sinistro è lo specchio esatto del destro.
- Una mano, scudo, due armi, arma a due mani, mani nude: ogni corpo ha la sua versione. Con due armi ogni lama
  colpisce e para dal suo lato; nelle altre mosse la seconda lama resta in guardia.
- La parata si vede **dal lato da cui arriva il colpo**: conta dove sta l'attaccante e, se è di fronte, da che
  parte spazza la sua arma. Anche chi viene ferito mentre parava mostra la parata, poi le ferite.
- Ogni gesto sa in che istante colpisce (o è alzato): la difesa parte in tempo per incontrare il colpo.
- Chi si sposta di lato o arretra tenendo lo stesso fronte fa passi laterali o all'indietro invece di voltarsi;
  la rotolata si tuffa verso l'esagono d'arrivo.
- Il replay ripete i passi nell'ordine della partita (prima raggruppava tutti gli spostamenti del turno e poi
  i colpi, che così finivano nel vuoto).

Per guardarli: `tools/poses/strip.gd` (fotogrammi di una clip, dall'alto e di fronte) con `tools/poses/montage.py`,
`tests/gesture_shot.gd` (un duello di prova fotografato) e `tests/battle3d.gd` (scontro intero fra IA più replay).

## Sviluppo

Aprire project.godot in Godot 4.7. La scena principale è scenes/main.tscn.
Le prove 3D sono in scenes/<personaggio>_preview.tscn (gascor, anteos, ut,
shannon, nuchra, ramok), da aprire dall’editor; la mappa 3D è scripts/board3d.gd. I modelli si rigenerano con
tools/anteos/assemble.py, tools/gascor/assemble_meshy.py e tools/heroes/assemble.py
(pipeline Meshy; armi a due mani per Ut, Shannon, Nuchra e Ramok).
Le fonti ad alta risoluzione e i file Blender rimangono locali in source_art.

Ogni aggiornamento di main verifica le regole (tests/rules_test.gd, tests/forge_rules.gd) e i caratteri
dell'interfaccia, esporta la versione web senza thread e pubblica il risultato su GitHub Pages tramite GitHub Actions.

## Regole confermate dall’autore

- Punti magia iniziali: 5 + 1d6.
- I valori aggiuntivi stampati su Shannon sono errori e vengono ignorati.
- Pedine ricontrollate una per una sulle scansioni (15 novembre 2026): corrette Meditazione di Zenyo (ha il
  pallino bianco del riposo, come quella di Shaara) e Affondo di Sanguinaria (lati rossi: fronte e fronte-destra).
- Disperdi magia è possibile prima della propria mossa: il successo la consuma,
  il fallimento no; in entrambi i casi si paga il costo in magia.

Le credenziali degli utenti Firebase e i salvataggi restano sui dispositivi.
Il repository contiene solo la configurazione pubblica del client.
