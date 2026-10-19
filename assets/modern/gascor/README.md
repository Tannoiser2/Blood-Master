# Gascor — prova grafica v1

Generato con lo strumento integrato imagegen, partendo da assets/cards/gascor.webp.
Gli originali sono conservati. Nessun valore di gioco è modificato.

- gascor-concept-v1.png: figura intera, riferimento per Meshy.
- gascor-token-v1.png: ritratto esagonale con trasparenza esterna.

Direzione artistica: fantasy dipinto da gioco da tavolo moderno, volto squadrato
maturo e rasato, elmo aperto con cimiero dorato, smalto turchese/verde, decorazioni
oro, cotta di maglia, spada lunga e scudo argento/turchese.

Prompt figura: single full-body Gascor knight, preserve original broad clean-shaven
face and open teal gold-trimmed helmet; turquoise enamel armor, gold filigree,
chainmail joints, steel longsword in right hand, elongated heater shield in left;
premium painted fantasy boardgame art, near-frontal relaxed stance, separated
limbs, full weapons in frame, neutral warm-gray background, no text or scenery.

Prompt pedina: exact same Gascor, tight chest-up portrait, large readable face;
straight-on flat-top hex token, engraved double gold border, deep teal interior,
small ivory orientation triangle at top, transparent exterior, no text or stats.

Modello 3D completato con Meshy 7.1 (Ultra 2K + texture, 35 crediti).
Originale: source_art/gascor/gascor-meshy-original.glb, 1.659.412 triangoli.
Copia ottimizzata in Blender 4.2: assets/models/gascor/gascor-preview.glb,
79.999 triangoli, materiali e texture incorporati, altezza normalizzata 2,2.
Studio modificabile: source_art/gascor/gascor-studio.blend.
Anteprime: assets/models/gascor/gascor-3d-front.png e gascor-3d-back.png.
Scena interattiva Godot 4.7: scenes/gascor_preview.tscn.
Trascina per ruotare, rotella per zoom, pulsante per rotazione automatica.
Verificata importazione ed esecuzione della scena in Godot 4.7 Compatibility.
Aggiornamento animazioni: basetta rimossa dalla scena Godot e dallo studio Blender.
Il modello statico resta disponibile come riferimento.
Nuovo asset: assets/models/gascor/gascor-animated.glb.
Sorgente modificabile: source_art/gascor/gascor-rig.blend.
Scheletro di 17 ossa; quattro clip: Riposo, Camminata, Affondo, Parata.
La camminata è sul posto, pronta da combinare con lo spostamento nell'arena.
Queste sono animazioni prototipo: impugnatura, spallacci e falde dell'armatura
richiedono una rifinitura dei pesi prima di una versione definitiva.
Non sono ancora collegate alle azioni della partita.
Il retro è una ricostruzione di Meshy, da sottoporre alla revisione dell'autore.
