# Blood Master — versione digitale in sviluppo

Gioca: https://tannoiser2.github.io/Blood-Master/

Trasposizione autorizzata dall’autore, sviluppata con Godot 4.7.
Il menu offre partite contro IA, sullo stesso dispositivo e online con codice
stanza Firebase, le prove 3D di Gascor e Anteos e un duello 3D di prova.

Questa è una versione in sviluppo: la verifica completa delle magie, degli
scenari e della fedeltà al regolamento è ancora in corso. Le scansioni e la
grafica originale restano la presentazione del gioco.

## Miniature 3D

Durante la partita il tasto "Miniature 3D" sotto la mappa sostituisce le pedine
con miniature animate (Gascor e Anteos; gli altri personaggi restano pedine in
piedi). Quando una tessera viene estratta la miniatura esegue la mossa
corrispondente, si sposta sulla nuova cella e rispetta il facing; chi viene
colpito reagisce. A fine scontro "Replay 3D" ripropone tutte le animazioni di
seguito, senza pause fra i turni. Tasto destro: ruota la vista · tasto centrale:
sposta · rotellina: zoom · "Inquadra" riattiva la camera che segue lo scontro.

## Sviluppo

Aprire project.godot in Godot 4.7. La scena principale è scenes/main.tscn.
Le prove 3D sono in scenes/gascor_preview.tscn, scenes/anteos_preview.tscn e
scenes/duel_3d.tscn; la mappa 3D è scripts/board3d.gd. I modelli si rigenerano con
tools/anteos/assemble.py e tools/gascor/assemble_meshy.py (pipeline Meshy).
Le fonti ad alta risoluzione e i file Blender rimangono locali in source_art.

Ogni aggiornamento di main verifica le regole, esporta la versione web senza
thread e pubblica il risultato su GitHub Pages tramite GitHub Actions.

## Regole confermate dall’autore

- Punti magia iniziali: 5 + 1d6.
- I valori aggiuntivi stampati su Shannon sono errori e vengono ignorati.
- Disperdi magia è possibile prima della propria mossa: il successo la consuma,
  il fallimento no; in entrambi i casi si paga il costo in magia.

Le credenziali degli utenti Firebase e i salvataggi restano sui dispositivi.
Il repository contiene solo la configurazione pubblica del client.
