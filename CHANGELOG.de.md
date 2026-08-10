# Changelog – redmine_expert_agile

> 🇩🇪 Deutsche Version · [English version](CHANGELOG.md)

Alle nennenswerten Aenderungen an diesem Plugin sind hier dokumentiert. Das
Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), das
Projekt verwendet [Semantic Versioning](https://semver.org/lang/de/).

Massgeblich ist die englische [CHANGELOG.md](CHANGELOG.md) — daraus erzeugt der
Release-Workflow die Release-Notes. Diese Datei ist die deutsche Spiegelung.

## [Unreleased]

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

### Behoben

- **Das Umhuellen von Kernmethoden fuehrt nicht mehr zu Endlosrekursion**, wenn RedmineUP-Plugins
  installiert sind. `IssueQuery#available_columns`, `#initialize_available_filters` und
  `IssuesController#parse_params_for_bulk_update` werden per UnboundMethod-Capture statt
  `prepend` + `super` umhuellt: Jene Plugins patchen dieselben Methoden mit
  `alias_method`-Paaren, wodurch eine per prepend eingefuegte Methode als ihr eigenes "Original"
  eingefangen wird und die erste Abfrage mit `SystemStackError` abbricht.
