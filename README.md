# BeatRunner

BeatRunner ist ein SwiftUI-Prototyp für iPhone und Apple Watch. Die App hört Musik über das
Mikrofon, schätzt deren BPM und berechnet anhand der Körpergröße eine
persönliche Laufbandgeschwindigkeit. Die Körpergröße kann manuell eingestellt
oder mit Erlaubnis aus Apple Health gelesen werden.

Erkannte BPM, Zielkadenz und Geschwindigkeit werden per WatchConnectivity an
die Watch-App übertragen. Der letzte Wert bleibt dort auch dann sichtbar, wenn
die direkte Verbindung kurz unterbrochen ist.

Für bekannte Songs lässt sich außerdem manuell speichern, bei welcher
Geschwindigkeit man tatsächlich gelaufen ist. Ein ausgewähltes Song-Ziel hat
Vorrang vor der rechnerischen Empfehlung und wird ebenfalls an die Watch
übertragen.

Aus den gespeicherten Songs kann BeatRunner dynamisch alle Titel im Bereich
von ±0,6 km/h um ein gewähltes Zieltempo zusammenstellen, als echte Playlist
in der Apple-Music-Mediathek anlegen und direkt abspielen. Dafür muss der
MusicKit App Service für die Bundle-ID im Apple Developer Portal aktiviert
sein.

## Voraussetzungen

- Xcode 16 oder neuer
- iPhone mit iOS 17 oder neuer
- Ein echtes Gerät für die Mikrofonanalyse (der Simulator liefert kein
  brauchbares Musiksignal)

## Starten

1. `BeatRunner.xcodeproj` in Xcode öffnen.
2. Im Target **BeatRunner** ein Development Team auswählen.
3. Auf einem iPhone starten und Mikrofonzugriff erlauben.
4. Musik über einen Lautsprecher abspielen und **Analyse starten** wählen.

Musik aus dem iPhone-Lautsprecher kann ebenfalls erkannt werden. Bei AirPods
oder kabelgebundenen Kopfhörern erreicht der Musikstream das Mikrofon nicht;
dafür ist als nächster Schritt ein Metadaten-/BPM-Katalog vorgesehen.

## Funktionsweise

Der Detektor bildet aus kurzen Audioblöcken eine Energie-Hüllkurve. Positive
Energieanstiege werden per Autokorrelation auf periodische Wiederholungen
zwischen 70 und 190 BPM untersucht. Die Anzeige wird geglättet, damit das
Laufband nicht auf einzelne Fehlschätzungen reagiert.

Bei jedem erkannten Audio-Onset pulsiert das grüne Wellenform-Symbol. Wenn die
Mikrofonanalyse ausgeschaltet ist, dient genau dieses Symbol als Tap-Tempo-
Knopf und bestimmt das manuelle Tempo aus den letzten Taps.

Die Zielgeschwindigkeit wird so berechnet:

```text
Basis-Schrittlänge bei 10 km/h = Körpergröße x 0,60 x persönliche Korrektur
dynamische Schrittlänge = Basis x (Geschwindigkeit / 10)^0,35
km/h = effektive Schritte pro Minute x dynamische Schrittlänge x 0,06
```

Da Geschwindigkeit und Schrittlänge voneinander abhängen, löst die App die
Formeln iterativ. Der Geschwindigkeitsfaktor ist begrenzt, damit sehr langsame
oder schnelle BPM-Schätzungen keine unrealistischen Schrittlängen erzeugen.

Die angezeigte Geschwindigkeit ist eine Empfehlung. Änderungen am Laufband
sollten immer manuell und schrittweise erfolgen.
