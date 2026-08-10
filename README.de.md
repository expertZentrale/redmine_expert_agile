# redmine_expert_agile

> 🇩🇪 Deutsche Version · [English version](README.md)

Agile Boards fuer Redmine: ein Kanban-/Scrum-Board auf Basis des Redmine-eigenen
Query-Systems, Story Points, Sprints mit Backlog-Planer und Diagramme.

Benoetigt **Redmine 5.0 oder neuer**. Lizenziert unter der **GPL-2.0-or-later**
(siehe [LICENSE](LICENSE)).

## Inhalt

- [Funktionen](#funktionen)
- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Berechtigungen](#berechtigungen)
- [Entwicklung](#entwicklung)
- [Lizenz](#lizenz)

## Funktionen

> Das Plugin befindet sich in aktiver Entwicklung Richtung erstes Release (0.1.0). Die folgenden
> Punkte beschreiben dessen Umfang; was bereits umgesetzt ist, steht in
> [CHANGELOG.de.md](CHANGELOG.de.md).

- **Board** — Spalten aus Ticket-Status, Drag & Drop, Swimlanes, WIP-Limits (nur hinweisend),
  konfigurierbare Kartenfelder, Unterspalten ueber ein gemeinsames Statusnamen-Praefix, eine
  Backlog-Spalte und gespeicherte Boards. Boards sind Redmine-Queries — alle bekannten Filter,
  Gruppierungen und Sichtbarkeitsregeln gelten unveraendert.
- **Story Points** — pro Ticket gespeichert, als konfigurierbare Werteliste angeboten
  (standardmaessig modifizierte Fibonacci-Reihe), auf ausgewaehlte Tracker begrenzbar, als
  Spalte und Filter in der Ticketliste verfuegbar.
- **Sprints** — eine eigenstaendige Entitaet mit Start- und Enddatum, Lebenszyklus
  offen/aktiv/geschlossen und Freigabe ueber den Projektbaum wie bei Versionen.
  Redmine-Versionen bleiben parallel zur Planung nutzbar.
- **Backlog-Planer** — Tickets in einer eigenen Planungsansicht per Drag & Drop Sprints oder
  Versionen zuordnen.
- **Diagramme** — Burndown, Burnup, Velocity, kumulierter Fluss und Durchlaufzeit, wahlweise in
  Tickets, Stunden oder Story Points.
- **Farben** — Karten eingefaerbt nach Tracker, Prioritaet, Status, Bearbeiter, Projekt,
  aufgewendeter Zeit oder pro Ticket.
- **REST-API** — Agile-Daten (Story Points, Sprint-Zuordnung) lesen *und* schreiben, dazu
  Sprint-CRUD.

### Entwurfsentscheidungen

Einige bewusste Unterschiede zu vergleichbaren Plugins, weil sie die Korrektheit betreffen:

- **Board-Positionen sind gebrochene Dezimalwerte und werden auf dem Server berechnet.** Ein Zug
  uebertraegt nur die gezogene Karte und ihre beiden Nachbarn und schreibt eine Zeile. Wird
  stattdessen die ganze Spalte im Browser neu durchnummeriert, zerstoeren gleichzeitige Zuege
  zweier Benutzer die Reihenfolge — und Karten, die ausserhalb der geladenen Seite liegen,
  werden stillschweigend mit umsortiert.
- **Die Diagramm-Historie wird in einem Durchlauf** ueber eine einzige `journal_details`-Abfrage
  rekonstruiert und zwischengespeichert, statt die Journale jedes Tickets pro Datum erneut zu
  durchsuchen.
- **Kein Inline-JavaScript.** Views liefern nur Markup; Daten erreichen den Browser ueber eine
  JSON-Insel. Das Board funktioniert unter einer `script-src 'self'`-Content-Security-Policy.
- **Kein globales Monkeypatching** von `ActiveRecord::Base` oder `ApplicationController`.

## Installation

```bash
cd /pfad/zu/redmine/plugins
git clone https://github.com/expertZentrale/redmine_expert_agile.git
cd /pfad/zu/redmine
bundle exec rake redmine:plugins:migrate NAME=redmine_expert_agile RAILS_ENV=production
```

Redmine neu starten, danach das Modul **expert Agile** (und optional **expert Agile Backlog**)
pro Projekt unter *Projekteinstellungen → Module* aktivieren.

Alternativ ein Release-Archiv von der
[Releases-Seite](https://github.com/expertZentrale/redmine_expert_agile/releases) herunterladen
und nach `plugins/` entpacken.

### Parallelbetrieb mit RedmineUP Agile

Alle Klassen, Tabellen und Routen sind praefixiert, beide Plugins koennen also gleichzeitig
installiert sein. Allerdings patchen beide `Issue#safe_attributes=`, `IssueQuery` und
`ProjectsHelper#project_settings_tabs`, und RedmineUP verwendet dafuer `alias_method`-Paare —
**beide Module im selben Projekt zu aktivieren wird nicht unterstuetzt.** Ein Projekt wird
umgestellt, indem das eine Modul deaktiviert und das andere aktiviert wird.

## Konfiguration

*Administration → Plugins → Redmine expert Agile*. Die Einstellungen sind in Board, Farben,
Schaetzungen, Sprints und Diagramme gegliedert. Jeder Schluessel hat einen Standardwert, eine
frische Installation ist also sofort nutzbar.

Zwei erwaehnenswerte:

- **Maximale Tickets pro Board** (Standard 500) begrenzt, wie viele Tickets eine Board-Ansicht
  laedt.
- **Maximale Tickets pro Diagramm** (Standard 1000) und **Diagramm-Cache** (Standard 60 Minuten)
  begrenzen den Aufwand der historienauswertenden Diagramme.

## Berechtigungen

Pro Rolle unter *Administration → Rollen und Rechte* vergeben.

| Modul | Berechtigung | Erlaubt |
| --- | --- | --- |
| expert Agile | Agile-Board ansehen | Board oeffnen, Karten lesen |
| expert Agile | Agile-Board bearbeiten | Drag & Drop, Karten anlegen und bearbeiten |
| expert Agile | Agile-Boards speichern | Private gespeicherte Boards anlegen |
| expert Agile | Oeffentliche Agile-Boards verwalten | Oeffentliche Boards anlegen und bearbeiten |
| expert Agile | Agile-Diagramme ansehen | Diagrammseite oeffnen |
| expert Agile | Sprints verwalten | Sprints anlegen, bearbeiten und schliessen |
| expert Agile Backlog | Backlog ansehen | Backlog-Planer oeffnen |
| expert Agile Backlog | Backlog verwalten | Tickets Sprints und Versionen zuordnen |

## Entwicklung

Der vollstaendige Entwicklungsleitfaden steht in [CLAUDE.md](CLAUDE.md). Kurzfassung, aus dem
Wurzelverzeichnis des uebergeordneten `redmine-expert`-Repositorys:

```bash
# Lokalen Stack starten (Redmine auf :3000)
docker-compose -f docker-compose.yml up --build

# Testsuite des Plugins ausfuehren
PLUGIN=redmine_expert_agile docker-compose -f docker-compose.yml --profile test run --build --rm redmine-test
```

Innerhalb einer Redmine-Umgebung:

```bash
bundle exec rake redmine:plugins:test NAME=redmine_expert_agile RAILS_ENV=test
```

## Lizenz

GPL-2.0-or-later. Dieses Plugin ist eine unabhaengige Clean-Room-Implementierung und enthaelt
keinen Code aus anderen Agile-Plugins.
