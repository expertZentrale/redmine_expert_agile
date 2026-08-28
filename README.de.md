# redmine_expert_agile

> 🇩🇪 Deutsche Version · [English version](README.md)

Agile Boards fuer Redmine: ein Kanban-/Scrum-Board auf Basis des Redmine-eigenen
Query-Systems, Story Points, Sprints mit Backlog-Planer und Diagramme.

Benoetigt **Redmine 5.0 oder neuer**. Lizenziert unter der **GPL-2.0-or-later**
(siehe [LICENSE](LICENSE)).

## Inhalt

- [Funktionen](#funktionen)
- [Bildschirmfotos](#bildschirmfotos)
- [REST-API](API.md)
- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Berechtigungen](#berechtigungen)
- [Entwicklung](#entwicklung)
- [Lizenz](#lizenz)

## Funktionen

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
  Versionen zuordnen, mit denselben Filtern, Kartenfeldern und gespeicherten Abfragen wie das
  Board.
- **Diagramme** — Burndown, Burnup, Velocity, kumulierter Fluss und Durchlaufzeit, wahlweise in
  Tickets, Stunden oder Story Points.
- **Farben** — Karten eingefaerbt nach Tracker, Prioritaet, Status, Bearbeiter, Projekt oder
  aufgewendeter Zeit, aus einer festen Palette von 18 Toenen, als Farbfelder statt ueber Namen.
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

## Bildschirmfotos

Alle Bildschirmfotos zeigen ein Demo-Projekt mit synthetischen Daten, aufgebaut von
`scripts/seed_screenshot_demo.rb`.

### Board

Die Spalten sind Ticketstatus, Karten werden zwischen ihnen verschoben. Status mit gemeinsamem
Praefix — `Dev: Review` und `Dev: Test` — laufen unter einer gemeinsamen Ueberschrift zusammen,
und eine Spalte oberhalb ihrer WIP-Grenze markiert sich selbst.

![Agile-Board mit fuenf Statusspalten: Zu erledigen, In Arbeit, eine gemeinsame Dev-Ueberschrift
ueber den Unterspalten Review und Test sowie Fertig. Jede Spaltenueberschrift traegt ihre
Kartenzahl und WIP-Grenze, Review ist hervorgehoben, weil dort fuenf Karten gegen eine Grenze von
vier stehen, und die Karten zeigen Ticketnummer, Tracker, Titel, Bearbeiter, Story Points und
Fortschritt](docs/screenshots/de/01-board.png)

Jedes Feld, nach dem die Abfrage gruppieren kann, wird zur Swimlane — dasselbe Board laesst sich
so nach Bearbeiter, Tracker oder Prioritaet lesen.

Ein Board traegt die Tickets seiner Unterprojekte, das globale Board traegt alles. Ob eine Karte
gezogen werden darf, ist deshalb eine Frage an das Projekt der Karte, nicht an das Projekt, dessen
Board angezeigt wird. Eine Karte aus einem Projekt, in dem Sie keine Karten verschieben duerfen,
wird angezeigt, laesst sich aber nicht ziehen.

Ein Board, das sich zu behalten lohnt, wird ueber das Optionsfeld gespeichert und ueber die
Seitenleiste wieder geoeffnet. Beim Bearbeiten eines gespeicherten Boards oeffnet sich dasselbe
Optionsfeld, mit dem es angelegt wurde: Filter, Kartenfelder, Swimlanes, Einfaerbung,
Statusspalten und WIP-Grenzen lassen sich alle aendern. "Bearbeiten" nimmt ausserdem mit, was
gerade angewandt ist — das Board oeffnet sich also so, wie es auf dem Bildschirm steht, und nicht
so, wie es zuletzt gespeichert wurde.

![Dasselbe Board, in Swimlanes nach Bearbeiter gruppiert: ein beschriftetes Band je Teammitglied
plus ein Band fuer nicht zugewiesene Tickets, jedes ueber alle fuenf Statusspalten](docs/screenshots/de/02-board-swimlanes.png)

### Story Points

Story Points sind eine Spalte der plugineigenen Tabelle, kein benutzerdefiniertes Feld. Das
Ticketformular bietet sie als feste Skala an, direkt neben dem Sprint des Tickets.

![Ticketformular mit Redmines eigenen Attributfeldern und darunter zwei Feldern des Plugins: ein
Auswahlfeld Story Points mit dem Wert 5 und ein Auswahlfeld Sprint mit Sprint 24](docs/screenshots/de/05-story-points.png)

### Sprints

Sprints sind datierte Behaelter mit eigenem Lebenszyklus — offen, aktiv, abgeschlossen —, die in
den Projekteinstellungen verwaltet werden. Ein Projekt fuehrt genau einen aktiven Sprint.

![Reiter Sprints in den Projekteinstellungen mit fuenf Sprints samt Status, Start- und Enddatum:
einer aktiv, einer offen und drei abgeschlossen](docs/screenshots/de/04-sprints.png)

### Backlog-Planer

Der Planer stellt den ungeplanten Backlog neben die Sprints, in die er gezogen werden kann; jede
Bahn summiert Ticketzahl und Story Points. Ein zweiter Reiter plant stattdessen in
Redmine-Versionen.

Er traegt dasselbe Filter- und Optionsfeld wie das Board: Redmines eigenes Filterwerkzeug, die
Kartenfelder und die Einfaerbung sowie Anwenden / Zuruecksetzen / Speichern. Das Angewandte bleibt
in der Sitzung erhalten, der Rueckweg zum Planer zeigt ihn also so, wie er verlassen wurde, und ein
Planer, der sich lohnt, laesst sich speichern und aus der Seitenleiste wieder oeffnen. Spalten und
WIP-Grenzen gibt es hier nicht — der Planer ignoriert, wo ein Ticket im Workflow steht, denn ein
Ticket ist geplant oder nicht.

![Backlog-Planer mit den Reitern Sprints und Versionen: links eine Backlog-Bahn, daneben je eine
Bahn pro verfuegbarem Sprint, jede mit Ticketzahl, Story-Point-Summe, Zeitraum und Restlaufzeit in
der Kopfzeile](docs/screenshots/de/03-backlog.png)

### Diagramme

Burndown und Burnup rekonstruieren den Ticketverlauf aus den Journalen. Gemessene Linien enden am
heutigen Tag, die Ideallinie laeuft bis zum Ende des Zeitraums.

![Burndown-Diagramm ueber einen Sprint in Story Points: die Restlinie faellt von 200 Punkten und
endet heute, darunter eine gestrichelte graue Ideallinie, die zum Sprintende auf null laeuft. Die
Seitenleiste listet die gespeicherten Diagramme und die Sprints des Projekts](docs/screenshots/de/06-chart-burndown.png)

![Velocity-Diagramm als gruppierte Balken je Woche, das erstellte gegen abgeschlossene Tickets der
letzten sechzig Tage stellt](docs/screenshots/de/07-chart-velocity.png)

![Diagramm des kumulativen Flusses: sieben gestapelte Baender, eines je Ticketstatus, die ueber
sechzig Tage von fuenf auf hundertfuenfundzwanzig Tickets anwachsen](docs/screenshots/de/08-chart-cumulative-flow.png)

### Farben

Karten beziehen ihre Farbe aus Tracker, Status, Prioritaet, Bearbeiter, Projekt oder dem
Verhaeltnis von geschaetztem zu gebuchtem Aufwand — oder aus einer Farbe am Ticket selbst. Die
Zuordnung wird zentral verwaltet.

![Verwaltungsseite fuer Kartenfarben mit Reitern fuer Ticket, Projekt, Tracker, Prioritaet und
Status, die jeden Status neben einem Farb-Auswahlfeld auflistet](docs/screenshots/de/09-card-colors.png)

### Konfiguration

![Plugin-Einstellungen mit fuenf Abschnitten — Board, Farben, Schaetzungen, Sprints und
Diagramme — mit den Standard-Kartenfeldern, dem Board-Limit, der Farbbasis, der Schaetzeinheit,
der Story-Point-Skala, den Sprint-Schaltern und den Diagramm-Vorgaben](docs/screenshots/de/10-settings.png)

Die REST-API hat keine eigene Oberflaeche — siehe [API.md](API.md).

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

# Testsuite des Plugins ausfuehren. Der Pluginname muss als -e uebergeben werden:
# eine Shell-Variable erreicht den Container nicht, und der Dienst testet dann
# stillschweigend sein Standard-Plugin.
docker-compose -f docker-compose.yml --profile test run --build --rm \
  -e PLUGIN=redmine_expert_agile redmine-test
```

Innerhalb einer Redmine-Umgebung:

```bash
bundle exec rake redmine:plugins:test NAME=redmine_expert_agile RAILS_ENV=test
```

## Lizenz

GPL-2.0-or-later. Dieses Plugin ist eine unabhaengige Clean-Room-Implementierung und enthaelt
keinen Code aus anderen Agile-Plugins.
