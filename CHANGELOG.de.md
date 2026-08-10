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

### Behoben

- **Das Umhuellen von Kernmethoden fuehrt nicht mehr zu Endlosrekursion**, wenn RedmineUP-Plugins
  installiert sind. `IssueQuery#available_columns`, `#initialize_available_filters` und
  `IssuesController#parse_params_for_bulk_update` werden per UnboundMethod-Capture statt
  `prepend` + `super` umhuellt: Jene Plugins patchen dieselben Methoden mit
  `alias_method`-Paaren, wodurch eine per prepend eingefuegte Methode als ihr eigenes "Original"
  eingefangen wird und die erste Abfrage mit `SystemStackError` abbricht.
