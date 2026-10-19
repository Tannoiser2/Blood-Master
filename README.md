# Blood Master — versione digitale in sviluppo

Gioca: https://tannoiser2.github.io/Blood-Master/

Trasposizione autorizzata dall’autore, sviluppata con Godot 4.7.
Il menu offre partite contro IA, sullo stesso dispositivo e online con codice
stanza Firebase, oltre alla prova 3D animata di Gascor senza basetta.

Questa è una versione in sviluppo: la verifica completa delle magie, degli
scenari e della fedeltà al regolamento è ancora in corso. Il prototipo 3D di
Gascor è una prova separata; le sue animazioni non sono ancora collegate alla
partita. Le scansioni e la grafica originale restano la presentazione del gioco.

## Sviluppo

Aprire project.godot in Godot 4.7. La scena principale è scenes/main.tscn.
La scena scenes/gascor_preview.tscn contiene la prova 3D.
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
