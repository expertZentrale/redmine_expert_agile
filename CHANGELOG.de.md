# Changelog – redmine_expert_agile

> 🇩🇪 Deutsche Version · [English version](CHANGELOG.md)

Alle nennenswerten Aenderungen an diesem Plugin sind hier dokumentiert. Das
Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), das
Projekt verwendet [Semantic Versioning](https://semver.org/lang/de/).

Massgeblich ist die englische [CHANGELOG.md](CHANGELOG.md) — daraus erzeugt der
Release-Workflow die Release-Notes. Diese Datei ist die deutsche Spiegelung.

## [Unreleased]

### Behoben
- **Die Farbauswahl zeigte keine Farben.** 0.2.3 ersetzte die Auswahlfelder durch Farbfelder, aber
  keiner der beiden Bildschirme, die sie zeigen, laedt das Stylesheet des Plugins — eingebunden
  wird es vom Board, vom Backlog und von den Diagrammen, und der Kartenfarben-Bildschirm wie das
  Ticketformular sind nichts davon. Ohne das Stylesheet waren die Farbfelder leere Elemente ohne
  Groesse, und die Radiobuttons dahinter wurden nie ausgeblendet; uebrig blieb eine Reihe
  Radiobuttons, deren Farben nur noch im Tooltip existierten. Dieselbe Aenderung hatte die
  Farbnamen aus dem sichtbaren Text genommen, aus lesbar wurde also unbenutzbar. Beide Bildschirme
  laden das Stylesheet jetzt, und jedes Farbfeld traegt Farbe, Groesse und Rahmen inline bei sich —
  es ist damit auch auf einer Seite sichtbar, die gar kein Stylesheet laedt.
- **Das Farbfeld am Ticket lief auf einen Fehler, statt zu rendern.** Die Farbfelder holen ihre
  Darstellung aus einem Plugin-Helper, und Redmine schaltet Rails' automatische Helper-Einbindung
  ab: ein Helper steht nur dem gleichnamigen Controller zur Verfuegung. Das Kartenfarbfeld wird
  per Hook ins Ticketformular gerendert — im Ticket-Controller von Redmine —, wo der Helper nicht
  registriert war.

### Hinzugefuegt
- **Die aktuelle Farbe steht neben der Palette im Klartext**: als Farbfeld mit Namen und
  Hex-Code, und sie folgt dem, was angeklickt wird, statt dem zuletzt Gespeicherten. Welches von
  neunzehn Farbfeldern die Markierung traegt, ist nichts, woran man eine Tabelle ablesen sollte.

## [0.2.3] - 2026-08-26

### Geaendert
- **Kartenfarben werden aus der Palette selbst gewaehlt statt aus einer Liste von Farbnamen.**
  Beide Stellen, an denen man eine vergibt — der Administrationsbildschirm und das Farbfeld am
  Ticket —, boten ein Auswahlfeld mit "Gruen", "Hellgruen", "Tuerkis" an; ausgerechnet das, was man
  beim Waehlen sehen muss, naemlich die Farbe, war nicht zu sehen. Beide zeigen jetzt die Palette
  als Farbfelder, die aktuelle markiert, dazu ein durchgestrichenes Feld zum Loeschen. Darunter
  sind es weiterhin Radiobuttons: Tastaturbedienung wie bisher, und abgeschickt wird dasselbe.
- **Die Palette waechst von 9 auf 18 Farben** und ist nach Farbton sortiert statt danach, wann
  welche dazukam — verwandte Toene stehen so beieinander. Die bisherigen neun behalten Namen und
  Werte, und alles bereits Gefaerbte behaelt seine Farbe. Eine Ausnahme: Faerbt ein Board nach
  Bearbeiter, wird die Farbe aus der Palette abgeleitet — diese Karten wechseln also die Farbe.
  Gespeichert ist dafuer nichts, die Zuordnung war nie inhaltlich, nur stabil.
- **Das Plugin hat einen nach ihm benannten Eintrag im Administrationsmenue.** Seine Einstellungen
  waren nur ueber Administration → Plugins → Konfiguration erreichbar, waehrend das Einzige, was
  das Plugin ins Administrationsmenue stellte, der Bildschirm fuer die Kartenfarben war — zwischen
  Redmines eigenen Bereichen als "Farben der Agile-Karten" gelistet, ohne Hinweis darauf, wozu er
  gehoert oder wo der Rest des Plugins konfiguriert wird. Es gibt jetzt einen einzigen Eintrag
  *expert Agile*, der zu den Einstellungen fuehrt — dieselbe Form, die das Helpdesk-Plugin
  verwendet —, und die Kartenfarben erreicht man aus dem Farben-Abschnitt dieser Einstellungen.
  Auf der Einstellungsseite selbst hat sich nichts verschoben, und der Farben-Bildschirm bleibt
  unveraendert unter seiner bisherigen Adresse erreichbar.

### Behoben
- **Der Administrationseintrag des Plugins hatte unter Redmine 6 und neuer kein Symbol.** Er
  forderte das Symbol "palette" aus dem eigenen Icon-Sprite des Plugins an, das dieses Plugin nie
  mitgeliefert hat — und ein so angefordertes Symbol wird nicht in Redmines Kernsatz gesucht. Also
  wurde nichts gezeichnet, und der Eintrag stand als einziger ohne Symbol zwischen den anderen.
  Das Plugin liefert jetzt ein Sprite mit, und ein Test schlaegt fehl, sobald ein Menueeintrag ein
  Symbol anfordert, das nicht darin enthalten ist.

## [0.2.2] - 2026-08-26

### Behoben
- **Ein vom Workflow abgelehnter Zug wurde trotzdem als erledigt angezeigt.** Wurde eine Karte in
  eine Spalte gezogen, die der Workflow nicht erlaubt, meldete das Board die Ablehnung — und liess
  die Karte anschliessend in der Zielspalte liegen, als haette es den eben noch fuer unmoeglich
  erklaerten Zug doch angenommen. Erst ein Neuladen holte die Karte zurueck, denn gespeichert
  wurde nie etwas. Die Karte kehrt jetzt genau an die Position zurueck, von der sie aufgenommen
  wurde, ebenso bei jeder anderen Ablehnung. Ob ein Zug ueberhaupt abgelehnt wird, haengt am
  Workflow der Rolle: derselbe Zug kann fuer den einen Benutzer erlaubt und fuer den anderen
  abgelehnt sein.
- **Jeder fehlgeschlagene Zug meldete einen abgelehnten Statuswechsel.** Die Meldung fuer eine
  Anfrage, die nie zurueckkam — abgerissene Verbindung, Serverfehler, unerwartete Antwort —, war
  auf dem Board die Workflow-Meldung und im Backlog-Planer "Sprint bzw. Version steht nicht zur
  Verfuegung"; beide hatten mit der tatsaechlichen Ursache nichts zu tun. Sie bleiben das, was der
  Server bei einer echten Ablehnung schickt; eine Anfrage ohne Antwort sagt das jetzt auch.

## [0.2.1] - 2026-08-19

### Behoben
- **In der Spalte "Neu" liessen sich Karten nicht umsortieren.** Eine zwischen zwei Karten
  abgelegte Karte sprang an den Anfang der Spalte, statt dort zu bleiben, wo sie abgelegt wurde;
  betroffen war nur diese eine Spalte. Raenge entstehen erst bei Bedarf — ein Ticket, das noch nie
  gezogen wurde, hat gar keinen Rang und sortiert zusammen mit allen anderen ranglosen Karten nach
  Ticket-Id hinter die mit Rang —, und "Neu" ist die Spalte, in der Tickets entstehen, besteht also
  ausschliesslich aus ranglosen Karten. Eine Karte zu platzieren hiess, die Mitte zwischen den
  Raengen ihrer beiden Nachbarn zu nehmen, und zwischen zwei Karten ohne Rang gibt es keine Mitte:
  Der Zug wurde berechnet, als waere die Spalte leer, und die Karte landete ganz oben. Die Karten
  oberhalb der Ablagestelle bekommen jetzt echte Raenge, in genau der Reihenfolge, in der sie schon
  angezeigt werden, bevor die Mitte gebildet wird. Und nur sie: Eine Ablage nahe dem Anfang einer
  Spalte mit Tausenden Karten fasst eine Handvoll Zeilen an, nicht Tausende — die Karten darunter
  werden weder gelesen noch geschrieben und behalten ihren Platz. Spalten, in denen bereits
  gezogene Karten liegen, waren nicht betroffen und bleiben, wie sie sind.
- **Zwei an derselben Stelle abgelegte Karten konnten denselben Rang bekommen.** Alles, was
  unterhalb der letzten Karte mit Rang abgelegt wurde, bekam einen Rang eine Stufe darunter; eine
  zweite Ablage an derselben Stelle wiederholte damit den Rang der ersten, und die Reihenfolge
  zwischen beiden entschied die Ticket-Id. Der Rang wird jetzt gegen die gesamte Spalte gemessen
  statt gegen die Karte oberhalb der Ablagestelle.

## [0.2.0] - 2026-08-14

### Sicherheit
- **Ein gespeichertes Board oder Backlog liess sich ueber seine ID von jedem oeffnen.** Beide
  Abfragen loesten die ID direkt in der Tabelle auf, sodass ein privates Board eines anderen
  Benutzers fuer jedes Projektmitglied aufging — Name und vollstaendiger Filtersatz, nicht jedoch
  Ticketdaten, die weiterhin ueber `Issue.visible` geschuetzt sind. Beide loesen jetzt ueber
  `visible` und `global_or_on_project` auf, also ueber den Bereich, den Seitenleiste und
  Abfrage-Controller ohnehin schon verwendeten.
- **Ein gespeichertes Board oder Backlog blieb offen, nachdem es nicht mehr sichtbar war.** Die
  Sitzung haelt nur eine ID und ueberlebt die Abfrage, auf die sie zeigt; ein Eigentuemer, der ein
  geteiltes Board auf privat stellt, oder eine Rolle, die das Recht verliert, blieb daher ohne
  Wirkung, bis die Sitzung des Betrachters zufaellig endete. Die Wiederherstellung aus der Sitzung
  loest jetzt ueber denselben Bereich auf und faellt auf ein frisches Board zurueck, wenn das
  gespeicherte fehlt oder nicht mehr sichtbar ist.

### Hinzugefuegt

- **Der Backlog-Planer hat jetzt das Filter- und Optionsfeld des Boards.** Der Backlog-Tab war der
  einzige Agile-Bildschirm ohne eines: er baute bei jedem Aufruf eine Wegwerf-Abfrage, zeigte
  dadurch immer alle offenen Tickets des Projekts, und nichts von dem, was jemand einstellte,
  ueberlebte einen Seitenwechsel. Er traegt nun dasselbe Feld wie das Board — Redmines eigenes
  Filterwerkzeug, ein einklappbares Feld *Optionen* mit Kartenfeldern und Einfaerbung sowie
  Anwenden / Zuruecksetzen / Speichern —, abgelegt in einem eigenen Sitzungsschluessel, sodass der
  Rueckweg ueber das Projektmenue den Backlog so zeigt, wie er verlassen wurde. Spalten und
  WIP-Grenzen fehlen bewusst: der Planer ignoriert, wo ein Ticket im Workflow steht.
- **Gespeicherte Backlogs.** Ein Backlog laesst sich wie ein Board oder ein Diagramm speichern,
  bearbeiten und loeschen; gespeicherte Backlogs erscheinen in der Agile-Seitenleiste, die der
  Backlog-Tab jetzt ueberhaupt erst darstellt. Es sind `ExpertAgileBacklogQuery`-Zeilen in Redmines
  Tabelle `queries`, sichtbar ueber das Recht `view_expert_agile_backlog` statt ueber das des
  Boards, und `ExpertAgileBacklogQueriesController` ist der Abfrage-Controller des Boards auf diese
  Klasse gerichtet — dieselbe Wiederverwendung, die die Diagramm-Variante bereits nutzt. Speichern
  verlangt `add_expert_agile_queries` aus dem Modul `expert_agile`; ein Projekt, das nur das
  Backlog-Modul aktiviert hat, kann daher filtern, aber nicht speichern.
- **Backlog-Karten zeigen die im Feld gewaehlten Felder.** Sie hatten einen festen Satz aus Nummer,
  Tracker, Thema, Status und Story Points; sie zeigen nun Bearbeiter samt Avatar, geschaetzten
  Aufwand, Fortschritt, den Beschreibungsauszug und jede gewaehlte Spalte einschliesslich
  benutzerdefinierter Felder — genau wie eine Board-Karte.
- **Bildschirmfotos in beiden READMEs.** `README.md` und `README.de.md` haben jetzt einen Abschnitt
  *Bildschirmfotos*: das Board mit Unterspalten und WIP-Grenzen, Swimlanes, den Backlog-Planer, die
  Sprintliste, Story Points im Ticketformular, Burndown, Velocity, kumulativen Fluss, die
  Kartenfarben-Verwaltung und die Plugin-Einstellungen — das Plugin laesst sich damit beurteilen,
  ohne es vorher zu installieren. Die Bilder liegen in `docs/screenshots/{en,de}/` und sind wie der
  Rest von `docs/` aus den Release-Archiven ausgeschlossen; das Installationspaket waechst dadurch
  nicht.
- **`scripts/seed_screenshot_demo.rb` und `scripts/teardown_screenshot_demo.rb`** bauen das
  synthetische Demo-Projekt auf, aus dem die Bildschirmfotos stammen, und raeumen es wieder ab:
  fuenf Sprints ueber den gesamten Lebenszyklus offen/aktiv/abgeschlossen, ~130 Tickets mit
  rueckdatierten Statusjournalen, damit die verlaufsauswertenden Diagramme etwas auszuwerten haben,
  Story Points, Board-Positionen, Zeiterfassung, Kartenfarben und drei gespeicherte Boards. Anders
  als ihre Helpdesk-Gegenstuecke schreiben diese Skripte globalen Zustand — Story Points und
  Sprints sind standardmaessig aus, sonst waere keines der beiden Funktionen sichtbar —, deshalb
  sichert das Seed-Skript jeden veraenderten Wert und jede angelegte Zeile in der Einstellung
  `expert_agile_screenshot_backup`, aus der das Teardown-Skript den Ausgangszustand
  wiederherstellt. `RELABEL=de` benennt die Demo-Status zwischen dem englischen und dem deutschen
  Durchlauf um, sodass beide Bildstrecken denselben Datenbestand zeigen. Beide Skripte verweigern
  den Dienst ohne `DEMO_STACK=1`: sie laufen unter dem offiziellen Redmine-Image, das im
  Production-Modus startet, sodass `Rails.env` eine Wegwerf-Datenbank nicht von einer echten
  unterscheiden kann — die Zustimmung muss also ausdruecklich getippt werden.

### Behoben

- **Ein auf seinem eigenen Bildschirm gespeichertes Diagramm wurde als Board abgelegt.**
  `expert_agile_queries/new` und `edit` hatten die Routen des Boards fest verdrahtet, sodass jede
  Variante des Abfrage-Controllers ihr Formular an `ExpertAgileQueriesController` schickte,
  gleichgueltig von welchem Bildschirm sie kam. Wohin das gemeinsame Formular schickt und wie es
  ueberschrieben ist, entscheidet jetzt der Controller. Die Diagramm-Variante hatte keinen
  Speichern-Link in der Oberflaeche, der Fehler traf also nur die API; das Backlog waere beim
  ersten Klick hineingelaufen.
- **„Zukunftsdaten in Diagrammen anzeigen" war wirkungslos.** Die Einstellung war deklariert, in
  den Einstellungen dokumentiert und ueber `RedmineExpertAgile.chart_future_data?` lesbar, aber
  kein Diagramm hat sie je ausgewertet: jede Reihe wurde bis zum Ende des gewaehlten Zeitraums
  gezeichnet. Ein mitten im Sprint betrachteter Burndown lief dadurch ab heute waagerecht bis zum
  Sprintende, und die Velocity zeigte leere Balken fuer Wochen, die noch gar nicht stattgefunden
  haben. Gemessene Reihen (`:actual`, `:total`, `:created`, `:closed`, `:trend`) enden jetzt am
  heutigen Tag, solange die Einstellung aus ist; die Ideallinie — eine Projektion, keine Messung —
  laeuft weiterhin ueber den ganzen Zeitraum. Ein Intervall, das den heutigen Tag *enthaelt*,
  bleibt erhalten, denn eine Woche ist an dem Tag, an dem man sie ansieht, zu Recht unvollstaendig.
- **Die Baender des kumulativen Flusses waren nicht unterscheidbar.** Die Bandfarbe war ein
  Farbton, der sich aus der Position des Status unter *allen* Status der Installation ergab. Auf
  einer Installation mit fuenfzig Status zeichnete ein Diagramm mit sechs Baendern deshalb sechs
  benachbarte Farbtoene — sechs Abstufungen desselben Rosas uebereinander. Die Palette verteilt
  sich jetzt auf die Baender, die das Diagramm tatsaechlich zeichnet, sodass sie im Farbkreis so
  weit auseinanderliegen wie moeglich.
- **Unuebersetzte Spaltenueberschrift in der Kartenfarben-Verwaltung.** Die Tabelle rief
  `l(:label_name)` auf — einen Schluessel, den weder das Plugin noch Redmine definiert —, sodass
  die Verwaltungsseite „Translation missing: de.label_name" anzeigte. Sie verwendet jetzt Redmines
  eigenes `field_name`.
- **Der dokumentierte Testbefehl fuehrte das falsche Plugin aus.** Beide READMEs stellten `PLUGIN=`
  vor `docker-compose … run`, wo es eine Shell-Variable bleibt und den Container nie erreicht — der
  Dienst fiel auf seinen Standard zurueck und fuehrte die Helpdesk-Suite aus, die mit 417 gruenen
  Tests meldete, waehrend die Agile-Suite nie lief. Der Befehl uebergibt jetzt `-e PLUGIN=…`.

## [0.1.9] - 2026-08-11

### Behoben

- **Die Backlog-Bahnen ueberlappten einander.** Die feste Spaltenbreite von 300 Pixeln des Boards
  stand als ungebundene `.ea-cell`-Regel, und der Backlog verwendet dieselbe Klasse — jede
  Ablagezone wurde daher 314 Pixel breit in einer 280 Pixel breiten Bahn und ragte in die
  Nachbarbahn hinein. Die Breite gehoert jetzt zur Tabelle des Boards, und die Elemente des
  Plugins rechnen mit `border-box`.

### Geaendert

- **Der Backlog-Planer sieht nach Planungswerkzeug aus.** Die Umschaltung zwischen Sprints und
  Versionen ist ein Segment-Schalter statt zweier blanker Links. Eine Sprint-Bahn zeigt Status,
  Zeitraum und verbleibende Tage, sodass ohne Seitenwechsel erkennbar ist, welcher Sprint laeuft;
  eine Versionsbahn zeigt ihr Datum. Die ungeplante Spalte ist gestrichelt und damit als Quelle
  statt als Ziel gekennzeichnet, Bahnen tragen dieselbe Akzentfarbe wie auf dem Board, eine leere
  Bahn erklaert sich selbst, und jede Bahn scrollt intern — ein grosses Backlog macht die Seite
  also nicht mehr tausende Pixel lang.

### Hinzugefuegt

- Controller-Tests fuer den Backlog-Planer, der bisher keine hatte: Aufbau der Bahnen, genau eine
  Ablagezone je Bahn, Container-IDs, Summen, die Sprint-Metadaten, Modul- und
  Berechtigungspruefung sowie das Planen eines Tickets in einen Sprint und zurueck.

## [0.1.8] - 2026-08-11

### Geaendert

- **Der Optionsbereich des Boards ist kompakt.** Aus drei gestapelten Fieldsets — darunter
  Redmines Spaltenauswahl mit zwei Listen und Pfeilen, allein rund 400 Pixel hoch — ist ein
  Bereich mit drei nebeneinander liegenden Gruppen geworden, die auf schmalen Bildschirmen
  umbrechen: Kartenfelder, Darstellung sowie Spalten mit ihren WIP-Limits. Das Aufklappen kostet
  279 statt fast einer Bildschirmhoehe, und alle Einstellungen sind gleichzeitig sichtbar.
- **Kartenfelder sind ein Kaestchenraster.** Die Reihenfolge von Spalten zaehlt in einer Tabelle,
  auf einer Karte kaum; der Platz, den die Pfeilauswahl fuer die Sortierung verbrauchte, zeigt
  nun alle verfuegbaren Felder — auch benutzerdefinierte und die Beschreibung — in zwei dichten
  Spalten. Die Auswahl wird weiterhin als `c[]` gesendet, Redmines Parameterverarbeitung bleibt
  unveraendert.

  Damit entfaellt die Moeglichkeit, Kartenfelder zu *sortieren*; sie folgen jetzt Redmines
  eigener Spaltenreihenfolge.
- Statusspalten und ihre WIP-Limits bilden ein dreispaltiges Raster, geschlossene Status kursiv,
  damit die "Erledigt"-Spalte leicht zu finden ist. Lange Feldnamen tragen einen Tooltip, und
  beide scrollbaren Listen blenden am unteren Rand aus, damit eine halb sichtbare Zeile als
  "weiter unten geht es weiter" gelesen wird und nicht als Darstellungsfehler.

## [0.1.7] - 2026-08-11

### Behoben

- **Jede Ticketseite lieferte einen 500er.** Der Hook im Ticketformular rief eine Pruefmethode
  auf, die nie geschrieben worden war; das Oeffnen eines Tickets — auch per Klick auf eine Karte
  des Boards — scheiterte mit `undefined method 'sprint_visible?'`. Die Pruefung existiert nun
  und zeigt die Sprint-Auswahl nur, wenn Sprints aktiviert sind und das Projekt einen Sprint zur
  Planung hat.
- **Die View-Hooks des Plugins sind jetzt durch Tests abgedeckt, die Redmines eigene Seiten
  rendern** — Ticketansicht, Bearbeiten, Neu, Massenbearbeitung und Ticketliste, jeweils mit
  aktiviertem und deaktiviertem Modul sowie mit Sprints und Story Points. Die gesamte Testsuite
  lief waehrend dieses Ausfalls durch, weil nie eine Kernseite mit geladenem Plugin gerendert
  wurde; ein Hook, der eine Kernseite zerstoert, ist genau der Fehler, den ein Plugin am
  dringendsten abfangen muss.

## [0.1.6] - 2026-08-11

### Hinzugefuegt

- **Mehr Kartenfelder.** Angelegt und Aktualisiert waren bereits waehlbar; die Feldauswahl bietet
  nun zusaetzlich **Zeit im Status** — volle Tage seit dem letzten Statuswechsel, beantwortet aus
  einer einzigen gruppierten Journalabfrage fuer das gesamte Board statt einer Abfrage je Karte —
  sowie einen **kurzen Auszug der Beschreibung**, dessen Laenge in den Plugin-Einstellungen
  konfigurierbar ist. Die Beschreibung ist in Redmine eine Blockspalte, daher bietet der
  Optionsbereich Blockspalten jetzt so an, wie es Redmines eigenes Abfrageformular tut.
- Der Auszug ist reiner Text: HTML und Wiki-Markup werden entfernt statt gerendert, denn eine
  Karte ist eine Zusammenfassung, und vollstaendiges Markup zoege Ueberschriften, Tabellen und
  Bilder hinein. Aus E-Mails uebernommene Beschreibungen bestehen groesstenteils aus HTML, was
  das praktisch relevant macht.

### Behoben

- **Eine spaeter hinzugefuegte Einstellung wurde in einer bestehenden Installation nie wirksam.**
  Redmine liefert den gespeicherten Einstellungs-Hash vollstaendig zurueck, sobald das Formular
  einmal gespeichert wurde; ein neu deklarierter Schluessel fehlt darin schlicht und wird als nil
  gelesen — bei einer Zahl also als 0. Die deklarierten Standardwerte liegen jetzt unter den
  gespeicherten Werten, ein gespeicherter Wert hat also weiterhin Vorrang (auch ein bewusst
  leerer), waehrend neue Schluessel ihren Standard erhalten. Genau dadurch fiel der
  Beschreibungsauszug auf seine Untergrenze von 20 Zeichen zurueck.

## [0.1.5] - 2026-08-11

### Behoben

- **Swimlanes waren als Bahnen kaum zu erkennen.** Jede Bahn war eine Tabellenzeile mit einer
  schmalen Beschriftungszelle am linken Rand; ueber die Spalten hinweg hielt die Zeile optisch
  nichts zusammen. Eine Bahn ist jetzt ein Band ueber die volle Breite des Boards, mit dem Namen
  der Bahn und ihren eigenen Summen aus Tickets und Story Points. Ist das Board breit genug zum
  Scrollen, bleibt der Name der Bahn stehen, waehrend die Spalten darunter wandern.
- **Alle Bahnen sahen gleich aus.** Bahnen haben nun eine Akzentfarbe. Eine Bahn, deren Wert
  faerbbar ist — Tracker, Prioritaet oder Status — nutzt dessen Farbe, sodass das Band zu seinen
  Karten passt und die Gruppierung nach Prioritaet die erwartete Skala von ruhig bis rot ergibt;
  alles andere erhaelt eine stabile, aus der ID abgeleitete Palettenfarbe.

## [0.1.4] - 2026-08-10

### Hinzugefuegt

- **Seitenleiste auf den Agile-Seiten.** Board und Diagrammseite haben nun eine Seitenleiste in
  derselben Form wie Redmines Ticketliste: Schnellzugriff auf Board, Diagramme und Backlog, die
  gespeicherten Boards (bzw. Diagramme), getrennt nach "Meine eigenen Abfragen" und geteilten,
  sowie die Sprints des Projekts mit Link zum Anlegen. Der Wechsel zwischen den Ansichten ist ein
  Klick.
- **Gespeicherte Diagramme.** `ExpertAgileChartsQueriesController` — wie beim Board existierten
  Routen und Berechtigungen seit dem ersten Commit ohne Controller dahinter. Diagrammauswahl,
  Einheit, Intervall und Zeitraum werden mitgespeichert. Es ist der Query-Controller des Boards
  auf eine andere Klasse gerichtet, keine zweite Kopie.

### Behoben

- **Das Speichern eines Diagramms wurde mit 403 abgelehnt.** Fuer den Diagramm-Query-Controller
  war nur `:index` zugeordnet, und `find_optional_project` prueft das Paar aus Controller und
  Aktion — jede andere Aktion war damit nicht absichtlich, sondern mangels Zuordnung verboten.
- **Der Link "Speichern" zeigte auf die falsche Route.** Er verwies auf den Sammelpfad, also
  `#index`, der lediglich zum Board zurueckleitet und die zu speichernde Konfiguration
  stillschweigend verwirft. Er sendet nun an die Aktion `new`, wie Redmines eigenes Abfrageformular.
- **Gespeicherte Diagramme erscheinen nicht mehr unter den Boards.** `ExpertAgileChartsQuery` ist
  eine Unterklasse von `ExpertAgileQuery`; eine ungefilterte Abfrage listete beides. Die
  Seitenleiste filtert jetzt auf den exakten Typ.

## [0.1.3] - 2026-08-10

### Behoben

- **Board-Optionen gingen beim naechsten Seitenaufruf verloren.** Status, WIP-Limits, Swimlanes
  und Farbgrundlage lagen nur in der URL; ein gesetztes WIP-Maximum war nach dem Neuladen — oder
  schon beim Rueckweg ueber das Projektmenue — stillschweigend wieder weg. Das Board merkt sich
  seine Konfiguration jetzt in der Session, genau wie Redmines eigene Ticketliste. Gespeichert
  wird nur, was zum Wiederaufbau noetig ist, nicht der gesamte Optionsblock.
- **Wer Boards speichern durfte, konnte fremde private Boards bearbeiten und loeschen.**
  `editable_by?` prueft bisher nur die Berechtigung zum Speichern und ignorierte die
  Eigentuemerschaft. Es folgt nun Redmines eigener Regel: eigene Boards gehoeren einem selbst,
  oeffentliche Projekt-Boards erfordern die Verwaltungsberechtigung, globale Boards bleiben
  Administratoren vorbehalten.
- **Das Speichern eines Boards funktionierte nie**: Der Controller setzte `safe_attributes`, das
  `Query` nicht kennt, wodurch das Anlegen eine Ausnahme warf. Name, Beschreibung und
  Sichtbarkeit werden jetzt ausdruecklich zugewiesen; die Sichtbarkeit nur mit der
  Verwaltungsberechtigung — ohne sie entsteht ein privates statt eines oeffentlichen Boards,
  wie in Redmine.

### Geaendert

- Der Anzeigezustand des Boards liegt in der Session; was ein **Zug** aendern darf, ergibt sich
  aber weiterhin ausschliesslich aus der Anfrage und dem Workflow des Tickets — nie aus der
  Session.

## [0.1.2] - 2026-08-10

### Hinzugefuegt

- **Optionsbereich am Board.** Das Board hat nun denselben ein- und ausklappbaren Filter- und
  Optionsbereich wie jede andere Redmine-Liste; ein Board wird also dort konfiguriert, wo es
  benutzt wird, und nicht nur in den globalen Einstellungen. Er bietet Redmines eigenes
  Filter-Widget und erlaubt die Auswahl, welche Status zu Spalten werden (geschlossene
  eingeschlossen, fuer die "Erledigt"-Spalte), WIP-Limits je Spalte, das Swimlane-Feld, die
  Farbgrundlage, ob der Avatar des Bearbeiters erscheint und welche Felder auf den Karten stehen.
- **Kartenfelder sind die Spalten der Abfrage selbst**, sodass alles, was Redmine in der
  Ticketliste anzeigen kann — auch benutzerdefinierte Felder — auf eine Karte passt, formatiert
  von Redmines eigener Spaltenausgabe.
- **Gespeicherte Boards.** `ExpertAgileQueriesController` war von Anfang an in Routen und
  Berechtigungen deklariert, aber nie geschrieben worden; das Speichern eines Boards lief daher
  in einen 404. Boards lassen sich jetzt speichern, bearbeiten und loeschen, privat oder
  oeffentlich gemaess den Agile-Berechtigungen.
- **Avatare der Bearbeiter auf den Karten**, standardmaessig aktiv und je Board abschaltbar.

### Behoben

- **Das Setzen eines WIP-Limits liess das Board mit einem 500er abstuerzen.**
  `ActionController::Parameters` ist kein Hash und kennt kein `each_with_object`; die
  Modelltests uebergaben einfache Hashes und haben eine echte Anfrage nie nachgestellt. Die
  Setter akzeptieren jetzt beides, und der Optionsbereich ist durch Controller-Tests mit echten
  Request-Parametern abgedeckt.

## [0.1.1] - 2026-08-10

### Behoben

- **Das Board zeigte alle offenen Status der Instanz statt der des Projekts.** In einer echten
  Installation waren das 37 Spalten, von denen 3 genutzt wurden, jede auf etwa 27 Pixel
  zusammengedrueckt, mit Kartentext im Umbruch von einem Zeichen pro Zeile. Die Spalten stammen
  jetzt aus Redmines `Project#rolled_up_statuses` — den Status, die die Tracker des Projekts
  tatsaechlich erreichen koennen.
- **Karten wurden nie eingefaerbt, solange nicht ein Administrator jede Farbe von Hand vergeben
  hatte.** Die Auswahl einer Farbgrundlage schien wirkungslos. Ein Objekt ohne ausdrueckliche
  Farbe erhaelt nun eine stabile, aus seiner ID abgeleitete Palettenfarbe, so dass ein Board
  sofort farbcodiert ist; eine ausdrueckliche Farbe hat weiterhin Vorrang. Die Einfaerbung *nach
  Ticket* verzichtet bewusst auf diesen Rueckfall, denn dort sollen nur markierte Tickets
  hervorstechen.
- **Prioritaeten werden auf einer semantischen Skala eingefaerbt** (ruhig bis rot), abgeleitet aus
  ihrer Position in der Aufzaehlung statt aus einer beliebigen Palettenfarbe — "dringend" sieht
  damit auch dringend aus.
- **Kartentext lief ueber und Spalten waren unterschiedlich breit.** Lange Betreffs, URLs und
  Komposita brechen jetzt innerhalb der Karte um, Betreffs werden auf drei Zeilen begrenzt, und
  alle Spalten haben dieselbe feste Breite; das Board scrollt seitlich, statt zu quetschen.
- **Der Backlog-Planer hatte keinen Menueeintrag**, seine Karten waren nicht wie die des Boards
  eingefaerbt, und ein Projekt ohne Sprints zeigte eine leere Seite ohne Erklaerung. Er erscheint
  nun im Projektmenue, faerbt Karten einheitlich und bietet an, den ersten Sprint anzulegen.
- **Spaltenkoepfe werden nach Status eingefaerbt**, wenn Statusfarben aktiviert sind.
- **Zwei Diagrammbeschriftungen erschienen als "Translation missing"** — der Datumsbereich nutzte
  Redmine-Kernschluessel, die es im deutschen Locale nicht gibt. Ausserdem hob die
  Diagrammseite den Menueeintrag des Boards statt ihren eigenen hervor.

### Geaendert

- Karten- und Spaltengestaltung ueberarbeitet: groessere Spalten, klarere Kartenhierarchie,
  Status- und Story-Point-Chips, Hover-Zustaende.

## [0.1.0] - 2026-08-10

### Hinzugefuegt

- **Plugin-Geruest.** Registrierung, Plugin-Einstellungen mit deklariertem
  Standardwert fuer jeden Schluessel, die Projektmodule `expert_agile` und
  `expert_agile_backlog` samt Berechtigungen, das Schema (`expert_agile_data`,
  `expert_agile_sprints`, `expert_agile_colors`), Routen, englische und deutsche
  Locales sowie die Workflows fuer CI, Docker-Smoke-Test und Release.
- **Story Points.** Ein Story-Point-Wert je Ticket, gespeichert in `expert_agile_data` statt als
  benutzerdefiniertes Feld. Das Feld erscheint im Ticketformular, in der Attributtabelle und in
  der Massenbearbeitung und wird wahlweise als konfigurierbare Werteliste (standardmaessig
  modifizierte Fibonacci-Reihe) oder als freie Zahleneingabe angeboten. Es laesst sich auf
  ausgewaehlte Tracker begrenzen. Uebergeordnete Tickets zeigen zusaetzlich die Summe ihres
  Teilbaums; "nicht geschaetzt" bleibt dabei von "mit 0 geschaetzt" unterscheidbar.
- **Story Points in der Ticketliste.** Eine sortierbare Spalte `story_points` und ein
  Ganzzahlfilter in der Redmine-Ticketabfrage. Tickets ohne Agile-Datensatz gelten korrekt als
  "ohne Story Points", werden von `ist nicht` und `keiner` also eingeschlossen statt
  stillschweigend ausgelassen.

- **Gespeicherte Agile-Boards.** `ExpertAgileQuery` erbt von Redmines eigener `IssueQuery`;
  damit gelten saemtliche Ticketfilter, Spalten, Sichtbarkeitsregeln und Projektbezuege
  unveraendert auch fuer ein Board, und ein gespeichertes Board ist eine einzige Zeile in der
  Tabelle `queries` ohne zusaetzliches Schema. Die boardeigenen Einstellungen — sichtbare
  Statusspalten, WIP-Limits, Farbgrundlage, Swimlane-Feld, Kartenfelder, Boardtyp, Sprint- und
  Backlog-Schalter — liegen in den serialisierten Optionen, mit typisierten Zugriffsmethoden, so
  dass die gespeicherte Struktur an genau einer Stelle definiert ist. WIP-Limits werden als
  Ganzzahlpaare gespeichert statt als Zeichenkette `"2-7"`, die bei jeder Anzeige neu zerlegt
  werden muesste.
- **Boardspalten und Swimlanes.** Spalten sind schlichte `BoardColumn`-Wertobjekte mit
  Ticketanzahl, geschaetzten Stunden, Story Points und WIP-Zustand; Status mit gemeinsamem
  Praefix `Praefix:` liefern einen `path` fuer Unterspaltenkoepfe. Swimlanes nutzen Redmines
  Gruppierung und werden aus den geladenen Karten abgeleitet, eine Bahn erscheint also nur, wenn
  sie auch eine Karte enthaelt. Das gesamte Board entsteht aus einem einzigen Ticket-Ladevorgang;
  ein Board, das seine Obergrenze erreicht, meldet dies, statt vollstaendig zu wirken.

- **Das Board selbst.** Spalten aus Ticketstatus, Drag & Drop zwischen und innerhalb von
  Spalten, Swimlanes, Unterspaltenkoepfe aus gemeinsamem Statuspraefix `Praefix:`, hinweisende
  WIP-Limits, Karten-Tooltips und ein Eintrag im Projektmenue neben dem Gantt-Diagramm. Das
  Kartenmarkup enthaelt weder Inline-Skripte noch Inline-Eventhandler, und das Board liest seine
  Konfiguration aus einer JSON-Insel — es funktioniert damit unter einer
  `script-src 'self'`-Content-Security-Policy.
- **Serverseitig berechnete gebrochene Kartenraenge.** Ein Zug uebertraegt nur die gezogene Karte
  und ihre beiden Nachbarn; der Server berechnet den Mittelwert und schreibt genau eine Zeile,
  innerhalb derselben Transaktion wie die Ticketspeicherung. Gleichzeitige Zuege in derselben
  Spalte ueberschreiben sich nicht mehr gegenseitig, und ein Zug innerhalb einer paginierten
  Spalte sortiert die Karten unterhalb der Sichtgrenze nicht mehr um. Wenn wiederholte Zuege in
  dieselbe Luecke die verfuegbare Genauigkeit erschoepfen, wird die Spalte automatisch neu
  verteilt.
- **Explizite Workflow-Pruefung auf dem Board.** Ein Zug auf einen vom Workflow verbotenen Status
  wird mit einer konkreten Fehlermeldung abgelehnt und aendert nichts — statt aus einer
  Attributzuweisung abgeleitet zu werden, die stillschweigend nicht gegriffen hat.

- **Kartenfarben.** Karten lassen sich nach Tracker, Prioritaet, Status, Projekt, Bearbeiter,
  aufgewendeter Zeit oder je Ticket einfaerben, aus einer geschlossenen Palette von neun Farben,
  die so gewaehlt sind, dass der Kartentext lesbar bleibt. Farben fuer Tracker, Prioritaeten und
  Status werden ueber eine neue Administrationsseite gepflegt; die Farbe je Ticket erscheint im
  Ticketformular, sobald ein Board nach Ticket einfaerbt. Die Farbunterstuetzung ist ein Concern,
  das nur in die fuenf faerbbaren Modelle eingebunden wird und nicht in `ActiveRecord::Base`, und
  die Administrationsseite loest ihre Zielklasse ueber eine Whitelist auf, statt einen
  Request-Parameter zu constantizen.

- **Sprints.** Ein eigenstaendiger Sprint mit Name, Beschreibung, Start- und Enddatum,
  Lebenszyklus offen/aktiv/geschlossen und Freigabe ueber den Projektbaum wie bei Versionen.
  Das Aktivieren eines Sprints setzt den bisher aktiven Sprint des Projekts auf offen, ein
  Sprint laesst sich nicht schliessen, solange er offene Tickets enthaelt, und ueberlappende
  Sprints werden abgelehnt, sofern nicht ausdruecklich erlaubt. Sprints werden ueber einen
  Reiter in den Projekteinstellungen und eine eigene Verwaltungsseite gepflegt, sind im
  Ticketformular zuweisbar und ueber die REST-API verfuegbar. Das Loeschen eines Sprints hebt
  die Zuordnung seiner Tickets auf, statt sie zu loeschen. Sprintwechsel werden in das Journal
  des Tickets geschrieben und erscheinen damit in der Ticket-Historie.

- **Backlog-Planer.** Eine eigene Planungsansicht hinter dem Modul `expert Agile Backlog`, die
  ein ungeplantes Backlog neben je einer Bahn pro Sprint oder Version zeigt. Tickets werden mit
  derselben serverseitigen Rangberechnung wie auf dem Board in eine Bahn gezogen, die Summen der
  Bahnen aktualisieren sich direkt, und das Backlog laesst sich nach Betreff oder Ticketnummer
  durchsuchen. Die Planung in Sprints und in Versionen ist eine parameterisierte Abfrage statt
  zweier nahezu identischer, und Drag & Drop verwendet dieselbe Implementierung wie das Board.
  Eine Container-ID, in die das Projekt nicht planen darf, wird abgelehnt — ein manipulierter
  Aufruf kann ein Ticket also nicht in den Sprint eines fremden Projekts verschieben.

- **Diagramme.** Burndown, Burnup, kumulierter Fluss, Velocity und Durchlaufzeit, wahlweise in
  Tickets, Stunden oder Story Points, ueber Tages-, Wochen- oder Monatsintervalle. Der historische
  Zustand wird aus einer einzigen Journalabfrage rekonstruiert, in einem Durchlauf zu einer
  Zeitleiste je Ticket verdichtet und per binaerer Suche abgefragt — der Aufwand haengt damit an
  der Zahl der Journaleintraege statt an Datum x Tickets x Journale. Berechnete Reihen werden
  anhand eines Fingerabdrucks aller ergebnisrelevanten Groessen zwischengespeichert. Die
  Mengenbegrenzung gilt nur fuer Diagramme, die tatsaechlich Historie auswerten; die zaehlenden
  Diagramme sind unbegrenzt, weil sie guenstig sind. Chart.js liegt dem Plugin bei, statt aus dem
  Asset-Verzeichnis eines anderen Plugins zu stammen, und Datumswerte werden in die Zeitzone des
  Betrachters umgerechnet, damit ein Diagramm oestlich von UTC nicht um einen Tag verschoben ist.

- **REST-API.** Die Agile-Daten je Ticket sind les- *und* schreibbar — Story Points und
  Sprint-Zuordnung lassen sich direkt setzen, nicht nur ueber verschachtelte Attribute am
  Ticket-Endpunkt — dazu vollstaendiges Sprint-CRUD. Eine Sprint-ID wird gegen die Sprints
  aufgeloest, in die das Projekt des Tickets tatsaechlich planen darf; eine fremde ID wird
  abgelehnt statt uebernommen. Der Board-Rang ist bewusst nur lesbar: Raenge berechnet der Server
  aus den Nachbarkarten, und ein vom Client gesetzter Rang wuerde genau das
  Nebenlaeufigkeitsproblem zurueckholen, das der Entwurf vermeidet. Dokumentiert in `API.md`.

### Behoben

- **Das Umhuellen von Kernmethoden fuehrt nicht mehr zu Endlosrekursion**, wenn RedmineUP-Plugins
  installiert sind. `IssueQuery#available_columns`, `#initialize_available_filters` und
  `IssuesController#parse_params_for_bulk_update` werden per UnboundMethod-Capture statt
  `prepend` + `super` umhuellt: Jene Plugins patchen dieselben Methoden mit
  `alias_method`-Paaren, wodurch eine per prepend eingefuegte Methode als ihr eigenes "Original"
  eingefangen wird und die erste Abfrage mit `SystemStackError` abbricht.
